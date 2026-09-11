import math

MIN_DUR = 0.12
SEMI_TOL = 100.0
VELOCITY = 80


def freq_to_midi(freq):
    if freq <= 0:
        return 0
    return int(round(69 + 12 * math.log2(freq / 440.0)))


def cents_diff(f1, f2):
    if f1 <= 0 or f2 <= 0:
        return 999999.0
    return abs(1200 * math.log2(f1 / f2))


def smooth(f0):
    out = list(f0)
    for i in range(1, len(f0) - 1):
        w = sorted([f0[i - 1], f0[i], f0[i + 1]])
        out[i] = w[1]
    return out


def median(vals):
    if not vals:
        return 0.0
    s = sorted(vals)
    return s[len(s) // 2]


def segment_notes(times, f0):
    sm = smooth(f0)
    step = times[1] - times[0] if len(times) > 1 else 0.0
    notes = []
    start = -1
    anchor = 0.0
    buf = []
    i = 0
    n = len(sm)
    while i < n:
        f = sm[i]
        if f <= 0:
            if start >= 0:
                nxt = sm[i + 1] if i + 1 < n else 0
                if nxt > 0 and cents_diff(nxt, anchor) <= SEMI_TOL:
                    buf.append(f)
                    i += 1
                    continue
                close = i - len(buf) if buf else i
                flush = [v for v in sm[start:close] if v > 0]
                if flush and times[close - 1] - times[start] + step >= MIN_DUR - 0.001:
                    m = median(flush)
                    notes.append({
                        "midi": freq_to_midi(m),
                        "freq": round(m, 1),
                        "start": round(times[start], 3),
                        "end": round(times[close - 1] + step, 3),
                        "velocity": VELOCITY,
                    })
                start = -1
                buf = []
            i += 1
            continue
        if start < 0:
            start = i
            anchor = f
            buf = []
        elif cents_diff(f, anchor) > SEMI_TOL:
            flush = [v for v in sm[start:i] if v > 0]
            if flush and times[i - 1] - times[start] + step >= MIN_DUR - 0.001:
                m = median(flush)
                notes.append({
                    "midi": freq_to_midi(m),
                    "freq": round(m, 1),
                    "start": round(times[start], 3),
                    "end": round(times[i - 1] + step, 3),
                    "velocity": VELOCITY,
                })
            start = i
            anchor = f
            buf = []
        else:
            if buf:
                buf = []
        i += 1
    if start >= 0:
        flush = [v for v in sm[start:] if v > 0]
        if flush and times[-1] - times[start] + step >= MIN_DUR - 0.001:
            m = median(flush)
            notes.append({
                "midi": freq_to_midi(m),
                "freq": round(m, 1),
                "start": round(times[start], 3),
                "end": round(times[-1] + step, 3),
                "velocity": VELOCITY,
            })
    return notes
