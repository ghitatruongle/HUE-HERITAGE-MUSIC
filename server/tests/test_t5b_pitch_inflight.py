import math
import threading

import pytest
from fastapi import HTTPException

from app.api.lessons import (
    _PRACTICE_INFLIGHT,
    _practice_slot_acquire,
    _practice_slot_release,
)
from app.services import pitch_service
from tests.test_alpha2_learning import _tone_wav


def _median_f0(freq, seconds=1.5, sr=16000):
    wav = _tone_wav([freq], tone_len=seconds, gap=0.0)
    times, f0 = pitch_service.estimate_f0(*pitch_service.resample_16k(*pitch_service.read_mono_wav(wav, max_seconds=30.0)), hop=512)
    voiced = [f for f in f0 if f > 0]
    assert voiced
    voiced.sort()
    return voiced[len(voiced) // 2]


def test_nacf_pure_tones_no_octave_drift():
    for freq in (110.0, 220.0, 330.0, 440.0):
        med = _median_f0(freq)
        cents_err = 1200.0 * math.log2(med / freq)
        assert abs(cents_err) < 30.0, (freq, med, cents_err)


def test_nacf_note_edges_no_octave_flip():
    wav = _tone_wav([220.0, 330.0, 220.0], tone_len=1.2)
    times, f0 = pitch_service.estimate_f0(*pitch_service.resample_16k(*pitch_service.read_mono_wav(wav, max_seconds=30.0)), hop=512)
    voiced = [f for f in f0 if f > 0]
    assert len(voiced) >= 30
    for target, seg in ((220.0, voiced[: len(voiced) // 3]), (330.0, voiced[len(voiced) // 3 : 2 * len(voiced) // 3])):
        seg_sorted = sorted(seg)
        med = seg_sorted[len(seg_sorted) // 2]
        assert abs(1200.0 * math.log2(med / target)) < 60.0, (target, med)


def test_octave_smooth_fixes_edge_flip():
    f0 = [880.0] + [440.0] * 8
    out = pitch_service._octave_smooth(f0)
    assert abs(1200.0 * math.log2(out[0] / 440.0)) < 30.0, out[0]
    assert abs(1200.0 * math.log2(out[-1] / 440.0)) < 30.0


def test_octave_smooth_edge_pad_steady_tone_unchanged():
    f0 = [220.0] * 12
    out = pitch_service._octave_smooth(f0)
    assert all(abs(1200.0 * math.log2(v / 220.0)) < 1.0 for v in out)


def test_practice_inflight_acquire_release_limits():
    _PRACTICE_INFLIGHT.clear()
    _practice_slot_acquire("u1")
    _practice_slot_acquire("u1")
    with pytest.raises(HTTPException) as ei:
        _practice_slot_acquire("u1")
    assert ei.value.status_code == 429
    _practice_slot_release("u1")
    _practice_slot_acquire("u1")
    assert _PRACTICE_INFLIGHT.get("u1") == 2
    _practice_slot_release("u1")
    _practice_slot_release("u1")
    assert "u1" not in _PRACTICE_INFLIGHT


def test_practice_inflight_thread_stress_no_leak():
    _PRACTICE_INFLIGHT.clear()
    errors = []
    barrier = threading.Barrier(8)

    def worker():
        barrier.wait()
        for _ in range(50):
            try:
                _practice_slot_acquire("stress")
                _practice_slot_release("stress")
            except Exception as e:
                errors.append(e)

    threads = [threading.Thread(target=worker) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert "stress" not in _PRACTICE_INFLIGHT
    assert _PRACTICE_INFLIGHT == {}
    ok_errors = [e for e in errors if getattr(e, "status_code", None) == 429]
    assert len(errors) == len(ok_errors)
