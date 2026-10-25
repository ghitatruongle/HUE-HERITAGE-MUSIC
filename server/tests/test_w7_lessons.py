import io
import math
import wave

from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app
from app.storage import manager


def _tone_wav(freqs, sr=16000, tone_len=2.0, gap=1.2):
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
            for _ in range(int(sr * gap)):
                w.writeframes((0).to_bytes(2, "little", signed=True))
    return buf.getvalue()


def _upload_lesson(client, title, data, lyrics="Câu mot\nCâu hai"):
    return client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", data, "audio/wav")},
        data={
            "title": title,
            "type": "Ca Hue",
            "lyrics_with_ornaments": lyrics,
            "mode_system": "Nam",
            "featured_in_creation": "true",
        },
    )


def test_lesson_flow(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    audio = _tone_wav([220.0, 330.0])
    r = _upload_lesson(client, "Bai hoc mau", audio)
    assert r.status_code == 200, r.text
    lesson_id = r.json()["id"]

    lessons = client.get("/api/lessons").json()
    ids = [x["id"] for x in lessons]
    assert lesson_id in ids

    detail = client.get(f"/api/lessons/{lesson_id}")
    assert detail.status_code == 200
    body = detail.json()
    assert len(body["sections"]) >= 2
    assert body["contour"]["f0"]
    assert "Câu" in (body["lyrics"] or "") or body["lyrics"] == "Câu mot\nCâu hai"

    lessons = client.get("/api/lessons").json()
    summary = next(x for x in lessons if x["id"] == lesson_id)
    assert summary["sections"] >= 2

    practice = client.post(
        f"/api/lessons/{lesson_id}/practice?section=0",
        files={"file": ("user.wav", _tone_wav([220.0]), "audio/wav")},
    )
    assert practice.status_code == 200, practice.text
    pres = practice.json()
    assert pres["metrics"]["score"] >= 0
    assert len(pres["sample"]["f0"]) == len(pres["user_warped"]["f0"])
    assert pres["section"]["index"] == 0

    missing = client.post(
        f"/api/lessons/{lesson_id}/practice?section=99",
        files={"file": ("user.wav", _tone_wav([220.0]), "audio/wav")},
    )
    assert missing.status_code == 404


def test_lesson_missing_audio_404(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    r = client.get("/api/lessons/nope")
    assert r.status_code == 404
