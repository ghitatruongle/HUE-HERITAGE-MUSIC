import io
import math
import struct
import time
import wave
from pathlib import Path
from types import SimpleNamespace

from app.services import compare_service, lesson_service, pitch_service, user_inflight
from app.storage import manager
from app.config import settings


def _sine(freq, seconds, sr):
    n = int(sr * seconds)
    return [0.8 * math.sin(2 * math.pi * freq * i / sr) for i in range(n)]


def setup_function(function):
    compare_service._REF_CACHE.clear()
    compare_service._REF_KEY_LOCKS.clear()


def test_reference_cache_hit_identity():
    data = _wav_bytes(_sine(440.0, 0.6, 16000))
    s1 = compare_service._reference_state(data)
    s2 = compare_service._reference_state(data)
    assert s1 is s2


def test_reference_cache_distinct_key_recomputed():
    data = _wav_bytes(_sine(440.0, 0.6, 16000))
    s1 = compare_service._reference_state(data, key="k1")
    s2 = compare_service._reference_state(data, key="k2")
    assert s1 is not s2


def test_reference_cache_eviction_cap():
    data = _wav_bytes(_sine(440.0, 0.3, 16000))
    for i in range(compare_service.REF_CACHE_MAX + 5):
        compare_service._reference_state(data, key=f"key-{i}")
    assert len(compare_service._REF_CACHE) <= compare_service.REF_CACHE_MAX


def test_compare_analyzes_reference_once(monkeypatch):
    sample = _wav_bytes(_sine(440.0, 0.8, 16000))
    user = _wav_bytes(_sine(442.0, 0.8, 16000))
    calls = {"n": 0}
    real = pitch_service.estimate_f0

    def counting(samples, sr, **kw):
        calls["n"] += 1
        return real(samples, sr, **kw)

    monkeypatch.setattr(compare_service.pitch_service, "estimate_f0", counting)
    r1 = compare_service.compare(sample, user)
    r2 = compare_service.compare(sample, user)
    assert r1["metrics"]["score"] == r2["metrics"]["score"]
    assert calls["n"] == 3


def test_reference_state_concurrent_single_compute(monkeypatch):
    data = _wav_bytes(_sine(493.88, 0.6, 16000))
    calls = {"n": 0}
    real = pitch_service.estimate_f0

    def counting(samples, sr, **kw):
        calls["n"] += 1
        time.sleep(0.05)
        return real(samples, sr, **kw)

    monkeypatch.setattr(compare_service.pitch_service, "estimate_f0", counting)

    import concurrent.futures

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        states = list(ex.map(lambda _: compare_service._reference_state(data), range(4)))

    assert all(s is states[0] for s in states)
    assert calls["n"] == 1


def test_resample_16k_antialias_keeps_pitch_and_length():
    arr = _sine(440.0, 1.0, 44100)
    out, sr = pitch_service.resample_16k(arr, 44100)
    assert sr == 16000
    assert len(out) == 16000
    times, f0s = pitch_service.estimate_f0(out, sr)
    voiced = [f for f in f0s if f > 0]
    assert voiced, "expected voiced frames after anti-alias resample"
    mean_f0 = sum(voiced) / len(voiced)
    assert abs(mean_f0 - 440.0) < 25.0


def test_write_wav16_matches_reference_bytes(tmp_path):
    samples = [0.5 * math.sin(2 * math.pi * 220.0 * i / 16000) for i in range(2000)]
    samples[100] = 1.7
    samples[200] = -1.7
    target = Path(tmp_path) / "sec.wav"
    lesson_service._write_wav16(target, samples, 16000)
    with wave.open(str(target), "rb") as w:
        raw = w.readframes(w.getnframes())
        rate = w.getframerate()
    assert rate == 16000
    expected = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, float(s))) * 32767.0)
        expected += v.to_bytes(2, "little", signed=True)
    assert raw == bytes(expected)


def test_features_rms_zcr_match_reference():
    samples = [0.3 * math.sin(2 * math.pi * 300.0 * i / 16000) + (0.01 if i % 7 == 0 else 0.0) for i in range(4000)]

    def ref_rms(xs):
        return math.sqrt(sum(s * s for s in xs) / len(xs))

    def ref_zcr(xs):
        n = len(xs)
        c = 0
        for i in range(1, n):
            if (xs[i - 1] < 0) != (xs[i] < 0):
                c += 1
        return c / (n - 1)

    from app.audio_dsp import features

    assert abs(features.rms(samples) - ref_rms(samples)) < 1e-9
    assert abs(features.zero_crossing_rate(samples) - ref_zcr(samples)) < 1e-12


def test_lesson_summary_counts_wav_without_json_parse():
    orig = manager.original_dir()
    orig.mkdir(parents=True, exist_ok=True)
    fake_audio = orig / "lesson_summary_fake.wav"
    fake_audio.write_bytes(b"RIFF-dummy-audio")
    sha = "b" * 64
    item = SimpleNamespace(
        id="id-summary",
        sha256=sha,
        filename="lesson_summary_fake.wav",
        title="t",
        type="Ca Huế",
        artist="a",
        mode_system="bac",
        bpm=60,
        lyrics="",
        lyrics_with_ornaments="",
    )
    sec_dir = lesson_service.lessons_dir() / sha
    cache_path = lesson_service._lesson_cache_path(item)
    try:
        d0 = lesson_service.lesson_summary(item)
        assert d0 is not None and d0["sections"] == 0
        sec_dir.mkdir(parents=True, exist_ok=True)
        (sec_dir / "00.wav").write_bytes(b"x")
        (sec_dir / "01.wav").write_bytes(b"x")
        d_mid = lesson_service.lesson_summary(item)
        assert d_mid is not None and d_mid["sections"] == 0
        cache_path.write_text('{"sections": [{"index": 0}, {"index": 1}]}', encoding="utf-8")
        d1 = lesson_service.lesson_summary(item)
        assert d1["sections"] == 2
    finally:
        try:
            if cache_path.exists():
                cache_path.unlink()
        except OSError:
            pass
        try:
            fake_audio.unlink()
        except OSError:
            pass
        if sec_dir.exists():
            for p in sec_dir.iterdir():
                p.unlink()
            sec_dir.rmdir()


def test_user_inflight_limit_from_settings(monkeypatch):
    monkeypatch.setattr(settings, "heavy_inflight_per_user", 1)
    key = user_inflight.user_key("t2test", "user-x")
    try:
        assert user_inflight.try_acquire(key) is True
        assert user_inflight.try_acquire(key) is False
        user_inflight.release(key)
        assert user_inflight.try_acquire(key) is True
    finally:
        user_inflight.release(key)


def _wav_bytes(samples, sr=16000):
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    frames = []
    for s in samples:
        v = int(max(-1.0, min(1.0, float(s))) * 32767.0)
        frames.append(v)
    w.writeframes(struct.pack("<%dh" % len(frames), *frames))
    w.close()
    return bio.getvalue()
