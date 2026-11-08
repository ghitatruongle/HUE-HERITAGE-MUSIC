import threading
import time

from ..ai import ace_step_engine, lora_adapter
from ..audio_access import sign_path
from ..config import settings
from ..database.session import SessionLocal
from ..database import crud
from ..storage import manager

TASKS = {}
TASKS_LOCK = threading.Lock()
MAX_TASKS = 200

_GENERATION_SEMAPHORE = threading.Semaphore(max(1, settings.generation_concurrency))
_QUEUE_LOCK = threading.Lock()
_QUEUE_WAITING = 0


def models_info():
    st = ace_step_engine.status()
    return {
        "base": st["engine"],
        "base_ready": st["weights_found"],
        "mode": st.get("mode", ""),
        "adapters": lora_adapter.list_adapters(),
    }


def create_task(kind, prompt, duration, lora, strength, seed, extra=None, user_id=None):
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
    params = {"prompt": prompt, "duration": duration, "lora": lora, "strength": strength, "seed": seed, **extra}
    db = SessionLocal()
    try:
        saved = crud.create_task(db, kind, params, user_id=user_id)
        tid = saved.id
        if reason:
            crud.update_task(db, saved.id, status=status, error=reason, finished=True)
        else:
            crud.update_task(db, saved.id, status="running")
    finally:
        db.close()
    task = {"id": tid, "kind": kind, "status": status, "created_at": time.time(), "user_id": user_id}
    if reason:
        task["reason"] = reason
    task["task_db_id"] = tid
    with TASKS_LOCK:
        if len(TASKS) >= MAX_TASKS:
            oldest = [k for k in sorted(TASKS, key=lambda k: TASKS[k]["created_at"]) if TASKS[k].get("status") != "running"]
            for k in oldest[: max(0, len(TASKS) - MAX_TASKS + 1)]:
                TASKS.pop(k, None)
        TASKS[tid] = task
    if status == "running":
        from ..workers.pool import get_pool

        get_pool("generation", max(2, settings.generation_concurrency + 1)).submit(
            lambda: _run_generation(tid, tid, prompt, duration, seed, lora, strength, extra)
        )
    return task


def _fold_extra(prompt: str, extra: dict) -> str:
    if not extra:
        return prompt
    bits = [prompt]
    for key in ("lyrics", "genre", "instruments", "tempo", "mood", "vocal"):
        val = extra.get(key)
        if val not in (None, ""):
            bits.append(f"{key}: {val}")
    return "; ".join(bits)


def _enter_generation_queue(tid, db, db_task_id):
    global _QUEUE_WAITING
    with _QUEUE_LOCK:
        _QUEUE_WAITING += 1
        position = _QUEUE_WAITING
    with TASKS_LOCK:
        task = TASKS.get(tid)
        if task is not None:
            task["status"] = "queued"
            if position > 1:
                task["queue_position"] = position - 1
    try:
        crud.update_task(db, db_task_id, status="queued")
        _GENERATION_SEMAPHORE.acquire()
    finally:
        with _QUEUE_LOCK:
            _QUEUE_WAITING -= 1
    with TASKS_LOCK:
        task = TASKS.get(tid)
        if task is not None:
            task["status"] = "running"
            task.pop("queue_position", None)


def _run_generation(tid, db_task_id, prompt, duration, seed, lora="", strength=0.8, extra=None):
    def _cancelled():
        with TASKS_LOCK:
            task = TASKS.get(tid)
            return bool(task and task.get("cancel_requested"))

    db = SessionLocal()
    entered = False
    try:
        _enter_generation_queue(tid, db, db_task_id)
        entered = True
        if _cancelled():
            raise ace_step_engine.GenerationCancelled("cancelled while queued")
        crud.update_task(db, db_task_id, status="running")
        engine_prompt = _fold_extra(prompt, extra or {})
        result = ace_step_engine.generate(
            engine_prompt, duration, seed, lora=lora, strength=strength, should_cancel=_cancelled
        )
        dest = manager.generated_dir() / f"{tid}.mp3"
        dest.write_bytes(result["audio"])
        audio_url = f"/api/music/generated/{tid}.mp3"
        with TASKS_LOCK:
            task = TASKS.get(tid)
            if task is not None:
                task["status"] = "done"
                task["audio_url"] = audio_url
                task["info"] = result.get("info", "")
        crud.update_task(db, db_task_id, status="done", result={"audio_url": audio_url, "info": result.get("info", "")}, finished=True)
    except ace_step_engine.GenerationCancelled:
        with TASKS_LOCK:
            task = TASKS.get(tid)
            if task is not None:
                task["status"] = "cancelled"
                task.pop("cancel_requested", None)
        crud.update_task(db, db_task_id, status="cancelled", error="cancelled by user", finished=True)
    except Exception as e:
        ace_step_engine.invalidate_availability()
        with TASKS_LOCK:
            task = TASKS.get(tid)
            if task is not None:
                task["status"] = "error"
                task["reason"] = str(e)
        crud.update_task(db, db_task_id, status="error", error=str(e), finished=True)
    finally:
        if entered:
            _GENERATION_SEMAPHORE.release()
        db.close()


def cancel_task(task_id):
    with TASKS_LOCK:
        task = TASKS.get(task_id)
        if task is not None:
            if task.get("status") in ("running", "pending", "queued"):
                task["cancel_requested"] = True
            return dict(task)
    db = SessionLocal()
    try:
        row = crud.get_task(db, task_id)
        if not row:
            return None
        if row.status in ("running", "pending", "queued"):
            crud.update_task(db, task_id, status="cancelled", error="cancelled by user", finished=True)
            row = crud.get_task(db, task_id)
        return crud.task_to_dict(row)
    finally:
        db.close()


def _signed_audio_url(audio_url):
    if not audio_url:
        return audio_url
    if not settings.auth_required:
        return audio_url
    path = audio_url.split("?")[0]
    return sign_path(path)["url"]


def get_task(task_id):
    with TASKS_LOCK:
        cached = TASKS.get(task_id)
        if cached:
            payload = dict(cached)
            if payload.get("audio_url"):
                payload["audio_url"] = _signed_audio_url(payload["audio_url"])
            return payload
    db = SessionLocal()
    try:
        task = crud.get_task(db, task_id)
        if not task:
            return None
        payload = crud.task_to_dict(task)
        if task.kind:
            result = payload.get("result") or {}
            audio_url = result.get("audio_url")
            if audio_url:
                payload["audio_url"] = _signed_audio_url(audio_url)
            if result.get("info"):
                payload["info"] = result.get("info")
        return payload
    finally:
        db.close()
