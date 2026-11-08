from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..database import crud
from ..database.session import acquire_write_slot, get_db
from .auth import require_user

router = APIRouter(prefix="/crash-reports", tags=["crash-reports"])

MAX_DETAIL_BYTES = 256 * 1024


class CrashReportRequest(BaseModel):
    app_version: str = Field(default="", max_length=64)
    platform: str = Field(default="", max_length=64)
    summary: str = Field(default="", max_length=500)
    detail: str = Field(default="")


@router.post("")
def submit_crash_report(
    body: CrashReportRequest,
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(require_user),
    _write_slot: None = Depends(acquire_write_slot),
):
    if not (body.summary or body.detail):
        raise HTTPException(status_code=400, detail="empty crash report")
    if len(body.detail.encode("utf-8", errors="replace")) > MAX_DETAIL_BYTES:
        raise HTTPException(status_code=413, detail="crash detail too large")
    report_id = crud.create_crash_report(
        db, user_id, body.app_version, body.platform, body.summary, body.detail
    )
    return {"id": report_id, "received": True}
