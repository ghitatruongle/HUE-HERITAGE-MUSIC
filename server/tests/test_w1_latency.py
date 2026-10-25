import time

from fastapi.testclient import TestClient

from app.ai import ace_step_engine
from app.main import create_app
from app.services import generator_service


def test_availability_cached_within_ttl(monkeypatch):
    calls = {"n": 0}

    def fake_check():
        calls["n"] += 1
        return True

    ace_step_engine.invalidate_availability()
    monkeypatch.setattr(ace_step_engine, "_check_available", fake_check)
    assert ace_step_engine.api_available() is True
    assert ace_step_engine.api_available() is True
    assert calls["n"] == 1
    assert ace_step_engine.api_available(force=True) is True
    assert calls["n"] == 2


def test_status_single_health_check(monkeypatch):
    calls = {"n": 0}

    def fake_check():
        calls["n"] += 1
        return True

    ace_step_engine.invalidate_availability()
    monkeypatch.setattr(ace_step_engine, "_check_available", fake_check)
    st = ace_step_engine.status()
    assert st["loaded"] is True
    assert st["weights_found"] is True
    assert calls["n"] == 1


def test_cancel_unknown_task_404():
    client = TestClient(create_app())
    r = client.post("/api/music/task/nope/cancel")
    assert r.status_code == 404


def test_cancel_running_task_marks_request():
    tid = "task-cancel-1"
    with generator_service.TASKS_LOCK:
        generator_service.TASKS[tid] = {
            "id": tid,
            "kind": "generate",
            "status": "running",
            "created_at": time.time(),
        }
    try:
        result = generator_service.cancel_task(tid)
        assert result["cancel_requested"] is True
        client = TestClient(create_app())
        r = client.post(f"/api/music/task/{tid}/cancel")
        assert r.status_code == 200
        assert r.json()["cancel_requested"] is True
    finally:
        with generator_service.TASKS_LOCK:
            generator_service.TASKS.pop(tid, None)


def test_cancel_finished_task_keeps_status():
    tid = "task-cancel-2"
    with generator_service.TASKS_LOCK:
        generator_service.TASKS[tid] = {
            "id": tid,
            "kind": "generate",
            "status": "done",
            "created_at": time.time(),
        }
    try:
        result = generator_service.cancel_task(tid)
        assert result["status"] == "done"
        assert "cancel_requested" not in result
    finally:
        with generator_service.TASKS_LOCK:
            generator_service.TASKS.pop(tid, None)


def test_generate_respects_cancel(monkeypatch):
    monkeypatch.setattr(ace_step_engine, "api_available", lambda force=False: True)
    monkeypatch.setattr(ace_step_engine, "_release", lambda *a, **k: "eng-1")
    monkeypatch.setattr(ace_step_engine, "_query", lambda tid: None)
    raised = False
    try:
        ace_step_engine.generate("p", 30, should_cancel=lambda: True)
    except ace_step_engine.GenerationCancelled:
        raised = True
    assert raised
