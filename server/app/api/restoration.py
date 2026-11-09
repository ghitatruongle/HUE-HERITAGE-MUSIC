from __future__ import annotations

import asyncio
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import SessionLocal, get_db
from ..database import crud
from ..database.models import HeritageItem
from ..services import media_pipeline, user_inflight
from ..storage import manager
from ..audio_access import sign_path, verify_path
from .auth import require_user, resolve_bearer_user

router = APIRouter(tags=["restoration"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


def restored_dir():
    return manager.restored_dir()


def _sha_item(db: Session, sha: str):
    return db.query(HeritageItem).filter(HeritageItem.sha256 == sha).first()


def _sha_viewable(db: Session, request: Request, sha: str) -> bool:
    item = _sha_item(db, sha)
    if item is None:
        return True
    viewer = resolve_bearer_user(request, db)
    return crud.can_view_item(item, viewer)


def run_restore(data, heritage_id):
    try:
        report, dest = media_pipeline.restore_audio(data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    digest = report["sha"]
    if heritage_id:
        db = SessionLocal()
        try:
            item = crud.get_item(db, heritage_id)
            if item and not crud.has_audio(db, item.id, "restored", str(dest)):
                try:
                    size = dest.stat().st_size
                except OSError:
                    size = 0
                crud.create_audio(db, item.id, "restored", str(dest), digest, size)
        finally:
            db.close()
    return report


@router.post("/music/restore")
async def restore_upload(request: Request, file: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    if manager.content_length_exceeds(request, MAX_BYTES):
        raise HTTPException(status_code=413, detail="file too large")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if not user_inflight.try_acquire(user_inflight.user_key("restore", user_id)):
        raise HTTPException(status_code=429, detail="too many concurrent requests")
    try:
        report = await asyncio.to_thread(run_restore, data, "")
        db = SessionLocal()
        try:
            crud.record_artifact_owner(db, report.get("sha", ""), user_id, kind="restore")
        finally:
            db.close()
        return report
    finally:
        user_inflight.release(user_inflight.user_key("restore", user_id))


@router.post("/music/restore-item/{item_id}")
def restore_item(item_id: str, request: Request, db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="not found")
    viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    if not crud.can_view_item(item, viewer):
        raise HTTPException(status_code=404, detail="not found")
    if not manager.safe_original_name(item.filename):
        raise HTTPException(status_code=400, detail="bad filename")
    path = manager.original_dir() / item.filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="file missing")
    try:
        data = path.read_bytes()
    except OSError:
        raise HTTPException(status_code=404, detail="file missing")
    if not user_inflight.try_acquire(user_inflight.user_key("restore", user_id)):
        raise HTTPException(status_code=429, detail="too many concurrent requests")
    try:
        report = run_restore(data, item.id)
        db2 = SessionLocal()
        try:
            crud.record_artifact_owner(db2, report.get("sha", ""), user_id, kind="restore")
        finally:
            db2.close()
        return report
    finally:
        user_inflight.release(user_inflight.user_key("restore", user_id))


@router.get("/music/restored/{sha}")
def download_restored(sha: str, request: Request, db: Session = Depends(get_db)):
    if not manager.is_sha256(sha):
        raise HTTPException(status_code=404, detail="not found")
    item = _sha_item(db, sha)
    viewer = resolve_bearer_user(request, db)
    if viewer is not None:
        from ..audio_access import sha_viewable

        if not sha_viewable(db, request, sha):
            raise HTTPException(status_code=404, detail="not found")
    elif settings.auth_required:
        scope = f"vis:{getattr(item, 'visibility', None) or 'public'}" if item is not None else ""
        if not verify_path(
            request.url.path, request.query_params.get("e"), request.query_params.get("s"), scope=scope
        ):
            raise HTTPException(status_code=401, detail="authentication or signed url required")
    elif item is not None and not crud.can_view_item(item, None):
        raise HTTPException(status_code=404, detail="not found")
    path = restored_dir() / (sha + "_restored.wav")
    if not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/wav")


@router.get("/music/restored-url/{sha}")
def issue_restored_url(
    sha: str, request: Request, db: Session = Depends(get_db), user_id=Depends(require_user)
):
    if not manager.is_sha256(sha):
        raise HTTPException(status_code=404, detail="not found")
    item = _sha_item(db, sha)
    if item is not None:
        viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
        if not crud.can_view_item(item, viewer):
            raise HTTPException(status_code=404, detail="not found")
        scope = f"vis:{getattr(item, 'visibility', None) or 'public'}"
    else:
        scope = ""
    token = sign_path(f"/api/music/restored/{sha}", scope=scope)
    return {"url": token["url"], "expires": token["expires"]}
