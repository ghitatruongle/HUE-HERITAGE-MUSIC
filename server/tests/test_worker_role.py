import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.models import HeritageItem, User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture(autouse=True)
def _wipe_users():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _register(client, username, password="secret123"):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": password,
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def _login(client, identifier, password="secret123"):
    r = client.post("/api/auth/login", json={"identifier": identifier, "password": password})
    assert r.status_code == 200, r.text
    return r.json()


def _admin_ready():
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    client = TestClient(create_app())
    token = _login(client, settings.admin_truong_username)["token"]
    r = client.post("/api/auth/admin-unlock", json={"password": "secret123"}, headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, r.text
    return client, token


def _create_worker(client, admin_token, username, idx=None):
    r = client.post(
        "/api/auth/users",
        json={"username": username, "password": "worker123a", "role": "worker", "note": "t1"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    return r


def _worker_token(client, username):
    logged = _login(client, username, "worker123a")
    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "worker123a", "new_password": "worker456b"},
        headers={"Authorization": f"Bearer {logged['token']}"},
    )
    assert r.status_code == 200, r.text
    logged2 = _login(client, username, "worker456b")
    return logged2["token"]


def test_admin_creates_worker_and_response_has_role(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    r = _create_worker(client, admin_token, "worker01")
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "worker"
    assert r.json()["must_change_password"] is True


def test_invalid_role_rejected(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    r = client.post(
        "/api/auth/users",
        json={"username": "badrole1", "password": "worker123a", "role": "admin"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 400
    r2 = client.post(
        "/api/auth/users",
        json={"username": "badrole2", "password": "worker123a", "role": "superadmin"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r2.status_code == 400


def test_worker_cap_five(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    for i in range(5):
        r = _create_worker(client, admin_token, f"capped{i:02d}")
        assert r.status_code == 200, r.text
    sixth = _create_worker(client, admin_token, "capped05")
    assert sixth.status_code == 409


def test_worker_cap_counts_active_only(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    for i in range(5):
        assert _create_worker(client, admin_token, f"active{i:02d}").status_code == 200
    db = SessionLocal()
    try:
        victim = crud.get_user(db, "active00")
        victim.active = 0
        db.commit()
    finally:
        db.close()
    r = _create_worker(client, admin_token, "active05")
    assert r.status_code == 200, r.text


def test_worker_survives_restart_and_foreign_role_demoted(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    assert _create_worker(client, admin_token, "survivor1").status_code == 200
    db = SessionLocal()
    try:
        weird = crud.get_user(db, "survivor1")
        db.add(User(username="weirdrole1", email="weirdrole1@gmail.com", password_hash="x", role="moderator"))
        db.commit()
    finally:
        db.close()

    TestClient(create_app())
    db = SessionLocal()
    try:
        assert (crud.get_user(db, "survivor1").role or "user") == "worker"
        assert (crud.get_user(db, "weirdrole1").role or "user") == "user"
    finally:
        db.close()


def test_worker_clamped_to_cap_on_boot(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, _ = _admin_ready()
    db = SessionLocal()
    try:
        from datetime import datetime, timedelta

        base = datetime(2026, 1, 1, 0, 0, 0)
        for i in range(7):
            db.add(
                User(
                    username=f"clamp{i:02d}",
                    email=f"clamp{i:02d}@gmail.com",
                    password_hash="x",
                    role="worker",
                    created_at=base + timedelta(minutes=i),
                )
            )
        db.commit()
    finally:
        db.close()

    TestClient(create_app())
    db = SessionLocal()
    try:
        workers = [u.username for u in db.query(User).filter(User.role == "worker").all()]
        assert len(workers) == settings.worker_max_active
        assert "clamp06" in workers
        assert "clamp00" not in workers
    finally:
        db.close()


def test_worker_staff_read_endpoints(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    assert _create_worker(client, admin_token, "staff01").status_code == 200
    wtoken = _worker_token(client, "staff01")
    headers = {"Authorization": f"Bearer {wtoken}"}

    assert client.get("/api/auth/users", headers=headers).status_code == 200
    assert client.get("/api/admin/stats", headers=headers).status_code == 200
    assert client.get("/api/admin/storage", headers=headers).status_code == 200
    assert client.get("/api/admin/learning/stats", headers=headers).status_code == 200
    r = client.post("/api/auth/invites", json={"note": "t1"}, headers=headers)
    assert r.status_code == 200, r.text
    assert len(r.json()["code"]) >= 4


def test_worker_sees_private_items_in_storage_list(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    assert _create_worker(client, admin_token, "staff02").status_code == 200
    wtoken = _worker_token(client, "staff02")
    db = SessionLocal()
    try:
        db.add(HeritageItem(title="Rieng", filename="rieng.wav", sha256=secrets.token_hex(32), visibility="admin_only"))
        db.add(HeritageItem(title="Cong khai", filename="cong.wav", sha256=secrets.token_hex(32), visibility="public"))
        db.commit()
    finally:
        db.close()

    r = client.get("/api/admin/storage", headers={"Authorization": f"Bearer {wtoken}"})
    assert r.status_code == 200
    titles = {x["title"] for x in r.json()["items"]}
    assert {"Rieng", "Cong khai"} <= titles


def test_worker_forbidden_admin_write_surface(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    assert _create_worker(client, admin_token, "staff03").status_code == 200
    wtoken = _worker_token(client, "staff03")
    headers = {"Authorization": f"Bearer {wtoken}"}

    assert client.post("/api/auth/users", json={"username": "nope1"}, headers=headers).status_code == 403
    victim_id = client.get("/api/auth/users", headers=headers).json()["items"][0]["id"]
    assert client.post(f"/api/auth/users/{victim_id}/reset-password", headers=headers).status_code == 403
    assert client.patch(f"/api/auth/users/{victim_id}/active", json={"active": False}, headers=headers).status_code == 403
    assert client.delete(f"/api/auth/users/{victim_id}", headers=headers).status_code == 403
    assert client.get("/api/auth/invites", headers=headers).status_code == 403
    assert client.delete("/api/auth/invites/nonexistent", headers=headers).status_code == 403
    assert client.get("/api/admin/crash-reports", headers=headers).status_code == 403
    assert client.get("/api/admin/security/events", headers=headers).status_code == 403
    assert client.post("/api/admin/maintenance/cleanup", json={}, headers=headers).status_code in (403, 422)
    assert client.patch("/api/admin/storage/nonexistent/visibility", json={"visibility": "public"}, headers=headers).status_code == 403
    assert client.delete("/api/admin/storage/nonexistent", headers=headers).status_code == 403


def test_worker_must_change_password_blocks_writes(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    assert _create_worker(client, admin_token, "fresh01").status_code == 200
    logged = _login(client, "fresh01", "worker123a")
    headers = {"Authorization": f"Bearer {logged['token']}"}
    r = client.post("/api/auth/invites", json={"note": "t1"}, headers=headers)
    assert r.status_code == 403
    assert client.get("/api/admin/stats", headers=headers).status_code == 200


def test_plain_user_still_forbidden_staff_surface(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, _ = _admin_ready()
    _register(client, "plain07")
    utoken = _login(client, "plain07")["token"]
    headers = {"Authorization": f"Bearer {utoken}"}
    assert client.get("/api/auth/users", headers=headers).status_code == 403
    assert client.get("/api/admin/stats", headers=headers).status_code == 403
    assert client.post("/api/auth/invites", json={"note": "t1"}, headers=headers).status_code == 403


def test_admin_stats_worker_count_live(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    headers = {"Authorization": f"Bearer {admin_token}"}
    r0 = client.get("/api/admin/stats", headers=headers)
    assert r0.status_code == 200
    assert r0.json()["users"]["workers"] == 0
    assert _create_worker(client, admin_token, "live01").status_code == 200
    r1 = client.get("/api/admin/stats", headers=headers)
    assert r1.json()["users"]["workers"] == 1
    assert _create_worker(client, admin_token, "live02").status_code == 200
    r2 = client.get("/api/admin/stats", headers=headers)
    assert r2.json()["users"]["workers"] == 2
