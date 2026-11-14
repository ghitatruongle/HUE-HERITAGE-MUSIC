import io
import struct
import wave

from fastapi.testclient import TestClient

from app.main import app
from app.database.session import SessionLocal
from app.database import crud
from app.ai import basic_pitch_amt as bp_amt
from app.api import lessons as lessons_api
from app.services import media_pipeline


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


def test_velocity_from_amplitude_full_range():
    assert bp_amt.velocity_from_amplitude(0.87) == 110
    assert bp_amt.velocity_from_amplitude(1.0) == 127
    assert bp_amt.velocity_from_amplitude(0.0) == 1
    assert bp_amt.velocity_from_amplitude(-0.5) == 1
    assert bp_amt.velocity_from_amplitude(0.004) == 1
    assert bp_amt.velocity_from_amplitude(0.008) == 1


def test_transcribe_notes_cache_roundtrip(monkeypatch):
    client = TestClient(app)
    data = make_sine_wav(freq=523.25, duration=0.9)
    r1 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60", "engine": "dsp"})
    assert r1.status_code == 200
    b1 = r1.json()
    assert b1["cached"] is False
    assert b1["count"] >= 1

    cache_path = media_pipeline.notes_cache_path(b1["sha"], 60.0, "dsp")
    assert cache_path.exists()

    r2 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60", "engine": "dsp"})
    assert r2.status_code == 200
    b2 = r2.json()
    assert b2["cached"] is True
    assert b2["notes"] == b1["notes"]
    assert b2["count"] == b1["count"]


def test_transcribe_cache_invalidated_by_bpm_change():
    client = TestClient(app)
    data = make_sine_wav(freq=587.33, duration=0.8)
    r1 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60", "engine": "dsp"})
    r2 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "90", "engine": "dsp"})
    assert r1.status_code == 200 and r2.status_code == 200
    assert r1.json()["cached"] is False
    assert r2.json()["cached"] is False


def test_scale_practice_precheck_413_before_read(monkeypatch):
    monkeypatch.setattr(lessons_api, "MAX_BYTES", 10)
    client = TestClient(app)
    r = client.post("/api/lessons/scales/bac/practice", files={"file": ("t.wav", make_sine_wav(duration=0.5), "audio/wav")}, params={"transpose": 0})
    assert r.status_code == 413
    assert b"too large" in r.content


def test_fail_stale_tasks_sweeps_pending_when_inline():
    db = SessionLocal()
    try:
        t_pending = crud.create_task(db, "transcribe", {"bpm": 60})
        t_running = crud.create_task(db, "transcribe", {"bpm": 60})
        crud.update_task(db, t_running.id, status="running")
        n = crud.fail_stale_running_tasks(db, include_pending=True)
        assert n >= 2
        db.expire_all()
        fresh_p = db.get(type(t_pending), t_pending.id)
        fresh_r = db.get(type(t_running), t_running.id)
        assert fresh_p.status == "error"
        assert fresh_p.error == "interrupted by server restart"
        assert fresh_p.finished_at is not None
        assert fresh_r.status == "error"
    finally:
        db.close()


def test_fail_stale_running_only_keeps_pending():
    db = SessionLocal()
    try:
        t_pending = crud.create_task(db, "transcribe", {"bpm": 60})
        t_running = crud.create_task(db, "transcribe", {"bpm": 60})
        crud.update_task(db, t_running.id, status="running")
        n = crud.fail_stale_running_tasks(db, include_pending=False)
        assert n >= 1
        db.expire_all()
        fresh_p = db.get(type(t_pending), t_pending.id)
        assert fresh_p.status == "pending"
    finally:
        db.close()


def test_transcribe_cache_respects_fractional_bpm():
    client = TestClient(app)
    data = make_sine_wav(freq=659.25, duration=0.8)
    r1 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60.5", "engine": "dsp"})
    r2 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60.7", "engine": "dsp"})
    r3 = client.post("/api/music/transcribe", files={"file": ("t.wav", data, "audio/wav")}, data={"bpm": "60.5", "engine": "dsp"})
    assert r1.status_code == 200 and r2.status_code == 200 and r3.status_code == 200
    assert r1.json()["cached"] is False
    assert r2.json()["cached"] is False
    assert r3.json()["cached"] is True


def test_notes_cache_path_separates_engine_and_bpm():
    sha = "c" * 64
    p_dsp = media_pipeline.notes_cache_path(sha, 60.5, "dsp")
    p_bp = media_pipeline.notes_cache_path(sha, 60.5, "basic_pitch")
    p_round = media_pipeline.notes_cache_path(sha, 60, "dsp")
    assert p_dsp != p_bp
    assert p_dsp == media_pipeline.notes_cache_path(sha, 60.5, "dsp")
    assert p_round == media_pipeline.notes_cache_path(sha, 60.0, "dsp")
    assert "60.5" in p_dsp.name
    assert "dsp" in p_dsp.name
