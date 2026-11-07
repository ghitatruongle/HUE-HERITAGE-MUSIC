from typing import Optional
import asyncio
import logging
import re
import secrets
import time

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Request
from fastapi.responses import FileResponse, Response
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import get_db
from ..database import crud
from ..services import lesson_service, compare_service, scale_service
from ..storage import manager
from ..audio_access import require_audio_access, verify_path
from .auth import require_user, resolve_bearer_user, require_admin_fresh

router = APIRouter(prefix="/lessons", tags=["lessons"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


def _lesson_audio_guard(request: Request, item, db: Session):
    user = resolve_bearer_user(request, db)
    if user is not None:
        if not crud.can_view_item(item, user):
            raise HTTPException(status_code=404, detail="not found")
        return
    if not settings.auth_required:
        if (getattr(item, "visibility", None) or "public") != "public":
            raise HTTPException(status_code=404, detail="not found")
        return
    scope = f"vis:{getattr(item, 'visibility', None) or 'public'}"
    if not verify_path(request.url.path, request.query_params.get("e"), request.query_params.get("s"), scope=scope):
        raise HTTPException(status_code=401, detail="authentication or signed url required")


def _load_item(lesson_id: str):
    from ..database.session import SessionLocal

    db = SessionLocal()
    try:
        return crud.get_item(db, lesson_id)
    finally:
        db.close()


def _section_exists(item, section: int) -> bool:
    try:
        lesson = lesson_service.get_lesson(item)
    except ValueError:
        return False
    return any(s["index"] == section for s in lesson.get("sections", []))


@router.post("/{lesson_id}/sections/{section}/sample.wav")
async def upload_lesson_sample(
    lesson_id: str,
    section: int,
    file: UploadFile = File(...),
    admin_id: str = Depends(require_admin_fresh),
):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")

    def _validate_and_save():
        item = _load_item(lesson_id)
        if not item:
            return None, "lesson not found", 404
        if not _section_exists(item, section):
            return None, "section not found", 404
        try:
            manager.save_lesson_sample(item.sha256 or item.id, section, data)
        except ValueError as e:
            msg = str(e)
            if "too large" in msg:
                return None, "file too large", 413
            return None, msg, 400
        return True, None, 200

    _, err, status = await asyncio.to_thread(_validate_and_save)
    if err:
        raise HTTPException(status_code=status, detail=err)
    from .. import security_log

    security_log.security_event("lesson_sample_uploaded", admin=admin_id, lesson=lesson_id, section=section, size=len(data))
    return {"saved": True, "section": section, "size": len(data)}


@router.get("/{lesson_id}/sections/{section}/sample.wav")
def get_lesson_sample(request: Request, lesson_id: str, section: int, db: Session = Depends(get_db)):
    item = crud.get_item(db, lesson_id)
    if not item:
        raise HTTPException(status_code=404, detail="lesson not found")
    _lesson_audio_guard(request, item, db)
    path = manager.lesson_sample_path(item.sha256 or item.id, section)
    if not path.exists():
        raise HTTPException(status_code=404, detail="sample not found")
    return FileResponse(path, media_type="audio/wav")


@router.delete("/{lesson_id}/sections/{section}/sample.wav")
def delete_lesson_sample(lesson_id: str, section: int, admin_id: str = Depends(require_admin_fresh)):
    item = _load_item(lesson_id)
    if not item:
        raise HTTPException(status_code=404, detail="lesson not found")
    removed = manager.delete_lesson_sample(item.sha256 or item.id, section)
    from .. import security_log

    security_log.security_event("lesson_sample_deleted", admin=admin_id, lesson=lesson_id, section=section, removed=removed)
    return {"deleted": removed, "section": section}


@router.get("")
def list_lessons(request: Request, db: Session = Depends(get_db)):
    viewer = resolve_bearer_user(request, db)
    items = crud.get_creation_tunes(db, viewer=viewer)
    if not items:
        items = crud.list_items(db, limit=100, viewer=viewer)
    lessons = []
    for item in items:
        summary = lesson_service.lesson_summary(item)
        if summary is not None:
            lessons.append(summary)
    return lessons


@router.get("/scales")
def list_scales():
    return scale_service.list_scales()


@router.get("/scales/{scale_id}/reference.wav")
def scale_reference(scale_id: str, transpose: int = 0, access=Depends(require_audio_access)):
    try:
        wav = scale_service.reference_wav(scale_id, transpose)
    except ValueError:
        raise HTTPException(status_code=404, detail="unknown scale")
    return Response(content=wav, media_type="audio/wav", headers={"Cache-Control": "public, max-age=86400"})


@router.post("/scales/{scale_id}/practice")
async def practice_scale(
    scale_id: str,
    file: UploadFile = File(...),
    transpose: int = 0,
    user_id: Optional[str] = Depends(require_user),
):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    try:
        return await asyncio.to_thread(scale_service.practice_scale, scale_id, data, transpose)
    except ValueError as e:
        msg = str(e)
        if msg == "unknown scale":
            raise HTTPException(status_code=404, detail="unknown scale")
        if "empty contour" in msg:
            raise HTTPException(status_code=400, detail="empty pitch contour (silence or unvoiced audio)")
        raise HTTPException(status_code=400, detail="wav decode failed")


PRACTICE_MIDI_NAME = re.compile(r"^practice_[A-Za-z0-9]{8,32}(_\d+_\d{10})?\.mid$")


@router.get("/practice-midi/{name}")
def download_practice_midi(name: str, access=Depends(require_audio_access)):
    if not PRACTICE_MIDI_NAME.fullmatch(name):
        raise HTTPException(status_code=400, detail="bad filename")
    path = manager.midi_dir() / name
    if not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/midi")


@router.get("/my-progress")
def my_progress(
    lesson_id: str = "",
    limit: int = 100,
    user_id: Optional[str] = Depends(require_user),
    db: Session = Depends(get_db),
):
    if not user_id:
        return {"items": [], "server_history": False}
    rows = crud.list_practice_sessions(db, user_id, lesson_id or None, limit=limit)
    return {
        "items": [crud.practice_session_to_dict(r) for r in rows],
        "server_history": True,
    }


@router.get("/{lesson_id}")
def lesson_detail(request: Request, lesson_id: str, db: Session = Depends(get_db)):
    viewer = resolve_bearer_user(request, db)
    item = crud.get_item(db, lesson_id)
    if not item or not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="lesson not found")
    try:
        lesson = lesson_service.get_lesson(item)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    lyrics_text = (item.lyrics_with_ornaments or item.lyrics or "").strip()
    sha = item.sha256 or item.id
    for s in lesson.get("sections", []):
        has_sample = manager.lesson_sample_path(sha, s["index"]).exists()
        s["has_sample"] = has_sample
        s["sample_url"] = f"/api/lessons/{lesson_id}/sections/{s['index']}/sample.wav" if has_sample else ""
    lesson.update(
        {
            "lyrics": lyrics_text,
            "mode_system": item.mode_system,
            "bpm": item.bpm,
            "verse_structure": item.verse_structure,
        }
    )
    return lesson


@router.post("/{lesson_id}/practice")
async def practice_section(
    lesson_id: str,
    section: int,
    file: UploadFile = File(...),
    user_id: Optional[str] = Depends(require_user),
):
    from ..database.session import SessionLocal
    from ..database import crud as _crud

    db = SessionLocal()
    try:
        item = _crud.get_item(db, lesson_id)
        viewer = _crud.get_user_by_id(db, user_id) if user_id else None
    finally:
        db.close()
    if not item or not _crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="lesson not found")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")

    def _run():
        sha = item.sha256 or item.id
        sample_path = manager.lesson_sample_path(sha, section)
        if sample_path.exists():
            reference = sample_path.read_bytes()
            reference_kind = "sample"
        else:
            wav_path = lesson_service.section_wav(item, section)
            if wav_path is None:
                return None
            reference = wav_path.read_bytes()
            reference_kind = "original"
        result = compare_service.compare(reference, data)
        section_info = None
        lesson = lesson_service.get_lesson(item)
        for s in lesson.get("sections", []):
            if s["index"] == section:
                section_info = s
        result["section"] = section_info
        result["lesson_id"] = lesson_id
        result["lesson_title"] = item.title
        result["reference"] = reference_kind
        if result.get("notes"):
            try:
                from ..services import midi_service

                bpm_val = int(item.bpm) if item.bpm and item.bpm > 0 else 60
                user_midi = midi_service.write_midi(result["notes"], bpm_val)
                mid_name = f"practice_{secrets.token_hex(12)}_{section}_{int(time.time())}.mid"
                mid_dir = manager.midi_dir()
                mid_dir.mkdir(parents=True, exist_ok=True)
                (mid_dir / mid_name).write_bytes(user_midi)
                result["user_midi"] = mid_name
            except Exception:
                logging.getLogger(__name__).warning("practice midi save failed", exc_info=True)
        return result

    try:
        result = await asyncio.to_thread(_run)
    except ValueError as e:
        msg = str(e)
        if "empty contour" in msg:
            raise HTTPException(status_code=400, detail="empty pitch contour (silence or unvoiced audio)")
        raise HTTPException(status_code=400, detail="wav decode failed")
    if result is None:
        raise HTTPException(status_code=404, detail="section not found")
    if user_id and result.get("metrics"):
        try:
            from ..database.session import SessionLocal

            m = result["metrics"]
            db2 = SessionLocal()
            try:
                crud.create_practice_session(
                    db2,
                    user_id,
                    lesson_id,
                    section,
                    m.get("score", 0.0),
                    m.get("pitch_score", 0.0),
                    m.get("rhythm_score", 0.0),
                    m.get("stability_score", 0.0),
                    result.get("reference", "original"),
                    metrics={
                        "mean_abs_cents": m.get("mean_abs_cents"),
                        "ornament": m.get("ornament"),
                        "matched_notes": m.get("matched_notes"),
                        "unmatched_notes": m.get("unmatched_notes"),
                        "missing_notes": m.get("missing_notes"),
                        "summary_hint": m.get("summary_hint"),
                    },
                )
            finally:
                db2.close()
        except Exception:
            logging.getLogger(__name__).warning("practice session save failed", exc_info=True)
    return result
