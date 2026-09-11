import time
import uuid

from fastapi import APIRouter, HTTPException

router = APIRouter(prefix="/task", tags=["tasks"])
MAX_TASKS = 500
_tasks = {}


@router.post("")
def create_task(kind: str = "generic"):
    tid = str(uuid.uuid4())
    if len(_tasks) >= MAX_TASKS:
        oldest = sorted(_tasks, key=lambda k: _tasks[k]["created_at"])
        for k in oldest[: len(_tasks) - MAX_TASKS + 1]:
            _tasks.pop(k, None)
    _tasks[tid] = {"id": tid, "kind": kind, "status": "pending", "created_at": time.time()}
    return _tasks[tid]


@router.get("/{task_id}")
def get_task(task_id: str):
    found = _tasks.get(task_id)
    if not found:
        raise HTTPException(status_code=404, detail="not found")
    return found
