from typing import Optional
import asyncio
import json
import math

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS

from ..database.session import get_db, SessionLocal
from ..database import crud
from ..ai import basic_pitch_amt
from ..services import amt_eval, media_pipeline, user_inflight
from ..storage import manager
from ..audio_access import require_audio_access
from .auth import require_user, resolve_bearer_user

router = APIRouter(tags=["transcription"])
LABEL = "Ký âm tự động – cần kiểm duyệt"
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


def midi_dir():
    return manager.midi_dir()


def xml_dir():
    return manager.xml_dir()


@router.post("/music/transcribe")
async def transcribe(
    request: Request,
    file: UploadFile = File(...),
    bpm: float = Form(60.0),
    heritage_id: str = Form(""),
    engine: str = Form("basic_pitch"),
    user_id: Optional[str] = Depends(require_user),
):
    if manager.content_length_exceeds(request, MAX_BYTES):
        raise HTTPException(status_code=413, detail="file too large")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if not math.isfinite(bpm) or bpm < 1 or bpm > 300:
        raise HTTPException(status_code=400, detail="bad bpm")
    if not user_inflight.try_acquire(user_inflight.user_key("transcribe", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    cached = False
    try:
        digest = await asyncio.to_thread(manager.sha256_bytes, data)
        try:
            hit = await asyncio.to_thread(media_pipeline.load_cached_notes, digest, bpm, engine)
        except Exception:
            hit = None
        if hit is not None:
            notes, used, engine_error = hit
            cached = True
        else:
            try:
                notes, used, engine_error = await asyncio.to_thread(
                    media_pipeline.extract_notes, data, bpm, engine
                )
            except ValueError:
                raise HTTPException(status_code=400, detail="wav decode failed")
            except basic_pitch_amt.EngineBusy as e:
                raise HTTPException(status_code=503, detail=str(e))
            await asyncio.to_thread(media_pipeline.save_cached_notes, digest, bpm, engine, notes, used, engine_error)
    finally:
        user_inflight.release(user_inflight.user_key("transcribe", user_id))
    item = None
    if heritage_id:
        db = SessionLocal()
        try:
            item = crud.get_item(db, heritage_id)
            if item:
                viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
                if not crud.can_view_item(item, viewer):
                    raise HTTPException(status_code=404, detail="not found")
                if item.sha256 != digest:
                    raise HTTPException(status_code=400, detail="sha mismatch with heritage item")
        finally:
            db.close()
    _, stem, mid, xm = await asyncio.to_thread(
        media_pipeline.write_artifacts, data, notes, bpm, file.filename or "hue", digest
    )
    if item:
        db = SessionLocal()
        try:
            if not crud.has_audio(db, item.id, "midi", str(mid)):
                crud.create_audio(db, item.id, "midi", str(mid), digest, mid.stat().st_size)
            if not crud.has_audio(db, item.id, "musicxml", str(xm)):
                crud.create_audio(db, item.id, "musicxml", str(xm), digest, xm.stat().st_size)
        finally:
            db.close()
    else:
        db = SessionLocal()
        try:
            crud.record_artifact_owner(db, digest, user_id, kind="transcribe")
        finally:
            db.close()
    result = {
        "label": LABEL,
        "engine": used,
        "cached": cached,
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


def _safe_bpm(bpm: float) -> float:
    if not math.isfinite(bpm) or bpm <= 0 or bpm > 10**6:
        return 0.0
    return bpm


def _sha_viewable(db: Session, request: Request, sha: str) -> bool:
    from ..audio_access import sha_viewable

    return sha_viewable(db, request, sha)


@router.get("/music/midi/{sha}")
def download_midi(sha: str, request: Request, bpm: float = 0.0, db: Session = Depends(get_db), access=Depends(require_audio_access)):
    if not _sha_viewable(db, request, sha):
        raise HTTPException(status_code=404, detail="not found")
    path = _find_artifact(midi_dir(), sha, "mid", _safe_bpm(bpm))
    if not path:
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/midi")


@router.get("/music/musicxml/{sha}")
def download_xml(sha: str, request: Request, bpm: float = 0.0, db: Session = Depends(get_db), access=Depends(require_audio_access)):
    if not _sha_viewable(db, request, sha):
        raise HTTPException(status_code=404, detail="not found")
    path = _find_artifact(xml_dir(), sha, "musicxml", _safe_bpm(bpm))
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
    if not user_inflight.try_acquire(user_inflight.user_key("evaluate", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        data = await file.read()
        if len(data) == 0:
            raise HTTPException(status_code=400, detail="empty file")
        if len(data) > MAX_BYTES:
            raise HTTPException(status_code=413, detail="file too large")
        if not math.isfinite(bpm) or bpm <= 0 or bpm > 300:
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
        except basic_pitch_amt.EngineBusy as e:
            raise HTTPException(status_code=503, detail=str(e))
        pred = [{"midi": n["midi"], "start": n["start"], "end": n["end"]} for n in notes]
        result = amt_eval.evaluate(pred, items)
        result["engine"] = used
        return result
    finally:
        user_inflight.release(user_inflight.user_key("evaluate", user_id))
