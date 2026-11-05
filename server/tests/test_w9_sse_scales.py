import io
import math
import secrets
import time
import wave

from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app
from app.services import generator_service


def _scale_tone_wav(freqs, sr=16000, tone_len=1.0):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for freq in freqs:
            n = int(sr * tone_len)
            for i in range(n):
                env = min(1.0, i / (sr * 0.05), (n - i) / (sr * 0.05))
                v = int(8000 * env * math.sin(2 * math.pi * freq * i / sr))
                w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def test_scales_listed(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    r = client.get("/api/lessons/scales")
    assert r.status_code == 200
    ids = [s["id"] for s in r.json()]
    assert "bac" in ids and "nam" in ids


def test_scale_reference_wav(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    r = client.get("/api/lessons/scales/bac/reference.wav")
    assert r.status_code == 200
    assert r.content[:4] == b"RIFF"
    missing = client.get("/api/lessons/scales/nope/reference.wav")
    assert missing.status_code == 404


def test_scale_practice_scores_on_scale(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    data = _scale_tone_wav([261.63, 293.66, 349.23, 392.0, 440.0])
    r = client.post(
        "/api/lessons/scales/bac/practice",
        files={"file": ("scale.wav", data, "audio/wav")},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["score"] >= 65
    assert body["on_scale_share"] >= 0.8

    off = client.post(
        "/api/lessons/scales/nam/practice",
        files={"file": ("scale.wav", _scale_tone_wav([311.13, 415.3]), "audio/wav")},
    )
    assert off.status_code == 200
    assert off.json()["score"] < 70


def test_sse_task_events_terminal(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    tid = "task-sse-1"
    with generator_service.TASKS_LOCK:
        generator_service.TASKS[tid] = {
            "id": tid,
            "kind": "generate",
            "status": "done",
            "created_at": time.time(),
            "audio_url": f"/api/music/generated/{tid}.mp3",
        }
    try:
        client = TestClient(create_app())
        with client.stream("GET", f"/api/music/task/{tid}/events") as resp:
            assert resp.status_code == 200
            assert resp.headers["content-type"].startswith("text/event-stream")
            events = []
            for line in resp.iter_lines():
                if line.startswith("data: "):
                    events.append(line)
            assert events
            assert '"status": "done"' in events[-1] or '"status":"done"' in events[-1]
    finally:
        with generator_service.TASKS_LOCK:
            generator_service.TASKS.pop(tid, None)
