import io
import secrets
import wave

import pytest
from fastapi.testclient import TestClient

from app import audio_access
from app.api import auth as auth_api
from app.api import transcription as trans_api
from app.config import settings
from app.database import crud
from app.database.models import HeritageItem, Task, User
from app.database.session import SessionLocal
from app.main import _json_nesting_exceeds, create_app
from app.services import user_inflight
from app.storage import manager


@pytest.fixture(autouse=True)
def _clean_state():
    db = SessionLocal()
    try:
        db.query(Task).delete()
        db.query(HeritageItem).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    with auth_api._auth_failures_lock:
        auth_api._auth_failures.clear()
    user_inflight.reset()
    yield
    db = SessionLocal()
    try:
        db.query(Task).delete()
        db.query(HeritageItem).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    user_inflight.reset()


def _wav_bytes(seconds=1, sr=8000):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"\x00\x30" * (sr * seconds))
    return bio.getvalue()


def test_boot_demote_ghost_admin_strips_privileges_immediately(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    r = client.post(
        "/api/auth/register",
        json={
            "username": "bootghost1",
            "email": "bootghost1@example.local",
            "password": "BootGhost123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200
    old_token = r.json()["token"]
    uid = r.json()["id"]

    db = SessionLocal()
    try:
        row = crud.get_user_by_id(db, uid)
        row.role = "admin"
        db.commit()
    finally:
        db.close()

    restarted = TestClient(create_app())
    hdr = {"Authorization": f"Bearer {old_token}"}
    assert restarted.get("/api/admin/stats", headers=hdr).status_code == 403
    assert restarted.get("/api/admin/storage", headers=hdr).status_code == 403
    assert restarted.get("/api/admin/crash-reports", headers=hdr).status_code == 403
    me = restarted.get("/api/auth/me", headers=hdr)
    assert me.status_code == 200
    assert me.json()["role"] == "user"
    db = SessionLocal()
    try:
        refreshed = crud.get_user_by_id(db, uid)
        assert refreshed.role == "user"
    finally:
        db.close()


def test_generated_signed_url_binds_task_owner_scope(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())

    r1 = client.post(
        "/api/auth/register",
        json={
            "username": "genowner1",
            "email": "gen1@example.local",
            "password": "GenOwner123",
            "invite_code": "TESTINVITE",
        },
    )
    r2 = client.post(
        "/api/auth/register",
        json={
            "username": "genother2",
            "email": "gen2@example.local",
            "password": "GenOther123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r1.status_code == 200 and r2.status_code == 200
    u1_id = r1.json()["id"]
    u2_id = r2.json()["id"]
    h1 = {"Authorization": f"Bearer {r1.json()['token']}"}
    h2 = {"Authorization": f"Bearer {r2.json()['token']}"}

    db = SessionLocal()
    try:
        t = crud.create_task(db, "generate", {"prompt": "test"}, user_id=u1_id)
        tid = t.id
    finally:
        db.close()

    manager.generated_dir().mkdir(parents=True, exist_ok=True)
    audio_path = manager.generated_dir() / f"{tid}.mp3"
    audio_path.write_bytes(b"ID3" + b"\x00" * 64)
    try:
        assert client.get(
            "/api/music/play-url",
            params={"path": f"/api/music/generated/{tid}.mp3"},
            headers=h2,
        ).status_code == 404

        minted = client.get(
            "/api/music/play-url",
            params={"path": f"/api/music/generated/{tid}.mp3"},
            headers=h1,
        )
        assert minted.status_code == 200
        signed_url = minted.json()["url"]
        assert client.get(signed_url).status_code == 200

        unscoped = audio_access.sign_path(f"/api/music/generated/{tid}.mp3")["url"]
        assert client.get(unscoped).status_code == 401
        assert client.get(f"/api/music/generated/{tid}.mp3", headers=h2).status_code == 404

        db = SessionLocal()
        try:
            task_row = db.get(Task, tid)
            task_row.user_id = u2_id
            db.commit()
        finally:
            db.close()
        assert client.get(signed_url).status_code == 401
    finally:
        audio_path.unlink(missing_ok=True)


def test_json_depth_guard_ignores_braces_in_strings_and_blocks_real_nesting(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    assert _json_nesting_exceeds(('{"a":' * 70 + '"x"' + '}' * 70).encode(), 64) is True
    assert _json_nesting_exceeds(b'{"detail": "' + (b'{' * 100) + b'\\"}' + (b'}' * 100) + b'"}', 64) is False

    client = TestClient(create_app())
    r = client.post(
        "/api/auth/register",
        json={
            "username": "depthuser1",
            "email": "depth@example.local",
            "password": "DepthUser123",
            "invite_code": "TESTINVITE",
        },
    )
    tok = r.json()["token"]
    cr = client.post(
        "/api/crash-reports",
        json={"summary": "trace", "detail": ("{" * 90) + "inner" + ("}" * 90)},
        headers={"Authorization": f"Bearer {tok}"},
    )
    assert cr.status_code == 200

    nested_raw = ('{"a":' * 100 + '"x"' + '}' * 100).encode()
    blocked = client.post(
        "/api/auth/login",
        content=nested_raw,
        headers={"Content-Type": "application/json"},
    )
    assert blocked.status_code == 400


def test_evaluate_precheck_413_and_invalid_input_does_not_leak_inflight(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(trans_api, "MAX_BYTES", 32)
    client = TestClient(create_app())
    r = client.post(
        "/api/auth/register",
        json={
            "username": "evaluser1",
            "email": "eval@example.local",
            "password": "EvalUser123",
            "invite_code": "TESTINVITE",
        },
    )
    uid = r.json()["id"]
    hdr = {"Authorization": f"Bearer {r.json()['token']}"}

    oversized = client.post(
        "/api/music/evaluate",
        files={"file": ("big.wav", b"0" * 64, "audio/wav")},
        data={"bpm": "60", "truth": "[]"},
        headers=hdr,
    )
    assert oversized.status_code == 413
    assert user_inflight.current(user_inflight.user_key("evaluate", uid)) == 0

    monkeypatch.setattr(trans_api, "MAX_BYTES", 1024 * 1024)
    bad_truth = client.post(
        "/api/music/evaluate",
        files={"file": ("ok.wav", _wav_bytes(), "audio/wav")},
        data={"bpm": "60", "truth": "not-json"},
        headers=hdr,
    )
    assert bad_truth.status_code == 400
    assert user_inflight.current(user_inflight.user_key("evaluate", uid)) == 0
