import time
import uuid

from ..ai import ace_step_engine, lora_adapter
from ..ai.ace_step_engine import EngineUnavailable

TASKS = {}
MAX_TASKS = 200


def models_info():
    st = ace_step_engine.status()
    return {
        "base": st["engine"],
        "base_ready": st["weights_found"],
        "adapters": lora_adapter.list_adapters(),
    }


def create_task(kind, prompt, duration, lora, strength, seed):
    tid = str(uuid.uuid4())
    if lora and not lora_adapter.resolve(lora):
        task = {"id": tid, "kind": kind, "status": "rejected", "reason": "lora not found", "created_at": time.time()}
        TASKS[tid] = task
        return task
    try:
        ace_step_engine.generate(prompt, duration, seed)
        task = {"id": tid, "kind": kind, "status": "running", "created_at": time.time()}
    except EngineUnavailable as e:
        task = {"id": tid, "kind": kind, "status": "blocked", "reason": str(e), "created_at": time.time()}
    if len(TASKS) >= MAX_TASKS:
        oldest = sorted(TASKS, key=lambda k: TASKS[k]["created_at"])
        for k in oldest[: len(TASKS) - MAX_TASKS + 1]:
            TASKS.pop(k, None)
    TASKS[tid] = task
    return task


def get_task(task_id):
    return TASKS.get(task_id)
