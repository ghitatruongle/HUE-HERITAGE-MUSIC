import asyncio
import json

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import pitch_service, amt_service, midi_service, musicxml_service, amt_eval
from ..ai import basic_pitch_amt as bp_amt
from ..audio_dsp import post_quantizer
from ..storage import manager
from .auth import require_user

router = APIRouter(tags=["transcription"])
LABEL = "Ký âm tự động – cần kiểm duyệt"
MAX_BYTES = 15 * 1024 * 1024


def midi_dir():
    return manager.midi_dir()


def xml_dir():
    return manager.xml_dir()


def _dsp_notes(samples, sr):
    times, f0s = pitch_service.estimate_f0(samples, sr)
    return amt_service.segment_notes(times, f0s)


@router.post("/music/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    bpm: float = Form(60.0),
    heritage_id: str = Form(""),
    engine: str = Form("basic_pitch"),
    db: Session = Depends(get_db),
    user_id: str | None = Depends(require_user),
):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if bpm < 1 or bpm > 300:
        raise HTTPException(status_code=400, detail="bad bpm")
    try:
        samples, sr = pitch_service.read_mono_wav(data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    used = "dsp"
    engine_error = None
    notes = None
    if engine == "basic_pitch" and bp_amt.available():
        try:
            notes = await asyncio.to_thread(bp_amt.transcribe, samples, sr)
            used = "basic_pitch"
        except Exception as e:
            notes = None
            engine_error = str(e)
    elif engine == "basic_pitch":
        engine_error = "basic_pitch unavailable"
    if notes is None:
        notes = await asyncio.to_thread(_dsp_notes, samples, sr)
    notes = post_quantizer.quantize(notes, bpm)
    digest = manager.sha256_bytes(data)
    if heritage_id:
        item = crud.get_item(db, heritage_id)
        if item and item.sha256 != digest:
            raise HTTPException(status_code=400, detail="sha mismatch with heritage item")
    stem = f"{digest}_{int(bpm)}"
    mid = midi_dir() / (stem + ".mid")
    mid.write_bytes(midi_service.write_midi(notes, bpm))
    xm = xml_dir() / (stem + ".musicxml")
    xm.write_text(musicxml_service.build_musicxml(notes, bpm, file.filename or "hue"), encoding="utf-8")
    if heritage_id:
        item = crud.get_item(db, heritage_id)
        if item:
            if not crud.has_audio(db, item.id, "midi", str(mid)):
                crud.create_audio(db, item.id, "midi", str(mid), digest, mid.stat().st_size)
            if not crud.has_audio(db, item.id, "musicxml", str(xm)):
                crud.create_audio(db, item.id, "musicxml", str(xm), digest, xm.stat().st_size)
    result = {
        "label": LABEL,
        "engine": used,
        "filename": file.filename,
        "bpm": bpm,
        "sha": digest,
        "artifact": stem,
        "count": len(notes),
        "notes": notes,
    }
    if engine_error:
        result["engine_error"] = engine_error
    return result


def _find_artifact(directory, sha: str, ext: str, bpm: float = 0.0):
    if not manager.is_sha256(sha):
        return None
    if bpm > 0:
        p = directory / f"{sha}_{int(bpm)}.{ext}"
        if p.exists():
            return p
    legacy = directory / f"{sha}.{ext}"
    if legacy.exists():
        return legacy
    matches = sorted(directory.glob(f"{sha}_*.{ext}"))
    return matches[-1] if matches else None


@router.get("/music/midi/{sha}")
def download_midi(sha: str, bpm: float = 0.0):
    path = _find_artifact(midi_dir(), sha, "mid", bpm)
    if not path:
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/midi")


@router.get("/music/musicxml/{sha}")
def download_xml(sha: str, bpm: float = 0.0):
    path = _find_artifact(xml_dir(), sha, "musicxml", bpm)
    if not path:
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="application/xml")


@router.post("/music/evaluate")
async def evaluate_transcription(
    file: UploadFile = File(...),
    truth: str = Form("[]"),
    bpm: float = Form(60.0),
    engine: str = Form("basic_pitch"),
    user_id: str | None = Depends(require_user),
):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if bpm <= 0 or bpm > 300:
        raise HTTPException(status_code=400, detail="bad bpm")
    try:
        items = json.loads(truth)
    except Exception:
        raise HTTPException(status_code=400, detail="bad truth")
    if not amt_eval.valid_truth(items):
        raise HTTPException(status_code=400, detail="bad truth")
    try:
        samples, sr = pitch_service.read_mono_wav(data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    used = "dsp"
    notes = None
    if engine == "basic_pitch" and bp_amt.available():
        try:
            notes = await asyncio.to_thread(bp_amt.transcribe, samples, sr)
            used = "basic_pitch"
        except Exception:
            notes = None
    if notes is None:
        notes = await asyncio.to_thread(_dsp_notes, samples, sr)
    notes = post_quantizer.quantize(notes, bpm)
    pred = [{"midi": n["midi"], "start": n["start"], "end": n["end"]} for n in notes]
    result = amt_eval.evaluate(pred, items)
    result["engine"] = used
    return result
