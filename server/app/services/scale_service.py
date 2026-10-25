from __future__ import annotations

import io
import math
import wave

from ..services import pitch_service

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


def _pitch_class(freq: float) -> int:
    midi = 69 + 12 * math.log2(freq / 440.0)
    return int(round(midi)) % 12


def reference_wav(scale_id: str) -> bytes:
    cfg = get_scale(scale_id)
    if cfg is None:
        raise ValueError("unknown scale")
    sr = 22050
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        seq = cfg["frequencies"] + list(reversed(cfg["frequencies"][:-1]))
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


def practice_scale(scale_id: str, data: bytes) -> dict:
    cfg = get_scale(scale_id)
    if cfg is None:
        raise ValueError("unknown scale")
    samples, sr = pitch_service.read_mono_wav(data, max_seconds=60.0)
    times, f0 = pitch_service.estimate_f0(samples, sr, hop=512)
    voiced = [f for f in f0 if f > 0]
    if not voiced:
        raise ValueError("empty contour")
    chroma = [0.0] * 12
    for f in voiced:
        chroma[_pitch_class(f)] += 1.0
    total = sum(chroma) or 1.0
    chroma = [round(v / total, 4) for v in chroma]
    scale_pc = sorted({_pitch_class(f) for f in cfg["frequencies"]})
    target = [1.0 if i in scale_pc else 0.0 for i in range(12)]
    tnorm = math.sqrt(sum(v * v for v in target)) or 1.0
    cnorm = math.sqrt(sum(v * v for v in chroma)) or 1.0
    cosine = sum(a * b for a, b in zip(target, chroma)) / (tnorm * cnorm)
    on_scale = sum(chroma[i] for i in scale_pc)
    score = round(max(0.0, min(1.0, (cosine + on_scale) / 2.0)) * 100, 1)
    matched = []
    for name, freq in zip(cfg["note_names"], cfg["frequencies"]):
        pc = _pitch_class(freq)
        matched.append({"name": name, "share": round(chroma[pc], 3), "hit": chroma[pc] >= 0.05})
    return {
        "scale_id": scale_id,
        "scale_name": cfg["name"],
        "score": score,
        "chroma": chroma,
        "scale_pitch_classes": scale_pc,
        "on_scale_share": round(on_scale, 3),
        "notes": matched,
        "voiced_frames": len(voiced),
    }
