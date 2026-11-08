import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture()
def admin_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-unlock-dos-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    app1 = create_app()
    client = TestClient(app1)
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "a@x.com",
        "password": "UnlockDos#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    TestClient(create_app())
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "UnlockDos#2026"})
    assert r.status_code == 200, r.text
    client.headers.update({"Authorization": "Bearer " + r.json()["token"]})
    yield client
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def test_correct_unlock_always_works_even_after_failure_flood(admin_env):
    client = admin_env
    for i in range(8):
        r = client.post("/api/auth/admin-unlock", json={"password": f"Theft{i}#x"})
        assert r.status_code in (401, 429), f"unlock sai {i}: {r.status_code}"
    r = client.post("/api/auth/admin-unlock", json={"password": "UnlockDos#2026"})
    assert r.status_code == 200, f"CHỦ unlock đúng MK bị chặn: {r.status_code} {r.text[:80]}"
    assert r.json().get("unlocked") is True


def test_wrong_unlock_still_rate_limited_after_correct(admin_env):
    client = admin_env
    r = client.post("/api/auth/admin-unlock", json={"password": "UnlockDos#2026"})
    assert r.status_code == 200
    for i in range(6):
        r = client.post("/api/auth/admin-unlock", json={"password": f"Brute{i}#x"})
    assert r.status_code in (401, 429), f"brute 6 lần phải bị giới hạn: {r.status_code}"
    r = client.post("/api/auth/admin-unlock", json={"password": f"BruteMore{i}#x"})
    assert r.status_code == 429, f"limiter phải giữ: {r.status_code} {r.text[:60]}"


def test_unlock_requires_admin_token(admin_env):
    client = admin_env
    anon = TestClient(create_app())
    r = anon.post("/api/auth/admin-unlock", json={"password": "Whatever#1"})
    assert r.status_code in (401, 403), f"không token vẫn unlock được? {r.status_code}"


def test_sse_events_endpoint_never_500_with_auth(admin_env):
    client = admin_env
    r = client.get("/api/music/task/00000000-0000-0000-0000-000000000000/events")
    assert r.status_code in (200, 404), f"SSE events 500 = regression F1: {r.status_code} {r.text[:80]}"
