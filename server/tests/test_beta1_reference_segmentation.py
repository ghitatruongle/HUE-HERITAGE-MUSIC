import io
import math
import secrets
import wave

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.api import auth as auth_mod
from app.config import settings
from app.database import crud as _crud
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app
from app.services import compare_service, lesson_service, pitch_service


def _synth_wav(freqs, sr=16000, tone_len=1.0, gap=0.5, jitter_cents=0.0):
    rng = np.random.default_rng(7)
    samples = []
    for f in freqs:
        n = int(sr * tone_len)
        t = np.arange(n) / sr
        cents = jitter_cents * rng.standard_normal(n) if jitter_cents else np.zeros(n)
        inst = f * (2 ** (cents / 1200.0))
        phase = 2 * math.pi * np.cumsum(inst) / sr
        samples.append(0.5 * np.sin(phase))
        samples.append(np.zeros(int(sr * gap)))
    arr = np.concatenate(samples)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((arr * 8000).astype("<i2").tobytes())
    return buf.getvalue()


def _voiced_runs(times, f0):
    runs = []
    cur = None
    for t, v in zip(times, f0):
        if v > 0:
            if cur is None:
                cur = [t, t]
            else:
                cur[1] = t
        elif cur is not None:
            runs.append(tuple(cur))
            cur = None
    if cur is not None:
        runs.append(tuple(cur))
    return runs


def _coverage(notes, runs):
    covered = 0.0
    total = 0.0
    for a, b in runs:
        total += b - a
        for nt in notes:
            covered += max(0.0, min(nt["end"], b) - max(nt["start"], a))
    return min(1.0, covered / total) if total > 0 else 0.0


def _fragmented_reference_contour():
    rng = np.random.default_rng(3)
    f0 = []
    for f in [220.0, 262.0, 330.0]:
        n_frames = 62
        for i in range(n_frames):
            jitter = 1 + (2 ** ((rng.uniform(-90, 90)) / 1200.0)) - 1
            f0.append(f * jitter if i % 9 != 4 else 0.0)
        f0.extend([0.0] * 10)
    times = [round(i * 0.016, 3) for i in range(len(f0))]
    return times, f0


def test_v2_reference_notes_cover_voiced_time(monkeypatch):
    monkeypatch.setattr(settings, "reference_segmentation", "v2", raising=False)
    times, f0 = _fragmented_reference_contour()
    smooth7 = pitch_service.smooth_series(f0, 7)
    notes = compare_service._reference_notes(times, smooth7, f0)
    runs = _voiced_runs(times, f0)
    assert runs
    coverage = _coverage(notes, runs)
    assert coverage >= 0.9
    assert len(notes) <= 6


def test_v1_flag_rollback_uses_legacy_segmentation(monkeypatch):
    times, f0 = _fragmented_reference_contour()
    smooth7 = pitch_service.smooth_series(f0, 7)
    monkeypatch.setattr(settings, "reference_segmentation", "v1", raising=False)
    notes = compare_service._reference_notes(times, smooth7, f0)
    legacy = compare_service._filter_transition_notes(
        compare_service.amt_service.segment_notes(times, smooth7)
    )
    assert notes == legacy


def test_merge_fragments_glues_close_and_short_notes():
    notes = [
        {"midi": 57, "freq": 220.0, "start": 0.0, "end": 0.5, "velocity": 80},
        {"midi": 57, "freq": 224.0, "start": 0.55, "end": 0.9, "velocity": 80},
        {"midi": 59, "freq": 246.9, "start": 1.0, "end": 1.06, "velocity": 80},
        {"midi": 59, "freq": 246.9, "start": 1.12, "end": 1.6, "velocity": 80},
    ]
    merged = compare_service._merge_fragments(notes)
    assert len(merged) == 2
    assert merged[0]["start"] == 0.0
    assert merged[0]["end"] == 0.9
    assert merged[1]["end"] == 1.6
    assert merged[1]["start"] == 1.0


def test_v2_scores_stable_on_clean_voice(monkeypatch):
    monkeypatch.setattr(settings, "reference_segmentation", "v2", raising=False)
    ref = _synth_wav([220.0, 262.0, 330.0], tone_len=1.0, gap=0.4)
    user = _synth_wav([220.0, 262.0, 330.0], tone_len=1.0, gap=0.4)
    monkeypatch.setattr(settings, "reference_segmentation", "v1", raising=False)
    r_v1 = compare_service.compare(ref, user)
    monkeypatch.setattr(settings, "reference_segmentation", "v2", raising=False)
    r_v2 = compare_service.compare(ref, user)
    assert abs(r_v1["metrics"]["score"] - r_v2["metrics"]["score"]) <= 5.0


def test_v2_fragmented_reference_scores_high(monkeypatch):
    monkeypatch.setattr(settings, "reference_segmentation", "v2", raising=False)
    ref = _synth_wav(
        [220.0, 262.0, 330.0],
        tone_len=1.0,
        gap=0.4,
        jitter_cents=90.0,
    )
    user = _synth_wav([220.0, 262.0, 330.0], tone_len=1.0, gap=0.4)
    monkeypatch.setattr(settings, "reference_segmentation", "v2", raising=False)
    r = compare_service.compare(ref, user)
    assert r["metrics"]["score"] >= 80.0


def test_compare_cap_matches_section_hard_max():
    assert compare_service.MAX_COMPARE_SECONDS == lesson_service.SECTION_HARD_MAX
    sr = 16000
    dur = 37.0
    t = np.arange(int(sr * dur)) / sr
    arr = (0.4 * np.sin(2 * math.pi * 220.0 * t) * 8000).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(arr.tobytes())
    samples, out_sr = pitch_service.read_mono_wav(buf.getvalue(), max_seconds=compare_service.MAX_COMPARE_SECONDS)
    assert out_sr == sr
    assert len(samples) <= int(sr * compare_service.MAX_COMPARE_SECONDS) + sr

def test_admin_login_survives_ip_flood(monkeypatch):
    import io as _io
    from fastapi.testclient import TestClient
    from app.database.session import SessionLocal
    from app.database.models import User
    from app.database import crud as _crud

    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    app = create_app()
    client = TestClient(app)

    u = _crud.create_user(SessionLocal(), username="floodvictim", email="floodvictim@gmail.com",
                          password_hash=auth_mod.hash_password("Victim#2026n"))
    SessionLocal().close()

    monkeypatch.setattr(settings, "auth_flood_ip_limit", 10, raising=False)
    r = None
    for i in range(15):
        r = client.post("/api/auth/login", json={"identifier": f"spam{i}", "password": "wrongpw1"})
    assert r is not None and r.status_code == 429, "IP bucket phải đầy sau trần+"

    r = client.post("/api/auth/login", json={"identifier": "floodvictim", "password": "Victim#2026n"})
    assert r.status_code == 429, "user thường vẫn phải 429 khi IP bucket đầy"

    con = SessionLocal()
    admin = con.query(User).filter(User.username == "ghitatruongle").first()
    if admin is None:
        admin = _crud.create_user(con, username="ghitatruongle", email="ghitatruongle@gmail.com",
                                  password_hash=auth_mod.hash_password("AdminFlood#2026"))
    admin.role = "admin"
    con.commit()
    con.close()
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminFlood#2026"})
    assert r.status_code == 200, f"admin trưởng phải login được dù IP bucket đầy (nhận {r.status_code})"
    assert r.json().get("role") == "admin"
