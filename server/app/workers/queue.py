import threading

from ..config import settings
from ..database.session import SessionLocal
from ..database import crud
from . import runner

QUEUE_NAME = "hue"
KINDS = ("transcribe", "restore", "instruments")


def redis_available() -> bool:
    try:
        import redis
        r = redis.Redis.from_url(settings.redis_url, socket_connect_timeout=0.5, socket_timeout=0.5)
        return bool(r.ping())
    except Exception:
        return False


def _run_inline(task_id: str, kind: str, params: dict):
    def work():
        db = SessionLocal()
        try:
            crud.update_task(db, task_id, status="running")
            result = runner.run(kind, params)
            crud.update_task(db, task_id, status="done", result=result, finished=True)
        except Exception as e:
            crud.update_task(db, task_id, status="error", error=str(e), finished=True)
        finally:
            db.close()
    threading.Thread(target=work, daemon=True).start()


def _enqueue_rq(task_id: str, kind: str, params: dict) -> bool:
    try:
        from redis import Redis
        from rq import Queue
        q = Queue(QUEUE_NAME, connection=Redis.from_url(settings.redis_url))
        q.enqueue(runner.run_job, task_id, kind, params, job_timeout=600)
        return True
    except Exception:
        return False


def dispatch(kind: str, params: dict) -> str:
    if kind not in KINDS:
        raise ValueError("unsupported kind")
    db = SessionLocal()
    try:
        task = crud.create_task(db, kind, params)
        task_id = task.id
    finally:
        db.close()
    if not _enqueue_rq(task_id, kind, params):
        _run_inline(task_id, kind, params)
    return task_id
