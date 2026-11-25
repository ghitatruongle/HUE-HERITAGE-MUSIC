from __future__ import annotations

import asyncio
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS
from ..database.session import SessionLocal, get_db
from ..database import crud
from ..database.models import HeritageItem
from ..services import media_pipeline, user_inflight
from ..storage import manager
from ..audio_access import require_sha_audio_access, sha_access_scope, sha_viewable, sign_path
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


def _record_restore_owner(sha: str, user_id: Optional[str]) -> None:
    if not sha:
        return
    db = SessionLocal()
    try:
        crud.record_artifact_owner(db, sha, user_id, kind="restore")
    finally:
        db.close()


def _resolve_restore_item(item_id: str, user_id: Optional[str], request: Request):
    db = SessionLocal()
    try:
        item = crud.get_item(db, item_id)
        if not item:
            return None
        viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
        if not crud.can_view_item(item, viewer):
            return None
        if not manager.safe_original_name(item.filename):
            return ("bad_filename", "")
        return (item.id, item.filename)
    finally:
        db.close()


@router.post("/music/restore")
async def restore_upload(request: Request, file: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    if manager.content_length_exceeds(request, MAX_BYTES):
        raise HTTPException(status_code=413, detail="file too large")
    data = await manager.read_upload_limited(file, MAX_BYTES)
    if not user_inflight.try_acquire(user_inflight.user_key("restore", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        report = await user_inflight.run_dsp(run_restore, data, "")
        await asyncio.to_thread(_record_restore_owner, report.get("sha", ""), user_id)
        return report
    finally:
        user_inflight.release(user_inflight.user_key("restore", user_id))


@router.post("/music/restore-item/{item_id}")
async def restore_item(item_id: str, request: Request, user_id: Optional[str] = Depends(require_user)):
    resolved = await asyncio.to_thread(_resolve_restore_item, item_id, user_id, request)
    if resolved is None:
        raise HTTPException(status_code=404, detail="not found")
    target_id, target_name = resolved
    if target_id == "bad_filename":
        raise HTTPException(status_code=400, detail="bad filename")

    path = manager.original_dir() / target_name
    if not path.exists():
        raise HTTPException(status_code=404, detail="file missing")
    if not user_inflight.try_acquire(user_inflight.user_key("restore", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        def _run():
            try:
                data = path.read_bytes()
            except OSError:
                return None
            return run_restore(data, target_id)

        report = await user_inflight.run_dsp(_run)
        if report is None:
            raise HTTPException(status_code=404, detail="file missing")
        await asyncio.to_thread(_record_restore_owner, report.get("sha", ""), user_id)
        return report
    finally:
        user_inflight.release(user_inflight.user_key("restore", user_id))


@router.get("/music/restored/{sha}")
def download_restored(sha: str, request: Request, db: Session = Depends(get_db)):
    require_sha_audio_access(request, db, sha)
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
    viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
    if not sha_viewable(db, request, sha, viewer=viewer):
        raise HTTPException(status_code=404, detail="not found")
    scope = sha_access_scope(db, sha)
    token = sign_path(f"/api/music/restored/{sha}", scope=scope)
    return {"url": token["url"], "expires": token["expires"]}
