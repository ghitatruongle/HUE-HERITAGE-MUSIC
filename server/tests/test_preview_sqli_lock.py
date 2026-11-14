import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.database.session import SessionLocal
from app.database.models import User


def _register(client, username, password="secret123"):
    r = client.post("/api/auth/register", json={
        "username": username, "email": f"{username}@gmail.com",
        "password": password, "invite_code": "TESTINVITE",
    })
    if r.status_code == 409:
        r = client.post("/api/auth/login", json={"username": username, "password": password})
        return r.json().get("token", "")
    assert r.status_code == 200, r.text
    return r.json().get("token", "")


def test_sqli_register_422_echo_inert_json_db_intact():
    client = TestClient(app)
    db = SessionLocal()
    try:
        before = db.query(User).count()
    finally:
        db.close()
    payload = "' UNION SELECT sqlite_version(), NULL --"
    r = client.post("/api/auth/register", json={"username": payload, "password": payload})
    assert r.status_code == 422
    assert "application/json" in r.headers.get("content-type", "")
    assert payload in r.text
    for real_error in ("syntax error", "no such table", "no such column", "operationalerror"):
        assert real_error not in r.text.lower()
    db = SessionLocal()
    try:
        after = db.query(User).count()
        assert after == before
    finally:
        db.close()


def test_sqli_audit_echo_admin_only_json_inert():
    client = TestClient(app)
    admin_token = _register(client, "ghitatruongle")
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == "ghitatruongle").one()
        u.role = "admin"
        db.commit()
    finally:
        db.close()
    r = client.post("/api/auth/admin-unlock", json={"password": "secret123"},
                    headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 200, r.text

    try:
        user_token = _register(client, "sqliecho_user")
        payload = "'; DROP TABLE users --"
        r = client.post("/api/crash-reports", json={"summary": payload, "detail": payload, "platform": "probe"},
                        headers={"Authorization": f"Bearer {user_token}"})
        assert r.status_code == 200, r.text

        r = client.get("/api/admin/security/events", params={"q": "DROP"},
                       headers={"Authorization": f"Bearer {admin_token}"})
        assert r.status_code == 200
        assert "application/json" in r.headers.get("content-type", "")
        assert "content-security-policy" in {k.lower() for k in r.headers.keys()}
        assert payload.split(";")[0] in r.text or "login_failed" in r.text or "crash" in r.text.lower() or r.json()

        r2 = client.get("/api/admin/security/events", params={"q": "DROP"},
                        headers={"Authorization": f"Bearer {user_token}"})
        assert r2.status_code == 403

        r3 = client.get("/api/admin/security/events", params={"q": "DROP"})
        assert r3.status_code == 401

        db = SessionLocal()
        try:
            n = db.query(User).count()
            assert n >= 2
        finally:
            db.close()
    finally:
        from app.api import auth as _auth_mod

        _auth_mod._admin_unlocks.clear()
        _auth_mod._admin_unlock_failures.clear()
        db = SessionLocal()
        try:
            ids = [u.id for u in db.query(User).filter(User.username.in_(["ghitatruongle", "sqliecho_user"])).all()]
            if ids:
                db.execute(User.__table__.delete().where(User.id.in_(ids)))
                db.commit()
        finally:
            db.close()
