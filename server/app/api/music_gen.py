from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import generator_service, heritage_service
from ..storage import manager
from .auth import require_user

router = APIRouter(tags=["music_gen"])

EXTRA_FIELDS = ("lyrics", "genre", "instruments", "tempo", "mood", "vocal")


@router.get("/music/generated/{filename}")
def download_generated(filename: str):
    if "/" in filename or "\\" in filename or ".." in filename or not filename.endswith(".mp3"):
        raise HTTPException(status_code=400, detail="bad filename")
    path = manager.generated_dir() / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/mpeg")


def _extra(**kwargs):
    return {k: v for k, v in kwargs.items() if v not in (None, "")}


@router.get("/music/models")
def list_models():
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
    if duration < 10 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")
    return generator_service.create_task(
        "generate", prompt.strip(), duration, lora.strip(), strength, seed,
        extra=_extra(lyrics=lyrics, genre=genre, instruments=instruments, tempo=tempo, mood=mood, vocal=vocal),
    )


@router.post("/music/cover")
def cover(
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
    if duration < 10 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")
    item = crud.get_item(db, heritage_id.strip())
    if not item:
        raise HTTPException(status_code=404, detail="heritage item not found")
    prompt = f"cover heritage {heritage_id.strip()}: {style.strip()}"
    return generator_service.create_task(
        "cover", prompt, duration, lora.strip(), strength, 0,
        extra=_extra(heritage_id=heritage_id.strip(), style=style.strip(), tempo=tempo, mood=mood, vocal=vocal),
    )


@router.get("/music/heritage-tunes")
def list_heritage_tunes(db: Session = Depends(get_db)):
    items = crud.get_creation_tunes(db)
    if not items:
        items = crud.list_items(db, limit=50)
    return [heritage_service.item_to_dict(i) for i in items]


@router.post("/music/sing-original")
def sing_original(
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
    if duration < 10 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")
    item = crud.get_item(db, heritage_id.strip())
    if not item:
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
    )


@router.post("/music/sing-new-lyrics")
def sing_new_lyrics(
    heritage_id: str = "",
    new_lyrics: str = "",
    vocal: str = "Nữ",
    tempo: str = "Vừa",
    mood: str = "Trữ tình",
    lora: str = "",
    strength: float = 0.8,
    duration: int = 60,
    seed: int = 0,
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
):
    if not heritage_id.strip() or not new_lyrics.strip():
        raise HTTPException(status_code=400, detail="missing heritage_id or new_lyrics")
    if duration < 10 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")
    item = crud.get_item(db, heritage_id.strip())
    if not item:
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
    )


@router.get("/music/task/{task_id}")
def gen_task(task_id: str):
    task = generator_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    return task
