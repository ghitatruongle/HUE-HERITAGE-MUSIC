import hashlib
import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.session import SessionLocal
from app.main import create_app
from app.storage import manager


def _set_env_auth(monkeypatch, auth_required: bool, secret: str):
    monkeypatch.setattr(settings, "auth_required", auth_required, raising=False)
    monkeypatch.setattr(settings, "secret_key", secret, raising=False)


def test_placeholder_secret_rejected(monkeypatch):
    _set_env_auth(monkeypatch, True, "change-me-to-a-long-random-string")
    with pytest.raises(RuntimeError):
        create_app()


def test_short_secret_rejected(monkeypatch):
    _set_env_auth(monkeypatch, True, "short-secret-key")
    with pytest.raises(RuntimeError):
        create_app()


def test_good_secret_accepted(monkeypatch):
    _set_env_auth(monkeypatch, True, secrets.token_hex(32))
    app = create_app()
    client = TestClient(app)
    r = client.get("/health")
    assert r.status_code == 200


def test_no_guard_when_auth_disabled(monkeypatch):
    _set_env_auth(monkeypatch, False, "dev-insecure-secret-key")
    app = create_app()
    client = TestClient(app)
    assert client.get("/health").status_code == 200


def test_security_headers_present(monkeypatch):
    _set_env_auth(monkeypatch, False, "dev-insecure-secret-key")
    client = TestClient(create_app())
    r = client.get("/health")
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert r.headers.get("X-Frame-Options") == "DENY"
    assert r.headers.get("Referrer-Policy") == "no-referrer"


def test_audio_download_not_gzipped(monkeypatch):
    _set_env_auth(monkeypatch, False, "dev-insecure-secret-key")
    manager.generated_dir().mkdir(parents=True, exist_ok=True)
    payload = secrets.token_bytes(4096)
    (manager.generated_dir() / "taskgz.mp3").write_bytes(payload)
    client = TestClient(create_app())
    r = client.get(
        "/api/music/generated/taskgz.mp3",
        headers={"Accept-Encoding": "gzip"},
    )
    assert r.status_code == 200
    assert r.headers.get("Content-Encoding") != "gzip"
    assert r.content == payload
    assert "immutable" in r.headers.get("Cache-Control", "")


def _legacy_hash(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 100_000).hex()
    return f"{salt}${digest}"


def test_legacy_hash_rehashed_on_login(monkeypatch):
    _set_env_auth(monkeypatch, False, secrets.token_hex(32))
    db = SessionLocal()
    try:
        user = crud.create_user(db, username="legacyuser", email="legacy@gmail.com", password_hash=_legacy_hash("secret123"))
        user_id = user.id
    finally:
        db.close()
    client = TestClient(create_app())
    r = client.post("/api/auth/login", json={"identifier": "legacyuser", "password": "secret123"})
    assert r.status_code == 200
    db = SessionLocal()
    try:
        row = crud.get_user_by_id(db, user_id)
        assert row.password_hash.startswith("pbkdf2$600000$")
        ok = client.post("/api/auth/login", json={"identifier": "legacyuser", "password": "secret123"})
        assert ok.status_code == 200
    finally:
        db.close()
