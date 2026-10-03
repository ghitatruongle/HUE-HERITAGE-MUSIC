import io
import math

import numpy as np
import soundfile as sf
from fastapi.testclient import TestClient

from server.app.main import app, create_app
from server.app.database.session import SessionLocal
from server.app.database import crud
from server.app.services import pitch_service


def make_sine_mp3(freq=220.0, duration=1.0, sr=22050):
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    tone = (0.5 * np.sin(2 * math.pi * freq * t) * 32767).astype(np.int16)
    bio = io.BytesIO()
    sf.write(bio, tone, sr, format="MP3")
    bio.seek(0)
    return bio.read()


def test_read_mono_wav_decodes_mp3_via_librosa():
    data = make_sine_mp3()
    samples, sr = pitch_service.read_mono_wav(data)
    assert sr == 22050
    assert len(samples) > 8000
    assert any(v != 0.0 for v in samples)


def test_analyze_pitch_accepts_mp3_upload():
    client = TestClient(app)
    data = make_sine_mp3(freq=220.0)
    r = client.post(
        "/api/music/analyze-pitch",
        files={"file": ("sine.mp3", data, "audio/mpeg")},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["sample_rate"] == 22050
    assert 200.0 < body["mean_f0"] < 240.0


def test_stale_running_tasks_fail_on_startup():
    db = SessionLocal()
    try:
        stuck = crud.create_task(db, "generate", {"prompt": "x"})
        crud.update_task(db, stuck.id, status="running")
        create_app()
        db.expire_all()
        task = crud.get_task(db, stuck.id)
        assert task.status == "error"
        assert "restart" in (task.error or "")
        assert task.finished_at is not None
    finally:
        db.close()
