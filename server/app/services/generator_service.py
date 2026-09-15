import threading
import time

from ..ai import ace_step_engine, lora_adapter
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
        saved = crud.create_task(db, kind, params)
        tid = saved.id
        if reason:
            crud.update_task(db, saved.id, status=status, error=reason, finished=True)
        else:
            crud.update_task(db, saved.id, status="running")
    finally:
        db.close()
    task = {"id": tid, "kind": kind, "status": status, "created_at": time.time()}
    if reason:
        task["reason"] = reason
    task["task_db_id"] = tid
    if len(TASKS) >= MAX_TASKS:
        oldest = [k for k in sorted(TASKS, key=lambda k: TASKS[k]["created_at"]) if TASKS[k].get("status") != "running"]
        for k in oldest[: max(0, len(TASKS) - MAX_TASKS + 1)]:
            TASKS.pop(k, None)
    TASKS[tid] = task
    if status == "running":
        threading.Thread(
            target=_run_generation,
            args=(tid, tid, prompt, duration, seed, lora, strength, extra),
            daemon=True,
        ).start()
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


def _run_generation(tid, db_task_id, prompt, duration, seed, lora="", strength=0.8, extra=None):
    db = SessionLocal()
    try:
        engine_prompt = _fold_extra(prompt, extra or {})
        result = ace_step_engine.generate(engine_prompt, duration, seed, lora=lora, strength=strength)
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
    cached = TASKS.get(task_id)
    if cached:
        return cached
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
                payload["audio_url"] = audio_url
            if result.get("info"):
                payload["info"] = result.get("info")
        return payload
    finally:
        db.close()
