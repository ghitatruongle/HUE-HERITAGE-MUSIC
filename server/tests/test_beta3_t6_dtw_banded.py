import math

import numpy as np

from app.audio_dsp import dtw_aligner

_BIG = 1e18
BAND_RATIO = dtw_aligner.BAND_RATIO
MIN_BAND = dtw_aligner.MIN_BAND
GAP_COST = dtw_aligner.GAP_COST


def _to_semi(freq):
    if freq <= 0:
        return 0.0
    return 69 + 12 * math.log2(freq / 440.0)


def _dtw_full_matrix_reference(a, b, band_ratio=BAND_RATIO):
    n = len(a)
    m = len(b)
    if n == 0 or m == 0:
        return [], 0.0
    w = max(MIN_BAND, int(band_ratio * max(n, m)), abs(n - m) + 1)
    semi_a = np.fromiter((_to_semi(v) for v in a), dtype=np.float64, count=n)
    semi_b = np.fromiter((_to_semi(v) for v in b), dtype=np.float64, count=m)
    both_v = (semi_a[:, None] > 0) & (semi_b[None, :] > 0)
    both_u = (semi_a[:, None] <= 0) & (semi_b[None, :] <= 0)
    diff = np.abs(semi_a[:, None] - semi_b[None, :])
    C = np.where(both_v, diff, np.where(both_u, 0.0, GAP_COST))
    mask = np.zeros((n, m), dtype=bool)
    for i in range(n):
        lo = max(0, i - w)
        hi = min(m, i + w + 1)
        mask[i, lo:hi] = True
    bt = np.zeros((n, m), dtype=np.uint8)
    prev = np.full(m, _BIG)
    for i in range(n):
        c = C[i]
        S = np.cumsum(c)
        P = np.concatenate(([0.0], S[:-1]))
        if i == 0:
            e = np.full(m, _BIG)
            if mask[0, 0]:
                e[0] = 0.0
        else:
            diag = np.concatenate(([_BIG], prev[:-1]))
            e = np.minimum(prev, diag)
            e = np.where(mask[i], e, _BIG)
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
        row[~mask[i]] = 0
        bt[i] = row
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
    dist = prev[m - 1] / len(path)
    return path, round(float(dist), 4)


def _contour(seed, n, base=220.0, unvoiced_ratio=0.15):
    rng = np.random.default_rng(seed)
    t = np.arange(n) / 100.0
    f0 = base * (2 ** (0.25 * np.sin(2 * math.pi * 0.7 * t) + rng.normal(0, 0.02, n)))
    mask = rng.uniform(size=n) < unvoiced_ratio
    f0[mask] = 0.0
    return [round(float(v), 2) for v in f0]


def test_dtw_banded_identical_to_full_matrix_same_length():
    a = _contour(1, 200)
    b = _contour(2, 200)
    got_path, got_dist = dtw_aligner.dtw(a, b)
    ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
    assert got_path == ref_path
    assert got_dist == ref_dist


def test_dtw_banded_identical_different_lengths():
    a = _contour(3, 260)
    b = _contour(4, 180)
    got_path, got_dist = dtw_aligner.dtw(a, b)
    ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
    assert got_path == ref_path
    assert got_dist == ref_dist


def test_dtw_banded_identical_pitch_shifted_heavy_unvoiced():
    a = _contour(5, 320, base=220.0, unvoiced_ratio=0.3)
    b = [v * 1.06 if v > 0 else 0.0 for v in _contour(5, 320, base=220.0, unvoiced_ratio=0.3)]
    rng = np.random.default_rng(9)
    drop = rng.uniform(size=len(b)) < 0.2
    b = [0.0 if drop[i] else b[i] for i in range(len(b))]
    got_path, got_dist = dtw_aligner.dtw(a, b)
    ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
    assert got_path == ref_path
    assert got_dist == ref_dist


def test_dtw_banded_identical_long_contours():
    a = _contour(6, 1200)
    b = _contour(7, 1100)
    got_path, got_dist = dtw_aligner.dtw(a, b)
    ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
    assert got_path == ref_path
    assert got_dist == ref_dist


def test_dtw_banded_identical_silence_and_single():
    for a, b in [([0.0] * 100, [0.0] * 120), ([220.0] * 60, [222.0] * 60), ([220.0], [220.0])]:
        got_path, got_dist = dtw_aligner.dtw(a, b)
        ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
        assert got_path == ref_path
        assert got_dist == ref_dist


def test_dtw_banded_empty_inputs():
    assert dtw_aligner.dtw([], [1.0]) == ([], 0.0)
    assert dtw_aligner.dtw([1.0], []) == ([], 0.0)


def _adversarial_contour(rng, length, base):
    out = []
    while len(out) < length:
        kind = int(rng.integers(0, 4))
        seg = int(rng.integers(1, max(2, length // 3)))
        if kind == 0:
            out += [float(base)] * seg
        elif kind == 1:
            out += [0.0] * seg
        elif kind == 2:
            out += [float(base * (1 + 0.01 * k)) for k in range(seg)]
        else:
            b2 = base * 2 ** rng.uniform(-0.2, 0.2)
            out += [float(b2)] * seg
    return [round(v, 2) for v in out[:length]]


def test_dtw_banded_property_sweep_matches_reference():
    for seed in range(30):
        rng = np.random.default_rng(seed)
        n = int(rng.integers(60, 400))
        m = int(rng.integers(60, 400))
        a = _adversarial_contour(rng, n, 220.0)
        b = _adversarial_contour(rng, m, 224.0)
        got_path, got_dist = dtw_aligner.dtw(a, b)
        ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
        assert got_path == ref_path, f"seed={seed} path diverged"
        assert got_dist == ref_dist, f"seed={seed} dist diverged"


def test_dtw_banded_adversarial_structures():
    cases = {
        "sustain+silence": ([220.0] * 140, [0.0] * 60 + [224.0] * 140),
        "sustain_long_b": ([220.0] * 200, [0.0] * 120 + [224.0] * 200),
        "alternating_gaps": ([220.0 if i % 7 else 0.0 for i in range(200)],
                             [0.0 if i % 5 else 224.0 for i in range(200)]),
        "right_heavy": ([0.0] * 30 + [220.0] * 150, [224.0] * 220),
    }
    for name, (a, b) in cases.items():
        got_path, got_dist = dtw_aligner.dtw(a, b)
        ref_path, ref_dist = _dtw_full_matrix_reference(a, b)
        assert got_path == ref_path, name
        assert got_dist == ref_dist, name
