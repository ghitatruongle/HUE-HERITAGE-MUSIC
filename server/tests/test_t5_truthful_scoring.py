import io
import math
import wave

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app
from app.services import compare_service, amt_service
from tests.test_alpha2_learning import _tone_wav


def test_octave_normalized_scoring_keeps_pitch_score_high():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([440.0, 660.0], tone_len=1.2))
    m = r["metrics"]
    assert m["pitch_score"] >= 90
    assert all(abs(n["err_cents"]) <= 100 for n in r["notes"])
    assert all(n["octave_diff"] for n in r["notes"])


def test_octave_below_reference_also_normalized():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([110.0, 165.0], tone_len=1.2))
    notes = [n for n in r["notes"] if n["verdict_code"] != "unclear"]
    assert notes
    assert all(n["octave_diff"] for n in notes)
    assert all(abs(n["err_cents"]) <= 100 for n in notes)


def test_beginner_verdict_thresholds_pinned():
    assert compare_service.OK_CENTS == 35.0
    assert compare_service.MINOR_CENTS == 65.0


def test_segmentation_thresholds_unified():
    assert compare_service.REF_DELTA_CENTS == amt_service.SEMI_TOL


def test_cents_25_now_verdict_ok():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2, cents_off=25))
    assert all(n["verdict_code"] == "ok" for n in r["notes"])


def test_unmatched_note_err_cents_is_null():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0, 587.0], tone_len=1.0, gap=0.4))
    extra = [n for n in r["notes"] if n["verdict_code"] == "unclear"]
    assert extra
    assert all(n["err_cents"] is None for n in extra)
    assert all(n["octave_diff"] is False for n in extra)


def test_silent_user_raises_too_quiet():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    silent = _tone_wav([220.0, 330.0], tone_len=1.2)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        for _ in range(16000 * 2):
            w.writeframes((0).to_bytes(2, "little", signed=True))
    with pytest.raises(compare_service.CompareEmptyError) as ei:
        compare_service.compare(ref, buf.getvalue())
    assert ei.value.code == "too_quiet"


def test_ultra_short_user_raises_too_short():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        for i in range(200):
            v = int(8000 * math.sin(2 * math.pi * 220.0 * i / 16000))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    with pytest.raises(compare_service.CompareEmptyError) as ei:
        compare_service.compare(ref, buf.getvalue())
    assert ei.value.code == "too_short"


def test_noise_user_completes_without_crash():
    import random

    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    rng = random.Random(7)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        for _ in range(16000 * 2):
            v = int(rng.uniform(-6000, 6000))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    r = compare_service.compare(ref, buf.getvalue())
    assert "metrics" in r


def test_long_take_flagged_truncated():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    user = _tone_wav([220.0, 330.0, 220.0, 330.0], tone_len=7.0, gap=2.5)
    r = compare_service.compare(ref, user)
    m = r["metrics"]
    assert m["truncated"] is True
    assert m["uploaded_seconds"] >= 37.0
    assert m["analyzed_seconds"] <= compare_service.MAX_COMPARE_SECONDS + 0.1


def test_short_take_not_flagged_truncated():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2))
    m = r["metrics"]
    assert m["truncated"] is False
    assert m["uploaded_seconds"] is not None
    assert m["analyzed_seconds"] > 0


def _env_client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    return TestClient(create_app())


def test_compare_endpoint_returns_structured_error_code(monkeypatch):
    client = _env_client(monkeypatch)
    ref = _tone_wav([220.0], tone_len=1.0)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        for _ in range(16000):
            w.writeframes((0).to_bytes(2, "little", signed=True))
    r = client.post(
        "/api/music/compare",
        files={"sample": ("ref.wav", ref, "audio/wav"), "user": ("u.wav", buf.getvalue(), "audio/wav")},
    )
    assert r.status_code == 422
    body = r.json()
    assert body["detail"]["code"] == "too_quiet"
    assert body["detail"]["message"]


def test_practice_endpoint_returns_structured_error_code(monkeypatch):
    client = _env_client(monkeypatch)
    audio = _tone_wav([220.0, 330.0], tone_len=1.2)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", audio, "audio/wav")},
        data={"title": "Bai T5", "type": "Ca Hue", "lyrics_with_ornaments": "Cau mot\nCau hai"},
    )
    assert up.status_code == 200, up.text
    lid = up.json()["id"]
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        for _ in range(16000 * 2):
            w.writeframes((0).to_bytes(2, "little", signed=True))
    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", buf.getvalue(), "audio/wav")})
    assert r.status_code == 422
    assert r.json()["detail"]["code"] in ("too_quiet", "no_voice", "reference_invalid")
