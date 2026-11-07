import io
import secrets
import threading
import time
import wave

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.models import User, PracticeSession
from app.database.session import SessionLocal
from app.main import create_app


def _tone_wav(freq=220.0, sr=16000, tone_len=0.4):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        n = int(sr * tone_len)
        for i in range(n):
            env = min(1.0, i / (sr * 0.02), (n - i) / (sr * 0.02))
            v = int(8000 * env * 0.5)
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


@pytest.fixture()
def _auth_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()


def test_practice_slot_helpers_unit():
    from app.api import lessons as L

    L._PRACTICE_INFLIGHT.clear()
    L._practice_slot_acquire("u1")
    L._practice_slot_acquire("u1")
    with pytest.raises(HTTPException) as e:
        L._practice_slot_acquire("u1")
    assert e.value.status_code == 429
    L._practice_slot_release("u1")
    L._practice_slot_acquire("u1")
    L._practice_slot_release("u1")
    L._practice_slot_release("u1")
    assert "u1" not in L._PRACTICE_INFLIGHT
    L._practice_slot_release("ghost")
    L._practice_slot_acquire(None)
    L._practice_slot_release(None)


def test_practice_inflight_cap_per_user(_auth_env, monkeypatch):
    from app.api import lessons as L

    L._PRACTICE_INFLIGHT.clear()
    app = create_app()
    first = TestClient(app)
    r = first.post(
        "/api/auth/register",
        json={"username": "capper", "email": "capper@x.com", "password": "secret123", "invite_code": "TESTINVITE"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    uh = {"Authorization": f"Bearer {token}"}

    def slow_practice(scale_id, data, transpose):
        time.sleep(1.0)
        return {"score": 50.0}

    monkeypatch.setattr(L.scale_service, "practice_scale", slow_practice)

    results = []

    def hit(i):
        c = TestClient(app)
        resp = c.post(
            "/api/lessons/scales/x/practice",
            files={"file": ("a.wav", _tone_wav(), "audio/wav")},
            headers=uh,
        )
        results.append(resp.status_code)

    threads = [threading.Thread(target=hit, args=(i,)) for i in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert results.count(200) == 2, results
    assert results.count(429) == 2, results
    assert "capper" not in L._PRACTICE_INFLIGHT or L._PRACTICE_INFLIGHT.get("capper", 0) <= 2

    time.sleep(0.1)
    resp = first.post(
        "/api/lessons/scales/x/practice",
        files={"file": ("a.wav", _tone_wav(), "audio/wav")},
        headers=uh,
    )
    assert resp.status_code == 200
