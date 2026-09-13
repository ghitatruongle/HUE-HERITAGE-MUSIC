import threading
import time
import uuid

from ..ai import ace_step_engine, lora_adapter
from ..ai.ace_step_engine import EngineUnavailable
from ..database.session import SessionLocal
from ..database import crud
from ..storage import manager

TASKS = {}
MAX_TASKS = 200


def models_info():
    st = ace_step_engine.status()
    return {
        "base": st["engine"],
        "base_ready": st["weights_found"],
        "mode": st.get("mode", ""),
        "adapters": lora_adapter.list_adapters(),
    }


def create_task(kind, prompt, duration, lora, strength, seed, extra=None):
    tid = str(uuid.uuid4())
    extra = extra or {}
    reason = ""
    if lora and not lora_adapter.resolve(lora):
        status = "rejected"
        reason = "lora not found"
    elif not ace_step_engine.api_available():
        status = "blocked"
        reason = "engine offline (acestep-api not reachable)"
    else:
        status = "running"
    task = {"id": tid, "kind": kind, "status": status, "created_at": time.time()}
    if reason:
        task["reason"] = reason
    if len(TASKS) >= MAX_TASKS:
        oldest = sorted(TASKS, key=lambda k: TASKS[k]["created_at"])
        for k in oldest[: len(TASKS) - MAX_TASKS + 1]:
            TASKS.pop(k, None)
    TASKS[tid] = task
    params = {"prompt": prompt, "duration": duration, "lora": lora, "strength": strength, "seed": seed, **extra}
    db = SessionLocal()
    try:
        saved = crud.create_task(db, kind, params)
        if reason:
            crud.update_task(db, saved.id, status=status, error=reason, finished=True)
        else:
            crud.update_task(db, saved.id, status="running")
    finally:
        db.close()
    task["task_db_id"] = saved.id
    if status == "running":
        threading.Thread(target=_run_generation, args=(tid, saved.id, prompt, duration, seed), daemon=True).start()
    return task


def _run_generation(tid, db_task_id, prompt, duration, seed):
    db = SessionLocal()
    try:
        result = ace_step_engine.generate(prompt, duration, seed)
        dest = manager.generated_dir() / f"{tid}.mp3"
        dest.write_bytes(result["audio"])
        audio_url = f"/api/music/generated/{tid}.mp3"
        task = TASKS.get(tid)
        if task is not None:
            task["status"] = "done"
            task["audio_url"] = audio_url
            task["info"] = result.get("info", "")
        crud.update_task(db, db_task_id, status="done", result={"audio_url": audio_url, "info": result.get("info", "")}, finished=True)
    except Exception as e:
        task = TASKS.get(tid)
        if task is not None:
            task["status"] = "error"
            task["reason"] = str(e)
        crud.update_task(db, db_task_id, status="error", error=str(e), finished=True)
    finally:
        db.close()


def get_task(task_id):
    return TASKS.get(task_id)
