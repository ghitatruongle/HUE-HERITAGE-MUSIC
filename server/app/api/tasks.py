from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import get_db
from ..database import crud
from ..workers import queue
from .auth import require_user

router = APIRouter(prefix="/task", tags=["tasks"])


@router.post("")
def create_task(body: Optional[dict] = None, kind: str = "generic", db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    if kind in queue.KINDS:
        params = (body or {}).get("params", body or {})
        if not isinstance(params, dict) or not params.get("audio_path"):
            raise HTTPException(status_code=400, detail="params.audio_path required")
        try:
            task_id = queue.dispatch(kind, params, user_id=user_id)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
        return crud.task_to_dict(crud.get_task(db, task_id))
    return crud.task_to_dict(crud.create_task(db, kind, body or {}, user_id=user_id))


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
