from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database.session import get_db, init_db
from ..database import crud
from ..workers import queue

router = APIRouter(prefix="/task", tags=["tasks"])
init_db()


@router.post("")
def create_task(body: dict | None = None, kind: str = "generic", db: Session = Depends(get_db)):
    if body and kind in queue.KINDS:
        params = body.get("params", body)
        task_id = queue.dispatch(kind, params)
        return crud.task_to_dict(crud.get_task(db, task_id))
    return crud.task_to_dict(crud.create_task(db, kind, body or {}))


@router.get("")
def list_tasks(kind: str = "", status: str = "", limit: int = 100, db: Session = Depends(get_db)):
    tasks = crud.list_tasks(db, kind, status, max(1, min(limit, 500)))
    return [crud.task_to_dict(t) for t in tasks]


@router.get("/{task_id}")
def get_task(task_id: str, db: Session = Depends(get_db)):
    task = crud.get_task(db, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    return crud.task_to_dict(task)
