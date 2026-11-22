import io
import re
import secrets
import wave

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
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


def _wav_bytes(seconds: float, freq: float = 220.0) -> bytes:
    sr = 8000
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        import math

        for i in range(int(sr * seconds)):
            v = int(12000 * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def _client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    return TestClient(create_app())


def test_analyze_pitch_long_audio_flags_truncated(monkeypatch):
    client = _client(monkeypatch)
    r = client.post(
        "/api/music/analyze-pitch",
        files={"file": ("long.wav", _wav_bytes(40.0), "audio/wav")},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["truncated"] is True
    assert body["duration_full"] is not None and 39.5 <= body["duration_full"] <= 40.5
    assert body["duration"] <= 35.6
    assert body["max_seconds"] == 35.0


def test_analyze_pitch_short_audio_not_truncated(monkeypatch):
    client = _client(monkeypatch)
    r = client.post(
        "/api/music/analyze-pitch",
        files={"file": ("short.wav", _wav_bytes(8.0), "audio/wav")},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["truncated"] is False
    assert body["duration_full"] is not None and 7.5 <= body["duration_full"] <= 8.5


def test_my_progress_returns_server_today(monkeypatch):
    client = _client(monkeypatch)
    r = client.post(
        "/api/auth/register",
        json={
            "username": "streakuser1",
            "email": "streakuser1@gmail.com",
            "password": "secret123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    r2 = client.get("/api/lessons/my-progress", headers={"Authorization": f"Bearer {token}"})
    assert r2.status_code == 200, r2.text
    body = r2.json()
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", body["server_today"]) is not None


def test_anonymous_my_progress_still_has_server_today(monkeypatch):
    client = _client(monkeypatch)
    r = client.get("/api/lessons/my-progress")
    assert r.status_code == 200
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", r.json()["server_today"]) is not None
