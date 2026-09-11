import io
import wave
import struct

FRAME = 1024
HOP = 1024
FMIN = 50.0
FMAX = 1000.0
MAX_SECONDS = 15.0
MAX_FRAMES = 4000


def read_mono_wav(data: bytes):
    bio = io.BytesIO(data)
    try:
        w = wave.open(bio, "rb")
    except Exception:
        raise ValueError("wav decode failed")
    n = w.getnframes()
    ch = w.getnchannels()
    sr = w.getframerate()
    sw = w.getsampwidth()
    raw = w.readframes(n)
    w.close()
    if sr <= 0 or ch <= 0 or sw not in (1, 2, 4) or n < 0:
        raise ValueError("bad wav header")
    frame_bytes = ch * sw
    n = min(n, len(raw) // frame_bytes)
    raw = raw[: n * frame_bytes]
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
    limit = int(sr * MAX_SECONDS)
    return samples[:limit], sr


def estimate_f0(samples, sr, frame=FRAME, hop=HOP):
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
            lag = lmin + pick
            if 0 < pick < len(norms) - 1:
                y0 = norms[pick - 1]
                y1 = norms[pick]
                y2 = norms[pick + 1]
                den = y0 - 2 * y1 + y2
                if den < 0:
                    lag = lag + 0.5 * (y0 - y2) / den
            if lag < 1:
                lag = 1
            f = round(sr / lag, 1)
        times.append(t)
        f0s.append(f)
        pos += hop
        if len(times) >= MAX_FRAMES:
            break
    return times, f0s
