import secrets

from fastapi.testclient import TestClient

from app.api import auth as auth_mod
from app.config import settings
from app.database.session import SessionLocal
from app.main import create_app


def _auth_on(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 100000, raising=False)
    return TestClient(create_app())


def _mk_admin(client, pw):
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "ghitatruongle@x.local",
        "password": pw, "invite_code": "TESTINVITE",
    })
    if r.status_code == 409:
        r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": pw})
    assert r.status_code == 200, r.text
    tok = r.json()["token"]
    db = SessionLocal()
    try:
        from app.database import crud

        user = crud.get_user(db, "ghitatruongle")
        user.role = "admin"
        crud.set_must_change_password(db, user.id, False)
        db.commit()
        admin_id = user.id
    finally:
        db.close()
    return tok, admin_id


def test_unlock_identifier_bucket_blocks_distributed_ips(monkeypatch):
    client = _auth_on(monkeypatch)
    pw = "Adm#2026aaa"
    tok, admin_id = _mk_admin(client, pw)
    auth_mod._admin_unlock_failures.clear()
    auth_mod._admin_unlocks.pop(admin_id, None)

    ip_counter = {"n": 0}

    def rotating_ip(request):
        ip_counter["n"] += 1
        return f"10.55.{ip_counter['n'] // 250}.{ip_counter['n'] % 250}"

    monkeypatch.setattr(auth_mod, "_client_ip", rotating_ip)
    try:
        codes = []
        for i in range(15):
            r = client.post("/api/auth/admin-unlock", json={"password": f"Wrong#{i}xxxx"},
                            headers={"Authorization": f"Bearer {tok}"})
            codes.append(r.status_code)
        n401 = codes.count(401)
        n429 = codes.count(429)
        assert n401 <= auth_mod._ADMIN_UNLOCK_FAILURE_LIMIT, f"phải chặn sau {auth_mod._ADMIN_UNLOCK_FAILURE_LIMIT} sai bất kể xoay IP: {codes}"
        assert n429 >= 10, f"phần còn lại phải 429: {codes}"

        r = client.post("/api/auth/admin-unlock", json={"password": pw},
                        headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code == 200, f"chủ đúng MK vẫn unlock được (verify-first anti-poison): {r.status_code}"
    finally:
        auth_mod._admin_unlock_failures.clear()
        auth_mod._admin_unlocks.pop(admin_id, None)


def test_admin_unlock_verify_first_survives_full_buckets(monkeypatch):
    client = _auth_on(monkeypatch)
    pw = "Adm#2026aaa"
    tok, admin_id = _mk_admin(client, pw)
    auth_mod._admin_unlock_failures.clear()
    auth_mod._admin_unlocks.pop(admin_id, None)
    try:
        for i in range(10):
            auth_mod._record_ip_failure(
                auth_mod._admin_unlock_failures, f"unlock:10.1.{i}.{i}:{admin_id}"
            )
        auth_mod._record_ip_failure(
            auth_mod._admin_unlock_failures, f"unlock-ident:{admin_id}"
        )
        r = client.post("/api/auth/admin-unlock", json={"password": pw},
                        headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code == 200, f"chủ đúng MK phải luôn unlock được (verify-first): {r.status_code}"
        r = client.post("/api/admin/maintenance/cleanup", headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code in (200, 429), "fresh window mở sau unlock"
        auth_mod._admin_unlocks.pop(admin_id, None)
        r = client.post("/api/admin/maintenance/cleanup", headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code == 403, "sau restart/window hết hạn → 403 (step-up hết hạn đúng)"
    finally:
        auth_mod._admin_unlock_failures.clear()
        auth_mod._admin_unlocks.pop(admin_id, None)
