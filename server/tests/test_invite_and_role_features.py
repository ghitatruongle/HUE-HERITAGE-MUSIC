import concurrent.futures
import secrets
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

from app.api import auth as auth_api
from app.config import settings
from app.database import crud
from app.database.models import InviteCode, User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture(autouse=True)
def _clean_db():
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
    db = SessionLocal()
    try:
        db.query(InviteCode).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _register(client, username, invite_code="TESTINVITE", password="UserPass#2026"):
    return client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@example.local",
            "password": password,
            "invite_code": invite_code,
        },
    )


def _setup_admin(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    assert _register(client, settings.admin_truong_username, password="AdminPass#2026").status_code == 200
    client = TestClient(create_app())
    tok = client.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "AdminPass#2026"},
    ).json()["token"]
    assert client.post(
        "/api/auth/admin-unlock",
        json={"password": "AdminPass#2026"},
        headers={"Authorization": f"Bearer {tok}"},
    ).status_code == 200
    return client, {"Authorization": f"Bearer {tok}"}


def test_multi_use_invite_and_concurrency_cap(monkeypatch):
    client, adm_h = _setup_admin(monkeypatch)
    r_inv = client.post(
        "/api/auth/invites",
        json={"note": "multi-3", "max_uses": 3},
        headers=adm_h,
    )
    assert r_inv.status_code == 200, r_inv.text
    inv = r_inv.json()
    assert inv["max_uses"] == 3
    assert inv["used_count"] == 0
    assert inv["remaining_uses"] == 3
    assert inv["active"] is True
    code = inv["code"]

    def reg_worker(i):
        return _register(client, f"multiuser{i}", invite_code=code).status_code

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        codes = list(ex.map(reg_worker, range(6)))

    assert codes.count(200) == 3, codes
    assert all(c in (200, 400, 409) for c in codes), codes

    listed = client.get("/api/auth/invites", headers=adm_h).json()["items"]
    match = [x for x in listed if x["code"] == code][0]
    assert match["used_count"] == 3
    assert match["remaining_uses"] == 0
    assert match["used"] is True
    assert match["active"] is False


def test_unlimited_and_expiring_invites_for_admin_and_worker(monkeypatch):
    client, adm_h = _setup_admin(monkeypatch)
    r_w = client.post(
        "/api/auth/users",
        json={"username": "workerinv1", "password": "WorkerPass#2026", "role": "worker"},
        headers=adm_h,
    )
    assert r_w.status_code == 200
    w_tok_tmp = client.post(
        "/api/auth/login",
        json={"identifier": "workerinv1", "password": "WorkerPass#2026"},
    ).json()["token"]
    w_tok = client.post(
        "/api/auth/change-password",
        json={"old_password": "WorkerPass#2026", "new_password": "WorkerPass#2026y"},
        headers={"Authorization": f"Bearer {w_tok_tmp}"},
    ).json()["token"]
    w_h = {"Authorization": f"Bearer {w_tok}"}

    unlim = client.post(
        "/api/auth/invites",
        json={"note": "open-demo", "max_uses": 0, "expires_minutes": 120},
        headers=w_h,
    )
    assert unlim.status_code == 200, unlim.text
    ub = unlim.json()
    assert ub["max_uses"] == 0
    assert ub["remaining_uses"] is None
    assert ub["expires_at"] is not None
    assert ub["expired"] is False
    assert ub["active"] is True

    assert _register(client, "unlimu1", invite_code=ub["code"]).status_code == 200
    assert _register(client, "unlimu2", invite_code=ub["code"]).status_code == 200
    assert _register(client, "unlimu3", invite_code=ub["code"]).status_code == 200

    db = SessionLocal()
    try:
        row = crud.get_invite_code(db, ub["code"])
        row.expires_at = crud._utc_now() - timedelta(minutes=5)
        db.commit()
    finally:
        db.close()

    assert _register(client, "unlimu4", invite_code=ub["code"]).status_code == 400
    listed = client.get("/api/auth/invites", headers=adm_h).json()["items"]
    entry = [x for x in listed if x["code"] == ub["code"]][0]
    assert entry["expired"] is True
    assert entry["active"] is False
    assert entry["used_count"] == 3

    assert client.post("/api/auth/invites", json={"max_uses": -1}, headers=adm_h).status_code == 400
    assert client.post("/api/auth/invites", json={"expires_minutes": 0}, headers=adm_h).status_code == 400


def test_admin_assigns_worker_role_with_cap_and_epoch_bump(monkeypatch):
    client, adm_h = _setup_admin(monkeypatch)
    u_reg = _register(client, "promote1")
    assert u_reg.status_code == 200
    u_id = u_reg.json()["id"]
    u_tok = u_reg.json()["token"]

    assert client.patch(
        f"/api/auth/users/{u_id}/role",
        json={"role": "worker"},
        headers={"Authorization": f"Bearer {u_tok}"},
    ).status_code == 403

    assert client.patch(
        f"/api/auth/users/{u_id}/role",
        json={"role": "admin"},
        headers=adm_h,
    ).status_code == 400

    r_prom = client.patch(
        f"/api/auth/users/{u_id}/role",
        json={"role": "worker"},
        headers=adm_h,
    )
    assert r_prom.status_code == 200
    assert r_prom.json()["role"] == "worker"

    assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {u_tok}"}).status_code == 401
    w_login = client.post(
        "/api/auth/login",
        json={"identifier": "promote1", "password": "UserPass#2026"},
    )
    assert w_login.status_code == 200
    assert w_login.json()["role"] == "worker"
    w_tok = w_login.json()["token"]
    assert client.get("/api/admin/stats", headers={"Authorization": f"Bearer {w_tok}"}).status_code == 200

    extra_ids = []
    for i in range(4):
        ex_r = _register(client, f"extra_w_{i}")
        assert ex_r.status_code == 200
        ex_id = ex_r.json()["id"]
        extra_ids.append(ex_id)
        assert client.patch(
            f"/api/auth/users/{ex_id}/role",
            json={"role": "worker"},
            headers=adm_h,
        ).status_code == 200

    overflow = _register(client, "overflow_u")
    assert overflow.status_code == 200
    assert client.patch(
        f"/api/auth/users/{overflow.json()['id']}/role",
        json={"role": "worker"},
        headers=adm_h,
    ).status_code == 409

    r_dem = client.patch(
        f"/api/auth/users/{u_id}/role",
        json={"role": "user"},
        headers=adm_h,
    )
    assert r_dem.status_code == 200
    assert r_dem.json()["role"] == "user"
    assert client.get("/api/admin/stats", headers={"Authorization": f"Bearer {w_tok}"}).status_code == 401
