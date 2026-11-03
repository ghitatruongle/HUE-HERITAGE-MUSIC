from typing import Optional
import asyncio
import re
import secrets
import time

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from fastapi.responses import FileResponse, Response
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import lesson_service, compare_service, scale_service
from ..storage import manager
from ..audio_access import require_audio_access
from .auth import require_user

router = APIRouter(prefix="/lessons", tags=["lessons"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


@router.get("")
def list_lessons(db: Session = Depends(get_db)):
    items = crud.get_creation_tunes(db)
    if not items:
        items = crud.list_items(db, limit=100)
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
def scale_reference(scale_id: str, access=Depends(require_audio_access)):
    try:
        wav = scale_service.reference_wav(scale_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="unknown scale")
    return Response(content=wav, media_type="audio/wav", headers={"Cache-Control": "public, max-age=86400"})


@router.post("/scales/{scale_id}/practice")
async def practice_scale(
    scale_id: str,
    file: UploadFile = File(...),
    user_id: Optional[str] = Depends(require_user),
):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    try:
        return await asyncio.to_thread(scale_service.practice_scale, scale_id, data)
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


@router.get("/{lesson_id}")
def lesson_detail(lesson_id: str, db: Session = Depends(get_db)):
    item = crud.get_item(db, lesson_id)
    if not item:
        raise HTTPException(status_code=404, detail="lesson not found")
    try:
        lesson = lesson_service.get_lesson(item)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    lyrics_text = (item.lyrics_with_ornaments or item.lyrics or "").strip()
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
    finally:
        db.close()
    if not item:
        raise HTTPException(status_code=404, detail="lesson not found")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")

    def _run():
        wav_path = lesson_service.section_wav(item, section)
        if wav_path is None:
            return None
        reference = wav_path.read_bytes()
        result = compare_service.compare(reference, data)
        section_info = None
        lesson = lesson_service.get_lesson(item)
        for s in lesson.get("sections", []):
            if s["index"] == section:
                section_info = s
        result["section"] = section_info
        result["lesson_id"] = lesson_id
        result["lesson_title"] = item.title
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
                pass
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
    return result
