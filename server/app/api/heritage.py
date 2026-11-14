from typing import Optional
from pathlib import Path
import asyncio

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS

from ..database.session import acquire_write_slot, get_db
from ..database import crud
from ..config import settings
from ..services import heritage_service, user_inflight
from ..storage import manager
from ..audio_access import require_audio_access, sign_path
from .auth import require_user, resolve_bearer_user

router = APIRouter(prefix="/heritage", tags=["heritage"])

METADATA_FORM_FIELDS = [
    "genre", "composer", "performers", "artisans", "collector", "recorded_time",
    "location", "lyrics", "instruments", "tonal", "description", "notes",
]


def _collect_metadata(**kwargs):
    return {k: v for k, v in kwargs.items() if v not in (None, "")}


@router.get("")
def list_heritage(
    request: Request,
    q: str = "",
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
):
    viewer = resolve_bearer_user(request, db)
    lim = max(1, min(limit, 200))
    items = crud.list_items(db, q, lim, offset=offset, viewer=viewer)
    total = crud.count_items(db, q, viewer=viewer)
    return {"items": [heritage_service.item_to_dict(i) for i in items], "total": total}


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
    lyrics_with_ornaments: str = Form(""),
    mode_system: str = Form(""),
    verse_structure: str = Form(""),
    instruments: str = Form(""),
    tonal: str = Form(""),
    description: str = Form(""),
    notes: str = Form(""),
    bpm: str = Form(""),
    source: str = Form(""),
    license: str = Form(""),
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
    _write_slot: None = Depends(acquire_write_slot),
):
    chunks = []
    total = 0
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > manager.MAX_SIZE:
            raise HTTPException(status_code=413, detail="file too large")
        chunks.append(chunk)
    data = b"".join(chunks)
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    ext = Path(file.filename or "").suffix.lower()
    if ext not in manager.ALLOWED_EXT:
        raise HTTPException(status_code=400, detail="unsupported type")
    if not manager.audio_magic_ok(ext, data[:16]):
        raise HTTPException(status_code=400, detail="file content does not match its extension")
    bpm_val = None
    bpm_raw = (bpm or "").strip()
    if bpm_raw:
        try:
            bpm_val = float(bpm_raw)
        except ValueError:
            raise HTTPException(status_code=400, detail="bad bpm")
        if not (0.0 < bpm_val <= 300.0):
            raise HTTPException(status_code=400, detail="bad bpm")
    metadata = _collect_metadata(
        genre=genre, composer=composer, performers=performers, artisans=artisans,
        collector=collector, recorded_time=recorded_time, location=location,
        lyrics=lyrics, lyrics_with_ornaments=lyrics_with_ornaments,
        mode_system=mode_system, verse_structure=verse_structure,
        instruments=instruments, tonal=tonal,
        description=description, notes=notes, bpm=bpm_val, source=source, license=license,
    )
    uploader = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    visibility = "admin_only" if crud.is_admin_user(uploader) else "public"
    if uploader is not None and not crud.is_admin_user(uploader) and settings.user_storage_quota_mb > 0:
        used = crud.user_storage_bytes(db, uploader.id)
        limit_bytes = settings.user_storage_quota_mb * 1024 * 1024
        if used + len(data) > limit_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"storage quota exceeded: {used // (1024 * 1024)}MB used of {settings.user_storage_quota_mb}MB",
            )
    if not user_inflight.try_acquire(user_inflight.user_key("heritage-upload", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        path, digest, _fresh = await asyncio.to_thread(
            heritage_service.save_upload_payload, data, file.filename or "audio.wav"
        )
        item, created = heritage_service.ingest_saved(
            db, path, digest, len(data), file.filename or "audio.wav", title, type, artist,
            owner_user_id=uploader.id if uploader is not None else None,
            visibility=visibility, **metadata,
        )
        if not created and not crud.can_view_item(item, uploader):
            raise HTTPException(status_code=404, detail="upload rejected: duplicate content")
    finally:
        user_inflight.release(user_inflight.user_key("heritage-upload", user_id))
    result = heritage_service.item_to_dict(item)
    result["created"] = created
    return result


@router.get("/{item_id}")
def get_heritage(request: Request, item_id: str, db: Session = Depends(get_db)):
    viewer = resolve_bearer_user(request, db)
    item = crud.get_item(db, item_id)
    if not item or not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="not found")
    return heritage_service.item_to_dict(item)


@router.get("/{item_id}/audio")
def download_audio(item_id: str, db: Session = Depends(get_db), access: Optional[str] = Depends(require_audio_access)):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="not found")
    if not manager.safe_original_name(item.filename):
        raise HTTPException(status_code=400, detail="bad filename")
    path = manager.original_dir() / item.filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="file missing")
    return FileResponse(path)


@router.get("/{item_id}/audio-url")
def issue_audio_url(request: Request, item_id: str, db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    item = crud.get_item(db, item_id)
    if not item or not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="not found")
    token = sign_path(f"/api/heritage/{item_id}/audio", scope=f"vis:{getattr(item, 'visibility', None) or 'public'}")
    return {"url": token["url"], "expires": token["expires"]}
