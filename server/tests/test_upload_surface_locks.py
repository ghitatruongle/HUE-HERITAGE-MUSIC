import asyncio
import secrets
import struct
import uuid
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import settings
from app.database.session import SessionLocal
from app.main import BodyLimitMiddleware, create_app
from app.storage import manager as storage_manager


def _wav(seconds=0.4, sr=16000):
    frames = b"".join(struct.pack("<h", (i * 43) % 30000 - 15000) for i in range(int(sr * seconds)))
    return (
        b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVEfmt "
        + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16) + b"data" + struct.pack("<I", len(frames)) + frames
    )


def test_body_limit_aborts_early_on_over_limit_stream():
    calls = {"n": 0}

    async def endless_receive():
        calls["n"] += 1
        return {"type": "http.request", "body": b"R" * (1024 * 1024), "more_body": True}

    sent = {}

    async def send(msg):
        sent[msg["type"]] = msg

    async def never_app(scope, receive, send):
        raise AssertionError("app không được chạy khi body đã vượt trần")

    mw = BodyLimitMiddleware(never_app)
    scope = {"type": "http", "method": "POST", "path": "/api/crash-reports"}
    asyncio.run(mw(scope, endless_receive, send))
    assert sent["http.response.start"]["status"] == 413
    assert calls["n"] <= 4, f"phải cắt sớm ở chunk vượt trần, không nuốt vô hạn (nhận {calls['n']} chunk)"


def test_body_limit_normal_body_still_reaches_app():
    handled = {"ok": False}

    async def app(scope, receive, send):
        handled["ok"] = True
        await send({"type": "http.response.start", "status": 200})
        await send({"type": "http.response.body", "body": b"ok"})

    async def receive():
        return {"type": "http.request", "body": b'{"a": 1}', "more_body": False}

    async def send(msg):
        return None

    mw = BodyLimitMiddleware(app)
    scope = {"type": "http", "method": "POST", "path": "/api/crash-reports"}
    asyncio.run(mw(scope, receive, send))
    assert handled["ok"]


def test_upload_fake_extension_and_magic_matrix():
    monkey_tokens = {}
    client = TestClient(create_app())
    uname = f"uplock{uuid.uuid4().hex[:8]}"
    r = client.post("/api/auth/register", json={
        "username": uname, "email": f"{uname}@x.local",
        "password": "Test#2026aa", "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200
    tok = r.json()["token"]
    ah = {"Authorization": f"Bearer {tok}"}

    fake_heads = [
        (b"MZ\x90\x00" + b"\x00" * 100, "MZ/PE"),
        (b"GIF89a" + b"\x00" * 100, "GIF89a"),
        (b"<html><script>alert(1)</script></html>", "HTML"),
        (b"\x7fELF" + b"\x00" * 100, "ELF"),
    ]
    for head, label in fake_heads:
        body = head + _wav()[44:]
        r = client.post("/api/heritage/upload", files={"file": (f"fake_{label}.wav", body, "audio/wav")},
                        data={"title": "fake"}, headers=ah)
        assert r.status_code == 400, f"{label} giả đuôi .wav phải 400: {r.status_code}"

    r = client.post("/api/heritage/upload", files={"file": ("double.exe", _wav(), "audio/wav")},
                    data={"title": "x"}, headers=ah)
    assert r.status_code == 400

    r = client.post("/api/heritage/upload", files={"file": ("mime_lie.wav", _wav(), "text/csv")},
                    data={"title": "x"}, headers=ah)
    assert r.status_code == 200, "Content-Type header nói dối không được tin — magic bytes quyết định"


def test_upload_traversal_filename_is_inert():
    client = TestClient(create_app())
    uname = f"travlock{uuid.uuid4().hex[:8]}"
    r = client.post("/api/auth/register", json={
        "username": uname, "email": f"{uname}@x.local",
        "password": "Test#2026aa", "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200
    ah = {"Authorization": f"Bearer {r.json()['token']}"}

    for fn in ("../../evil.wav", "..\\..\\evil.wav", "/etc/evil.wav", "C:\\evil.wav"):
        r = client.post("/api/heritage/upload", files={"file": (fn, _wav(), "audio/wav")},
                        data={"title": "trav"}, headers=ah)
        assert r.status_code in (200, 400), f"{fn} → {r.status_code}"

    db = SessionLocal()
    try:
        from app.database.models import HeritageItem

        rows = db.query(HeritageItem).filter(HeritageItem.title == "trav").all()
        for row in rows:
            assert "/" not in row.filename and "\\" not in row.filename and ".." not in row.filename
            assert row.filename.endswith(tuple(storage_manager.ALLOWED_EXT))
    finally:
        db.close()
    assert not list(Path("/tmp").glob("evil.wav")), "không được ghi file ra ngoài storage"
