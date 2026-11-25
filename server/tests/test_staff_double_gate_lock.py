import secrets

import pytest
from fastapi.testclient import TestClient

from app.api import auth as auth_api
from app.config import settings
from app.database import crud
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture(autouse=True)
def _clean_db():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    with auth_api._auth_failures_lock:
        auth_api._auth_failures.clear()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _register(client, username, password="UserPass#2026"):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@example.local",
            "password": password,
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_db_promoted_ghost_admin_blocked_by_staff_and_role_gates(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username, "AdminPass#2026x")
    ghost = _register(client, "ghostadmin1", "GhostPass#2026x")
    client = TestClient(create_app())

    admin_login = client.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "AdminPass#2026x"},
    )
    assert admin_login.status_code == 200
    admin_tok = admin_login.json()["token"]
    assert client.post(
        "/api/auth/admin-unlock",
        json={"password": "AdminPass#2026x"},
        headers={"Authorization": f"Bearer {admin_tok}"},
    ).status_code == 200

    assert client.post(
        "/api/auth/users",
        json={"username": "workerlock1", "password": "WorkerPass#2026x", "role": "worker"},
        headers={"Authorization": f"Bearer {admin_tok}"},
    ).status_code == 200
    w_login = client.post(
        "/api/auth/login",
        json={"identifier": "workerlock1", "password": "WorkerPass#2026x"},
    ).json()["token"]
    w_chg = client.post(
        "/api/auth/change-password",
        json={"old_password": "WorkerPass#2026x", "new_password": "WorkerPass#2026y"},
        headers={"Authorization": f"Bearer {w_login}"},
    )
    assert w_chg.status_code == 200
    worker_tok = w_chg.json()["token"]

    db = SessionLocal()
    try:
        user_row = crud.get_user_by_id(db, ghost["id"])
        user_row.role = "admin"
        db.commit()
    finally:
        db.close()

    ghost_headers = {"Authorization": f"Bearer {ghost['token']}"}
    assert client.get("/api/admin/stats", headers=ghost_headers).status_code == 403
    assert client.get("/api/admin/storage", headers=ghost_headers).status_code == 403
    assert client.get("/api/admin/learning/stats", headers=ghost_headers).status_code == 403
    assert client.get("/api/auth/users", headers=ghost_headers).status_code == 403
    assert client.post("/api/auth/invites", json={"note": "x"}, headers=ghost_headers).status_code == 403
    assert client.get("/api/admin/crash-reports", headers=ghost_headers).status_code == 403
    me_ghost = client.get("/api/auth/me", headers=ghost_headers)
    assert me_ghost.status_code == 200
    assert me_ghost.json()["role"] == "user"

    worker_headers = {"Authorization": f"Bearer {worker_tok}"}
    assert client.get("/api/admin/stats", headers=worker_headers).status_code == 200
    assert client.get("/api/admin/storage", headers=worker_headers).status_code == 200
    assert client.get("/api/auth/users", headers=worker_headers).status_code == 200
    assert client.post("/api/auth/invites", json={"note": "w"}, headers=worker_headers).status_code == 200

    admin_headers = {"Authorization": f"Bearer {admin_tok}"}
    assert client.get("/api/admin/stats", headers=admin_headers).status_code == 200
    assert client.get("/api/admin/storage", headers=admin_headers).status_code == 200

    db = SessionLocal()
    try:
        user_row = crud.get_user_by_id(db, ghost["id"])
        user_row.role = "user"
        db.commit()
        crud.bump_token_epoch(db, ghost["id"])
    finally:
        db.close()

    assert client.get("/api/auth/me", headers=ghost_headers).status_code == 401
    assert client.get("/api/admin/stats", headers=ghost_headers).status_code == 401
