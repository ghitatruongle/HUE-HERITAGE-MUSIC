from __future__ import annotations

import io
import math
import threading
import wave

try:
    import numpy as np
except Exception:
    np = None

from ..services import pitch_service, compare_service

_SCALE_WAV_CACHE: dict = {}
_SCALE_WAV_LOCK = threading.Lock()

ROOT_CENTS_REF = 261.63
SCALE_CENTS = {
    "bac": [0.0, 154.0, 386.0, 498.0, 702.0],
    "nam": [0.0, 154.0, 386.0, 631.0, 702.0],
}
SCALE_MATCH_TOLERANCE_CENTS = 130.0

SCALES = {
    "bac": {
        "name": "Ngũ cung Bắc",
        "cents": [0.0, 154.0, 386.0, 498.0, 702.0],
        "note_names": ["Cung", "Thương", "Tần", "Xứng", "Phu", "Cung cao"],
    },
    "nam": {
        "name": "Ngũ cung Nam",
        "cents": [0.0, 154.0, 386.0, 631.0, 702.0],
        "note_names": ["Cung", "Thương", "Tần", "Xứng", "Phu", "Cung cao"],
    },
}


def _freq_from_cents(cent, transpose=0):
    return round(ROOT_CENTS_REF * (2.0 ** ((cent + transpose * 100.0) / 1200.0)), 2)


for _sid, _cfg in SCALES.items():
    _cfg["frequencies"] = [
        _freq_from_cents(c, 0) for c in _cfg["cents"]
    ] + [_freq_from_cents(1200.0, 0)]

NOTE_SECONDS = 0.9
GAP_SECONDS = 0.15
LEAD_IN_SECONDS = 0.3
CONTOUR_STEP = 0.016
MAX_SCALE_SECONDS = 60.0


def list_scales():
    return [
        {
            "id": sid,
            "name": cfg["name"],
            "frequencies": cfg["frequencies"],
            "note_names": cfg["note_names"],
        }
        for sid, cfg in SCALES.items()
    ]


def get_scale(scale_id: str):
    return SCALES.get(scale_id)


def transposed_frequencies(cfg, transpose: int):
    transpose = max(-12, min(12, int(transpose)))
    return [_freq_from_cents(c, transpose) for c in cfg["cents"]] + [
        _freq_from_cents(1200.0, transpose)
    ]


def _pitch_class(freq: float) -> int:
    midi = 69 + 12 * math.log2(freq / 440.0)
    return int(round(midi)) % 12


def _cents_class(freq: float) -> float:
    return (1200.0 * math.log2(freq / ROOT_CENTS_REF)) % 1200.0


def _min_cents_distance(c: float, centers) -> float:
    best = 1200.0
    for x in centers:
        d = abs(c - x) % 1200.0
        d = min(d, 1200.0 - d)
        if d < best:
            best = d
    return best


def _scale_centers(scale_id: str, transpose: int):
    cfg = get_scale(scale_id)
    if cfg is None:
        return []
    shift = (transpose * 100.0) % 1200.0
    return [((c + shift) % 1200.0) for c in cfg["cents"]]


def reference_wav(scale_id: str, transpose: int = 0) -> bytes:
    cfg = get_scale(scale_id)
    if cfg is None:
        raise ValueError("unknown scale")
    transpose = max(-12, min(12, int(transpose)))
    cache_key = (scale_id, transpose)
    with _SCALE_WAV_LOCK:
        hit = _SCALE_WAV_CACHE.get(cache_key)
    if hit is not None:
        return hit
    freqs = transposed_frequencies(cfg, transpose)
    sr = 22050
    seq = freqs + list(reversed(freqs[:-1]))
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        if np is not None:
            parts = [np.zeros(int(sr * LEAD_IN_SECONDS), dtype="<i2")]
            n = int(sr * NOTE_SECONDS)
            t = np.arange(n, dtype=np.float64) / sr
            k = np.arange(n, dtype=np.float64) / n
            env = np.minimum(1.0, np.minimum(k / 0.08, (1.0 - k) / 0.15))
            gap = np.zeros(int(sr * GAP_SECONDS), dtype="<i2")
            for freq in seq:
                sig = (
                    0.72 * np.sin(2 * math.pi * freq * t)
                    + 0.20 * np.sin(4 * math.pi * freq * t)
                    + 0.08 * np.sin(6 * math.pi * freq * t)
                )
                parts.append(np.clip(9000.0 * env * sig, -32767.0, 32767.0).astype("<i2"))
                parts.append(gap)
            w.writeframes(np.concatenate(parts).tobytes())
        else:
            for _ in range(int(sr * LEAD_IN_SECONDS)):
                w.writeframes((0).to_bytes(2, "little", signed=True))
            for freq in seq:
                n = int(sr * NOTE_SECONDS)
                for i in range(n):
                    k = i / n
                    env = min(1.0, k / 0.08, (1.0 - k) / 0.15)
                    v = int(9000 * env * math.sin(2 * math.pi * freq * i / sr))
                    w.writeframes(v.to_bytes(2, "little", signed=True))
                for _ in range(int(sr * GAP_SECONDS)):
                    w.writeframes((0).to_bytes(2, "little", signed=True))
    data = buf.getvalue()
    with _SCALE_WAV_LOCK:
        if len(_SCALE_WAV_CACHE) >= 64:
            _SCALE_WAV_CACHE.pop(next(iter(_SCALE_WAV_CACHE)))
        _SCALE_WAV_CACHE[cache_key] = data
    return data


def _name_for_time(t: float, seq_names) -> str:
    if t <= 0:
        return "Không rõ"
    step = NOTE_SECONDS + GAP_SECONDS
    k = int(math.floor((t - LEAD_IN_SECONDS) / step + 1e-6))
    if k < 0 or k >= len(seq_names):
        return "Ngoài thang"
    offset = t - (LEAD_IN_SECONDS + k * (NOTE_SECONDS + GAP_SECONDS))
    if offset > NOTE_SECONDS + 0.05:
        return "Ngoài thang"
    return seq_names[k]


def _reference_contour(freqs):
    seq = freqs + list(reversed(freqs[:-1]))
    times = []
    f0 = []
    t = LEAD_IN_SECONDS
    step = CONTOUR_STEP
    for freq in seq:
        n = int(NOTE_SECONDS / step)
        for i in range(n):
            times.append(round(t + i * step, 3))
            f0.append(freq)
        t += NOTE_SECONDS
        n_gap = int(GAP_SECONDS / step)
        for i in range(n_gap):
            times.append(round(t + i * step, 3))
            f0.append(0.0)
        t += GAP_SECONDS
    return times, f0


def practice_scale(scale_id: str, data: bytes, transpose: int = 0) -> dict:
    cfg = get_scale(scale_id)
    if cfg is None:
        raise ValueError("unknown scale")
    transpose = max(-12, min(12, int(transpose)))
    freqs = transposed_frequencies(cfg, transpose)
    samples, sr = pitch_service.read_mono_wav(data, max_seconds=MAX_SCALE_SECONDS)
    samples, sr = pitch_service.resample_16k(samples, sr)
    u_times, u_f0 = pitch_service.estimate_f0(samples, sr, hop=256, fmin=70.0)
    voiced = [f for f in u_f0 if f > 0]
    if not voiced:
        raise ValueError("empty contour")

    chroma = [0.0] * 12
    for f in voiced:
        chroma[_pitch_class(f)] += 1.0
    total = sum(chroma) or 1.0
    chroma = [round(v / total, 4) for v in chroma]
    scale_pc = sorted({_pitch_class(f) for f in freqs})

    centers = _scale_centers(scale_id, transpose)
    total_voiced = len(voiced) or 1
    assigned = [0] * len(centers)
    on_count = 0
    for f in voiced:
        c = _cents_class(f)
        dists = [
            (min(abs(c - x) % 1200.0, 1200.0 - abs(c - x) % 1200.0), i)
            for i, x in enumerate(centers)
        ]
        d, idx = min(dists)
        if d <= SCALE_MATCH_TOLERANCE_CENTS:
            on_count += 1
            assigned[idx] += 1
    on_scale = on_count / total_voiced

    s_times, s_f0 = _reference_contour(freqs)
    first_voiced = next((t for t, f in zip(u_times, u_f0) if f > 0), u_times[0])
    shift = LEAD_IN_SECONDS - first_voiced
    aligned_u_times = [round(t + shift, 3) for t in u_times]
    result = compare_service.compare_contours(s_times, s_f0, aligned_u_times, u_f0, octave_normalize=False)
    metrics = result["metrics"]

    names = cfg["note_names"]
    seq = freqs + list(reversed(freqs[:-1]))
    seq_names = names + list(reversed(names[:-1]))

    perf = []
    note_list = result.get("notes", [])
    for idx, nt in enumerate(note_list):
        base = _name_for_time(nt.get("ref_start", 0.0), seq_names)
        perf.append({
            "name": base,
            "err_cents": nt["err_cents"],
            "onset_err_ms": nt["onset_err_ms"],
            "verdict": nt["verdict"],
            "verdict_code": nt["verdict_code"],
            "hint": nt["hint"],
            "hint_codes": nt.get("hint_codes", []),
        })

    legacy_hits = []
    for i, name in enumerate(cfg["note_names"][: len(centers)]):
        share = round(assigned[i] / total_voiced, 3)
        legacy_hits.append({"name": name, "share": share, "hit": share >= 0.05})

    return {
        "scale_id": scale_id,
        "scale_name": cfg["name"],
        "transpose": transpose,
        "score": metrics["score"],
        "pitch_score": metrics["pitch_score"],
        "rhythm_score": metrics["rhythm_score"],
        "stability_score": metrics["stability_score"],
        "time_score": metrics["rhythm_score"],
        "mean_abs_cents": metrics["mean_abs_cents"],
        "chroma": chroma,
        "scale_pitch_classes": scale_pc,
        "scale_cents": centers,
        "tuning": "phi_can_bang_tran_van_khe",
        "on_scale_share": round(on_scale, 3),
        "notes": legacy_hits,
        "performance": perf,
        "summary_hint": metrics["summary_hint"],
        "verdict_counts": metrics.get("verdict_counts", {}),
        "summary_codes": metrics.get("summary_codes", []),
        "voiced_frames": len(voiced),
    }
