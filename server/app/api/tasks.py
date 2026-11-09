from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import get_db
from ..database import crud
from ..database.models import AudioFile
from ..workers import queue
from .auth import require_user, resolve_bearer_user

router = APIRouter(prefix="/task", tags=["tasks"])


def _item_original_audio(db: Session, heritage_id: str):
    item = crud.get_item(db, heritage_id)
    if item is None:
        return None, None
    row = (
        db.query(AudioFile)
        .filter(AudioFile.item_id == item.id, AudioFile.kind == "original")
        .first()
    )
    return item, (row.path if row else None)


@router.post("")
def create_task(request: Request, body: Optional[dict] = None, kind: str = "generic", db: Session = Depends(get_db), user_id: Optional[str] = Depends(require_user)):
    params = (body or {}).get("params", body or {})
    if not isinstance(params, dict):
        raise HTTPException(status_code=400, detail="params must be an object")
    heritage_id = str((body or {}).get("heritage_id") or params.get("heritage_id") or "")
    if kind in queue.KINDS:
        if not heritage_id:
            raise HTTPException(status_code=400, detail="heritage_id required")
        item, audio_path = _item_original_audio(db, heritage_id)
        if item is None:
            raise HTTPException(status_code=404, detail="not found")
        viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
        if not crud.can_view_item(item, viewer):
            raise HTTPException(status_code=404, detail="not found")
        if not audio_path:
            raise HTTPException(status_code=400, detail="item has no original audio")
        merged = dict(params)
        merged.pop("audio_path", None)
        merged["audio_path"] = audio_path
        try:
            task_id = queue.dispatch(kind, merged, user_id=user_id)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
        return crud.task_to_dict(crud.get_task(db, task_id))
    if heritage_id:
        item = crud.get_item(db, heritage_id)
        if item is None:
            raise HTTPException(status_code=404, detail="not found")
        viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
        if not crud.can_view_item(item, viewer):
            raise HTTPException(status_code=404, detail="not found")
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
