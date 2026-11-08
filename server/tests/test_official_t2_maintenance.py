import threading

from sqlalchemy import text

from app.database.session import SessionLocal, engine
from app.services import maintenance


def test_run_maintenance_returns_all_groups():
    db = SessionLocal()
    try:
        result = maintenance.run_maintenance(db)
    finally:
        db.close()
    expected = {
        "generated", "practice_midi", "analysis", "lesson_cache",
        "restored", "musicxml", "lesson_samples_orphan", "tasks", "crash_reports",
    }
    assert expected <= set(result["details"].keys())
    assert isinstance(result["freed_bytes"], int)
    assert result["freed_bytes"] >= 0


def test_schema_meta_version_pinned():
    with engine.connect() as conn:
        row = conn.execute(text("SELECT value FROM schema_meta WHERE key='schema_version'")).fetchone()
    assert row is not None
    assert row[0] == "1"


def test_worker_pool_executes_submitted_work():
    from app.workers.pool import WorkerPool

    pool = WorkerPool("t2-test", 2)
    box = []
    done = threading.Event()
    pool.submit(lambda: (box.append(1), done.set()))
    assert done.wait(timeout=5)
    assert box == [1]


def test_worker_pool_survives_base_exception():
    from app.workers.pool import WorkerPool

    pool = WorkerPool("t2-baseexc", 1)
    box = []
    done = threading.Event()

    def _boom():
        raise SystemExit(1)

    pool.submit(_boom)
    pool.submit(lambda: (box.append(1), done.set()))
    assert done.wait(timeout=5)
    assert box == [1]


def test_crash_report_path_in_heavy_rate_limit():
    from app.main import HEAVY_POST_PATHS

    assert "/api/crash-reports" in HEAVY_POST_PATHS


def test_worker_pool_reuses_named_pool():
    from app.workers.pool import get_pool

    a = get_pool("t2-named", 3)
    b = get_pool("t2-named", 5)
    assert a is b
    assert a._size == 3


def test_task_queue_wired_to_pool():
    from app.workers import queue as task_queue

    assert callable(task_queue.dispatch)
    assert hasattr(task_queue, "get_pool")
