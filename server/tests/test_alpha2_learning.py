import io
import math
import secrets
import wave

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.audio_dsp import dtw_aligner
from app.database import crud
from app.database.models import User, PracticeSession
from app.database.session import SessionLocal
from app.main import create_app
from app.services import compare_service, scale_service, pitch_service


def _tone_wav(freqs, sr=16000, tone_len=1.0, gap=0.9, lead=0.0, cents_off=0.0, vib=None, vib_rate=5.5, sr_note=None):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for _ in range(int(sr * lead)):
            w.writeframes((0).to_bytes(2, "little", signed=True))
        for f in freqs:
            f2 = f * (2 ** (cents_off / 1200.0))
            n = int(sr * tone_len)
            phase = 0.0
            for i in range(n):
                env = min(1.0, i / (sr * 0.05), (n - i) / (sr * 0.05))
                val = f2
                if vib is not None:
                    val = f2 * (2 ** (vib * math.sin(2 * math.pi * vib_rate * i / sr) / 1200.0))
                phase += 2 * math.pi * val / sr
                v = int(8000 * env * math.sin(phase))
                w.writeframes(v.to_bytes(2, "little", signed=True))
            for _ in range(int(sr * gap)):
                w.writeframes((0).to_bytes(2, "little", signed=True))
    return buf.getvalue()


def _random_contour(n):
    rng = [0.0, 220.0, 262.0, 330.0, 392.0, 440.0]
    out = []
    for _ in range(n):
        out.append(rng[(len(out) * 7 + 3) % len(rng)] if (len(out) * 5) % 7 else 0.0)
    return out


def _path_cost(a, b, path):
    return sum(dtw_aligner.frame_cost(a[i], b[j]) for i, j in path)


def test_dtw_numpy_optimal_against_reference():
    for n, m in [(17, 41), (63, 22), (90, 90), (35, 37)]:
        a = _random_contour(n)
        b = _random_contour(m)
        p_np, d_np = dtw_aligner.dtw(a, b)
        p_py, d_py = dtw_aligner._dtw_python(a, b, band_ratio=dtw_aligner.BAND_RATIO)
        assert p_np[0] == [0, 0]
        assert p_np[-1] == [n - 1, m - 1]
        w = max(dtw_aligner.MIN_BAND, int(dtw_aligner.BAND_RATIO * max(n, m)), abs(n - m) + 1)
        for i, j in p_np:
            assert abs(i - j) <= w
        for k in range(len(p_np) - 1):
            assert p_np[k + 1][0] >= p_np[k][0]
            assert p_np[k + 1][1] >= p_np[k][1]
        assert abs(_path_cost(a, b, p_np) - _path_cost(a, b, p_py)) < 1e-9


def test_compare_perfect_match_scores_high():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2))
    m = r["metrics"]
    assert m["reference_quality"] == "good"
    assert m["score"] >= 95
    assert m["pitch_score"] >= 95
    assert m["rhythm_score"] >= 90
    assert [n["verdict_code"] for n in r["notes"]] == ["ok", "ok"]
    assert len(r["sample"]["f0"]) == len(r["user_warped"]["f0"])
    assert m["summary_hint"]


def test_compare_sharp_pitch_minor_verdict():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2, cents_off=40))
    m = r["metrics"]
    assert 45 <= m["pitch_score"] <= 85
    assert all(n["verdict_code"] == "minor" for n in r["notes"])
    assert any("cao" in n["hint"].lower() for n in r["notes"])


def test_compare_octave_error_flagged():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([440.0, 660.0], tone_len=1.2))
    codes = [n["verdict_code"] for n in r["notes"]]
    assert "octave" in codes
    assert any(n["verdict"] == "Sai quãng tám" for n in r["notes"])


def test_compare_vibrato_rewarded_not_punished():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2, vib=60))
    m = r["metrics"]
    assert m["score"] >= 90
    assert m["pitch_score"] >= 90
    assert m["ornament"] >= 50
    assert m["vibrato_rate"] > 2.0
    assert all(n["verdict_code"] == "ok" for n in r["notes"])
    assert all(n["vibrato"] for n in r["notes"])


def test_compare_late_start_hits_rhythm():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2, lead=0.5))
    m = r["metrics"]
    assert m["rhythm_score"] < 70
    assert m["pitch_score"] >= 95
    assert m["start_offset_ms"] >= 400


def test_compare_off_pitch_matched_with_verdict_off():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2, cents_off=450))
    codes = [n["verdict_code"] for n in r["notes"]]
    assert codes and all(c != "unclear" for c in codes)
    assert any(c in ("off", "octave") for c in codes)
    assert r["metrics"]["matched_notes"] >= 1


def test_estimate_f0_survives_pathological_sample_rate():
    tiny = _tone_wav([220.0], sr=40, tone_len=30.0, gap=0.0)
    times, f0 = pitch_service.estimate_f0(*pitch_service.resample_16k(*pitch_service.read_mono_wav(tiny, max_seconds=30.0)), hop=256)
    assert all(v == 0 for v in f0)


def test_scale_reference_wav_transpose_clamped():
    w = scale_service.reference_wav("bac", transpose=10**9)
    assert w[:4] == b"RIFF"
    base = scale_service.reference_wav("bac", transpose=0)
    assert len(w) == len(base)


def test_lesson_cache_44k_migrated_to_16k(_auth_env):
    client = TestClient(create_app())
    user = _register(client, "migrator")
    uh = {"Authorization": f"Bearer {user['token']}"}
    lid = _upload_lesson(client, "Legacy44", _tone_wav([220.0, 330.0], sr=44100, tone_len=2.0, gap=1.2), headers=uh)
    from app.database.session import SessionLocal as _SL
    from app.database.models import HeritageItem
    from app.services.lesson_service import lessons_dir
    import wave as _wave
    import json as _json
    import struct as _struct

    db = _SL()
    try:
        item = db.get(HeritageItem, lid)
        sha = item.sha256 or item.id
    finally:
        db.close()
    sec_dir = lessons_dir() / sha
    client.get(f"/api/lessons/{lid}", headers=uh)
    with _wave.open(str(sec_dir / "00.wav"), "rb") as w:
        assert w.getframerate() == 16000
    cached = _json.loads((lessons_dir() / f"{sha}.json").read_text(encoding="utf-8"))

    legacy_wav = _tone_wav([220.0], sr=44100, tone_len=2.0, gap=0.0)
    (sec_dir / "00.wav").write_bytes(legacy_wav)
    with _wave.open(str(sec_dir / "00.wav"), "rb") as w:
        assert w.getframerate() == 44100

    detail = client.get(f"/api/lessons/{lid}", headers=uh)
    assert detail.status_code == 200, detail.text
    with _wave.open(str(sec_dir / "00.wav"), "rb") as w:
        assert w.getframerate() == 16000
    cached2 = _json.loads((lessons_dir() / f"{sha}.json").read_text(encoding="utf-8"))
    assert [s2["index"] for s2 in cached2["sections"]] == [s1["index"] for s1 in cached["sections"]]


def test_poor_reference_fallback_no_missing_penalty(monkeypatch):
    monkeypatch.setattr(settings, "reference_segmentation", "v1", raising=False)
    s_times, s_f0 = [], []
    t = 0.0
    for _ in range(60):
        for i in range(3):
            s_times.append(round(t + i * 0.016, 3))
            s_f0.append(300.0)
        for i in range(3):
            s_times.append(round(t + 0.048 + i * 0.016, 3))
            s_f0.append(0.0)
        t += 0.096
    u_times = [round(i * 0.016, 3) for i in range(350)]
    u_f0 = [300.0] * 350
    r = compare_service.compare_contours(s_times, s_f0, u_times, u_f0)
    m = r["metrics"]
    assert m["reference_quality"] == "poor"
    assert m["missing_notes"] == 0
    assert m["pitch_score"] >= 90
    assert m["score"] >= 85
    assert "không rõ từng nốt" in m["summary_hint"]
    assert any("không rõ nốt" in n["hint"] for n in r["notes"] if n["verdict_code"] == "unclear")


def test_clean_single_note_reference_scores_high():
    ref = _tone_wav([300.0], tone_len=5.0, gap=0.0)
    r = compare_service.compare(ref, _tone_wav([300.0], tone_len=5.0, gap=0.0))
    m = r["metrics"]
    assert m["reference_quality"] == "good"
    assert m["score"] >= 95
    assert m["matched_notes"] >= 1


def test_compare_missing_notes_penalized():
    ref = _tone_wav([220.0, 330.0, 392.0, 440.0], tone_len=1.0, gap=0.4)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.0, gap=0.4))
    m = r["metrics"]
    assert m["missing_notes"] >= 2
    assert m["score"] < 80


def test_scale_practice_dtw_exact_and_transpose():
    bac = scale_service.SCALES["bac"]["frequencies"]
    seq = bac + list(reversed(bac[:-1]))
    r = scale_service.practice_scale("bac", _tone_wav(seq, tone_len=0.9, gap=0.15))
    assert r["score"] >= 90
    assert r["pitch_score"] >= 90
    assert r["transpose"] == 0

    r_oct = scale_service.practice_scale("bac", _tone_wav([f * 2 for f in seq], tone_len=0.9, gap=0.15))
    assert r_oct["score"] < 60
    assert r_oct["pitch_score"] < 20
    assert any(p["verdict_code"] == "octave" for p in r_oct["performance"])

    r_trans = scale_service.practice_scale("bac", _tone_wav([f * (2 ** (-3 / 12.0)) for f in seq], tone_len=0.9, gap=0.15), transpose=-3)
    assert r_trans["score"] >= 90
    assert r_trans["transpose"] == -3

    r_exact = scale_service.practice_scale("bac", _tone_wav(seq, tone_len=0.9, gap=0.15))
    assert not any(p["name"] == "Ngoài thang" for p in r_exact["performance"])

    r_mismatch = scale_service.practice_scale("bac", _tone_wav(seq, tone_len=0.9, gap=0.15), transpose=-3)
    assert r_mismatch["score"] < 70


def test_scale_reference_wav_transposed():
    base = scale_service.reference_wav("bac")
    t2 = scale_service.reference_wav("bac", transpose=-2)
    assert base[:4] == b"RIFF" and t2[:4] == b"RIFF"
    assert len(base) == len(t2)


@pytest.fixture()
def _auth_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()


def _register(client, username):
    r = client.post(
        "/api/auth/register",
        json={"username": username, "email": f"{username}@x.com", "password": "secret123", "invite_code": "TESTINVITE"},
    )
    assert r.status_code == 200, r.text
    return r.json()


def _promote_admin(username):
    db = SessionLocal()
    try:
        u = db.query(User).filter_by(username=username).first()
        u.role = "admin"
        db.commit()
    finally:
        db.close()


def _upload_lesson(client, title, data, headers=None):
    r = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", data, "audio/wav")},
        data={"title": title, "type": "Ca Hue", "lyrics_with_ornaments": "Câu một\nCâu hai", "featured_in_creation": "true"},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    return r.json()["id"]


@pytest.fixture()
def _wipe_users():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()


def test_lesson_sections_resampled_16k(_auth_env):
    client = TestClient(create_app())
    user = _register(client, "s16kuser")
    uh = {"Authorization": f"Bearer {user['token']}"}
    data_44k = _tone_wav([220.0, 330.0], sr=44100, tone_len=2.0, gap=1.2)
    lid = _upload_lesson(client, "S16k", data_44k, headers=uh)
    detail = client.get(f"/api/lessons/{lid}", headers=uh).json()
    assert len(detail["sections"]) >= 2
    from app.database.session import SessionLocal as _SL
    from app.database.models import HeritageItem
    from app.services.lesson_service import lessons_dir

    db = _SL()
    try:
        item = db.get(HeritageItem, lid)
        path = lessons_dir() / (item.sha256 or item.id) / "00.wav"
    finally:
        db.close()
    assert path.exists()
    with wave.open(str(path), "rb") as w:
        assert w.getframerate() == 16000


def test_sample_upload_flow_and_practice_reference(_auth_env):
    client = TestClient(create_app())
    admin = _register(client, "ghitatruongle")
    _promote_admin("ghitatruongle")
    ah = {"Authorization": f"Bearer {admin['token']}"}
    lid = _upload_lesson(client, "Sample flow", _tone_wav([220.0, 330.0]), headers=ah)

    r = client.post(f"/api/lessons/{lid}/sections/0/sample.wav", files={"file": ("s.wav", _tone_wav([220.0]), "audio/wav")}, headers=ah)
    assert r.status_code == 403

    r = client.post("/api/auth/admin-unlock", json={"password": "secret123"}, headers=ah)
    assert r.status_code == 200, r.text

    r = client.post(f"/api/lessons/{lid}/sections/0/sample.wav", files={"file": ("s.wav", _tone_wav([220.0]), "audio/wav")}, headers=ah)
    assert r.status_code == 200, r.text

    r = client.post(f"/api/lessons/{lid}/sections/0/sample.wav", files={"file": ("bad.wav", b"NOTWAV" * 50)}, headers=ah)
    assert r.status_code == 400

    r = client.post(f"/api/lessons/{lid}/sections/99/sample.wav", files={"file": ("s.wav", _tone_wav([220.0]), "audio/wav")}, headers=ah)
    assert r.status_code == 404

    detail = client.get(f"/api/lessons/{lid}", headers=ah).json()
    assert detail["sections"][0]["has_sample"] is True
    assert detail["sections"][0]["sample_url"].endswith("/sections/0/sample.wav")

    r = client.get(f"/api/lessons/{lid}/sections/0/sample.wav")
    assert r.status_code == 401

    r = client.get(f"/api/lessons/{lid}/sections/0/sample.wav", headers=ah)
    assert r.status_code == 200
    assert r.content[:4] == b"RIFF"

    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", _tone_wav([220.0]), "audio/wav")}, headers=ah)
    assert r.status_code == 200, r.text
    assert r.json()["reference"] == "sample"

    r = client.delete(f"/api/lessons/{lid}/sections/0/sample.wav", headers=ah)
    assert r.status_code == 200 and r.json()["deleted"] is True
    detail = client.get(f"/api/lessons/{lid}", headers=ah).json()
    assert detail["sections"][0]["has_sample"] is False


def test_sample_visibility_and_signed_url(_auth_env):
    client = TestClient(create_app())
    admin = _register(client, "ghitatruongle")
    _promote_admin("ghitatruongle")
    ah = {"Authorization": f"Bearer {admin['token']}"}
    client.post("/api/auth/admin-unlock", json={"password": "secret123"}, headers=ah)

    lid = _upload_lesson(client, "VisSample", _tone_wav([233.1, 349.2]), headers=ah)
    r = client.post(f"/api/lessons/{lid}/sections/0/sample.wav", files={"file": ("s.wav", _tone_wav([220.0]), "audio/wav")}, headers=ah)
    assert r.status_code == 200

    r = client.get(f"/api/lessons/{lid}/sections/0/sample.wav")
    assert r.status_code == 401

    r = client.get("/api/music/play-url", params={"path": f"/api/lessons/{lid}/sections/0/sample.wav"}, headers=ah)
    assert r.status_code == 200, r.text
    signed = r.json()["url"]
    r = client.get(signed)
    assert r.status_code == 200 and r.content[:4] == b"RIFF"




def test_practice_sessions_and_my_progress(_auth_env):
    client = TestClient(create_app())
    user = _register(client, "learner1")
    uh = {"Authorization": f"Bearer {user['token']}"}
    lid = _upload_lesson(client, "Progress", _tone_wav([246.9, 370.0], tone_len=2.0), headers=uh)

    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", _tone_wav([246.9]), "audio/wav")}, headers=uh)
    assert r.status_code == 200

    r = client.get("/api/lessons/my-progress", headers=uh)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["server_history"] is True
    assert len(body["items"]) >= 1
    item = body["items"][0]
    assert item["lesson_id"] == lid
    assert item["score"] > 0

    other = _register(client, "learner2")
    r = client.get("/api/lessons/my-progress", headers={"Authorization": f"Bearer {other['token']}"})
    assert r.json()["items"] == []

    r = client.post("/api/auth/register", json={"username": "ghitatruongle", "email": "gt@x.com", "password": "secret123", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    _promote_admin("ghitatruongle")
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "secret123"})
    assert r.status_code == 200, r.text
    ah = {"Authorization": f"Bearer {r.json()['token']}"}
    r = client.get("/api/admin/learning/stats", headers=ah)
    assert r.status_code == 200, r.text
    stats = r.json()
    assert stats["total_sessions"] >= 1
    assert any(x["lesson_id"] == lid for x in stats["by_lesson"])

    r = client.get("/api/admin/learning/stats", headers=uh)
    assert r.status_code == 403


def test_body_limit_large_uploads(_auth_env):
    client = TestClient(create_app())
    admin = _register(client, "ghitatruongle")
    _promote_admin("ghitatruongle")
    ah = {"Authorization": f"Bearer {admin['token']}"}
    lid = _upload_lesson(client, "BigBody", _tone_wav([261.6, 392.0]), headers=ah)
    big = _tone_wav([220.0], tone_len=115, gap=0.0)
    assert 2 * 1024 * 1024 < len(big) < 15 * 1024 * 1024
    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", big, "audio/wav")}, headers=ah)
    assert r.status_code == 200, r.text
    client.post("/api/auth/admin-unlock", json={"password": "secret123"}, headers=ah)
    huge = _tone_wav([220.0], tone_len=500, gap=0.0)
    assert len(huge) > 15 * 1024 * 1024
    r = client.post(f"/api/lessons/{lid}/sections/0/sample.wav", files={"file": ("s.wav", huge, "audio/wav")}, headers=ah)
    assert r.status_code == 413
