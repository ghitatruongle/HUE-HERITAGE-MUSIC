from __future__ import annotations

import asyncio
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import instrument_service
from ..storage import manager
from .auth import require_user, resolve_bearer_user

router = APIRouter(tags=["instruments"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


@router.post("/music/instruments")
async def detect_instruments(file: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    try:
        return await asyncio.to_thread(instrument_service.detect, data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")


@router.post("/music/instruments-item/{item_id}")
def detect_item(item_id: str, request: Request, db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
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
    try:
        return instrument_service.detect(data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
