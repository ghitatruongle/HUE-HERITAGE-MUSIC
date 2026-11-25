import io
import math
import secrets
import struct
import uuid
import wave

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.api import auth as auth_mod
from app.config import settings
from app.database import crud
from app.database.session import SessionLocal
from app.main import BodyLimitMiddleware, create_app
from app.services import compare_service, instrument_service, lesson_service, pitch_service, scale_service
from app.storage import manager as storage_manager
from tests.test_alpha2_learning import _tone_wav


def _custom_wav(segments, sr=16000):
    parts = []
    for freq, dur in segments:
        n = int(sr * dur)
        if freq <= 0:
            parts.append(np.zeros(n, dtype=np.float64))
        else:
            t = np.arange(n, dtype=np.float64) / sr
            env = np.minimum(1.0, np.minimum(t / 0.03, (dur - t) / 0.03))
            parts.append(0.5 * env * np.sin(2 * math.pi * freq * t))
    arr = np.concatenate(parts) if parts else np.zeros(0, dtype=np.float64)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(arr, -1.0, 1.0) * 16000).astype("<i2").tobytes())
    return buf.getvalue()


def test_p0_compare_octave_folded_dtw_and_frame_cents():
    ref = _tone_wav([220.0, 330.0, 293.66], tone_len=0.9, gap=0.25)
    user = _tone_wav([110.0, 165.0, 146.83], tone_len=0.9, gap=0.25)
    res = compare_service.compare(ref, user, include_warped_full=True)
    m = res["metrics"]
    assert m["mean_abs_cents"] <= 50.0
    assert m["median_cents"] <= 50.0
    assert m["pitch_score"] >= 90.0
    notes = [n for n in res["notes"] if n["verdict_code"] != "unclear"]
    assert len(notes) == 3
    assert all(n["octave_diff"] for n in notes)
    assert all(abs(n["err_cents"]) <= 50.0 for n in notes)


def test_p0_compare_detects_internal_note_delay():
    ref = _custom_wav([(220.0, 0.8), (0.0, 0.5), (330.0, 0.8), (0.0, 0.5)])
    user = _custom_wav([(220.0, 0.8), (0.0, 0.9), (330.0, 0.8), (0.0, 0.1)])
    res = compare_service.compare(ref, user)
    assert len(res["notes"]) >= 2
    assert res["notes"][1]["onset_err_ms"] >= 250.0
    assert res["metrics"]["rhythm_score"] < 90.0


def test_p0_lessons_skip_instrumental_and_strip_section_headers(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())

    wav_inst = _tone_wav([220.0, 330.0], tone_len=1.5, gap=0.9)
    wav_vocal = _tone_wav([261.63, 392.0], tone_len=1.5, gap=0.9)
    inst = client.post(
        "/api/heritage/upload",
        files={"file": ("inst.wav", wav_inst, "audio/wav")},
        data={"title": "Doc tau Dan Nguyet", "type": "Nhạc cụ truyền thống Huế", "lyrics_with_ornaments": "[Instrumental]"},
    )
    assert inst.status_code == 200
    inst_id = inst.json()["id"]

    vocal = client.post(
        "/api/heritage/upload",
        files={"file": ("vocal.wav", wav_vocal, "audio/wav")},
        data={"title": "Ho Mai Nhi", "type": "Ca Huế", "lyrics_with_ornaments": "[Intro]\nSông Hương đẹp lắm\n[Chorus]\nTình tang ơi à"},
    )
    assert vocal.status_code == 200
    vocal_id = vocal.json()["id"]

    lessons = client.get("/api/lessons").json()
    lesson_ids = {x["id"] for x in lessons}
    assert inst_id not in lesson_ids
    assert vocal_id in lesson_ids

    detail = client.get(f"/api/lessons/{vocal_id}").json()
    combined = "\n".join(s.get("lyrics", "") for s in detail["sections"])
    assert "[Intro]" not in combined
    assert "[Chorus]" not in combined
    assert "Sông Hương đẹp lắm" in combined


def test_p0_sample_word_feedback_and_cache_invalidation(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    db = SessionLocal()
    try:
        db.query(auth_mod.crud.User).delete()
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    reg = client.post(
        "/api/auth/register",
        json={"username": "ghitatruongle", "email": "admin@x.com", "password": "AdminWave1#2026", "invite_code": "TESTINVITE"},
    )
    assert reg.status_code == 200
    client = TestClient(create_app())
    login = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminWave1#2026"})
    assert login.status_code == 200
    token = login.json()["token"]
    ah = {"Authorization": f"Bearer {token}"}
    assert client.post("/api/auth/admin-unlock", json={"password": "AdminWave1#2026"}, headers=ah).status_code == 200

    orig_wav = _custom_wav([(220.0, 1.5), (0.0, 2.5)])
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("orig.wav", orig_wav, "audio/wav")},
        data={"title": "Mau Chuan", "type": "Ca Huế", "lyrics_with_ornaments": "Một hai\nBa bốn"},
        headers=ah,
    )
    assert up.status_code == 200
    lid = up.json()["id"]

    sample1 = _custom_wav([(0.0, 1.6), (261.63, 1.0), (0.0, 0.5), (329.63, 1.0)])
    assert client.post(
        f"/api/lessons/{lid}/sections/0/sample.wav",
        files={"file": ("s1.wav", sample1, "audio/wav")},
        headers=ah,
    ).status_code == 200

    user_take = _custom_wav([(0.0, 1.6), (130.81, 1.0), (0.0, 0.5), (164.81, 1.0)])
    p1 = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", user_take, "audio/wav")}, headers=ah)
    assert p1.status_code == 200, p1.text
    words = p1.json()["words"]
    assert words and all(w["verdict_code"] in ("ok", "minor") and w["octave_diff"] for w in words), words
    assert all(w["err_cents"] is not None and abs(w["err_cents"]) <= 50.0 for w in words)

    sample2 = _custom_wav([(392.0, 2.0)])
    assert client.post(
        f"/api/lessons/{lid}/sections/0/sample.wav",
        files={"file": ("s2.wav", sample2, "audio/wav")},
        headers=ah,
    ).status_code == 200
    p2 = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u2.wav", _custom_wav([(392.0, 2.0)]), "audio/wav")}, headers=ah)
    assert p2.status_code == 200
    med_sample = sorted(v for v in p2.json()["sample"]["f0"] if v > 0)[len([v for v in p2.json()["sample"]["f0"] if v > 0]) // 2]
    assert abs(med_sample - 392.0) < 25.0


def test_p0_octave_smooth_preserves_edges_and_folds_octave():
    smoothed = pitch_service._octave_smooth([220.0, 220.0, 440.0, 220.0, 220.0])
    assert abs(smoothed[2] - 220.0) < 5.0
    edges = pitch_service._octave_smooth([330.0, 330.0, 330.0, 220.0, 220.0, 220.0])
    assert abs(edges[0] - 330.0) < 5.0
    assert abs(edges[-1] - 220.0) < 5.0


def test_p0_instrument_short_audio_no_broadcast_crash():
    short_wav = _custom_wav([(220.0, 0.35)], sr=16000)
    res = instrument_service.detect(short_wav)
    assert res["duration"] >= 0.9
    assert isinstance(res["segments"], list)


def test_p0_scale_practice_uses_matching_step():
    wav = _custom_wav([(261.63, 0.9), (0.0, 0.15), (285.9, 0.9)])
    orig_fn = compare_service.compare_contours
    captured = {}

    def spy(s_times, s_f0, u_times, u_f0, **kwargs):
        captured["u_step"] = round(u_times[1] - u_times[0], 3) if len(u_times) > 1 else 0.0
        captured["s_step"] = round(s_times[1] - s_times[0], 3) if len(s_times) > 1 else 0.0
        return orig_fn(s_times, s_f0, u_times, u_f0, **kwargs)

    compare_service.compare_contours = spy
    try:
        scale_service.practice_scale("bac", wav)
    finally:
        compare_service.compare_contours = orig_fn
    assert abs(captured["u_step"] - captured["s_step"]) <= 0.002


def test_p0_security_restored_url_idor_and_practice_midi_signed_and_admin_must_change(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    db = SessionLocal()
    try:
        db.query(auth_mod.crud.User).delete()
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    reg_a = client.post(
        "/api/auth/register",
        json={"username": "ghitatruongle", "email": "adm@x.com", "password": "AdminSec1#2026", "invite_code": "TESTINVITE"},
    )
    assert reg_a.status_code == 200
    adm_tok = reg_a.json()["token"]
    adm_h = {"Authorization": f"Bearer {adm_tok}"}

    u_a = client.post(
        "/api/auth/register",
        json={"username": f"ua{uuid.uuid4().hex[:6]}", "email": f"{uuid.uuid4().hex[:6]}@x.com", "password": "UserSec1#2026", "invite_code": "TESTINVITE"},
    ).json()
    u_b = client.post(
        "/api/auth/register",
        json={"username": f"ub{uuid.uuid4().hex[:6]}", "email": f"{uuid.uuid4().hex[:6]}@x.com", "password": "UserSec1#2026", "invite_code": "TESTINVITE"},
    ).json()
    ah = {"Authorization": f"Bearer {u_a['token']}"}
    bh = {"Authorization": f"Bearer {u_b['token']}"}

    r_rest = client.post("/api/music/restore", files={"file": ("v.wav", _custom_wav([(220.0, 0.4)]), "audio/wav")}, headers=ah)
    assert r_rest.status_code == 200
    sha = r_rest.json()["sha"]
    assert client.get(f"/api/music/restored-url/{sha}", headers=bh).status_code == 404
    assert client.get(f"/api/music/restored-url/{sha}", headers=ah).status_code == 200

    midi_name = f"practice_{secrets.token_hex(12)}_0_{1700000000}.mid"
    db = SessionLocal()
    try:
        crud.create_practice_session(db, u_a["id"], "lesson-p0", 0, 90.0, 90.0, 90.0, 90.0, "original", user_midi=midi_name)
    finally:
        db.close()
    (storage_manager.midi_dir() / midi_name).write_bytes(b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60")

    assert client.get(f"/api/music/play-url?path=/api/lessons/practice-midi/{midi_name}", headers=bh).status_code == 404
    signed_midi = client.get(f"/api/music/play-url?path=/api/lessons/practice-midi/{midi_name}", headers=ah)
    assert signed_midi.status_code == 200
    assert client.get(signed_midi.json()["url"]).status_code == 200
    assert client.get(f"/api/lessons/practice-midi/{midi_name}").status_code == 401

    db = SessionLocal()
    try:
        crud.set_must_change_password(db, reg_a.json()["id"], True)
    finally:
        db.close()
    assert client.post("/api/auth/invites", json={"note": "blocked"}, headers=adm_h).status_code == 403


def test_p0_generated_passwords_always_meet_policy_and_body_limit_follows_settings(monkeypatch):
    for _ in range(100):
        pw_u = auth_mod._generate_temp_password(12)
        pw_a = auth_mod._generate_temp_password(16)
        assert auth_mod._user_password_ok(pw_u)
        assert auth_mod._admin_password_ok(pw_a)

    monkeypatch.setattr(settings, "heritage_upload_max_bytes", 1234567, raising=False)
    bl = BodyLimitMiddleware(app=None)
    assert bl._limit_for("/api/heritage/upload") == 1234567 + 2 * 1024 * 1024
