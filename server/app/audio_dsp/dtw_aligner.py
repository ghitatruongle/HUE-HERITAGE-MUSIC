import math
from array import array

BAND_RATIO = 0.1
MIN_BAND = 10
GAP_COST = 0.5


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
    dist = dp[n - 1][m - 1] / len(path)
    return path, round(dist, 4)
