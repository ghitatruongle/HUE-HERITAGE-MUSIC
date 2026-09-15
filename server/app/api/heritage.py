from pathlib import Path

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import heritage_service
from ..storage import manager
from .auth import require_user

router = APIRouter(prefix="/heritage", tags=["heritage"])

METADATA_FORM_FIELDS = [
    "genre", "composer", "performers", "artisans", "collector", "recorded_time",
    "location", "lyrics", "instruments", "tonal", "description", "notes",
]


def _collect_metadata(**kwargs):
    return {k: v for k, v in kwargs.items() if v not in (None, "")}


@router.get("")
def list_heritage(q: str = "", limit: int = 50, db: Session = Depends(get_db)):
    items = crud.list_items(db, q, max(1, min(limit, 200)))
    return [heritage_service.item_to_dict(i) for i in items]


@router.post("/upload")
async def upload_heritage(
    request: Request,
    file: UploadFile = File(...),
    title: str = Form(""),
    type: str = Form(""),
    artist: str = Form(""),
    genre: str = Form(""),
    composer: str = Form(""),
    performers: str = Form(""),
    artisans: str = Form(""),
    collector: str = Form(""),
    recorded_time: str = Form(""),
    location: str = Form(""),
    lyrics: str = Form(""),
    instruments: str = Form(""),
    tonal: str = Form(""),
    description: str = Form(""),
    notes: str = Form(""),
    bpm: str = Form(""),
    source: str = Form(""),
    license: str = Form(""),
    db: Session = Depends(get_db),
    user_id: str | None = Depends(require_user),
):
    content_length = request.headers.get("content-length")
    if content_length and content_length.isdigit() and int(content_length) > manager.MAX_SIZE + 1024 * 1024:
        raise HTTPException(status_code=413, detail="file too large")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > manager.MAX_SIZE:
        raise HTTPException(status_code=413, detail="file too large")
    ext = Path(file.filename or "").suffix.lower()
    if ext not in manager.ALLOWED_EXT:
        raise HTTPException(status_code=400, detail="unsupported type")
    bpm_val = None
    bpm_raw = (bpm or "").strip()
    if bpm_raw:
        try:
            bpm_val = float(bpm_raw)
        except ValueError:
            raise HTTPException(status_code=400, detail="bad bpm")
        if not (0.0 < bpm_val <= 500.0):
            raise HTTPException(status_code=400, detail="bad bpm")
    metadata = _collect_metadata(
        genre=genre, composer=composer, performers=performers, artisans=artisans,
        collector=collector, recorded_time=recorded_time, location=location,
        lyrics=lyrics, instruments=instruments, tonal=tonal,
        description=description, notes=notes, bpm=bpm_val, source=source, license=license,
    )
    item, created = heritage_service.ingest_upload(db, data, file.filename or "audio.wav", title, type, artist, **metadata)
    result = heritage_service.item_to_dict(item)
    result["created"] = created
    return result


@router.get("/{item_id}")
def get_heritage(item_id: str, db: Session = Depends(get_db)):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="not found")
    return heritage_service.item_to_dict(item)


@router.get("/{item_id}/audio")
def download_audio(item_id: str, db: Session = Depends(get_db)):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="not found")
    if not manager.safe_original_name(item.filename):
        raise HTTPException(status_code=400, detail="bad filename")
    path = manager.original_dir() / item.filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="file missing")
    return FileResponse(path)
