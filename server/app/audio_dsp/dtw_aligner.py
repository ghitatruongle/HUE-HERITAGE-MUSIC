import math
from array import array

try:
    import numpy as np
except Exception:
    np = None

BAND_RATIO = 0.12
MIN_BAND = 10
GAP_COST = 0.5
_BIG = 1e18


def to_semi(freq):
    if freq <= 0:
        return 0.0
    return 69 + 12 * math.log2(freq / 440.0)


def frame_cost(a, b):
    if a > 0 and b > 0:
        return abs(to_semi(a) - to_semi(b))
    if a <= 0 and b <= 0:
        return 0.0
    return GAP_COST


def dtw(a, b, band_ratio=BAND_RATIO):
    n = len(a)
    m = len(b)
    if n == 0 or m == 0:
        return [], 0.0
    w = max(MIN_BAND, int(band_ratio * max(n, m)), abs(n - m) + 1)
    if np is None:
        return _dtw_python(a, b, band_ratio=band_ratio)
    semi_a = np.fromiter((to_semi(v) for v in a), dtype=np.float64, count=n)
    semi_b = np.fromiter((to_semi(v) for v in b), dtype=np.float64, count=m)
    bt_band = np.zeros((n, 2 * w + 1), dtype=np.uint8)
    prev = np.full(m, _BIG)
    for i in range(n):
        c = np.abs(semi_a[i] - semi_b)
        c = np.where(
            (semi_a[i] > 0) & (semi_b > 0),
            c,
            np.where((semi_a[i] <= 0) & (semi_b <= 0), 0.0, GAP_COST),
        )
        S = np.cumsum(c)
        P = np.concatenate(([0.0], S[:-1]))
        lo = max(0, i - w)
        hi = min(m, i + w + 1)
        if i == 0:
            e = np.full(m, _BIG)
            e[0] = 0.0
        else:
            diag = np.concatenate(([_BIG], prev[:-1]))
            e = np.minimum(prev, diag)
            band_mask = np.zeros(m, dtype=bool)
            band_mask[lo:hi] = True
            e = np.where(band_mask, e, _BIG)
        vals = e - P
        cur = S + np.minimum.accumulate(vals)
        diag_v = np.concatenate(([_BIG], prev[:-1]))
        left_v = np.concatenate(([_BIG], cur[:-1]))
        eps = 1e-9
        row = np.where(
            (diag_v <= prev + eps) & (diag_v <= left_v + eps),
            0,
            np.where(prev <= left_v + eps, 1, 2),
        ).astype(np.uint8)
        if i > 0:
            row[:lo] = 0
            row[hi:] = 0
        bt_band[i, : hi - lo] = row[lo:hi]
        prev = cur
    if prev[m - 1] >= _BIG * 0.5:
        return [], 0.0
    path = []
    i = n - 1
    j = m - 1
    guard = n + m + 1
    while guard > 0:
        guard -= 1
        path.append([i, j])
        if i == 0 and j == 0:
            break
        if i == 0:
            j -= 1
            continue
        if j == 0:
            i -= 1
            continue
        off = j - max(0, i - w)
        if off < 0 or off >= 2 * w + 1:
            mv = 0
        else:
            mv = bt_band[i, off]
        if mv == 0:
            i -= 1
            j -= 1
        elif mv == 1:
            i -= 1
        else:
            j -= 1
    path.reverse()
    if not path:
        return [], 0.0
    dist = prev[m - 1] / len(path)
    return path, round(float(dist), 4)


def _dtw_python(a, b, band_ratio=BAND_RATIO):
    n = len(a)
    m = len(b)
    if n == 0 or m == 0:
        return [], 0.0
    w = max(MIN_BAND, int(band_ratio * max(n, m)), abs(n - m) + 1)
    INF = float("inf")
    dp = [array("d", [INF]) * m for _ in range(n)]
    bt = [bytearray(m) for _ in range(n)]
    for i in range(n):
        lo = max(0, i - w)
        hi = min(m, i + w + 1)
        for j in range(lo, hi):
            c = frame_cost(a[i], b[j])
            if i == 0 and j == 0:
                dp[i][j] = c
                continue
            best = INF
            move = 0
            if i > 0 and j > 0 and dp[i - 1][j - 1] < best:
                best = dp[i - 1][j - 1]
                move = 0
            if i > 0 and dp[i - 1][j] < best:
                best = dp[i - 1][j]
                move = 1
            if j > 0 and dp[i][j - 1] < best:
                best = dp[i][j - 1]
                move = 2
            dp[i][j] = c + best
            bt[i][j] = move
    if dp[n - 1][m - 1] == INF:
        return [], 0.0
    path = []
    i = n - 1
    j = m - 1
    guard = n + m + 1
    while guard > 0:
        guard -= 1
        path.append([i, j])
        if i == 0 and j == 0:
            break
        if i == 0:
            j -= 1
            continue
        if j == 0:
            i -= 1
            continue
        mv = bt[i][j]
        if mv == 0:
            i -= 1
            j -= 1
        elif mv == 1:
            i -= 1
        else:
            j -= 1
    path.reverse()
    if not path:
        return [], 0.0
    dist = dp[n - 1][m - 1] / len(path)
    return path, round(dist, 4)
