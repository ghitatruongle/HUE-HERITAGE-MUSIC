import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app
from app.api import auth as auth_api


@pytest.fixture(autouse=True)
def _wipe_users():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    with auth_api._auth_failures_lock:
        auth_api._auth_failures.clear()
    yield


def _register(client, username, code="TESTINVITE"):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": "secret123",
            "invite_code": code,
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def _login(client, identifier):
    r = client.post("/api/auth/login", json={"identifier": identifier, "password": "secret123"})
    assert r.status_code == 200, r.text
    return r.json()


def test_register_creates_user_role(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    body = _register(client, "roleuser1")
    assert body["role"] == "user"
    logged = _login(client, "roleuser1")
    assert logged["role"] == "user"


def test_admin_truong_promoted_on_startup(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    logged = _login(client, settings.admin_truong_username)
    assert logged["role"] == "user"

    client = TestClient(create_app())
    promoted = _login(client, settings.admin_truong_username)
    assert promoted["role"] == "admin"


def test_foreign_admin_demoted_on_startup(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    _register(client, "fakeadmin")
    db = SessionLocal()
    try:
        user = crud.get_user(db, "fakeadmin")
        user.role = "admin"
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    db = SessionLocal()
    try:
        assert (crud.get_user(db, "fakeadmin").role or "user") == "user"
    finally:
        db.close()


def test_users_endpoint_admin_only(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    _register(client, "plainuser2")
    client = TestClient(create_app())

    anon = client.get("/api/auth/users")
    assert anon.status_code == 401

    user_token = _login(client, "plainuser2")["token"]
    forbidden = client.get("/api/auth/users", headers={"Authorization": f"Bearer {user_token}"})
    assert forbidden.status_code == 403

    admin_token = _login(client, settings.admin_truong_username)["token"]
    ok = client.get("/api/auth/users", headers={"Authorization": f"Bearer {admin_token}"})
    assert ok.status_code == 200
    rows = {u["username"]: u["role"] for u in ok.json()["items"]}
    assert rows[settings.admin_truong_username] == "admin"
    assert rows["plainuser2"] == "user"


def test_me_returns_role(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    client = TestClient(create_app())
    token = _login(client, settings.admin_truong_username)["token"]
    r = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    assert r.json()["role"] == "admin"
