from __future__ import annotations

import asyncio
import json
import re
import threading
import time
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from pydantic import BaseModel
from fastapi.responses import FileResponse, StreamingResponse
from sqlalchemy.orm import Session
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS

from ..config import settings
from ..database.session import get_db
from ..database import crud
from ..services import generator_service, heritage_service
from ..storage import manager
from ..audio_access import require_audio_access, sign_path, HERITAGE_AUDIO_RE
from .auth import require_user, resolve_bearer_user

router = APIRouter(tags=["music_gen"])

GENERATED_NAME = re.compile(r"^[A-Za-z0-9_-]{1,80}\.mp3$")


def _validate_generation(duration: int, strength: float) -> None:
    if duration < 10 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")


PLAYABLE_PREFIXES = (
    "/api/heritage/",
    "/api/lessons/",
    "/api/music/generated/",
    "/api/music/restored/",
    "/api/music/midi/",
    "/api/music/musicxml/",
)
PLAYABLE_SUFFIXES = (
    "/audio",
    ".mp3",
    ".wav",
    ".mid",
    ".musicxml",
)

LESSON_SAMPLE_RE = re.compile(r"^/api/lessons/([A-Za-z0-9-]+)/sections/(\d+)/sample\.wav$")


@router.get("/music/play-url")
def issue_play_url(
    request: Request,
    path: str = "",
    user_id: Optional[str] = Depends(require_user),
    db: Session = Depends(get_db),
):
    cleaned = (path or "").split("?")[0].strip()
    if (
        not cleaned.startswith(PLAYABLE_PREFIXES)
        or not cleaned.endswith(PLAYABLE_SUFFIXES)
        or ".." in cleaned
        or "%" in cleaned
        or " " in cleaned
    ):
        raise HTTPException(status_code=400, detail="bad path")
    scope = ""
    m = HERITAGE_AUDIO_RE.match(cleaned)
    sm = LESSON_SAMPLE_RE.match(cleaned)
    if m or sm:
        viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
        item = crud.get_item(db, m.group(1) if m else sm.group(1))
        if item is None or not crud.can_view_item(item, viewer):
            raise HTTPException(status_code=404, detail="not found")
        scope = f"vis:{getattr(item, 'visibility', None) or 'public'}"
    for prefix in ("/api/music/midi/", "/api/music/musicxml/", "/api/music/restored/"):
        if cleaned.startswith(prefix):
            from ..audio_access import sha_viewable

            sha = cleaned[len(prefix):].split("/")[0]
            if not sha_viewable(db, request, sha):
                raise HTTPException(status_code=404, detail="not found")
            break
    if cleaned.startswith("/api/music/generated/"):
        gen_task = crud.get_task(db, cleaned.split("/")[-1].split(".")[0])
        if gen_task is not None and gen_task.user_id:
            viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
            if viewer is None or (viewer.id != gen_task.user_id and not crud.is_admin_user(viewer)):
                raise HTTPException(status_code=404, detail="not found")
    token = sign_path(cleaned, scope=scope)
    return {"url": token["url"], "expires": token["expires"]}


@router.get("/music/generated/{filename}")
def download_generated(
    filename: str,
    request: Request,
    db: Session = Depends(get_db),
    access: Optional[str] = Depends(require_audio_access),
):
    if not GENERATED_NAME.fullmatch(filename):
        raise HTTPException(status_code=400, detail="bad filename")
    task = crud.get_task(db, filename.split(".")[0])
    if task is not None and task.user_id and access != "signed":
        viewer = resolve_bearer_user(request, db)
        if viewer is None or (viewer.id != task.user_id and not crud.is_admin_user(viewer)):
            raise HTTPException(status_code=404, detail="not found")
    path = manager.generated_dir() / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(
        path,
        media_type="audio/mpeg",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


def _extra(**kwargs):
    return {k: v for k, v in kwargs.items() if v not in (None, "")}


@router.get("/music/models")
def list_models(user_id: Optional[str] = Depends(require_user)):
    return generator_service.models_info()


@router.post("/music/generate")
def generate(
    prompt: str = "",
    duration: int = 60,
    lora: str = "",
    strength: float = 0.8,
    seed: int = 0,
    lyrics: str = "",
    genre: str = "",
    instruments: str = "",
    tempo: str = "",
    mood: str = "",
    vocal: str = "",
    user_id: Optional[str] = Depends(require_user),
):
    if not prompt.strip():
        raise HTTPException(status_code=400, detail="empty prompt")
    _validate_generation(duration, strength)
    return generator_service.create_task(
        "generate", prompt.strip(), duration, lora.strip(), strength, seed,
        extra=_extra(lyrics=lyrics, genre=genre, instruments=instruments, tempo=tempo, mood=mood, vocal=vocal),
        user_id=user_id,
    )


@router.post("/music/cover")
def cover(
    request: Request,
    heritage_id: str = "",
    style: str = "",
    duration: int = 60,
    lora: str = "",
    strength: float = 0.8,
    tempo: str = "",
    mood: str = "",
    vocal: str = "",
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
):
    if not heritage_id.strip() or not style.strip():
        raise HTTPException(status_code=400, detail="missing params")
    _validate_generation(duration, strength)
    item = crud.get_item(db, heritage_id.strip())
    if not item:
        raise HTTPException(status_code=404, detail="heritage item not found")
    viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    if not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="heritage item not found")
    prompt = f"cover heritage {heritage_id.strip()}: {style.strip()}"
    return generator_service.create_task(
        "cover", prompt, duration, lora.strip(), strength, 0,
        extra=_extra(heritage_id=heritage_id.strip(), style=style.strip(), tempo=tempo, mood=mood, vocal=vocal),
        user_id=user_id,
    )


@router.get("/music/heritage-tunes")
def list_heritage_tunes(request: Request, db: Session = Depends(get_db)):
    viewer = resolve_bearer_user(request, db)
    items = crud.get_creation_tunes(db, viewer=viewer)
    if not items:
        items = crud.list_items(db, limit=50, viewer=viewer)
    return [heritage_service.item_to_dict(i) for i in items]


@router.post("/music/sing-original")
def sing_original(
    request: Request,
    heritage_id: str = "",
    vocal: str = "Nữ",
    tempo: str = "Vừa",
    lora: str = "",
    strength: float = 0.8,
    duration: int = 60,
    seed: int = 0,
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
):
    if not heritage_id.strip():
        raise HTTPException(status_code=400, detail="missing heritage_id")
    _validate_generation(duration, strength)
    item = crud.get_item(db, heritage_id.strip())
    if not item:
        raise HTTPException(status_code=404, detail="heritage item not found")
    viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    if not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="heritage item not found")
    lyrics_text = item.lyrics_with_ornaments or item.lyrics
    prompt = f"original heritage recreation {item.title}: {item.mode_system or item.tonal or item.genre}"
    return generator_service.create_task(
        "sing_original", prompt, duration, lora.strip(), strength, seed,
        extra=_extra(
            heritage_id=heritage_id.strip(),
            lyrics=lyrics_text,
            genre=item.genre or item.type,
            instruments=item.instruments,
            tempo=tempo,
            mood="Truyen thong",
            vocal=vocal,
        ),
        user_id=user_id,
    )


class SingNewLyricsBody(BaseModel):
    new_lyrics: str = ""


@router.post("/music/sing-new-lyrics")
def sing_new_lyrics(
    request: Request,
    heritage_id: str = "",
    new_lyrics: str = "",
    vocal: str = "Nữ",
    tempo: str = "Vừa",
    mood: str = "Trữ tình",
    lora: str = "",
    strength: float = 0.8,
    duration: int = 60,
    seed: int = 0,
    body: Optional[SingNewLyricsBody] = Body(default=None),
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
):
    if body is not None and body.new_lyrics.strip():
        new_lyrics = body.new_lyrics
    if not heritage_id.strip() or not new_lyrics.strip():
        raise HTTPException(status_code=400, detail="missing heritage_id or new_lyrics")
    _validate_generation(duration, strength)
    item = crud.get_item(db, heritage_id.strip())
    if not item:
        raise HTTPException(status_code=404, detail="heritage item not found")
    viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    if not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="heritage item not found")
    prompt = f"sing new lyrics on heritage melody {item.title}: {item.mode_system or item.tonal or item.genre}"
    return generator_service.create_task(
        "sing_new_lyrics", prompt, duration, lora.strip(), strength, seed,
        extra=_extra(
            heritage_id=heritage_id.strip(),
            lyrics=new_lyrics.strip(),
            genre=item.genre or item.type,
            instruments=item.instruments,
            tempo=tempo,
            mood=mood,
            vocal=vocal,
        ),
        user_id=user_id,
    )


@router.get("/music/task/{task_id}")
def gen_task(task_id: str, user_id: Optional[str] = Depends(require_user)):
    task = generator_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    if settings.auth_required and task.get("user_id") and task["user_id"] != user_id:
        raise HTTPException(status_code=404, detail="not found")
    return task


@router.post("/music/task/{task_id}/cancel")
def cancel_gen_task(
    task_id: str,
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
):
    task = generator_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    if settings.auth_required and task.get("user_id") and task["user_id"] != user_id:
        caller = crud.get_user_by_id(db, user_id) if user_id else None
        if not caller or (caller.role or "user") != "admin":
            raise HTTPException(status_code=404, detail="not found")
    task = generator_service.cancel_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    return task


NON_TERMINAL_STATUSES = ("running", "pending", "queued")

_SSE_LOCK = threading.Lock()
_SSE_ACTIVE: dict = {}
_SSE_LIMIT_PER_CLIENT = 8


@router.get("/music/task/{task_id}/events")
async def gen_task_events(request: Request, task_id: str):
    user_id = None
    if settings.auth_required:
        from ..database.session import SessionLocal

        db = SessionLocal()
        try:
            user_id = require_user(request)
        finally:
            db.close()
    task = generator_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    if settings.auth_required and task.get("user_id") and task["user_id"] != user_id:
        raise HTTPException(status_code=404, detail="not found")
    key = user_id or (request.client.host if request.client else "unknown")
    with _SSE_LOCK:
        if _SSE_ACTIVE.get(key, 0) >= _SSE_LIMIT_PER_CLIENT:
            raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
        _SSE_ACTIVE[key] = _SSE_ACTIVE.get(key, 0) + 1

    async def stream():
        try:
            deadline = time.time() + 960.0
            while time.time() < deadline:
                payload = await asyncio.to_thread(generator_service.get_task, task_id)
                if payload is None:
                    yield "event: gone\ndata: {}\n\n"
                    return
                yield f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
                if payload.get("status") not in NON_TERMINAL_STATUSES:
                    return
                await asyncio.sleep(2.0)
        finally:
            with _SSE_LOCK:
                remaining = _SSE_ACTIVE.get(key, 0) - 1
                if remaining > 0:
                    _SSE_ACTIVE[key] = remaining
                else:
                    _SSE_ACTIVE.pop(key, None)

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
