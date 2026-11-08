import asyncio
import io
import math
import struct
import wave

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import AudioFile, HeritageItem
from app.database.session import SessionLocal, engine
from app.main import SheddingMiddleware, create_app
from app.services import heritage_service, media_pipeline, pitch_service
from app.storage import manager


def _wav_bytes(frames, sr=8000, ch=1, sw=2):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(sw)
        w.setframerate(sr)
        if ch == 1:
            flat = list(frames)
        else:
            flat = []
            for v in frames:
                for _c in range(ch):
                    flat.append(v)
        if sw == 1:
            payload = bytes(bytearray((int(round(v * 127.0)) + 128) & 0xFF for v in flat))
        elif sw == 2:
            payload = struct.pack("<%dh" % len(flat), *[max(-32768, min(32767, int(round(v * 32768.0)))) for v in flat])
        else:
            payload = struct.pack("<%di" % len(flat), *[max(-2147483648, min(2147483647, int(round(v * 2147483647.0)))) for v in flat])
        w.writeframes(payload)
    return bio.getvalue()


def _reference_decode(data, max_seconds):
    bio = io.BytesIO(data)
    w = wave.open(bio, "rb")
    n = w.getnframes()
    ch = w.getnchannels()
    sr = w.getframerate()
    sw = w.getsampwidth()
    raw = w.readframes(n)
    w.close()
    frame_bytes = ch * sw
    n = min(n, len(raw) // frame_bytes)
    raw = raw[: n * frame_bytes]
    if sw == 1:
        vals = struct.unpack("<%dB" % (n * ch), raw)
        samples = [(v - 128) / 128.0 for v in vals]
    elif sw == 2:
        vals = struct.unpack("<%dh" % (n * ch), raw)
        samples = [v / 32768.0 for v in vals]
    else:
        vals = struct.unpack("<%di" % (n * ch), raw)
        samples = [v / 2147483648.0 for v in vals]
    if ch > 1:
        mono = []
        for i in range(n):
            s = 0.0
            for c in range(ch):
                s += samples[i * ch + c]
            mono.append(s / ch)
        samples = mono
    if max_seconds is not None and max_seconds > 0:
        samples = samples[: int(sr * max_seconds)]
    return samples


@pytest.mark.parametrize("sr,ch,sw,dur,max_seconds", [
    (8000, 1, 2, 1.0, None),
    (8000, 1, 2, 2.0, 0.5),
    (44100, 2, 2, 0.3, None),
    (8000, 1, 1, 0.4, None),
    (8000, 1, 4, 0.4, 0.2),
    (22050, 2, 2, 0.5, 0.25),
])
def test_read_mono_wav_matches_reference_bitwise(sr, ch, sw, dur, max_seconds):
    rng = np.random.default_rng(42)
    frames = (rng.uniform(-0.6, 0.6, size=int(sr * dur))).tolist()
    data = _wav_bytes(frames, sr=sr, ch=ch, sw=sw)
    got, got_sr = pitch_service.read_mono_wav(data, max_seconds=max_seconds)
    ref = _reference_decode(data, max_seconds)
    assert got_sr == sr
    assert isinstance(got, np.ndarray)
    assert np.array_equal(np.asarray(got, dtype=np.float64), np.asarray(ref, dtype=np.float64))


def test_read_mono_wav_cut_length_exact():
    sr = 8000
    frames = [0.1] * (sr * 2)
    data = _wav_bytes(frames, sr=sr)
    got, _ = pitch_service.read_mono_wav(data, max_seconds=0.5)
    assert len(got) == int(sr * 0.5)


def test_analyze_pitch_endpoint_ok():
    client = TestClient(create_app())
    sr = 16000
    t = np.arange(int(sr * 0.5)) / sr
    frames = (0.4 * np.sin(2 * math.pi * 220.0 * t)).tolist()
    r = client.post("/api/music/analyze-pitch", files={"file": ("a.wav", _wav_bytes(frames, sr=sr), "audio/wav")})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["sample_rate"] == sr
    assert "f0" in body and "times" in body


def test_transcribe_dsp_holds_no_db_connection(monkeypatch):
    def fake_extract(data, bpm, engine_name="basic_pitch"):
        status = engine.pool.status()
        assert "Current Checked out connections: 0" in status, status
        return [{"start": 0.0, "end": 0.1, "midi": 60, "duration": 0.1}], "dsp", None

    monkeypatch.setattr(media_pipeline, "extract_notes", fake_extract)
    client = TestClient(create_app())
    frames = [0.2] * 8000
    r = client.post(
        "/api/music/transcribe",
        files={"file": ("a.wav", _wav_bytes(frames), "audio/wav")},
        data={"bpm": "60"},
    )
    assert r.status_code == 200, r.text


def _clean_heritage():
    db = SessionLocal()
    try:
        db.query(AudioFile).delete()
        db.query(HeritageItem).delete()
        db.commit()
    finally:
        db.close()


def test_ingest_split_matches_ingest_upload():
    _clean_heritage()
    data = _wav_bytes([0.2] * 8000)
    db = SessionLocal()
    try:
        item, created = heritage_service.ingest_upload(db, data, "a.wav", "T1", "baihat")
        assert created is True
        item2, created2 = heritage_service.ingest_upload(db, data, "a.wav", "T1", "baihat")
        assert created2 is False and item2.id == item.id
    finally:
        db.close()
    path, digest, _fresh = heritage_service.save_upload_payload(data, "a.wav")
    db = SessionLocal()
    try:
        item3, created3 = heritage_service.ingest_saved(db, path, digest, len(data), "a.wav", "T1", "baihat")
        assert created3 is False and item3.id == item.id
    finally:
        db.close()


class _FakeRequest:
    def __init__(self, headers):
        self.headers = headers


def test_content_length_exceeds():
    assert manager.content_length_exceeds(_FakeRequest({"content-length": "11"}), 10) is True
    assert manager.content_length_exceeds(_FakeRequest({"content-length": "9"}), 10) is False
    assert manager.content_length_exceeds(_FakeRequest({}), 10) is False
    assert manager.content_length_exceeds(_FakeRequest({"content-length": "abc"}), 10) is False


def _receive():
    async def _recv():
        return {"type": "http.request", "body": b"", "more_body": False}
    return _recv


def _sender(bucket):
    async def _send(msg):
        bucket.append(msg)
    return _send


def _run_mw(mw, path):
    bucket = []
    asyncio.run(mw({"type": "http", "path": path}, _receive(), _sender(bucket)))
    return bucket


def test_shedding_exempts_auth_login_and_unlock():
    calls = []

    async def app(scope, receive, send):
        calls.append(scope["path"])
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    mw = SheddingMiddleware(app, max_in_flight=1)
    mw.in_flight = 1
    bucket = _run_mw(mw, "/api/auth/login")
    assert calls == ["/api/auth/login"]
    assert bucket[0]["status"] == 200
    bucket2 = _run_mw(mw, "/api/auth/admin-unlock")
    assert bucket2[0]["status"] == 200
    bucket3 = _run_mw(mw, "/api/heritage")
    assert bucket3[0]["status"] == 503


def test_cors_wildcard_suppressed_when_auth_on(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "allowed_origins", "*", raising=False)
    client = TestClient(create_app())
    r = client.options("/api/heritage", headers={
        "Origin": "http://evil.example",
        "Access-Control-Request-Method": "GET",
    })
    assert r.headers.get("access-control-allow-origin") is None


def test_cors_explicit_origin_allowed(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "allowed_origins", "http://good.example", raising=False)
    client = TestClient(create_app())
    r = client.options("/api/heritage", headers={
        "Origin": "http://good.example",
        "Access-Control-Request-Method": "GET",
    })
    assert r.headers.get("access-control-allow-origin") == "http://good.example"


def test_cors_auth_off_keeps_wildcard(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "allowed_origins", "*", raising=False)
    client = TestClient(create_app())
    r = client.options("/api/heritage", headers={
        "Origin": "http://any.example",
        "Access-Control-Request-Method": "GET",
    })
    assert r.headers.get("access-control-allow-origin") == "*"


def test_dsp_endpoints_accept_up_to_15mb_bodies():
    from fastapi.testclient import TestClient
    import wave as _wave
    import io as _io

    def wav_bytes_3mb():
        bio = _io.BytesIO()
        with _wave.open(bio, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(8000)
            w.writeframes(b"\x00\x40" * (8000 * 190))
        return bio.getvalue()

    client = TestClient(create_app())
    big = wav_bytes_3mb()
    assert len(big) > 2 * 1024 * 1024
    r = client.post("/api/music/instruments", files={"file": ("big.wav", big, "audio/wav")})
    assert r.status_code in (200, 400), f"BodyLimit/DSP fail: {r.status_code} {r.text[:120]}"
    r2 = client.post("/api/music/transcribe", files={"file": ("big.wav", big, "audio/wav")}, data={"bpm": "60", "engine": "dsp"})
    assert r2.status_code in (200, 400), f"BodyLimit/transcribe fail: {r2.status_code} {r2.text[:120]}"


def test_compare_middleware_allows_two_large_files():
    from app.main import COMPARE_BODY_LIMIT, BodyLimitMiddleware
    bl = BodyLimitMiddleware(app=None)
    assert bl._limit_for("/api/music/compare") == COMPARE_BODY_LIMIT == 2 * 15 * 1024 * 1024 + 2 * 1024 * 1024
    assert bl._limit_for("/api/music/instruments") == 15 * 1024 * 1024


def test_error_responses_carry_security_headers():
    import asyncio as _asyncio

    from app.main import SecurityHeadersMiddleware, SheddingMiddleware

    client = TestClient(create_app())
    r = client.get("/health")
    assert r.headers.get("content-security-policy"), "health thiếu CSP"
    assert r.headers.get("x-content-type-options") == "nosniff"

    class _Terminal:
        async def __call__(self, scope, receive, send):
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b"x"})

    shedding = SheddingMiddleware(_Terminal(), max_in_flight=1)
    stack = SecurityHeadersMiddleware(shedding)
    captured = []

    async def _recv():
        return {"type": "http.request", "body": b"", "more_body": False}

    async def _send(msg):
        captured.append(msg)

    shedding.in_flight = 1
    _asyncio.run(stack({"type": "http", "path": "/api/heritage", "method": "GET"}, _recv, _send))
    shed = captured[0]
    assert shed["status"] == 503, f"test phải thật sự shed 503, thấy {shed['status']}'"

    hdrs = {k.decode() if isinstance(k, bytes) else k: v.decode() if isinstance(v, bytes) else v
            for k, v in shed["headers"]}
    assert hdrs.get("content-security-policy"), "503 shed thiếu CSP"
    assert hdrs.get("x-content-type-options") == "nosniff", "503 shed thiếu nosniff"
    assert hdrs.get("x-frame-options") == "DENY", "503 shed thiếu X-Frame-Options"


def test_token_responses_are_no_store():
    client = TestClient(create_app())
    r = client.post("/api/auth/login", json={"identifier": "x", "password": "y"})
    assert r.headers.get("cache-control") == "no-store", f"login thiếu no-store: {r.headers.get('cache-control')}"
    r = client.get("/health")
    assert "no-store" not in r.headers.get("cache-control", ""), "health không cần no-store"
