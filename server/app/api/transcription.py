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
    if bpm < 4 or bpm > 300:
        raise HTTPException(status_code=400, detail="bad bpm")
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
    digest = manager.sha256_bytes(data)
    if heritage_id:
        item = crud.get_item(db, heritage_id)
        if item and item.sha256 != digest:
            raise HTTPException(status_code=400, detail="sha mismatch with heritage item")
    mid = midi_dir() / (digest + ".mid")
    mid.write_bytes(midi_service.write_midi(notes, bpm))
    xm = xml_dir() / (digest + ".musicxml")
    xm.write_text(musicxml_service.build_musicxml(notes, bpm, file.filename or "hue"), encoding="utf-8")
    if heritage_id:
        item = crud.get_item(db, heritage_id)
        if item:
            if not crud.has_audio(db, item.id, "midi", str(mid)):
                crud.create_audio(db, item.id, "midi", str(mid), digest, mid.stat().st_size)
            if not crud.has_audio(db, item.id, "musicxml", str(xm)):
                crud.create_audio(db, item.id, "musicxml", str(xm), digest, xm.stat().st_size)
    return {
        "label": LABEL,
        "engine": used,
        "filename": file.filename,
        "bpm": bpm,
        "sha": digest,
        "count": len(notes),
        "notes": notes,
    }


@router.get("/music/midi/{sha}")
def download_midi(sha: str):
    path = midi_dir() / (sha + ".mid")
    if not manager.is_sha256(sha) or not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/midi")


@router.get("/music/musicxml/{sha}")
def download_xml(sha: str):
    path = xml_dir() / (sha + ".musicxml")
    if not manager.is_sha256(sha) or not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="application/xml")


@router.post("/music/evaluate")
async def evaluate_transcription(
    file: UploadFile = File(...),
    truth: str = Form("[]"),
    bpm: float = Form(60.0),
    engine: str = Form("basic_pitch"),
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
