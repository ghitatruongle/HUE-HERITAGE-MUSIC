import io
import struct
import wave

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app

PAYLOAD = "<script>alert('xss003')</script><img src=x onerror=alert(2)>"


@pytest.fixture()
def xss_client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-xss-lock-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "x@x.com",
        "password": "XssLock#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    yield client
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _wav_bytes(salt: bytes) -> bytes:
    sr = 16000
    n = sr
    out = io.BytesIO()
    w = wave.open(out, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    frames = bytearray()
    for i in range(n):
        frames += int(((i % 800) - 400) * 30).to_bytes(2, "little", signed=True)
    frames += struct.pack("<I", len(salt)) + salt
    w.writeframes(bytes(frames))
    w.close()
    return out.getvalue()


def test_xss_heritage_metadata_stored_inert_never_html(xss_client):
    client = xss_client
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "XssLock#2026"})
    token = r.json()["token"]
    h = {"Authorization": f"Bearer {token}"}

    r = client.post("/api/heritage/upload", headers=h,
                    files={"file": ("xss_lock.wav", _wav_bytes(b"xsslock003"), "audio/wav")},
                    data={"title": PAYLOAD, "lyrics": PAYLOAD, "description": PAYLOAD})
    assert r.status_code == 200, r.text[:120]
    item_id = r.json()["id"]

    r = client.get("/api/heritage")
    assert r.status_code == 200
    assert r.headers.get("content-type", "").startswith("application/json")
    assert PAYLOAD in r.text, "payload phải lưu nguyên trong JSON (inert context)"
    assert "content-security-policy" in {k.lower() for k in r.headers.keys()}

    r = client.get(f"/api/heritage/{item_id}")
    assert r.status_code == 200
    assert r.headers.get("content-type", "").startswith("application/json")
    assert PAYLOAD in r.text

    r = client.get("/")
    assert r.status_code == 200
    assert r.headers.get("content-type", "").startswith("text/html")
    assert PAYLOAD not in r.text, "SPA index KHÔNG được chứa payload (0 sink)"
    assert "content-security-policy" in {k.lower() for k in r.headers.keys()}
    assert "nosniff" in r.headers.get("x-content-type-options", "").lower()


def test_xss_register_payload_blocked_at_door(xss_client):
    client = xss_client
    for p in ("<script>alert(1)</script>", "<img src=x onerror=alert(1)>", "<svg onload=alert(1)>"):
        r = client.post("/api/auth/register", json={
            "username": p, "email": "x@x.com", "password": "XssLock#2026", "invite_code": "TESTINVITE"})
        assert r.status_code == 400, f"register payload {p!r} -> {r.status_code} (charset door phải chặn)"
        assert "script" not in r.text.lower() or r.status_code == 400
