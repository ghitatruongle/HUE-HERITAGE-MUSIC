from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import get_db
from ..database import crud
from ..workers import queue
from .auth import require_user, resolve_bearer_user

router = APIRouter(prefix="/task", tags=["tasks"])


def _item_for_audio_path(db: Session, raw_path: str):
    from ..database.models import AudioFile
    from ..workers.runner import _safe_audio_path

    path = _safe_audio_path({"audio_path": raw_path})
    rows = db.query(AudioFile).filter(AudioFile.path.like(f"%{path.name}")).all()
    for row in rows:
        try:
            if Path(row.path).resolve() == path:
                return crud.get_item(db, row.item_id)
        except OSError:
            continue
    return None


@router.post("")
def create_task(request: Request, body: Optional[dict] = None, kind: str = "generic", db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    if kind in queue.KINDS:
        params = (body or {}).get("params", body or {})
        if not isinstance(params, dict) or not params.get("audio_path"):
            raise HTTPException(status_code=400, detail="params.audio_path required")
        try:
            item = _item_for_audio_path(db, params.get("audio_path"))
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
        if item is not None:
            viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
            if not crud.can_view_item(item, viewer):
                raise HTTPException(status_code=404, detail="not found")
        try:
            task_id = queue.dispatch(kind, params, user_id=user_id)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
        return crud.task_to_dict(crud.get_task(db, task_id))
    task = crud.create_task(db, kind, body or {}, user_id=user_id)
    crud.update_task(db, task.id, status="done", result={"accepted": True}, finished=True)
    return crud.task_to_dict(crud.get_task(db, task.id))


@router.get("")
def list_tasks(kind: str = "", status: str = "", limit: int = 100, db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    owner = user_id if settings.auth_required else None
    tasks = crud.list_tasks(db, kind, status, max(1, min(limit, 500)), user_id=owner)
    return [crud.task_to_dict(t) for t in tasks]


@router.get("/{task_id}")
def get_task(task_id: str, db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    task = crud.get_task(db, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    if settings.auth_required and task.user_id is not None and task.user_id != user_id:
        raise HTTPException(status_code=404, detail="not found")
    return crud.task_to_dict(task)
