import secrets
import threading
import time

import pytest
from fastapi.testclient import TestClient

from app.ai import ace_step_engine
from app.config import settings
from app.database import crud
from app.database.session import SessionLocal
from app.main import create_app
from app.services import generator_service
from app import rate_limit


@pytest.fixture(autouse=True)
def _reset_rate_limit():
    rate_limit.reset()
    yield
    rate_limit.reset()


def _register_and_token(client, username):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": "secret123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    return r.json()["token"]


def test_generation_task_records_user_id(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(ace_step_engine, "api_available", lambda force=False: True)
    monkeypatch.setattr(ace_step_engine, "_release", lambda *a, **k: (_ for _ in ()).throw(ace_step_engine.EngineUnavailable("stub")))
    client = TestClient(create_app())
    token = _register_and_token(client, "owner5")
    r = client.post(
        "/api/music/generate?prompt=x&duration=30",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200, r.text
    tid = r.json()["id"]
    db = SessionLocal()
    try:
        row = crud.get_task(db, tid)
        assert row.user_id is not None
    finally:
        db.close()
    deadline = time.time() + 10
    while time.time() < deadline:
        with generator_service.TASKS_LOCK:
            st = generator_service.TASKS.get(tid, {}).get("status")
        if st not in ("queued", "running", None):
            break
        time.sleep(0.1)
    ok = client.get(f"/api/music/task/{tid}", headers={"Authorization": f"Bearer {token}"})
    assert ok.status_code == 200
    other = _register_and_token(client, "stranger5")
    hidden = client.get(f"/api/music/task/{tid}", headers={"Authorization": f"Bearer {other}"})
    assert hidden.status_code == 404
    anon = client.get(f"/api/music/task/{tid}")
    assert anon.status_code == 401


def test_heavy_rate_limit_429(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 2, raising=False)
    client = TestClient(create_app())
    ok = 0
    limited = 0
    for _ in range(3):
        r = client.post("/api/music/sing-original?heritage_id=x")
        if r.status_code == 429:
            limited += 1
        else:
            ok += 1
    assert ok == 2
    assert limited == 1
    health = client.get("/health")
    assert health.status_code == 200


def test_queue_semaphore_and_cancel(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    monkeypatch.setattr(ace_step_engine, "api_available", lambda force=False: True)
    monkeypatch.setattr(ace_step_engine, "_release", lambda *a, **k: "eng-x")
    monkeypatch.setattr(ace_step_engine, "_query", lambda tid: None)
    client = TestClient(create_app())
    real_semaphore = generator_service._GENERATION_SEMAPHORE
    generator_service._GENERATION_SEMAPHORE = threading.Semaphore(0)
    try:
        r = client.post("/api/music/generate?prompt=x&duration=30")
        assert r.status_code == 200
        tid = r.json()["id"]
        deadline = time.time() + 5
        queued = False
        while time.time() < deadline:
            with generator_service.TASKS_LOCK:
                task = dict(generator_service.TASKS.get(tid, {}))
            if task.get("status") == "queued":
                queued = True
                break
            time.sleep(0.05)
        assert queued
        cancel = client.post(f"/api/music/task/{tid}/cancel")
        assert cancel.status_code == 200
        generator_service._GENERATION_SEMAPHORE.release()
        deadline = time.time() + 5
        final = ""
        while time.time() < deadline:
            with generator_service.TASKS_LOCK:
                final = generator_service.TASKS.get(tid, {}).get("status", "")
            if final == "cancelled":
                break
            time.sleep(0.05)
        assert final == "cancelled"
    finally:
        generator_service._GENERATION_SEMAPHORE = real_semaphore


def test_authed_user_gets_higher_heavy_budget(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 10, raising=False)
    from app.api.auth import hash_password, make_token
    from app.database.session import SessionLocal
    client = TestClient(create_app())
    db = SessionLocal()
    try:
        user = crud.create_user(db, username="heavyuser", email="heavyuser@gmail.com", password_hash=hash_password("secret123"))
        tok = make_token(user.id, user.token_epoch or 0)
    finally:
        db.close()
    codes = []
    for _ in range(25):
        rr = client.post("/api/music/sing-original?heritage_id=x", headers={"Authorization": f"Bearer {tok}"})
        codes.append(rr.status_code)
    assert 429 not in codes, codes
    anon = client.post("/api/music/sing-original?heritage_id=x")
    assert anon.status_code == 401  # auth ON chặn ẩn danh trước khi tới rate limit
