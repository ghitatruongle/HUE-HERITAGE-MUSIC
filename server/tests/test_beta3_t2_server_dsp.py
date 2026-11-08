import math
import time

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.audio_dsp import fft as dsp_fft
from app.audio_dsp import features
from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app
from app.services import user_inflight


def _py_fft(x):
    n = len(x)
    if n & (n - 1) != 0:
        p = 1
        while p < n:
            p <<= 1
        x = list(x) + [0.0] * (p - n)
        n = p
    a = [complex(v, 0) for v in x]
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    size = 2
    while size <= n:
        ang = -2 * math.pi / size
        wlen = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, size):
            w = complex(1, 0)
            half = size // 2
            for k in range(half):
                u = a[i + k]
                v = a[i + k + half] * w
                a[i + k] = u + v
                a[i + k + half] = u - v
                w *= wlen
        size <<= 1
    return a


def _py_ifft(x):
    n = len(x)
    if n & (n - 1) != 0:
        p = 1
        while p < n:
            p <<= 1
        x = list(x) + [0.0j] * (p - n)
    conj = [complex(v).conjugate() for v in x]
    y = _py_fft(conj)
    m = len(y)
    rec = [v.conjugate() / m for v in y]
    return rec[:n]


def _py_harmonicity(samples, sr):
    n = len(samples)
    e = sum(s * s for s in samples) / n
    if e < 0.0000001:
        return 0.0
    lmin = max(1, int(sr / 1000))
    lmax = min(int(sr / 50), n // 2)
    best = 0.0
    for lag in range(lmin, lmax):
        v = 0.0
        for i in range(n - lag):
            v += samples[i] * samples[i + lag]
        nv = v / ((n - lag) * e)
        if nv > best:
            best = nv
    return round(best, 3)


def test_fft_matches_python_reference_pow2_and_padded():
    rng = np.random.default_rng(7)
    for n in (64, 100):
        x = rng.uniform(-1, 1, size=n).tolist()
        got = dsp_fft.fft(x)
        ref = _py_fft(x)
        assert len(got) == len(ref)
        for g, r in zip(got, ref):
            assert abs(g - r) < 1e-6 * max(1.0, abs(r))


def test_ifft_matches_python_reference_roundtrip():
    rng = np.random.default_rng(11)
    for n in (64, 100):
        x = [complex(a, b) for a, b in rng.uniform(-1, 1, size=(n, 2))]
        got = dsp_fft.ifft(dsp_fft.fft([v.real for v in x]))
        ref = _py_ifft(_py_fft([v.real for v in x]))
        assert len(got) == len(ref)
        for g, r in zip(got, ref):
            assert abs(g - r) < 1e-6


def test_stft_istft_match_python_reference():
    rng = np.random.default_rng(3)
    samples = rng.uniform(-0.5, 0.5, size=5000).tolist()
    size, hop = 1024, 512
    win = dsp_fft.hann(size)
    frames, win2 = dsp_fft.stft(samples, size, hop)
    ref_frames = []
    pos = 0
    while pos + size <= len(samples):
        ref_frames.append([samples[pos + i] * win[i] for i in range(size)])
        pos += hop
    assert win2 == win
    assert len(frames) == len(ref_frames)
    for fr, rf in zip(frames, ref_frames):
        arr = np.asarray(fr)
        assert np.max(np.abs(arr - np.asarray(rf))) < 1e-12
    out = dsp_fft.istft(frames, win, size, hop)
    assert len(out) == (len(ref_frames) - 1) * hop + size
    center = size + 2 * hop
    ref_out = [0.0] * len(out)
    wsum = [0.0] * len(out)
    for f, fr in enumerate(ref_frames):
        p = f * hop
        for i in range(size):
            ref_out[p + i] += fr[i].real * win[i]
            wsum[p + i] += win[i] * win[i]
    for i in range(len(out)):
        if wsum[i] > 1e-9:
            ref_out[i] /= wsum[i]
    assert max(abs(a - b) for a, b in zip(out, ref_out)) < 1e-9


def test_harmonicity_matches_python_reference():
    sr = 16000
    n = 2048
    rng = np.random.default_rng(5)
    t = np.arange(n) / sr
    fixtures = [
        (0.5 * np.sin(2 * math.pi * 220.0 * t) + 0.05 * rng.uniform(-1, 1, n)).tolist(),
        rng.uniform(-0.8, 0.8, size=n).tolist(),
        (0.3 * np.sin(2 * math.pi * 330.0 * t)).tolist(),
        [0.0] * n,
    ]
    for samples in fixtures:
        got = features.harmonicity(samples, sr)
        ref = _py_harmonicity(samples, sr)
        assert got == ref, (got, ref)


def test_lesson_build_single_flight(monkeypatch):
    from app.services import lesson_service

    import threading as _t

    state = {"builds": 0}
    guard = _t.Lock()

    def fake_cached(item):
        with guard:
            built = state["builds"]
        if built == 0:
            return None
        return {"sections": [], "built": item.sha256}

    def fake_build(item):
        with guard:
            state["builds"] += 1
        time.sleep(0.03)
        return {"sections": [], "built": item.sha256}

    monkeypatch.setattr(lesson_service, "_try_cached_lesson", fake_cached)
    monkeypatch.setattr(lesson_service, "build_lesson", fake_build)

    class FakeItem:
        sha256 = "deadbeef" * 8
        id = "item-1"

    item = FakeItem()
    results = []
    errors = []
    threads = []
    for _ in range(5):
        th = _t.Thread(target=lambda: _safe(results, errors, lesson_service.get_lesson, item))
        threads.append(th)
        th.start()
    for th in threads:
        th.join()
    assert errors == []
    assert state["builds"] == 1
    assert len(results) == 5
    assert all(r["built"] == item.sha256 for r in results)


def _safe(results, errors, fn, item):
    try:
        results.append(fn(item))
    except Exception as e:
        errors.append(e)


def test_user_inflight_acquire_release():
    user_inflight.release("t:x")
    assert user_inflight.try_acquire("t:x", 2) is True
    assert user_inflight.try_acquire("t:x", 2) is True
    assert user_inflight.try_acquire("t:x", 2) is False
    user_inflight.release("t:x")
    assert user_inflight.try_acquire("t:x", 2) is True
    user_inflight.release("t:x")
    user_inflight.release("t:x")
    assert user_inflight.current("t:x") == 0


@pytest.fixture()
def heavy_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-t2-heavy-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    yield
    user_inflight.reset()


def test_instruments_per_user_cap_429(heavy_env):
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "t2user", "email": "t2user@x.com",
        "password": "DepCoDau#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client.post("/api/auth/login", json={"identifier": "t2user", "password": "DepCoDau#2026"})
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    me = client.get("/api/auth/me", headers=headers)
    assert me.status_code == 200, me.text
    uid = me.json()["id"]
    key = f"instruments:{uid}"
    assert user_inflight.try_acquire(key) is True
    assert user_inflight.try_acquire(key) is True
    r = client.post("/api/music/instruments", headers=headers, files={"file": ("a.wav", b"RIFFdummy", "audio/wav")})
    assert r.status_code == 429, r.text
    user_inflight.release(key)
    r = client.post("/api/music/instruments", headers=headers, files={"file": ("a.wav", b"RIFFdummy", "audio/wav")})
    assert r.status_code in (200, 400)
