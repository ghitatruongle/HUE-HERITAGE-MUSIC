import secrets
import struct
import time
import uuid

from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.session import SessionLocal
from app.main import create_app
from app.storage import manager as storage_manager


def _tone_wav(seconds=0.6, sr=16000):
    frames = b"".join(struct.pack("<h", int(8000 * ((i % 40) / 40 - 0.5))) for i in range(int(sr * seconds)))
    return (
        b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVEfmt "
        + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16) + b"data" + struct.pack("<I", len(frames)) + frames
    )


def _auth_on(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 100000, raising=False)
    return TestClient(create_app())


def _register(client, username, pw="Test#2026aa"):
    r = client.post("/api/auth/register", json={
        "username": username, "email": f"{username}@x.local",
        "password": pw, "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200, r.text
    return r.json()["token"]


def _bearer(tok):
    return {"Authorization": f"Bearer {tok}"}


def test_standalone_artifacts_owner_bound(monkeypatch):
    client = _auth_on(monkeypatch)
    victim = f"idoV{uuid.uuid4().hex[:8]}"
    attacker = f"idoA{uuid.uuid4().hex[:8]}"
    vt = _register(client, victim)
    at = _register(client, attacker)

    r = client.post(
        "/api/music/transcribe",
        files={"file": ("solo.wav", _tone_wav(), "audio/wav")},
        data={"bpm": "60", "engine": "dsp"},
        headers=_bearer(vt),
    )
    assert r.status_code == 200, r.text
    sha = r.json()["sha"]

    r = client.get(f"/api/music/midi/{sha}", headers=_bearer(vt))
    assert r.status_code == 200, f"owner phải đọc được artifact của chính mình: {r.status_code}"
    r = client.get(f"/api/music/midi/{sha}", headers=_bearer(at))
    assert r.status_code == 404, f"attacker đọc artifact victim phải 404: {r.status_code}"
    r = client.get(f"/api/music/musicxml/{sha}", headers=_bearer(at))
    assert r.status_code == 404
    r = client.get(f"/api/music/midi/{sha}")
    assert r.status_code == 401


def test_practice_midi_owner_bound(monkeypatch):
    client = _auth_on(monkeypatch)
    victim = f"idoP{uuid.uuid4().hex[:8]}"
    attacker = f"idoQ{uuid.uuid4().hex[:8]}"
    vt = _register(client, victim)
    at = _register(client, attacker)
    vid = client.get("/api/auth/me", headers=_bearer(vt)).json()["id"]

    midi_name = f"practice_{secrets.token_hex(12)}_1_{int(time.time())}.mid"
    db = SessionLocal()
    try:
        crud.create_practice_session(
            db, vid, "lesson-x", 1, 90.0, 90.0, 90.0, 90.0, "original",
            metrics={"score": 90.0}, user_midi=midi_name,
        )
    finally:
        db.close()
    (storage_manager.midi_dir() / midi_name).write_bytes(b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60")

    r = client.get(f"/api/lessons/practice-midi/{midi_name}", headers=_bearer(vt))
    assert r.status_code == 200, f"owner phải tải được bản thu luyện: {r.status_code}"
    r = client.get(f"/api/lessons/practice-midi/{midi_name}", headers=_bearer(at))
    assert r.status_code == 404, f"attacker tải bản thu luyện victim phải 404: {r.status_code}"
    r = client.get(f"/api/lessons/practice-midi/{midi_name}")
    assert r.status_code == 401


def test_task_generic_heritage_guard(monkeypatch):
    client = _auth_on(monkeypatch)
    victim = f"idoT{uuid.uuid4().hex[:8]}"
    attacker = f"idoU{uuid.uuid4().hex[:8]}"
    vt = _register(client, victim)
    at = _register(client, attacker)

    db = SessionLocal()
    try:
        secret_item = crud.create_item(
            db, "Bí mật IDOR", "bai_hat", secrets.token_hex(32), "secret.wav", 100,
            visibility="admin_only",
        )
        public_item = crud.create_item(
            db, "Công khai", "bai_hat", secrets.token_hex(32), "pub.wav", 100,
            visibility="public",
        )
        secret_id = secret_item.id
        public_id = public_item.id
    finally:
        db.close()

    r = client.post(
        "/api/task",
        params={"kind": "generic"},
        json={"note": "stealth", "heritage_id": secret_id},
        headers=_bearer(at),
    )
    assert r.status_code == 404, f"task generic tham chiếu item admin_only phải 404: {r.status_code}"

    r = client.post(
        "/api/task",
        params={"kind": "generic"},
        json={"note": "fine", "heritage_id": public_id},
        headers=_bearer(at),
    )
    assert r.status_code == 200, f"item public thì task generic phải 200: {r.status_code}"

    r = client.post(
        "/api/task",
        params={"kind": "generic"},
        json={"note": "no-ref"},
        headers=_bearer(at),
    )
    assert r.status_code == 200

    r = client.post(
        "/api/task",
        params={"kind": "generic"},
        json={"note": "anon-ref", "heritage_id": secret_id},
    )
    assert r.status_code == 401


def test_record_artifact_owner_race_serialized():
    import threading

    from app.database.session import SessionLocal

    sha = "race" + secrets.token_hex(28)
    results = []

    def worker(i):
        db = SessionLocal()
        try:
            crud.record_artifact_owner(db, sha, f"user-{i}", "test")
            results.append("ok")
        except Exception as e:
            results.append(f"EXC:{type(e).__name__}")
        finally:
            db.close()

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(16)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert all(r == "ok" for r in results), results
    db = SessionLocal()
    try:
        rows = db.query(crud.ArtifactOwner).filter(crud.ArtifactOwner.sha256 == sha).all()
        assert len(rows) == 1, f"phải đúng 1 row: {len(rows)}"
    finally:
        db.close()


def test_token_epoch_equality_blocks_future_epoch_forgery():
    import hashlib
    import hmac as _hmac
    import time as _time

    from app.api import auth as auth_mod

    client = TestClient(create_app())
    uname = f"epq{uuid.uuid4().hex[:8]}"
    r = client.post("/api/auth/register", json={
        "username": uname, "email": f"{uname}@x.local",
        "password": "Test#2026aa", "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200
    tok = r.json()["token"]
    uid, exp, epoch, _ = tok.split(".")
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert me.status_code == 200

    future_epoch = int(epoch) + 5
    exp_new = int(_time.time()) + 999
    payload = f"{uid}.{exp_new}.{future_epoch}"
    future = payload + "." + _hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    r = client.get("/api/auth/me", headers={"Authorization": f"Bearer {future}"})
    assert r.status_code == 401, f"epoch cao hơn hiện tại phải 401 (equality): {r.status_code}"


def test_admin_impersonation_usernames_blocked():
    client = TestClient(create_app())
    variants = ["GHITATRUONGLE", "ghitatruong.le", "gh_itatruongle", "ghitatruongle_"]
    for u in variants:
        r = client.post("/api/auth/register", json={
            "username": u, "email": f"{uuid.uuid4().hex[:6]}@x.local",
            "password": "Test#2026aa", "invite_code": "TESTINVITE",
        })
        assert r.status_code == 400, f"mạo danh '{u}' phải 400: {r.status_code} {r.text[:80]}"
    r = client.post("/api/auth/admin/users-x", json={})
    assert r.status_code in (404, 405, 401)
