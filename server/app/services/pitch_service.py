from __future__ import annotations

import io
import wave
import struct
from typing import Optional

try:
    import numpy as np
except Exception:
    np = None

FRAME = 1024
HOP = 1024
FMIN = 50.0
FMAX = 1000.0
MAX_SECONDS = 15.0
MAX_FRAMES = 24000
UNIFORM_SR = 16000


def resample_16k(samples, sr):
    if sr == UNIFORM_SR:
        return samples, sr
    if sr <= 0 or len(samples) == 0:
        return samples, sr
    if np is None:
        step = sr / UNIFORM_SR
        out = []
        for i in range(int(len(samples) / step)):
            pos = i * step
            k = int(pos)
            frac = pos - k
            a = samples[k]
            b = samples[k + 1] if k + 1 < len(samples) else a
            out.append(a + (b - a) * frac)
        return out, UNIFORM_SR
    arr = np.asarray(samples, dtype=np.float64)
    n_out = int(round(len(arr) * UNIFORM_SR / sr))
    if n_out <= 0:
        return [], UNIFORM_SR
    idx = np.linspace(0.0, max(0, len(arr) - 1), num=n_out)
    lo = np.floor(idx).astype(np.int64)
    hi = np.minimum(lo + 1, len(arr) - 1)
    frac = idx - lo
    out = arr[lo] * (1.0 - frac) + arr[hi] * frac
    return out.tolist(), UNIFORM_SR


def read_mono_wav(data: bytes, max_seconds: Optional[float] = MAX_SECONDS):
    bio = io.BytesIO(data)
    try:
        w = wave.open(bio, "rb")
    except Exception:
        return _decode_via_librosa(data, max_seconds=max_seconds)
    n = w.getnframes()
    ch = w.getnchannels()
    sr = w.getframerate()
    sw = w.getsampwidth()
    if sr <= 0 or ch <= 0 or sw not in (1, 2, 4) or n < 0:
        w.close()
        raise ValueError("bad wav header")
    frame_bytes = ch * sw
    limit = n
    if max_seconds is not None and max_seconds > 0:
        limit = min(limit, int(sr * max_seconds))
    raw = w.readframes(limit)
    w.close()
    n = min(limit, len(raw) // frame_bytes)
    raw = raw[: n * frame_bytes]
    if np is None:
        if sw == 1:
            vals = struct.unpack("<%dB" % (n * ch), raw)
            samples = [(v - 128) / 128.0 for v in vals]
        elif sw == 2:
            vals = struct.unpack("<%dh" % (n * ch), raw)
            samples = [v / 32768.0 for v in vals]
        else:
            vals = struct.unpack("<%di" % (n * ch), raw)
            samples = [v / 2147483648.0 for v in vals]
        if ch > 1:
            mono = []
            for i in range(n):
                s = 0.0
                for c in range(ch):
                    s += samples[i * ch + c]
                mono.append(s / ch)
            samples = mono
        return samples, sr
    if sw == 1:
        samples = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif sw == 2:
        samples = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    else:
        samples = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    if ch > 1:
        mono = np.zeros(n, dtype=np.float64)
        for c in range(ch):
            mono += samples[c::ch]
        samples = mono / ch
    return samples, sr


def _decode_via_librosa(data: bytes, max_seconds: Optional[float] = MAX_SECONDS):
    samples = None
    sr = None
    try:
        import soundfile as sf
        bio = io.BytesIO(data)
        data_arr, sr = sf.read(bio, dtype="float32")
        if data_arr.ndim > 1:
            data_arr = data_arr.mean(axis=1)
        samples = data_arr
    except Exception:
        try:
            import librosa
            bio = io.BytesIO(data)
            arr, sr = librosa.load(bio, sr=None, mono=True)
            samples = arr
        except Exception:
            raise ValueError("wav decode failed")

    if np is None:
        raise ValueError("wav decode failed")
    if sr is None or sr <= 0 or samples is None or len(samples) == 0:
        raise ValueError("bad wav header")
    arr = np.asarray(samples, dtype=np.float64)
    if max_seconds is not None and max_seconds > 0:
        limit = int(sr * max_seconds)
        arr = arr[:limit]
    return arr, int(sr)


def estimate_f0_reference(samples, sr, frame=FRAME, hop=HOP):
    if sr <= 0 or frame <= 0 or hop <= 0:
        return [], []
    times = []
    f0s = []
    n = len(samples)
    lmin = max(1, int(sr / FMAX))
    lmax = int(sr / FMIN)
    need = 2 * lmax + 1
    if frame < need:
        frame = 1
        while frame < need:
            frame <<= 1
    pos = 0
    while pos + frame <= n:
        seg = samples[pos:pos + frame]
        e = 0.0
        for s in seg:
            e += s * s
        e /= frame
        t = round(pos / sr, 3)
        if e < 0.000001:
            times.append(t)
            f0s.append(0.0)
            pos += hop
            continue
        best = 0.0
        norms = []
        top = min(lmax, frame // 2)
        if np is not None:
            s_arr = np.asarray(seg, dtype=np.float64)
            corr = np.correlate(s_arr, s_arr, mode="full")[len(s_arr) - 1 :]
            lens = np.arange(frame, frame - top, -1, dtype=np.float64)
            raw_norms = corr[:top] / (lens * (e + 1e-9))
            norms = raw_norms[lmin:top].tolist()
            best = max(norms) if norms else 0.0
        else:
            for lag in range(lmin, top):
                v = 0.0
                for i in range(frame - lag):
                    v += seg[i] * seg[i + lag]
                nv = v / ((frame - lag) * (e + 0.000000001))
                norms.append(nv)
                if nv > best:
                    best = nv
        if best < 0.3:
            f = 0.0
        else:
            pick = -1
            for k in range(1, len(norms) - 1):
                if norms[k] >= best * 0.9 and norms[k] >= norms[k - 1] and norms[k] >= norms[k + 1]:
                    pick = k
                    break
            if pick < 0:
                for k, nv in enumerate(norms):
                    if nv == best:
                        pick = k
                        break
            lag = float(lmin + pick)
            if 0 < pick < len(norms) - 1:
                y0 = norms[pick - 1]
                y1 = norms[pick]
                y2 = norms[pick + 1]
                den = y0 - 2 * y1 + y2
                if den < -1e-12:
                    delta = 0.5 * (y0 - y2) / den
                    if -1.0 <= delta <= 1.0:
                        lag = lag + delta
            if lag < 1.0:
                lag = 1.0
            f = round(sr / lag, 1)
        times.append(t)
        f0s.append(f)
        pos += hop
        if len(times) >= MAX_FRAMES:
            break
    return times, f0s


def _octave_smooth(f0s, window=5, passes=2, max_cents=700.0):
    if np is None or not f0s:
        return f0s
    arr = np.asarray(f0s, dtype=np.float64)
    voiced = arr > 0
    if int(voiced.sum()) < 5:
        return f0s
    half = window // 2
    for _ in range(passes):
        stacks = [arr]
        for off in range(1, half + 1):
            stacks.append(np.concatenate((arr[off:], arr[:off] * 0.0)))
            stacks.append(np.concatenate((arr[-off:] * 0.0, arr[:-off])))
        M = np.median(np.stack(stacks), axis=0)
        safe = np.where(M > 0, M, 1.0)
        ratio = np.where(voiced & (M > 0), arr / safe, 1.0)
        cents = 1200 * np.log2(np.where(ratio > 0, ratio, 1.0))
        fix = voiced & (M > 0) & (np.abs(cents) > max_cents)
        arr = np.where(fix, M, arr)
    return [round(float(v), 1) for v in arr]


def smooth_series(f0s, window=7):
    if not f0s or window <= 1:
        return list(f0s)
    if np is not None:
        arr = np.asarray(f0s, dtype=np.float64)
        half = window // 2
        stacks = [arr]
        for off in range(1, half + 1):
            padded = np.concatenate((np.full(off, arr[0] if len(arr) else 0.0), arr[:-off])) if off < len(arr) else np.full_like(arr, arr[0] if len(arr) else 0.0)
            stacks.append(padded)
            padded_hi = np.concatenate((arr[off:], np.full(min(off, len(arr)), arr[-1] if len(arr) else 0.0)))
            stacks.append(padded_hi)
        med = np.median(np.stack(stacks), axis=0)
        return [round(float(v), 1) for v in med]
    out = []
    n = len(f0s)
    for i in range(n):
        lo = max(0, i - window // 2)
        hi = min(n, i + window // 2 + 1)
        w = sorted(f0s[lo:hi])
        out.append(w[len(w) // 2])
    return out


def estimate_f0(samples, sr, frame=FRAME, hop=HOP):
    if np is None or sr <= 0 or frame <= 0 or hop <= 0:
        return estimate_f0_reference(samples, sr, frame=frame, hop=hop)
    arr = np.asarray(samples, dtype=np.float64)
    n = len(arr)
    lmin = max(1, int(sr / FMAX))
    lmax = int(sr / FMIN)
    need = 2 * lmax + 1
    if frame < need:
        frame = 1
        while frame < need:
            frame <<= 1
    if n < frame:
        return [], []

    starts = range(0, n - frame + 1, hop)
    times = [round(p / sr, 3) for p in starts]
    if len(times) >= MAX_FRAMES:
        starts = list(starts)[:MAX_FRAMES]
        times = times[:MAX_FRAMES]

    lags = np.arange(lmin, min(lmax + 1, frame))
    if lags.size == 0 or len(times) == 0:
        return [], []

    windows = np.lib.stride_tricks.sliding_window_view(arr, frame)[::hop][: len(times)]
    energy = np.mean(windows * windows, axis=1)

    fft_size = 1
    while fft_size < 2 * frame:
        fft_size <<= 1
    norms = np.empty((len(times), lags.size), dtype=np.float64)
    batch = 512
    for lo in range(0, len(times), batch):
        hi = min(lo + batch, len(times))
        chunk = np.ascontiguousarray(windows[lo:hi])
        spec = np.fft.rfft(chunk, fft_size, axis=1)
        ac = np.fft.irfft(spec * np.conj(spec), fft_size, axis=1)[:, :frame].real
        denom = (frame - lags)[None, :] * (energy[lo:hi, None] + 1e-9)
        norms[lo:hi] = ac[:, lags] / denom
    del windows

    best = np.zeros(len(times))
    pick = np.zeros(len(times), dtype=np.int64)
    voiced = (energy >= 0.000001) & (norms.max(axis=1) >= 0.3)
    if voiced.any():
        nrm_v = norms[voiced]
        best_v = nrm_v.max(axis=1)
        threshold = 0.98 * best_v

        if nrm_v.shape[1] >= 3:
            local_max = np.zeros_like(nrm_v, dtype=bool)
            local_max[:, 1:-1] = (nrm_v[:, 1:-1] >= nrm_v[:, :-2]) & (nrm_v[:, 1:-1] >= nrm_v[:, 2:])
            local_max[:, 0] = nrm_v[:, 0] > nrm_v[:, 1] if nrm_v.shape[1] > 1 else True
            local_max[:, -1] = nrm_v[:, -1] > nrm_v[:, -2] if nrm_v.shape[1] > 1 else True
        else:
            local_max = np.ones_like(nrm_v, dtype=bool)

        hit = (nrm_v >= threshold[:, None]) & local_max
        has_hit = np.any(hit, axis=1)
        pick_hit = np.where(has_hit, hit.argmax(axis=1), 0)
        fallback = nrm_v.argmax(axis=1)
        pick_v = np.where(has_hit, pick_hit, fallback)
        best[voiced] = best_v
        pick[voiced] = pick_v

    idx = pick
    y1 = norms[np.arange(len(times)), idx]
    lag_lo = np.maximum(idx - 1, 0)
    lag_hi = np.minimum(idx + 1, norms.shape[1] - 1)
    y0 = norms[np.arange(len(times)), lag_lo]
    y2 = norms[np.arange(len(times)), lag_hi]
    den = y0 - 2 * y1 + y2
    delta = np.zeros(len(times))
    valid = den < -1e-12
    d = 0.5 * (y0 - y2) / np.where(valid, den, 1.0)
    delta = np.where(valid & (np.abs(d) <= 1.0), d, 0.0)

    lag = lmin + idx + delta
    lag = np.maximum(lag, 1.0)
    f0 = np.where(voiced & (lag >= 1.0), sr / lag, 0.0)
    f0s = _octave_smooth([round(float(v), 1) for v in f0])
    return times, f0s
