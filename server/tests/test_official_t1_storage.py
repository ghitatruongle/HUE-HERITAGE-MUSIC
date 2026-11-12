import io
import os
import time
import wave
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.models import AudioFile, HeritageItem, PracticeSession, User
from app.database.session import SessionLocal
from app.main import create_app
from app.services import maintenance
from app.storage import manager


def _db():
    return SessionLocal()


def test_cleanup_covers_restored_and_musicxml():
    restored = manager.restored_dir() / "official_t1_old_restored.wav"
    restored.write_bytes(b"x" * 2048)
    xml = manager.xml_dir() / "official_t1_old_stem.musicxml"
    xml.write_text("<score/>" * 100, encoding="utf-8")
    fresh = manager.restored_dir() / "official_t1_fresh_restored.wav"
    fresh.write_bytes(b"y" * 512)
    old = time.time() - 40 * 86400
    os.utime(restored, (old, old))
    os.utime(xml, (old, old))
    db = _db()
    try:
        details = maintenance.run_storage_cleanup(db)
    finally:
        db.close()
    assert details["restored"]["files"] >= 1
    assert details["restored"]["bytes"] >= 2048
    assert details["musicxml"]["files"] >= 1
    assert not restored.exists()
    assert not xml.exists()
    assert fresh.exists()
    fresh.unlink(missing_ok=True)


def test_orphan_lesson_samples_removed():
    db = _db()
    try:
        item = HeritageItem(title="t1-orphan", type="audio", sha256="a" * 64, filename="f.wav", size=1)
        db.add(item)
        db.commit()
        root = Path(settings.storage_dir) / "heritage" / "lesson_samples"
        orphan = root / ("b" * 64)
        orphan.mkdir(parents=True, exist_ok=True)
        (orphan / "1.wav").write_bytes(b"z" * 1024)
        live = root / ("a" * 64)
        live.mkdir(parents=True, exist_ok=True)
        (live / "0.wav").write_bytes(b"z" * 1024)
        details = maintenance._cleanup_orphan_lesson_samples(db)
        assert details["dirs"] >= 1
        assert details["bytes"] >= 1024
        assert not orphan.exists()
        assert live.exists()
        db.delete(item)
        db.commit()
    finally:
        db.close()


def test_cleanup_preserves_gitkeep_marker():
    marker = manager.restored_dir() / ".gitkeep"
    old = time.time() - 40 * 86400
    marker.touch()
    os.utime(marker, (old, old))
    victim = manager.restored_dir() / "official_t1_gitkeep_victim.wav"
    victim.write_bytes(b"x" * 128)
    os.utime(victim, (old, old))
    db = _db()
    try:
        details = maintenance.run_storage_cleanup(db)
    finally:
        db.close()
    assert marker.exists()
    assert not victim.exists()
    assert details["restored"]["files"] >= 1
    victim.unlink(missing_ok=True)


def test_delete_user_cascades_practice_sessions():
    db = _db()
    try:
        u = User(username="official_t1_cascade_user", email="t1cascade@x.com", password_hash="x")
        db.add(u)
        db.commit()
        crud.create_practice_session(db, u.id, "lessonX", 1, 90, 90, 90, 90)
        assert db.query(PracticeSession).filter(PracticeSession.user_id == u.id).count() == 1
        assert crud.delete_user_everything(db, u.id) is True
        assert db.query(PracticeSession).filter(PracticeSession.user_id == u.id).count() == 0
    finally:
        db.close()


def _wav_bytes(seconds, sr=16000, fill=None):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(fill if fill else b"\x00\x40" * (sr * seconds))
    return bio.getvalue()


def _wipe_users():
    db = _db()
    try:
        db.query(AudioFile).delete()
        db.query(HeritageItem).delete()
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()


def test_upload_quota_blocks_regular_user_and_admin_exempt(monkeypatch):
    monkeypatch.setattr(settings, "user_storage_quota_mb", 1, raising=False)
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    _wipe_users()
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "quota_user1", "email": "t1quota@x.com",
        "password": "QuotaPass#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client.post("/api/auth/login", json={"identifier": "quota_user1", "password": "QuotaPass#2026"})
    assert r.status_code == 200, r.text
    client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    big = _wav_bytes(seconds=40)
    assert len(big) > 1024 * 1024
    r = client.post("/api/heritage/upload", files={"file": ("big.wav", big, "audio/wav")}, data={"title": "over quota"})
    assert r.status_code == 413, r.text
    assert "quota" in r.json()["detail"].lower()
    me = client.get("/api/auth/me")
    assert me.status_code == 200
    assert me.json()["storage_quota_bytes"] == 1024 * 1024

    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "t1admin@x.com",
        "password": "QuotaAdmin#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    admin_client = TestClient(create_app())
    r = admin_client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "QuotaAdmin#2026"})
    assert r.status_code == 200, r.text
    admin_client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    r = admin_client.post(
        "/api/heritage/upload", files={"file": ("big.wav", big, "audio/wav")},
        data={"title": "admin exempt"})
    assert r.status_code == 200, r.text
    me = client.get("/api/auth/me")
    assert me.status_code == 200
    admin_me = admin_client.get("/api/auth/me")
    assert admin_me.json()["storage_quota_bytes"] is None
    _wipe_users()


def test_me_reports_storage_used():
    db = _db()
    try:
        u = User(username="official_t1_me_user", email="t1me@x.com", password_hash="x")
        db.add(u)
        db.commit()
        item = HeritageItem(title="t1me", type="audio", sha256="c" * 64, filename="f.wav", size=7777, owner_user_id=u.id)
        db.add(item)
        db.commit()
        db.add(AudioFile(item_id=item.id, kind="original", path="/tmp/x.wav", sha256="c" * 64, size=7777))
        db.commit()
        used = crud.user_storage_bytes(db, u.id)
        assert used == 7777
        assert crud.user_storage_bytes(db, None) == 0
        db.delete(db.query(AudioFile).filter(AudioFile.item_id == item.id).first())
        db.delete(item)
        db.delete(u)
        db.commit()
    finally:
        db.close()


def test_dedup_does_not_leak_admin_only_metadata(monkeypatch):
    import time as _time

    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    _wipe_users()
    admin_client = TestClient(create_app())
    r = admin_client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "dk1@x.com",
        "password": "DkAdmin#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    TestClient(create_app())
    r = admin_client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "DkAdmin#2026"})
    admin_client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    wav = _wav_bytes(seconds=1, fill=b"\x51\x52" * 4000)
    r = admin_client.post("/api/heritage/upload", files={"file": ("secret.wav", wav, "audio/wav")},
                          data={"title": "BI MAT NOI BO", "description": "nhaay cam"})
    assert r.status_code == 200, r.text
    assert r.json()["visibility"] == "admin_only"
    tag = int(_time.time() % 100000)
    r = client_reg = TestClient(create_app())
    r = client_reg.post("/api/auth/register", json={
        "username": f"dkuser{int(tag)}", "email": f"dk{int(tag)}@x.com",
        "password": "DkUser#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client_reg.post("/api/auth/login", json={"identifier": f"dkuser{int(tag)}", "password": "DkUser#2026"})
    client_reg.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    r = client_reg.post("/api/heritage/upload", files={"file": ("same.wav", wav, "audio/wav")},
                        data={"title": "cua toi"})
    check_leak = r.status_code == 200 and "BI MAT" in str(r.json())
    assert r.status_code == 404, f"dedup leak: {r.status_code} {r.text[:120]}"
    assert "BI MAT" not in r.text
    r = client_reg.get("/api/heritage")
    assert "BI MAT" not in r.text
    _wipe_users()
