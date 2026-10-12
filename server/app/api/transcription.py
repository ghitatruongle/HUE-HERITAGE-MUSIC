from typing import Optional
import asyncio
import json

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import amt_eval, media_pipeline
from ..storage import manager
from .auth import require_user

router = APIRouter(tags=["transcription"])
LABEL = "Ký âm tự động – cần kiểm duyệt"
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


def midi_dir():
    return manager.midi_dir()


def xml_dir():
    return manager.xml_dir()


@router.post("/music/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    bpm: float = Form(60.0),
    heritage_id: str = Form(""),
    engine: str = Form("basic_pitch"),
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if bpm < 1 or bpm > 300:
        raise HTTPException(status_code=400, detail="bad bpm")
    try:
        notes, used, engine_error = await asyncio.to_thread(
            media_pipeline.extract_notes, data, bpm, engine
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    digest = manager.sha256_bytes(data)
    item = crud.get_item(db, heritage_id) if heritage_id else None
    if item and item.sha256 != digest:
        raise HTTPException(status_code=400, detail="sha mismatch with heritage item")
    _, stem, mid, xm = await asyncio.to_thread(
        media_pipeline.write_artifacts, data, notes, bpm, file.filename or "hue"
    )
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
    user_id: Optional[str] = Depends(require_user),
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
        notes, used, _ = await asyncio.to_thread(
            media_pipeline.extract_notes, data, bpm, engine
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    pred = [{"midi": n["midi"], "start": n["start"], "end": n["end"]} for n in notes]
    result = amt_eval.evaluate(pred, items)
    result["engine"] = used
    return result
