import io
import math
import wave
from concurrent.futures import ThreadPoolExecutor

from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app


def _tone(freq=220.0, seconds=2.0, sr=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        n = int(seconds * sr)
        for i in range(n):
            env = min(1.0, i / (sr * 0.05), (n - i) / (sr * 0.05))
            v = int(8000 * env * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def test_concurrent_practice_no_500(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    app = create_app()
    setup = TestClient(app)
    r = setup.post(
        "/api/heritage/upload",
        files={"file": ("load.wav", _tone(220.0, 3.0), "audio/wav")},
        data={"title": "Load lesson", "type": "Ca Hue", "featured_in_creation": "true"},
    )
    assert r.status_code == 200
    lesson_id = r.json()["id"]
    detail = setup.get(f"/api/lessons/{lesson_id}")
    assert detail.status_code == 200
    assert detail.json()["sections"]

    upload = _tone(220.0, 2.0)
    results = []

    def one(i):
        client = TestClient(app)
        rr = client.post(
            f"/api/lessons/{lesson_id}/practice?section=0",
            files={"file": ("u.wav", upload, "audio/wav")},
        )
        return rr.status_code

    with ThreadPoolExecutor(max_workers=12) as ex:
        results = list(ex.map(one, range(12)))

    assert all(code == 200 for code in results), results
