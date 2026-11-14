import math

try:
    import numpy as np
except Exception:
    np = None

from . import fft as dsp_fft


def zero_crossing_rate(samples):
    n = len(samples)
    if n < 2:
        return 0.0
    if np is not None:
        arr = np.asarray(samples)
        return float(np.count_nonzero((arr[:-1] < 0) != (arr[1:] < 0)) / (n - 1))
    c = 0
    for i in range(1, n):
        if (samples[i - 1] < 0) != (samples[i] < 0):
            c += 1
    return c / (n - 1)


def rms(samples):
    if len(samples) == 0:
        return 0.0
    if np is not None:
        arr = np.asarray(samples, dtype=np.float64)
        return float(math.sqrt(float(np.dot(arr, arr)) / len(arr)))
    return math.sqrt(sum(s * s for s in samples) / len(samples))


_HANN_CACHE: dict = {}


def _hann_np(size):
    w = _HANN_CACHE.get(size)
    if w is None:
        w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(size) / size)
        _HANN_CACHE[size] = w
    return w


def spectrum(samples, size=2048):
    if np is not None:
        arr = np.asarray(samples[:size], dtype=np.float64)
        seg = np.zeros(size, dtype=np.float64)
        seg[: len(arr)] = arr
        spec = np.fft.rfft(seg * _hann_np(size))
        return [abs(v) for v in spec[: size // 2]]
    seg = list(samples[:size]) + [0.0] * max(0, size - len(samples))
    win = dsp_fft.hann(size)
    spec = dsp_fft.fft([seg[i] * win[i] for i in range(size)])
    return [abs(v) for v in spec[:size // 2]]


def avg_spectrum(samples, size=2048):
    n = len(samples)
    offs = [0, n // 4, n // 2, 3 * n // 4]
    acc = None
    for o in offs:
        mags = spectrum(samples[o:o + size], size)
        if acc is None:
            acc = mags
        else:
            for k in range(len(mags)):
                acc[k] += mags[k]
    return [v / len(offs) for v in acc]


def centroid_rolloff(mags, sr, size=2048, roll=0.85):
    total = sum(mags)
    if total <= 0:
        return 0.0, 0.0
    cent = 0.0
    for k, m in enumerate(mags):
        f = k * sr / size
        cent += f * m
    cent /= total
    run = 0.0
    off = 0.0
    for k, m in enumerate(mags):
        run += m
        if run >= total * roll:
            off = k * sr / size
            break
    return round(cent, 1), round(off, 1)


def harmonicity(samples, sr):
    n = len(samples)
    if n < 512:
        return 0.0
    if np is None:
        e = sum(s * s for s in samples) / n
        if e < 0.0000001:
            return 0.0
        lmin = max(1, int(sr / 1000))
        lmax = min(int(sr / 50), n // 2)
        best = 0.0
        for lag in range(lmin, lmax):
            v = 0.0
            for i in range(n - lag):
                v += samples[i] * samples[i + lag]
            nv = v / ((n - lag) * e)
            if nv > best:
                best = nv
        return round(best, 3)
    arr = np.asarray(samples, dtype=np.float64)
    e = float(np.dot(arr, arr)) / n
    if e < 0.0000001:
        return 0.0
    lmin = max(1, int(sr / 1000))
    lmax = min(int(sr / 50), n // 2)
    if lmin >= lmax:
        return 0.0
    size = 1
    while size < 2 * n:
        size <<= 1
    spec = np.fft.rfft(arr, size)
    ac = np.fft.irfft(spec * np.conj(spec), size)[:n]
    lags = np.arange(lmin, lmax)
    lens = (n - lags).astype(np.float64)
    nv = ac[lags] / (lens * e)
    best = float(nv.max())
    return round(best, 3)


def window_features(samples, sr):
    mags = avg_spectrum(samples)
    cent, off = centroid_rolloff(mags, sr)
    half = len(samples) // 2
    r1 = rms(samples[:half])
    r2 = rms(samples[half:])
    decay = round(r2 / (r1 + 1e-9), 3)
    return {
        "rms": round(rms(samples), 4),
        "zcr": round(zero_crossing_rate(samples), 4),
        "centroid": cent,
        "rolloff": off,
        "decay": decay,
        "harmonic": harmonicity(samples, sr),
    }
