import io
import math
import wave

from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app
from app.services import compare_service, lesson_service


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


def _synth_contour():
    times = []
    f0 = []
    t = 0.0
    while t <= 8.0:
        times.append(round(t, 3))
        if 1.0 <= t <= 3.0 or 4.0 <= t <= 6.0:
            f0.append(220.0)
        else:
            f0.append(0.0)
        t += 0.02
    return times, f0


def test_line_times_two_anchors_split_at_gap_midpoint():
    times, f0 = _synth_contour()
    out = lesson_service.section_line_times(times, f0, 0.5, 6.5, ["cau mot", "cau hai"])
    assert len(out) == 2
    assert abs(out[0]["start"] - 1.0) < 0.06
    assert abs(out[0]["end"] - 3.5) < 0.06
    assert abs(out[1]["start"] - 3.5) < 0.06
    assert abs(out[1]["end"] - 6.0) < 0.06


def test_line_times_fallback_equal_split_within_voiced_span():
    times, f0 = _synth_contour()
    out = lesson_service.section_line_times(times, f0, 0.5, 6.5, ["a", "b", "c", "d", "e"])
    assert len(out) == 5
    assert abs(out[0]["start"] - 1.0) < 0.06
    assert abs(out[-1]["end"] - 6.0) < 0.06
    for i in range(1, len(out)):
        assert abs(out[i]["start"] - out[i - 1]["end"]) < 1e-6


def test_line_times_single_line_covers_voiced_span():
    times, f0 = _synth_contour()
    out = lesson_service.section_line_times(times, f0, 0.5, 6.5, ["cau duy nhat"])
    assert len(out) == 1
    assert abs(out[0]["start"] - 1.0) < 0.06
    assert abs(out[0]["end"] - 6.0) < 0.06


def test_line_times_empty_inputs():
    times, f0 = _synth_contour()
    assert lesson_service.section_line_times(times, f0, 0.5, 6.5, []) == []
    assert lesson_service.section_line_times(times, [0.0] * len(f0), 0.5, 6.5, ["a"]) == []
    assert lesson_service.section_line_times([], [], 0.5, 6.5, ["a"]) == []


def test_line_times_multi_line_clamps_to_anchor_spans_not_dropped_segments():
    times = []
    f0 = []
    t = 0.0
    while t <= 8.0:
        times.append(round(t, 3))
        if 0.9 <= t <= 1.0 or 2.0 <= t <= 4.0 or 5.0 <= t <= 7.0:
            f0.append(220.0)
        else:
            f0.append(0.0)
        t += 0.02
    out = lesson_service.section_line_times(times, f0, 0.5, 7.5, ["cau mot", "cau hai"])
    assert len(out) == 2
    assert abs(out[0]["start"] - 2.0) < 0.06
    assert abs(out[0]["end"] - 4.5) < 0.06
    assert abs(out[1]["start"] - 4.5) < 0.06
    assert abs(out[1]["end"] - 7.0) < 0.06


def _sine_wav(freq, duration=2.0, sr=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        n = int(sr * duration)
        for i in range(n):
            v = int(8000 * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def test_compare_metrics_include_verdict_counts_and_summary_codes():
    ref = _sine_wav(220.0)
    user = _sine_wav(233.08)
    result = compare_service.compare(ref, user)
    m = result["metrics"]
    assert isinstance(m["verdict_counts"], dict)
    assert m["verdict_counts"].get("off", 0) + m["verdict_counts"].get("minor", 0) >= 1
    assert "off_count" in m["summary_codes"] or "minor_count" in m["summary_codes"]
    notes = result["notes"]
    assert notes
    assert all("hint_codes" in n for n in notes)
    codes = [c for n in notes for c in n["hint_codes"]]
    assert any(c in ("pitch_high", "pitch_low", "pitch_slightly_high", "pitch_slightly_low") for c in codes)
    vi_hints = [n["hint"] for n in notes if n["hint"]]
    assert vi_hints
    assert any("cents" in h for h in vi_hints)


def test_compare_empty_result_has_new_keys():
    empty = compare_service.empty_result()
    assert empty["metrics"]["verdict_counts"] == {}
    assert empty["metrics"]["summary_codes"] == []


def test_lesson_detail_sections_carry_line_times(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    audio = _tone_wav([220.0, 330.0])
    r = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", audio, "audio/wav")},
        data={
            "title": "Bai hoc timing",
            "type": "Ca Hue",
            "lyrics_with_ornaments": "Câu mot\nCâu hai",
            "mode_system": "Nam",
            "featured_in_creation": "true",
        },
    )
    assert r.status_code == 200, r.text
    lesson_id = r.json()["id"]
    detail = client.get(f"/api/lessons/{lesson_id}")
    assert detail.status_code == 200
    body = detail.json()
    assert body["sections"]
    for s in body["sections"]:
        lines = [ln for ln in (s.get("lyrics") or "").splitlines() if ln.strip()]
        lt = s.get("line_times")
        assert isinstance(lt, list)
        if lines:
            assert len(lt) == len(lines)
            for w in lt:
                assert w["end"] > w["start"]
                assert w["start"] >= s["start"] - 0.1
                assert w["end"] <= s["end"] + 0.1
