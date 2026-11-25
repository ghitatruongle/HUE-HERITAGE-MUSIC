from __future__ import annotations

import asyncio
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Request

from ..database.session import SessionLocal
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS
from ..database import crud
from ..services import instrument_service, user_inflight
from ..storage import manager
from .auth import require_user, resolve_bearer_user

router = APIRouter(tags=["instruments"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


@router.post("/music/instruments")
async def detect_instruments(request: Request, file: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    if manager.content_length_exceeds(request, MAX_BYTES):
        raise HTTPException(status_code=413, detail="file too large")
    data = await manager.read_upload_limited(file, MAX_BYTES)
    if not user_inflight.try_acquire(user_inflight.user_key("instruments", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        return await user_inflight.run_dsp(instrument_service.detect, data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    finally:
        user_inflight.release(user_inflight.user_key("instruments", user_id))


def _resolve_instrument_item(item_id: str, user_id: Optional[str], request: Request):
    db = SessionLocal()
    try:
        item = crud.get_item(db, item_id)
        if not item:
            return None, 404, "not found"
        viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
        if not crud.can_view_item(item, viewer):
            return None, 404, "not found"
        if not manager.safe_original_name(item.filename):
            return None, 400, "bad filename"
        return item.filename, 200, ""
    finally:
        db.close()


@router.post("/music/instruments-item/{item_id}")
async def detect_item(item_id: str, request: Request, user_id: Optional[str] = Depends(require_user)):
    target_name, status_err, detail_err = await asyncio.to_thread(
        _resolve_instrument_item, item_id, user_id, request
    )
    if status_err != 200:
        raise HTTPException(status_code=status_err, detail=detail_err)

    path = manager.original_dir() / target_name
    if not path.exists():
        raise HTTPException(status_code=404, detail="file missing")
    if not user_inflight.try_acquire(user_inflight.user_key("instruments", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        def _run():
            try:
                data = path.read_bytes()
            except OSError:
                return None
            return instrument_service.detect(data)

        out = await user_inflight.run_dsp(_run)
        if out is None:
            raise HTTPException(status_code=404, detail="file missing")
        return out
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    finally:
        user_inflight.release(user_inflight.user_key("instruments", user_id))
