from __future__ import annotations

import io
import math
import wave

from ..services import pitch_service, compare_service

SCALES = {
    "bac": {
        "name": "Ngũ cung Bắc",
        "frequencies": [261.63, 293.66, 349.23, 392.0, 440.0, 523.25],
        "note_names": ["Do", "Re", "Fa", "Sol", "La", "Do cao"],
    },
    "nam": {
        "name": "Ngũ cung Nam",
        "frequencies": [261.63, 293.66, 349.23, 392.0, 466.16, 523.25],
        "note_names": ["Do", "Re", "Fa", "Sol", "Si giáng", "Do cao"],
    },
}

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
    factor = 2.0 ** (transpose / 12.0)
    return [round(f * factor, 2) for f in cfg["frequencies"]]


def _pitch_class(freq: float) -> int:
    midi = 69 + 12 * math.log2(freq / 440.0)
    return int(round(midi)) % 12


def reference_wav(scale_id: str, transpose: int = 0) -> bytes:
    cfg = get_scale(scale_id)
    if cfg is None:
        raise ValueError("unknown scale")
    transpose = max(-12, min(12, int(transpose)))
    freqs = transposed_frequencies(cfg, transpose)
    sr = 22050
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for _ in range(int(sr * LEAD_IN_SECONDS)):
            w.writeframes((0).to_bytes(2, "little", signed=True))
        seq = freqs + list(reversed(freqs[:-1]))
        for freq in seq:
            n = int(sr * NOTE_SECONDS)
            for i in range(n):
                k = i / n
                env = min(1.0, k / 0.08, (1.0 - k) / 0.15)
                v = int(9000 * env * math.sin(2 * math.pi * freq * i / sr))
                w.writeframes(v.to_bytes(2, "little", signed=True))
            for _ in range(int(sr * GAP_SECONDS)):
                w.writeframes((0).to_bytes(2, "little", signed=True))
    return buf.getvalue()


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
    u_times, u_f0 = pitch_service.estimate_f0(samples, sr, hop=512)
    voiced = [f for f in u_f0 if f > 0]
    if not voiced:
        raise ValueError("empty contour")

    chroma = [0.0] * 12
    for f in voiced:
        chroma[_pitch_class(f)] += 1.0
    total = sum(chroma) or 1.0
    chroma = [round(v / total, 4) for v in chroma]
    scale_pc = sorted({_pitch_class(f) for f in freqs})
    on_scale = sum(chroma[i] for i in scale_pc)

    s_times, s_f0 = _reference_contour(freqs)
    result = compare_service.compare_contours(s_times, s_f0, u_times, u_f0)
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
        })

    legacy_hits = []
    for name, freq in zip(cfg["note_names"], cfg["frequencies"]):
        pc = _pitch_class(freq)
        legacy_hits.append({"name": name, "share": round(chroma[pc], 3), "hit": chroma[pc] >= 0.05})

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
        "on_scale_share": round(on_scale, 3),
        "notes": legacy_hits,
        "performance": perf,
        "summary_hint": metrics["summary_hint"],
        "voiced_frames": len(voiced),
    }
