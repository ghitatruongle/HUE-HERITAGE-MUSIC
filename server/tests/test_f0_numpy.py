import io
import math
import time
import wave

import numpy as np

from app.services import pitch_service


def _tone(freqs, sr=16000, seg=1.5):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for f in freqs:
            n = int(sr * seg)
            for i in range(n):
                v = int(7000 * math.sin(2 * math.pi * f * i / sr))
                w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def _decode(data):
    samples, sr = pitch_service.read_mono_wav(data, max_seconds=60)
    return samples, sr


def test_f0_vectorized_matches_reference_on_tones():
    for freq in (220.0, 330.0, 440.0):
        samples, sr = _decode(_tone([freq]))
        t_ref, f_ref = pitch_service.estimate_f0_reference(samples, sr, hop=256)
        t_new, f_new = pitch_service.estimate_f0(samples, sr, hop=256)
        assert len(t_new) == len(t_ref)
        voiced_ref = np.array([v for v in f_ref if v > 0])
        voiced_new = np.array([v for v in f_new if v > 0])
        assert len(voiced_ref) > 0 and len(voiced_new) > 0
        diff = np.abs(voiced_new[: len(voiced_ref)] - voiced_ref[: len(voiced_new)])
        assert float(np.median(diff)) <= 1.5, f"{freq}Hz: median diff {np.median(diff):.2f}"
        assert abs(float(np.median(voiced_new)) - freq) <= 2.0


def test_f0_silence_is_unvoiced():
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\x00\x00" * 16000)
    samples, sr = pitch_service.read_mono_wav(buf.getvalue(), max_seconds=60)
    _, f0 = pitch_service.estimate_f0(samples, sr, hop=256)
    assert all(v == 0.0 for v in f0)


def test_f0_speed_long_input():
    samples, sr = _decode(_tone([220.0] * 20))
    t0 = time.perf_counter()
    pitch_service.estimate_f0(samples, sr, hop=256)
    dt = time.perf_counter() - t0
    assert dt < 1.0, f"F0 vector hóa quá chậm: {dt:.2f}s cho 30s audio"
