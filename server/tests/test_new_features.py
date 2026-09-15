import io
import json
import struct
import wave

from fastapi.testclient import TestClient

from server.app.main import app
from server.app.database.session import SessionLocal
from server.app.database import crud
from server.app.config import settings
from server.app.ai import basic_pitch_amt as bp_amt


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
    r = client.post("/api/auth/register", json={"username": "ghita", "password": "hue12345"})
    assert r.status_code == 200
    token = r.json()["token"]
    assert token.count(".") == 2
    r = client.post("/api/auth/login", json={"username": "ghita", "password": "hue12345"})
    assert r.status_code == 200
    r = client.post("/api/auth/login", json={"username": "ghita", "password": "wrong-pass"})
    assert r.status_code == 401
    r = client.post("/api/auth/register", json={"username": "ghita", "password": "hue12345"})
    assert r.status_code == 409
    r = client.post("/api/auth/register", json={"username": "x", "password": "123"})
    assert r.status_code == 400


def test_auth_guard_blocks_writes_when_required(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True)
    client = TestClient(app)
    data = make_sine_wav()
    r = client.post("/api/heritage/upload", files={"file": ("a.wav", data, "audio/wav")})
    assert r.status_code == 401
    r = client.post("/api/auth/register", json={"username": "guarduser", "password": "pass1234"})
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
    assert any(i["id"] == item_id for i in r.json())
    r = client.get("/api/heritage", params={"q": "Sáu Thùng"})
    assert any(i["id"] == item_id for i in r.json())
    r = client.get("/api/heritage", params={"q": "1968"})
    assert any(i["id"] == item_id for i in r.json())


def test_transcribe_basic_pitch_detects_440hz():
    import pytest
    if not bp_amt.available():
        pytest.skip("basic_pitch unavailable")
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


def test_musicxml_dotted_output():
    from server.app.services import musicxml_service

    notes = [{"midi": 69, "freq": 440.0, "start": 0.0, "end": 1.5, "velocity": 80}]
    xml = musicxml_service.build_musicxml(notes, 60.0, "dotted")
    assert "<type>quarter</type>" in xml
    assert "<dot" in xml


def test_task_dispatch_inline(monkeypatch):
    from server.app.workers import queue as task_queue
    from server.app.storage import manager as storage_manager

    monkeypatch.setattr(task_queue, "_enqueue_rq", lambda *a, **k: False)
    wav = make_sine_wav(freq=523.25, duration=0.8)
    audio_path = storage_manager.temp_dir() / "clip.wav"
    audio_path.write_bytes(wav)
    client = TestClient(app)
    r = client.post("/api/task", json={"params": {"audio_path": str(audio_path), "bpm": 60}}, params={"kind": "transcribe"})
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
