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
        p = pp[best]
        tol = t["end"] - t["start"]
        tol = tol * OFFSET_RATIO
        if tol < OFFSET_MIN:
            tol = OFFSET_MIN
        if p["midi"] == t["midi"] and abs(p["end"] - t["end"]) <= tol + 0.000001:
            used[best] = True
            hits += 1
    return hits, onset_hits


def prf(hits, n_pred, n_truth):
    p = hits / n_pred if n_pred else 0.0
    r = hits / n_truth if n_truth else 0.0
    f = 2 * p * r / (p + r) if (p + r) > 0 else 0.0
    return round(p, 3), round(r, 3), round(f, 3)


def evaluate(pred, truth):
    hits, onset_hits = match(pred, truth)
    p, r, f = prf(hits, len(pred), len(truth))
    po, ro, fo = prf(onset_hits, len(pred), len(truth))
    pitch_acc = round(hits / onset_hits, 3) if onset_hits else 0.0
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
    }
