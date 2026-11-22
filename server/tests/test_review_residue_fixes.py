import json

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.models import HeritageItem, User
from app.database.session import SessionLocal
from app.main import create_app
from app.services import media_pipeline
from app.services.task_error import safe_task_error
from app.workers import queue as task_queue


def test_safe_task_error_strips_local_paths():
    err = FileNotFoundError("[Errno 2] No such file: /home/dev/hue/workers/runner.py")
    out = safe_task_error(err)
    assert "/Users/" not in out
    assert "runner.py" not in out
    assert out.startswith("FileNotFoundError:")


def test_safe_task_error_truncates_long_messages():
    err = RuntimeError("x" * 5000)
    assert len(safe_task_error(err)) <= 300


def test_write_artifacts_leaves_no_part_files(monkeypatch):
    import pathlib
    import shutil

    from app.config import settings as _s

    root = pathlib.Path("/tmp/hue_s2_test_storage")
    shutil.rmtree(root, ignore_errors=True)
    monkeypatch.setattr(_s, "storage_dir", root)
    notes = [{"midi": 60, "start": 0.0, "end": 0.5, "velocity": 80}]
    digest, stem, mid, xm = media_pipeline.write_artifacts(b"data", notes, 90.0, "src")
    assert mid.exists()
    assert xm.exists()
    parts = list(mid.parent.glob("*.part")) + list(xm.parent.glob("*.part"))
    assert parts == [], f"file .part sót: {parts}"


def test_dispatch_marks_error_when_inline_crashes(monkeypatch):
    from sqlalchemy import text

    monkeypatch.setattr(settings, "use_rq", False, raising=False)

    def boom(task_id, kind, params):
        raise RuntimeError("inline exploded")

    monkeypatch.setattr(task_queue, "_run_inline", boom)
    with pytest.raises(RuntimeError):
        task_queue.dispatch("transcribe", {}, user_id=None)
    db = SessionLocal()
    try:
        row = db.execute(
            text("SELECT status, error FROM tasks WHERE error LIKE '%failed to start%' ORDER BY created_at DESC LIMIT 1")
        ).first()
        assert row is not None, "task không được đánh dấu error"
        assert row[0] == "error", f"task phải thành error, nhận {row[0]}"
    finally:
        db.close()


def test_ingest_saved_compensates_when_audio_create_fails(monkeypatch):
    import secrets as _secrets
    from pathlib import Path
    import tempfile

    from app.services import heritage_service

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", _secrets.token_hex(32), raising=False)
    db = SessionLocal()
    try:
        before = db.query(HeritageItem).count()
    finally:
        db.close()

    def broken_audio(*a, **k):
        raise RuntimeError("audio row exploded")

    monkeypatch.setattr(crud, "create_audio", broken_audio)
    tmp = Path(tempfile.mkdtemp()) / "up.wav"
    tmp.write_bytes(b"\x00" * 64)
    digest = "digest" + _secrets.token_hex(16)
    db = SessionLocal()
    try:
        with pytest.raises(RuntimeError):
            heritage_service.ingest_saved(db, tmp, digest, 64, "up.wav", "S6 title", "audio")
        orphans = db.query(HeritageItem).filter(HeritageItem.sha256 == digest).count()
        assert orphans == 0, f"item cụt phải bị dọn, còn {orphans}"
    finally:
        db.close()


def test_crash_reports_list_omits_detail_by_design(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", __import__("secrets").token_hex(32), raising=False)
    client = TestClient(create_app())
    db = SessionLocal()
    try:
        crud.create_crash_report(db, None, "0.0.5-alpha", "macos", "boom summary", "boom detail body")
    finally:
        db.close()
    r = client.post(
        "/api/auth/register",
        json={
            "username": settings.admin_truong_username,
            "email": f"{settings.admin_truong_username}@gmail.com",
            "password": "secret123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    client2 = TestClient(create_app())  # boot thứ hai: promote admin trưởng
    tok = client2.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]
    resp = client2.get("/api/admin/crash-reports", headers={"Authorization": f"Bearer {tok}"})
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert len(items) >= 1
    assert all("detail" not in i for i in items), "list giữ design cũ: không trả detail (unbounded guard)"
    target = items[0]["id"]
    r2 = client2.get(f"/api/admin/crash-reports/{target}", headers={"Authorization": f"Bearer {tok}"})
    assert r2.status_code == 200
    assert r2.json().get("detail") == "boom detail body", "detail đầy đủ qua endpoint {id}"


def test_wav_magic_rejects_zero_riff_size(monkeypatch):
    from app.storage.manager import audio_magic_ok

    assert audio_magic_ok(".wav", b"RIFF" + b"\x00\x00\x00\x00" + b"WAVE" + b"\x00" * 8) is False
    assert audio_magic_ok(".wav", b"RIFF" + (100).to_bytes(4, "little") + b"WAVE" + b"\x00" * 8) is True
