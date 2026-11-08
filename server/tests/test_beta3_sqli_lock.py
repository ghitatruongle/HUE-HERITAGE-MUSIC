import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app

PAYLOADS = [
    "' OR 1=1--",
    "' UNION SELECT NULL,sql FROM sqlite_master--",
    "'; DROP TABLE users;--",
    "' AND CAST((SELECT password_hash FROM users LIMIT 1) AS INTEGER)--",
    "' OR randomblob(200000000)--",
    "pragma table_info(users)",
    "admin'--",
    "%' OR '%",
]


@pytest.fixture()
def raid_client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-sqli-lock-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "a@x.com",
        "password": "SqliLock#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    yield client
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


SQL_ERROR_SIGS = ("sqlite", "OperationalError", "IntegrityError", "syntax error",
                  "unrecognized token", "no such table", "no such column", "SQLITE_")


def test_sqli_payloads_never_authenticate_or_leak(raid_client):
    client = raid_client
    for p in PAYLOADS:
        r = client.post("/api/auth/login", json={"identifier": p, "password": p})
        assert r.status_code in (401, 400, 422), f"login {p!r} -> {r.status_code} {r.text[:80]}"
        low = r.text.lower()
        assert not any(sig.lower() in low for sig in SQL_ERROR_SIGS), f"login {p!r} lộ SQL: {r.text[:120]}"


def test_sqli_register_stays_rejected(raid_client):
    client = raid_client
    for p in PAYLOADS:
        r = client.post("/api/auth/register", json={
            "username": p, "email": "x@x.com", "password": "SqliLock#2026", "invite_code": "TESTINVITE"})
        assert r.status_code in (400, 401, 422), f"register {p!r} -> {r.status_code} {r.text[:80]}"


def test_sqli_id_lookup_never_leaks_or_500(raid_client):
    client = raid_client
    for p in PAYLOADS:
        r = client.get(f"/api/heritage/{p}")
        assert r.status_code in (400, 401, 404, 422), f"heritage get {p!r} -> {r.status_code} {r.text[:80]}"
        r = client.get(f"/api/lessons/{p}")
        assert r.status_code in (400, 401, 404, 422), f"lesson get {p!r} -> {r.status_code} {r.text[:80]}"
        low = r.text.lower()
        assert not any(sig.lower() in low for sig in SQL_ERROR_SIGS), f"{p!r} lộ SQL: {r.text[:120]}"


def test_users_table_survives_payload_burst(raid_client):
    client = raid_client
    db = SessionLocal()
    try:
        before = db.execute(__import__("sqlalchemy").text("SELECT COUNT(*) FROM users")).scalar()
    finally:
        db.close()
    for p in PAYLOADS[:4]:
        client.post("/api/auth/login", json={"identifier": p, "password": "x"})
        client.get(f"/api/lessons/{p}")
    db = SessionLocal()
    try:
        after = db.execute(__import__("sqlalchemy").text("SELECT COUNT(*) FROM users")).scalar()
    finally:
        db.close()
    assert before == after == 1, f"users bảng bị đụng: trước={before} sau={after}"
