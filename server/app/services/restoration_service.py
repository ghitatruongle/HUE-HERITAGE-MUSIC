import io
import math
import struct
import wave

from ..audio_dsp import fft as dsp_fft
from . import pitch_service

MAX_SECONDS = 10.0
CLICK_THR = 0.3
GATE_MULT = 2.0
GATE_FLOOR = 0.15
TARGET_PEAK = 0.89
LABEL = "Phục dựng – bản xử lý"


def remove_dc(samples):
    mean = sum(samples) / len(samples) if samples else 0.0
    return [s - mean for s in samples], mean


def remove_clicks(samples):
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
    return [s * g for s in samples], peak


def to_wav_bytes(samples, sr):
    clamped = []
    for s in samples:
        if s > 1.0:
            s = 1.0
        elif s < -1.0:
            s = -1.0
        clamped.append(int(s * 32767))
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
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
    samples = samples + [0.0] * (count_frames * hop + size - total)
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
