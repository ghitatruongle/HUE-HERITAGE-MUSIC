import asyncio
import io
import math
import re
import secrets
import warnings
import wave
from pathlib import Path

from fastapi.testclient import TestClient

from app.api import auth as auth_mod
from app.config import settings
from app.database import crud
from app.database.session import SessionLocal
from app.main import create_app
from app.services import generator_service
from app.storage import manager as storage_manager
from app.workers import queue as task_queue


def _wav_bytes(seconds=0.6, freq=220.0, sr=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for i in range(int(sr * seconds)):
            v = int(8000 * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def test_w2_no_gzip_and_206_range_on_all_media_routes(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())

    wav = _wav_bytes(1.0)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("range_test.wav", wav, "audio/wav")},
        data={"title": "Range Check", "type": "Ca Huế"},
    )
    assert up.status_code == 200
    item_id = up.json()["id"]
    sha = up.json()["sha256"]

    res_restore = client.post(f"/api/music/restore-item/{item_id}")
    assert res_restore.status_code == 200

    for url in (f"/api/heritage/{item_id}/audio", f"/api/music/restored/{sha}"):
        r_full = client.get(url, headers={"Accept-Encoding": "gzip"})
        assert r_full.status_code == 200, f"{url} full -> {r_full.status_code}"
        assert r_full.headers.get("content-encoding") != "gzip", f"{url} was compressed by GZip"
        assert int(r_full.headers.get("content-length", "0")) > 1000
        r = client.get(url, headers={"Accept-Encoding": "gzip", "Range": "bytes=0-2047"})
        assert r.status_code == 206, f"{url} -> {r.status_code}"
        assert r.headers.get("content-encoding") != "gzip"
        assert len(r.content) == 2048
        assert r.headers.get("content-range", "").startswith("bytes 0-2047/")


def test_w2_compare_items_server_side_supports_archive_and_upload(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    db = SessionLocal()
    try:
        db.query(auth_mod.crud.User).delete()
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    client.post(
        "/api/auth/register",
        json={"username": "ghitatruongle", "email": "adm@x.com", "password": "AdminCmp1#2026", "invite_code": "TESTINVITE"},
    )
    client = TestClient(create_app())
    adm_tok = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminCmp1#2026"}).json()["token"]
    ah = {"Authorization": f"Bearer {adm_tok}"}

    pub = client.post(
        "/api/auth/register",
        json={"username": "pubcmp1", "email": "pubcmp1@x.com", "password": "UserCmp1#2026", "invite_code": "TESTINVITE"},
    ).json()
    uh = {"Authorization": f"Bearer {pub['token']}"}

    priv_up = client.post(
        "/api/heritage/upload",
        files={"file": ("priv.wav", _wav_bytes(1.2, 220.0), "audio/wav")},
        data={"title": "Secret Song"},
        headers=ah,
    )
    assert priv_up.status_code == 200
    priv_id = priv_up.json()["id"]

    pub_up = client.post(
        "/api/heritage/upload",
        files={"file": ("pub.wav", _wav_bytes(1.2, 330.0), "audio/wav")},
        data={"title": "Pub Song"},
        headers=uh,
    )
    assert pub_up.status_code == 200
    pub_id = pub_up.json()["id"]

    r_ok = client.post(
        "/api/music/compare-items",
        data={"sample_item_id": pub_id, "user_item_id": pub_id},
        headers=uh,
    )
    assert r_ok.status_code == 200, r_ok.text
    assert r_ok.json()["metrics"]["score"] >= 95.0

    r_upload_mix = client.post(
        "/api/music/compare-items",
        data={"sample_item_id": pub_id},
        files={"user": ("u.wav", _wav_bytes(1.2, 330.0), "audio/wav")},
        headers=uh,
    )
    assert r_upload_mix.status_code == 200, r_upload_mix.text
    assert r_upload_mix.json()["metrics"]["score"] >= 95.0

    r_forbidden = client.post(
        "/api/music/compare-items",
        data={"sample_item_id": priv_id, "user_item_id": pub_id},
        headers=uh,
    )
    assert r_forbidden.status_code == 404


def test_w2_safe_task_error_in_memory_and_queue(monkeypatch):
    def boom_generate(*a, **k):
        raise RuntimeError("failed reading /Users/secret/app.py on 127.0.0.1")

    monkeypatch.setattr(generator_service.ace_step_engine, "generate", boom_generate)
    db = SessionLocal()
    try:
        t = crud.create_task(db, "generate", {}, user_id=None)
        db_id = t.id
    finally:
        db.close()

    tid = db_id
    with generator_service.TASKS_LOCK:
        generator_service.TASKS[tid] = {"id": tid, "kind": "generate", "status": "queued", "created_at": 0}
    try:
        generator_service._run_generation(tid, db_id, "p", 30, 1, "", 0.8)
        reason = generator_service.TASKS[tid]["reason"]
        assert "/Users/secret" not in reason
        assert ".py" not in reason
    finally:
        with generator_service.TASKS_LOCK:
            generator_service.TASKS.pop(tid, None)

    monkeypatch.setattr(task_queue.runner, "run", boom_generate)
    db = SessionLocal()
    try:
        q_row = crud.create_task(db, "restore", {}, user_id=None)
        q_id = q_row.id
    finally:
        db.close()

    class _SyncPool:
        def submit(self, fn):
            fn()

    monkeypatch.setattr(task_queue, "get_pool", lambda *a, **k: _SyncPool())
    task_queue._run_inline(q_id, "restore", {})
    db = SessionLocal()
    try:
        err = crud.get_task(db, q_id).error
        assert "/Users/secret" not in err
        assert ".py" not in err
    finally:
        db.close()


def test_w2_lifespan_no_on_event_deprecation_and_utc_progress(monkeypatch):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        with TestClient(create_app()) as client:
            r = client.get("/health")
            assert r.status_code == 200
            assert r.json()["version"] == "0.0.5-beta2"
            prog = client.get("/api/lessons/my-progress").json()
            assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", prog["server_today"])
            assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", prog["server_utc_now"])
    on_event_warns = [w for w in caught if "on_event is deprecated" in str(w.message)]
    assert not on_event_warns


def test_w2_restore_item_and_detect_item_are_async_and_avatar_is_atomic():
    from app.api import instruments, restoration

    assert asyncio.iscoroutinefunction(restoration.restore_item)
    assert asyncio.iscoroutinefunction(instruments.detect_item)
    assert re.search(r"mkstemp|replace\(", Path(auth_mod.__file__).read_text(encoding="utf-8"))
