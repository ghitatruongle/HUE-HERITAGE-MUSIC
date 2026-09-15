import math

ONSET_TOL = 0.05
OFFSET_MIN = 0.05
OFFSET_RATIO = 0.2


def valid_truth(items):
    if not isinstance(items, list):
        return False
    for e in items:
        if not isinstance(e, dict):
            return False
        if not isinstance(e.get("midi"), int):
            return False
        if not isinstance(e.get("start"), (int, float)):
            return False
        if not isinstance(e.get("end"), (int, float)):
            return False
        if e["end"] <= e["start"]:
            return False
    return True


def match(pred, truth):
    tp = sorted(truth, key=lambda x: x["start"])
    pp = sorted(pred, key=lambda x: x["start"])
    used = [False] * len(pp)
    hits = 0
    onset_hits = 0
    for t in tp:
        best = -1
        best_dt = ONSET_TOL + 0.000001
        for i, p in enumerate(pp):
            if used[i]:
                continue
            dt = abs(p["start"] - t["start"])
            if dt <= ONSET_TOL and dt < best_dt:
                best = i
                best_dt = dt
        if best < 0:
            continue
        onset_hits += 1
        used[best] = True
        p = pp[best]
        tol = t["end"] - t["start"]
        tol = tol * OFFSET_RATIO
        if tol < OFFSET_MIN:
            tol = OFFSET_MIN
        if p["midi"] == t["midi"] and abs(p["end"] - t["end"]) <= tol + 0.000001:
            hits += 1
    return hits, onset_hits


def prf(hits, n_pred, n_truth):
    p = hits / n_pred if n_pred else 0.0
    r = hits / n_truth if n_truth else 0.0
    f = 2 * p * r / (p + r) if (p + r) > 0 else 0.0
    return round(p, 3), round(r, 3), round(f, 3)


def cents(m1, m2):
    return abs(1200.0 * math.log2(m1 / m2)) if m1 > 0 and m2 > 0 else 0.0


def error_stats(pred, truth):
    tp = sorted(truth, key=lambda x: x["start"])
    pp = sorted(pred, key=lambda x: x["start"])
    used = [False] * len(pp)
    pitch_errs = []
    onset_errs = []
    offset_errs = []
    for t in tp:
        best = -1
        best_dt = ONSET_TOL + 0.000001
        for i, p in enumerate(pp):
            if used[i]:
                continue
            dt = abs(p["start"] - t["start"])
            if dt <= ONSET_TOL and dt < best_dt:
                best = i
                best_dt = dt
        if best < 0:
            continue
        used[best] = True
        p = pp[best]
        onset_errs.append(best_dt * 1000.0)
        offset_errs.append(abs(p["end"] - t["end"]) * 1000.0)
        pitch_errs.append(cents(2 ** (p["midi"] / 12.0), 2 ** (t["midi"] / 12.0)))
    return _summarize(pitch_errs), _summarize(onset_errs), _summarize(offset_errs)


def _summarize(vals):
    if not vals:
        return {"count": 0, "mean": 0.0, "median": 0.0, "max": 0.0}
    s = sorted(vals)
    return {
        "count": len(vals),
        "mean": round(sum(vals) / len(vals), 2),
        "median": round(s[len(s) // 2], 2),
        "max": round(s[-1], 2),
    }


def evaluate(pred, truth):
    hits, onset_hits = match(pred, truth)
    p, r, f = prf(hits, len(pred), len(truth))
    po, ro, fo = prf(onset_hits, len(pred), len(truth))
    pitch_acc = round(hits / onset_hits, 3) if onset_hits else 0.0
    pitch_err, onset_err, offset_err = error_stats(pred, truth)
    return {
        "pred_count": len(pred),
        "truth_count": len(truth),
        "hits": hits,
        "onset_hits": onset_hits,
        "precision": p,
        "recall": r,
        "f1": f,
        "onset_precision": po,
        "onset_recall": ro,
        "onset_f1": fo,
        "pitch_given_onset": pitch_acc,
        "pitch_error_cents": pitch_err,
        "onset_error_ms": onset_err,
        "offset_error_ms": offset_err,
    }
