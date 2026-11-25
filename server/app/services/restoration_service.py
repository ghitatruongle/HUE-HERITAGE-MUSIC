import io
import math
import struct
import wave

try:
    import numpy as np
except Exception:
    np = None

from ..audio_dsp import fft as dsp_fft
from . import pitch_service

MAX_SECONDS = 10.0
CLICK_THR = 0.3
GATE_MULT = 2.0
GATE_FLOOR = 0.15
TARGET_PEAK = 0.89
LABEL = "Phục dựng – bản xử lý"


def remove_dc(samples):
    if np is not None:
        arr = np.asarray(samples, dtype=np.float64)
        mean = float(arr.mean()) if arr.size else 0.0
        return (arr - mean if arr.size else arr), mean
    n = len(samples)
    mean = sum(samples) / n if n else 0.0
    return [s - mean for s in samples], mean


def remove_clicks(samples):
    if np is not None:
        arr = np.asarray(samples, dtype=np.float64)
        if arr.size < 3:
            return arr.copy(), 0
        prev = arr[:-2]
        mid = arr[1:-1]
        nxt = arr[2:]
        mask = (np.abs(mid - prev) > CLICK_THR) & (np.abs(mid - nxt) > CLICK_THR) & (np.abs(prev - nxt) < CLICK_THR)
        fixed = int(mask.sum())
        out = arr.copy()
        if fixed > 0:
            out[1:-1][mask] = 0.5 * (prev[mask] + nxt[mask])
        return out, fixed
    out = list(samples)
    fixed = 0
    for i in range(1, len(samples) - 1):
        a = samples[i - 1]
        b = samples[i]
        c = samples[i + 1]
        if abs(b - a) > CLICK_THR and abs(b - c) > CLICK_THR and abs(a - c) < CLICK_THR:
            out[i] = (a + c) / 2
            fixed += 1
    return out, fixed


def spectral_gate(frames):
    if np is not None and frames:
        mat = np.asarray(frames, dtype=np.float64)
        n_fft = mat.shape[1] if mat.ndim == 2 else 0
        if n_fft > 0 and (n_fft & (n_fft - 1)) == 0:
            spec = np.fft.fft(mat, axis=1)
            mags = np.abs(spec)
            mid_idx = mags.shape[1] // 2
            med = np.partition(mags, mid_idx, axis=1)[:, mid_idx : mid_idx + 1]
            thr = med * GATE_MULT + 0.0000001
            gated = np.where(mags >= thr, spec, spec * GATE_FLOOR)
            rec = np.fft.ifft(gated, axis=1).real
            return [rec[i] for i in range(rec.shape[0])]
    out = []
    for fr in frames:
        spec = dsp_fft.fft(fr)
        mags = sorted([abs(v) for v in spec])
        med = mags[len(mags) // 2]
        thr = med * GATE_MULT + 0.0000001
        gated = []
        for v in spec:
            if abs(v) >= thr:
                gated.append(v)
            else:
                gated.append(v * GATE_FLOOR)
        rec = dsp_fft.ifft(gated)
        out.append([v.real for v in rec])
    return out


def peak_of(samples):
    if np is not None:
        arr = np.asarray(samples, dtype=np.float64)
        return float(np.max(np.abs(arr))) if arr.size else 0.0
    p = 0.0
    for s in samples:
        v = abs(s)
        if v > p:
            p = v
    return p


def normalize(samples):
    peak = peak_of(samples)
    if peak <= 0.000001:
        return samples, 0.0
    g = TARGET_PEAK / peak
    if np is not None:
        return np.asarray(samples, dtype=np.float64) * g, peak
    return [s * g for s in samples], peak


def to_wav_bytes(samples, sr):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        if np is not None:
            pcm = (np.clip(np.asarray(samples, dtype=np.float64), -1.0, 1.0) * 32767.0).astype("<i2")
            w.writeframes(pcm.tobytes())
        else:
            clamped = []
            for s in samples:
                if s > 1.0:
                    s = 1.0
                elif s < -1.0:
                    s = -1.0
                clamped.append(int(s * 32767))
            w.writeframes(struct.pack("<%dh" % len(clamped), *clamped))
    return bio.getvalue()


def restore(data):
    samples, sr = pitch_service.read_mono_wav(data)
    truncated = False
    limit = int(sr * MAX_SECONDS)
    if len(samples) > limit:
        samples = samples[:limit]
        truncated = True
    total = len(samples)
    peak_before = round(peak_of(samples), 4)
    samples, dc = remove_dc(samples)
    samples, clicks = remove_clicks(samples)
    size = 1024
    hop = 512
    count_frames = 0
    while count_frames * hop + size < total:
        count_frames += 1
    count_frames += 1
    if np is None:
        samples = samples + [0.0] * (count_frames * hop + size - total)
    else:
        pad = np.zeros(count_frames * hop + size - total, dtype=np.float64)
        samples = np.concatenate([np.asarray(samples, dtype=np.float64), pad])
    frames, win = dsp_fft.stft(samples, size, hop)
    first = sorted([abs(v) for v in dsp_fft.fft(frames[len(frames) // 2])])
    med = first[len(first) // 2]
    noise_db = round(20 * math.log10(med + 1e-12), 1)
    gated = spectral_gate(frames)
    samples = dsp_fft.istft(gated, win, size, hop)[:total]
    samples, _ = normalize(samples)
    out = to_wav_bytes(samples, sr)
    return out, {
        "label": LABEL,
        "sample_rate": sr,
        "duration": round(len(samples) / sr, 2),
        "dc_removed": round(dc, 5),
        "clicks_fixed": clicks,
        "peak_before": peak_before,
        "peak_after": round(peak_of(samples), 4),
        "noise_floor_db": noise_db,
        "truncated": truncated,
    }
