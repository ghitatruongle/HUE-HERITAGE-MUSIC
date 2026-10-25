import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app
from app.services import generator_service
from app.storage import manager
from app import audio_access


def _auth_on(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)


def _auth_off(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)


def _make_generated_file(name="signed1.mp3"):
    manager.generated_dir().mkdir(parents=True, exist_ok=True)
    payload = secrets.token_bytes(2048)
    (manager.generated_dir() / name).write_bytes(payload)
    return name, payload


@pytest.fixture(autouse=True)
def _clean_tasks():
    yield
    with generator_service.TASKS_LOCK:
        generator_service.TASKS.clear()


def test_audio_open_when_auth_disabled(monkeypatch):
    _auth_off(monkeypatch)
    name, _ = _make_generated_file()
    client = TestClient(create_app())
    r = client.get(f"/api/music/generated/{name}")
    assert r.status_code == 200


def test_audio_requires_auth_or_signature(monkeypatch):
    _auth_on(monkeypatch)
    name, payload = _make_generated_file("signed2.mp3")
    client = TestClient(create_app())

    anon = client.get(f"/api/music/generated/{name}")
    assert anon.status_code == 401

    token = audio_access.sign_path(f"/api/music/generated/{name}")
    signed = client.get(token["url"])
    assert signed.status_code == 200
    assert signed.content == payload

    tampered = client.get(f"/api/music/generated/{name}?e={token['expires']}&s={'0' * 32}")
    assert tampered.status_code == 401

    expired = audio_access.sign_path(f"/api/music/generated/{name}", expires=1)
    stale = client.get(expired["url"])
    assert stale.status_code == 401


def test_play_url_endpoint(monkeypatch):
    _auth_on(monkeypatch)
    name, _ = _make_generated_file("signed3.mp3")
    client = TestClient(create_app())

    noauth = client.get("/api/music/play-url", params={"path": f"/api/music/generated/{name}"})
    assert noauth.status_code == 401

    db_user = None
    from app.database import crud
    from app.database.session import SessionLocal
    from app.api.auth import hash_password, make_token

    db = SessionLocal()
    try:
        user = crud.create_user(db, username="signer", email="signer@gmail.com", password_hash=hash_password("secret123"))
        token = make_token(user.id)
    finally:
        db.close()

    ok = client.get(
        "/api/music/play-url",
        params={"path": f"/api/music/generated/{name}"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert ok.status_code == 200
    url = ok.json()["url"]
    played = client.get(url)
    assert played.status_code == 200

    bad = client.get(
        "/api/music/play-url",
        params={"path": "/etc/passwd"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert bad.status_code == 400


def test_get_task_signs_audio_url_when_auth_on(monkeypatch):
    _auth_on(monkeypatch)
    tid = "task-signed-1"
    with generator_service.TASKS_LOCK:
        generator_service.TASKS[tid] = {
            "id": tid,
            "kind": "generate",
            "status": "done",
            "created_at": 0,
            "audio_url": f"/api/music/generated/{tid}.mp3",
        }
    payload = generator_service.get_task(tid)
    assert "e=" in payload["audio_url"]
    assert "s=" in payload["audio_url"]

    _auth_off(monkeypatch)
    payload_off = generator_service.get_task(tid)
    assert payload_off["audio_url"] == f"/api/music/generated/{tid}.mp3"
