import math

try:
    import numpy as np
except Exception:
    np = None


def _fft_python(x):
    n = len(x)
    if n == 0:
        return []
    if n & (n - 1) != 0:
        p = 1
        while p < n:
            p <<= 1
        x = list(x) + [0.0] * (p - n)
        n = p
    a = [complex(v, 0) for v in x]
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    size = 2
    while size <= n:
        ang = -2 * math.pi / size
        wlen = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, size):
            w = complex(1, 0)
            half = size // 2
            for k in range(half):
                u = a[i + k]
                v = a[i + k + half] * w
                a[i + k] = u + v
                a[i + k + half] = u - v
                w *= wlen
        size <<= 1
    return a


def _ifft_python(x):
    n = len(x)
    if n == 0:
        return []
    conj = [complex(v).conjugate() for v in x]
    y = _fft_python(conj)
    m = len(y)
    rec = [v.conjugate() / m for v in y]
    return rec[:n]


def fft(x):
    if np is None:
        return _fft_python(x)
    arr = np.asarray(x, dtype=np.float64)
    n = len(arr)
    if n == 0:
        return []
    if n & (n - 1) != 0:
        p = 1
        while p < n:
            p <<= 1
        arr = np.concatenate([arr, np.zeros(p - n, dtype=np.float64)])
        n = p
    return np.fft.fft(arr).tolist()


def ifft(x):
    if np is None:
        return _ifft_python(x)
    arr = np.asarray(x, dtype=np.complex128)
    n = len(arr)
    if n == 0:
        return []
    if n & (n - 1) != 0:
        p = 1
        while p < n:
            p <<= 1
        arr = np.concatenate([arr, np.zeros(p - n, dtype=np.complex128)])
    m = len(arr)
    rec = np.conj(np.fft.fft(np.conj(arr))) / m
    return rec[:n].tolist()


def hann(n):
    return [0.5 - 0.5 * math.cos(2 * math.pi * i / n) for i in range(n)]


def stft(samples, size=1024, hop=512):
    win = hann(size)
    n = len(samples)
    if np is None:
        frames = []
        pos = 0
        while pos + size <= n:
            frames.append([samples[pos + i] * win[i] for i in range(size)])
            pos += hop
        return frames, win
    if n < size:
        return [], win
    count = (n - size) // hop + 1
    arr = np.asarray(samples, dtype=np.float64)
    idx = np.arange(size)[None, :] + hop * np.arange(count)[:, None]
    frames = arr[idx] * np.asarray(win, dtype=np.float64)[None, :]
    return [frames[i] for i in range(count)], win


def istft(frames, win, size=1024, hop=512):
    if np is None or not frames:
        total = (len(frames) - 1) * hop + size if frames else 0
        out = [0.0] * total
        wsum = [0.0] * total
        for f, fr in enumerate(frames):
            pos = f * hop
            for i in range(size):
                w = win[i]
                out[pos + i] += fr[i].real * w
                wsum[pos + i] += w * w
        for i in range(total):
            if wsum[i] > 1e-9:
                out[i] /= wsum[i]
        return out
    total = (len(frames) - 1) * hop + size
    out = np.zeros(total, dtype=np.float64)
    wsum = np.zeros(total, dtype=np.float64)
    w = np.asarray(win, dtype=np.float64)
    w2 = w * w
    for f, fr in enumerate(frames):
        pos = f * hop
        arr = np.asarray(fr, dtype=np.complex128)
        out[pos:pos + size] += arr.real * w
        wsum[pos:pos + size] += w2
    nz = wsum > 1e-9
    out[nz] /= wsum[nz]
    return out.tolist()
