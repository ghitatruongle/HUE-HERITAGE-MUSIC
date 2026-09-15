from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import generator_service
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
    user_id: str | None = Depends(require_user),
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
    user_id: str | None = Depends(require_user),
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


@router.get("/music/task/{task_id}")
def gen_task(task_id: str):
    task = generator_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    return task
