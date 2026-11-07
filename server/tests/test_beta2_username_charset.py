import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture()
def _auth_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "invite_codes", "TESTINVITE", raising=False)
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


def test_username_charset_policy(_auth_env):
    client = TestClient(create_app())

    bad = [
        "<script>alert(1)</script>",
        "ab<script>",
        "user name",
        "user;drop",
        "user'name--",
        'user"quote',
        "a" * 33,
        "ab",
        "",
        "user name 🙂",
    ]
    for u in bad:
        r = client.post(
            "/api/auth/register",
            json={"username": u, "email": f"u{abs(hash(u))}@x.com", "password": "secret123", "invite_code": "TESTINVITE"},
        )
        assert r.status_code == 400, f"{u!r} -> {r.status_code}"

    good = ["abc", "user.name", "user_name", "user-name", "a" * 32, "User123"]
    for u in good:
        r = client.post(
            "/api/auth/register",
            json={"username": u if u != "a" * 32 else "a" * 32, "email": f"g{abs(hash(u))}@x.com", "password": "secret123", "invite_code": "TESTINVITE"},
        )
        assert r.status_code == 200, f"{u!r} -> {r.status_code} {r.text[:80]}"


def test_legacy_username_login_unaffected(_auth_env):
    from app.database import crud
    from app.database.models import PracticeSession as _PS

    app = create_app()
    client = TestClient(app)
    r = client.post(
        "/api/auth/register",
        json={"username": "legacyuser", "email": "legacy@x.com", "password": "secret123", "invite_code": "TESTINVITE"},
    )
    assert r.status_code == 200

    db = SessionLocal()
    try:
        u = db.query(User).filter_by(username="legacyuser").first()
        u.username = "old.user-name_1"
        db.commit()
    finally:
        db.close()

    r = client.post("/api/auth/login", json={"identifier": "old.user-name_1", "password": "secret123"})
    assert r.status_code == 200
    assert r.json().get("token")
