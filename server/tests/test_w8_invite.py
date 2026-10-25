from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.session import SessionLocal
from app.main import create_app


def _register(client, username, code):
    return client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": "secret123",
            "invite_code": code,
        },
    )


def test_one_time_invite_code_single_use(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    db = SessionLocal()
    try:
        crud.create_invite_code(db, "ONETIME-XYZ", "test one-time")
    finally:
        db.close()

    first = _register(client, "inv1", "ONETIME-XYZ")
    assert first.status_code == 200

    second = _register(client, "inv2", "ONETIME-XYZ")
    assert second.status_code == 400

    db = SessionLocal()
    try:
        row = crud.get_invite_code(db, "ONETIME-XYZ")
        assert row.used_by is not None
    finally:
        db.close()


def test_static_file_code_still_multi_use(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    a = _register(client, "filecode1", "QHH2026")
    b = _register(client, "filecode2", "QHH2026")
    assert a.status_code == 200
    assert b.status_code == 200


def test_unknown_code_rejected(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    r = _register(client, "nocode", "DOES-NOT-EXIST")
    assert r.status_code == 400
