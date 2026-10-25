import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.session import SessionLocal
from app.main import create_app
from app.api import auth as auth_api


@pytest.fixture(autouse=True)
def _wipe_users():
    from app.database.models import User, InviteCode

    db = SessionLocal()
    try:
        db.query(InviteCode).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    with auth_api._auth_failures_lock:
        auth_api._auth_failures.clear()
    yield


def _register(client, username):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": "secret123",
            "invite_code": "QHH2026",
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def _login(client, identifier):
    r = client.post("/api/auth/login", json={"identifier": identifier, "password": "secret123"})
    assert r.status_code == 200
    return r.json()["token"]


def _setup_admin(client):
    _register(client, settings.admin_truong_username)
    client = TestClient(create_app())
    return _login(client, settings.admin_truong_username)


def test_invite_crud_admin_only(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    _register(client, "invplain")
    client = TestClient(create_app())
    admin_token = _login(client, settings.admin_truong_username)
    user_token = _login(client, "invplain")

    anon_list = client.get("/api/auth/invites")
    assert anon_list.status_code == 401
    forbidden = client.get("/api/auth/invites", headers={"Authorization": f"Bearer {user_token}"})
    assert forbidden.status_code == 403

    created = client.post(
        "/api/auth/invites",
        json={"code": "", "note": "cho bạn A"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert created.status_code == 200
    body = created.json()
    assert body["code"].startswith("HUE-") and len(body["code"]) == 12
    assert body["used"] is False

    dup = client.post(
        "/api/auth/invites",
        json={"code": body["code"]},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert dup.status_code == 409

    custom = client.post(
        "/api/auth/invites",
        json={"code": "MACHUNGCHI"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert custom.status_code == 200
    assert custom.json()["code"] == "MACHUNGCHI"

    listing = client.get("/api/auth/invites", headers={"Authorization": f"Bearer {admin_token}"})
    assert listing.status_code == 200
    codes = {x["code"] for x in listing.json()}
    assert body["code"] in codes and "MACHUNGCHI" in codes

    deleted = client.delete(
        f"/api/auth/invites/{custom.json()['id']}",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert deleted.status_code == 200
    listing2 = client.get("/api/auth/invites", headers={"Authorization": f"Bearer {admin_token}"})
    assert "MACHUNGCHI" not in {x["code"] for x in listing2.json()}

    missing = client.delete(
        "/api/auth/invites/nonexistent",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert missing.status_code == 404


def test_invite_created_via_admin_registers_once(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    client = TestClient(create_app())
    admin_token = _login(client, settings.admin_truong_username)

    created = client.post(
        "/api/auth/invites",
        json={"note": "e2e"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    code = created.json()["code"]

    first = client.post(
        "/api/auth/register",
        json={"username": "invited1", "email": "invited1@gmail.com", "password": "secret123", "invite_code": code},
    )
    assert first.status_code == 200
    second = client.post(
        "/api/auth/register",
        json={"username": "invited2", "email": "invited2@gmail.com", "password": "secret123", "invite_code": code},
    )
    assert second.status_code == 400
