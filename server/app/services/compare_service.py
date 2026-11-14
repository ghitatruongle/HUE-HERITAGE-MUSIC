import hashlib
import math
import threading

from ..audio_dsp import dtw_aligner
from ..config import settings
from . import pitch_service, amt_service

MAX_POINTS = 300
MAX_COMPARE_SECONDS = 35.0
REF_SMOOTH_WINDOW = 17
REF_DELTA_CENTS = 80.0
REF_MIN_DUR = 0.12
REF_MERGE_GAP = 0.09
REF_MERGE_CENTS = 120.0
REF_ABSORB_DUR = 0.08
REF_ABSORB_CENTS = 200.0
WEIGHT_PITCH = 0.5
WEIGHT_RHYTHM = 0.3
WEIGHT_STABILITY = 0.2
OK_CENTS = 20.0
MINOR_CENTS = 50.0
OCTAVE_LOW = 1050.0
OCTAVE_HIGH = 1350.0
ONSET_TOLERANCE_MS = 120.0
PITCH_SLOPE_NOTE = 0.75
PITCH_SLOPE_FRAME = 1.5
RHYTHM_SLOPE_MS = 8.0
RHYTHM_NEUTRAL_BASE = 75.0
UNMATCHED_PENALTY = 50.0
SCORE_MISSING_PENALTY = 25.0
MATCH_ERR_LIMIT_CENTS = 700.0
MATCH_OCTAVE_LOW = 1050.0
MATCH_OCTAVE_HIGH = 1350.0
DENSE_MATCH_RATIO = 0.6
STABILITY_SLOPE = 1.0
VIBRATO_MIN_EXTENT_CENTS = 20.0
VIBRATO_MIN_RATE = 2.5
VIBRATO_MAX_RATE = 10.0
VIBRATO_MIN_CROSSINGS = 4

VERDICT_TEXT = {
    "ok": "Chuẩn",
    "minor": "Lệch nhẹ",
    "off": "Lệch",
    "octave": "Sai quãng tám",
    "unclear": "Không rõ",
}

_REF_CACHE: dict = {}
_REF_CACHE_LOCK = threading.Lock()
REF_CACHE_MAX = 32
_REF_KEY_LOCKS: dict = {}
_REF_KEY_LOCKS_GUARD = threading.Lock()
REF_KEY_LOCKS_MAX = 256


def _ref_key_lock(key):
    with _REF_KEY_LOCKS_GUARD:
        if len(_REF_KEY_LOCKS) >= REF_KEY_LOCKS_MAX:
            for stale in list(_REF_KEY_LOCKS)[: REF_KEY_LOCKS_MAX // 2]:
                _REF_KEY_LOCKS.pop(stale, None)
        return _REF_KEY_LOCKS.setdefault(key, threading.Lock())


def _reference_state(data, key=None):
    if key is None:
        key = "sha:" + hashlib.sha256(data).hexdigest()
    with _REF_CACHE_LOCK:
        hit = _REF_CACHE.get(key)
    if hit is not None:
        return hit
    lock = _ref_key_lock(key)
    with lock:
        with _REF_CACHE_LOCK:
            hit = _REF_CACHE.get(key)
        if hit is not None:
            return hit
        samples, sr = pitch_service.read_mono_wav(data, max_seconds=MAX_COMPARE_SECONDS)
        samples, sr = pitch_service.resample_16k(samples, sr)
        times, f0 = pitch_service.estimate_f0(samples, sr, hop=256)
        if not times:
            state = {"has_frames": False, "valid": False, "times": [], "f0": [], "onset_a": 0.0}
        else:
            a, b = onset_trim(samples, sr)
            keep = [i for i, t in enumerate(times) if a - 0.001 <= t <= b + 0.001] if b > a else []
            state = {
                "has_frames": True,
                "valid": bool(keep),
                "times": [times[i] for i in keep],
                "f0": [f0[i] for i in keep],
                "onset_a": a,
            }
        with _REF_CACHE_LOCK:
            if len(_REF_CACHE) >= REF_CACHE_MAX:
                _REF_CACHE.pop(next(iter(_REF_CACHE)))
            _REF_CACHE[key] = state
        return state


def to_cents(freq):
    if freq <= 0:
        return 0.0
    return 1200 * math.log2(freq / 440.0)


def downsample(times, vals):
    n = len(times)
    if n <= MAX_POINTS:
        return [round(t, 3) for t in times], [round(v, 1) for v in vals]
    step = n / MAX_POINTS
    ot = []
    ov = []
    k = 0
    while int(k) < n and len(ot) < MAX_POINTS:
        ot.append(round(times[int(k)], 3))
        ov.append(round(vals[int(k)], 1))
        k += step
    return ot, ov


def clamp_score(v):
    if v < 0:
        return 0.0
    if v > 100:
        return 100.0
    return round(v, 1)


def verdict_code(err):
    a = abs(err)
    if OCTAVE_LOW <= a <= OCTAVE_HIGH:
        return "octave"
    if a <= OK_CENTS:
        return "ok"
    if a <= MINOR_CENTS:
        return "minor"
    return "off"


def onset_trim(samples, sr):
    try:
        import numpy as _np

        arr = _np.asarray(samples, dtype=_np.float64)
        if arr.size == 0:
            return 0.0, 0.0
        peak = float(_np.abs(arr).max())
        if peak < 0.005:
            return 0.0, 0.0
        thr = peak * 0.1
        if thr < 0.02:
            thr = 0.02
        idx = _np.nonzero(_np.abs(arr) >= thr)[0]
        if idx.size == 0:
            return 0.0, 0.0
        a = int(idx[0])
        b = int(idx[-1]) + 1
        if a >= b:
            return 0.0, 0.0
        return round(a / sr, 3), round(b / sr, 3)
    except Exception:
        pass
    peak = 0.0
    for s in samples:
        v = abs(s)
        if v > peak:
            peak = v
    if peak < 0.005:
        return 0.0, 0.0
    thr = peak * 0.1
    if thr < 0.02:
        thr = 0.02
    n = len(samples)
    a = 0
    while a < n and abs(samples[a]) < thr:
        a += 1
    b = n
    while b > a and abs(samples[b - 1]) < thr:
        b -= 1
    if a >= b:
        return 0.0, 0.0
    return round(a / sr, 3), round(b / sr, 3)


def empty_result():
    return {
        "metrics": {
            "reference_quality": "",
            "mean_abs_cents": 0.0,
            "median_cents": 0.0,
            "mean_offset_ms": 0.0,
            "start_offset_ms": 0.0,
            "pairs": 0,
            "dtw_distance": 0.0,
            "pitch_score": 0.0,
            "time_score": 0.0,
            "rhythm_score": 0.0,
            "stability_score": 0.0,
            "ornament": 0.0,
            "matched_notes": 0,
            "unmatched_notes": 0,
            "missing_notes": 0,
            "vibrato_rate": 0.0,
            "score": 0.0,
            "summary_hint": "",
            "verdict_counts": {},
            "summary_codes": [],
        },
        "sample": {"times": [], "f0": []},
        "user_warped": {"times": [], "f0": []},
        "notes": [],
    }


def _moving_median(vals, window=5):
    out = []
    half = window // 2
    for i in range(len(vals)):
        lo = max(0, i - half)
        hi = min(len(vals), i + half + 1)
        w = sorted(vals[lo:hi])
        out.append(w[len(w) // 2])
    return out


def _note_stats(times, f0, note):
    frames = [f for t, f in zip(times, f0) if note["start"] - 1e-6 <= t <= note["end"] + 1e-6 and f > 0]
    if len(frames) < 4:
        return None
    dur = max(1e-3, note["end"] - note["start"])
    med = sorted(frames)[len(frames) // 2]
    if med <= 0:
        return None
    cents = [1200 * math.log2(f / med) for f in frames]
    mean = sum(cents) / len(cents)
    dev = [c - mean for c in cents]
    crossings = sum(1 for i in range(len(dev) - 1) if dev[i] * dev[i + 1] < 0)
    rate = crossings / (2.0 * dur)
    ordered = sorted(abs(d) for d in dev)
    extent = ordered[min(len(ordered) - 1, int(len(ordered) * 0.9))]
    mov = _moving_median(cents)
    mad = sum(abs(c - m) for c, m in zip(cents, mov)) / len(cents)
    vibrato = extent >= VIBRATO_MIN_EXTENT_CENTS and VIBRATO_MIN_RATE <= rate <= VIBRATO_MAX_RATE and crossings >= VIBRATO_MIN_CROSSINGS
    return {"vibrato": vibrato, "rate": round(rate, 2), "extent": round(extent, 1), "mad": round(mad, 1)}


def _hint_for(err, onset_ms, dur_ratio, stats, voiced):
    parts = []
    codes = []
    a = abs(err)
    if a > MINOR_CENTS:
        if err > 0:
            codes.append("pitch_high")
            parts.append(f"Cao hơn {a:.0f} cents — hát trầm xuống")
        else:
            codes.append("pitch_low")
            parts.append(f"Thấp hơn {a:.0f} cents — hát cao lên")
    elif a > OK_CENTS:
        if err > 0:
            codes.append("pitch_slightly_high")
            parts.append(f"Hơi cao {a:.0f} cents")
        else:
            codes.append("pitch_slightly_low")
            parts.append(f"Hơi thấp {a:.0f} cents")
    if onset_ms > ONSET_TOLERANCE_MS:
        codes.append("onset_late")
        parts.append(f"Vào trễ {onset_ms:.0f}ms")
    elif onset_ms < -ONSET_TOLERANCE_MS:
        codes.append("onset_early")
        parts.append(f"Vào sớm {abs(onset_ms):.0f}ms")
    if dur_ratio < 0.6:
        codes.append("hold_longer")
        parts.append("Giữ nốt dài hơn")
    if stats is not None and stats["vibrato"] and a <= MINOR_CENTS:
        codes.append("vibrato_good")
        parts.append("Rền đẹp — giữ chất này")
    if not voiced:
        codes.append("unclear_voice")
        parts.append("Chưa rõ giọng — thu gần mic hơn")
    return "; ".join(parts), codes


def _filter_transition_notes(notes, min_dur=0.15, near_cents=250.0):
    out = []
    for i, nt in enumerate(notes):
        dur = nt["end"] - nt["start"]
        if dur >= min_dur:
            out.append(nt)
            continue
        prev_f = out[-1]["freq"] if out else 0.0
        next_f = notes[i + 1]["freq"] if i + 1 < len(notes) else 0.0
        near_prev = prev_f > 0 and abs(to_cents(nt["freq"]) - to_cents(prev_f)) < near_cents
        near_next = next_f > 0 and abs(to_cents(nt["freq"]) - to_cents(next_f)) < near_cents
        oct_prev = prev_f > 0 and abs(abs(to_cents(nt["freq"]) - to_cents(prev_f)) - 1200.0) < 60.0
        oct_next = next_f > 0 and abs(abs(to_cents(nt["freq"]) - to_cents(next_f)) - 1200.0) < 60.0
        if near_prev or near_next or oct_prev or oct_next:
            continue
        out.append(nt)
    return out


def _flush_delta_note(notes, times, frames, start, end_i, step):
    voiced = [v for v in frames if v > 0]
    if not voiced or end_i <= start:
        return
    dur = times[end_i - 1] + step - times[start]
    if dur < REF_MIN_DUR - 0.001:
        return
    m = amt_service.median(voiced)
    notes.append({
        "midi": amt_service.freq_to_midi(m),
        "freq": round(m, 1),
        "start": round(times[start], 3),
        "end": round(times[end_i - 1] + step, 3),
        "velocity": amt_service.VELOCITY,
    })


def _delta_segment(times, f0):
    notes = []
    step = times[1] - times[0] if len(times) > 1 else 0.0
    start = -1
    frames = []
    prev_cents = None
    for i, f in enumerate(f0):
        if f <= 0:
            if start >= 0:
                _flush_delta_note(notes, times, frames, start, i, step)
                start = -1
                frames = []
                prev_cents = None
            continue
        c = 1200 * math.log2(f / 440.0)
        if start < 0:
            start = i
            frames = [f]
        elif prev_cents is not None and abs(c - prev_cents) > REF_DELTA_CENTS:
            _flush_delta_note(notes, times, frames, start, i, step)
            start = i
            frames = [f]
        else:
            frames.append(f)
        prev_cents = c
    if start >= 0:
        _flush_delta_note(notes, times, frames, start, len(f0), step)
    return notes


def _merge_fragments(notes):
    if len(notes) < 2:
        return notes
    out = []
    for nt in notes:
        if out:
            a = out[-1]
            gap = nt["start"] - a["end"]
            delta = amt_service.cents_diff(nt["freq"], a["freq"])
            dur_a = a["end"] - a["start"]
            dur_b = nt["end"] - nt["start"]
            if gap < REF_MERGE_GAP and delta < REF_MERGE_CENTS:
                a["end"] = nt["end"]
                w = max(1e-6, dur_a + dur_b)
                m = (a["freq"] * dur_a + nt["freq"] * dur_b) / w
                a["freq"] = round(m, 1)
                a["midi"] = amt_service.freq_to_midi(m)
                continue
            if dur_b < REF_ABSORB_DUR and gap < REF_MERGE_GAP and delta < REF_ABSORB_CENTS:
                a["end"] = nt["end"]
                continue
            if dur_a < REF_ABSORB_DUR and gap < REF_MERGE_GAP and delta < REF_ABSORB_CENTS:
                out[-1] = {
                    "midi": nt["midi"],
                    "freq": nt["freq"],
                    "start": a["start"],
                    "end": nt["end"],
                    "velocity": nt["velocity"],
                }
                continue
        out.append(nt)
    return out


def _reference_notes(times, smooth7, f0_raw):
    if (settings.reference_segmentation or "").strip().lower() != "v2":
        return _filter_transition_notes(amt_service.segment_notes(times, smooth7))
    heavy = pitch_service.smooth_series(f0_raw, REF_SMOOTH_WINDOW)
    notes = _delta_segment(times, heavy)
    return _merge_fragments(notes)


def _match_note_sequences(ref_notes, user_notes):
    n = len(ref_notes)
    m = len(user_notes)
    if n == 0 or m == 0:
        return []
    INF = 1e18
    SKIP_USER = 800.0
    OCTAVE_MATCH_COST = 300.0
    dp = [[INF] * (m + 1) for _ in range(n + 1)]
    take = [[False] * (m + 1) for _ in range(n + 1)]
    skip_user = [[False] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        dp[i][0] = 0.0
    for j in range(1, m + 1):
        dp[0][j] = dp[0][j - 1] + SKIP_USER
        skip_user[0][j] = True
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            best = dp[i - 1][j]
            if dp[i][j - 1] + SKIP_USER < best:
                best = dp[i][j - 1] + SKIP_USER
                skip_user[i][j] = True
                take[i][j] = False
            err = abs(to_cents(user_notes[j - 1]["freq"]) - to_cents(ref_notes[i - 1]["freq"]))
            ok = err <= MATCH_ERR_LIMIT_CENTS or MATCH_OCTAVE_LOW <= err <= MATCH_OCTAVE_HIGH
            if ok:
                cost = OCTAVE_MATCH_COST if err >= MATCH_ERR_LIMIT_CENTS else err
                if dp[i - 1][j - 1] + cost < best:
                    best = dp[i - 1][j - 1] + cost
                    take[i][j] = True
                    skip_user[i][j] = False
            dp[i][j] = best
    pairs = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and take[i][j]:
            pairs.append((i - 1, j - 1))
            i -= 1
            j -= 1
        elif j > 0 and (i == 0 or skip_user[i][j]):
            j -= 1
        else:
            i -= 1
    pairs.reverse()
    return pairs


def compare_contours(s_times, s_f0, u_times, u_f0, start_off_ms=0.0):
    if not s_times or not u_times:
        return empty_result()
    s_smooth = pitch_service.smooth_series(s_f0, 7)
    u_smooth = pitch_service.smooth_series(u_f0, 7)
    path, dist = dtw_aligner.dtw(s_smooth, u_smooth)
    if not path:
        return empty_result()
    errs = []
    offs = []
    warp = {}
    for i, j in path:
        a = s_f0[i]
        b = u_f0[j]
        warp.setdefault(i, []).append(b)
        if a > 0 and b > 0:
            errs.append(abs(to_cents(b) - to_cents(a)))
            offs.append(abs(u_times[j] - s_times[i]))
    if not errs:
        return empty_result()
    mean_cents = round(sum(errs) / len(errs), 1)
    med_cents = round(sorted(errs)[len(errs) // 2], 1)
    mean_off = round(sum(offs) / len(offs), 3)

    ref_notes = _reference_notes(s_times, s_smooth, s_f0)
    user_notes = _filter_transition_notes(amt_service.segment_notes(u_times, u_smooth))

    ref_step = (s_times[1] - s_times[0]) if len(s_times) > 1 else 0.016
    ref_voiced_seconds = sum(1 for v in s_f0 if v > 0) * ref_step
    ref_covered = sum(
        max(0.0, min(rn["end"], s_times[-1]) - max(rn["start"], s_times[0])) for rn in ref_notes
    )
    if ref_voiced_seconds > 0.5:
        ref_poor = ref_covered / ref_voiced_seconds < 0.5
    else:
        ref_poor = len(ref_notes) == 0
    reference_quality = "poor" if ref_poor else "good"

    pairs_by_j = {}
    for i, j in path:
        pairs_by_j.setdefault(j, []).append(i)

    used_ref = set()
    matched = 0
    onset_errs = []
    weight_sum = 0.0
    weighted_err = 0.0
    mads = []
    vibrato_rates = []
    vibrato_count = 0
    notes_out = []

    seq_pairs = _match_note_sequences(ref_notes, user_notes)
    ref_of_user = {}
    for r_idx, u_idx in seq_pairs:
        ref_of_user[u_idx] = r_idx
        used_ref.add(r_idx)

    for u_idx, nt in enumerate(user_notes):
        r_idx = ref_of_user.get(u_idx, -1)
        js = [j for j, t in enumerate(u_times) if nt["start"] - 1e-6 <= t <= nt["end"] + 1e-6]
        ref_window = [s_times[i] for j in js for i in pairs_by_j.get(j, []) if s_f0[i] > 0]
        if r_idx < 0:
            notes_out.append({
                "midi": nt["midi"],
                "start": nt["start"],
                "end": nt["end"],
                "err_cents": 0.0,
                "verdict": VERDICT_TEXT["unclear"],
                "verdict_code": "unclear",
                "hint": "Bản mẫu không rõ nốt ở đoạn này" if ref_poor else "Nốt này không có trong bản mẫu",
                "hint_codes": ["ref_unclear_here"] if ref_poor else ["note_not_in_ref"],
                "onset_err_ms": 0.0,
                "ref_start": 0.0,
                "ref_end": 0.0,
                "vibrato": False,
            })
            continue
        rn = ref_notes[r_idx]
        matched += 1
        err = round(to_cents(nt["freq"]) - to_cents(rn["freq"]), 1)
        onset_ms = 0.0
        if ref_window:
            onset_ms = round((min(ref_window) - rn["start"]) * 1000.0, 1)
        onset_errs.append(abs(onset_ms))
        dur_ratio = (nt["end"] - nt["start"]) / max(1e-3, rn["end"] - rn["start"])
        stats = _note_stats(u_times, u_f0, nt)
        code = verdict_code(err)
        hint, hint_codes = _hint_for(err, onset_ms, dur_ratio, stats, True)
        notes_out.append({
            "midi": nt["midi"],
            "start": nt["start"],
            "end": nt["end"],
            "err_cents": err,
            "verdict": VERDICT_TEXT[code],
            "verdict_code": code,
            "hint": hint,
            "hint_codes": hint_codes,
            "onset_err_ms": onset_ms,
            "ref_start": round(min(ref_window), 3) if ref_window else 0.0,
            "ref_end": round(max(ref_window), 3) if ref_window else 0.0,
            "vibrato": bool(stats and stats["vibrato"]),
        })
        w = max(0.05, nt["end"] - nt["start"])
        weighted_err += w * abs(err)
        weight_sum += w
        if stats is not None:
            mads.append(stats["mad"])
            if stats["vibrato"]:
                vibrato_count += 1
                vibrato_rates.append(stats["rate"])

    n_user = len(user_notes)
    n_ref = len(ref_notes)
    unmatched = sum(1 for n in notes_out if n["verdict_code"] == "unclear")
    missing = 0 if ref_poor else max(0, n_ref - len(used_ref))

    if ref_poor:
        pitch_score = clamp_score(100 - mean_cents * PITCH_SLOPE_FRAME)
        rhythm_score = clamp_score(100 - (abs(start_off_ms) + mean_off * 1000) / 5)
    else:
        if weight_sum > 0:
            pitch_score = clamp_score(100 - (weighted_err / weight_sum) * PITCH_SLOPE_NOTE)
        else:
            pitch_score = clamp_score(100 - mean_cents * PITCH_SLOPE_FRAME)

        denom = max(1, max(n_user, n_ref))
        density = matched / denom
        if onset_errs and density >= DENSE_MATCH_RATIO:
            mean_onset = sum(onset_errs) / len(onset_errs)
            base = 100 - (abs(start_off_ms) + mean_onset) / RHYTHM_SLOPE_MS
        elif onset_errs:
            base = RHYTHM_NEUTRAL_BASE
        else:
            base = 100 - (abs(start_off_ms) + mean_off * 1000) / 5
        rhythm_score = clamp_score(base - UNMATCHED_PENALTY * (unmatched + missing) / denom)

    if mads:
        stability_score = clamp_score(100 - (sum(mads) / len(mads)) * STABILITY_SLOPE)
    else:
        stability_score = 100.0

    ornament = round(100.0 * vibrato_count / n_user, 1) if n_user else 0.0
    vibrato_rate = round(sum(vibrato_rates) / len(vibrato_rates), 2) if vibrato_rates else 0.0

    if ref_poor:
        score = clamp_score(pitch_score * WEIGHT_PITCH + rhythm_score * WEIGHT_RHYTHM + stability_score * WEIGHT_STABILITY)
    else:
        denom = max(1, max(n_user, n_ref))
        score = clamp_score(
            pitch_score * WEIGHT_PITCH + rhythm_score * WEIGHT_RHYTHM + stability_score * WEIGHT_STABILITY
            - SCORE_MISSING_PENALTY * (unmatched + missing) / denom
        )

    ok_count = sum(1 for n in notes_out if n["verdict_code"] == "ok")
    off_count = sum(1 for n in notes_out if n["verdict_code"] in ("off", "octave"))
    minor_count = sum(1 for n in notes_out if n["verdict_code"] == "minor")
    unclear_count = sum(1 for n in notes_out if n["verdict_code"] == "unclear")
    verdict_counts = {
        "ok": ok_count,
        "minor": minor_count,
        "off": off_count,
        "octave": sum(1 for n in notes_out if n["verdict_code"] == "octave"),
        "unclear": unclear_count,
    }
    summary_codes = []
    hint_bits = []
    if ref_poor:
        summary_codes.append("ref_poor")
        hint_bits.append("Bản mẫu không rõ từng nốt — chấm cao độ và đều giọng")
    if ok_count:
        summary_codes.append("ok_count")
        hint_bits.append(f"{ok_count} nốt chuẩn")
    if minor_count:
        summary_codes.append("minor_count")
        hint_bits.append(f"{minor_count} nốt lệch nhẹ")
    if off_count:
        summary_codes.append("off_count")
        hint_bits.append(f"{off_count} nốt lệch cao độ")
    if unclear_count:
        summary_codes.append("unclear_count")
        hint_bits.append(f"{unclear_count} nốt chưa khớp được")
    if missing:
        summary_codes.append("missing_count")
        hint_bits.append(f"thiếu {missing} nốt so với mẫu")
    summary_hint = ", ".join(hint_bits) if hint_bits else ""

    warped = []
    for i in range(len(s_times)):
        vs = [v for v in warp.get(i, []) if v > 0]
        warped.append(round(sum(vs) / len(vs), 1) if vs else 0.0)
    st, sf = downsample(s_times, s_f0)
    _, wf = downsample(s_times, warped)

    notes_out.sort(key=lambda n: n["start"])
    return {
        "metrics": {
            "reference_quality": reference_quality,
            "mean_abs_cents": mean_cents,
            "median_cents": med_cents,
            "mean_offset_ms": round(mean_off * 1000, 1),
            "start_offset_ms": round(start_off_ms, 1),
            "pairs": len(errs),
            "dtw_distance": dist,
            "pitch_score": pitch_score,
            "time_score": rhythm_score,
            "rhythm_score": rhythm_score,
            "stability_score": stability_score,
            "ornament": ornament,
            "matched_notes": matched,
            "unmatched_notes": unmatched,
            "missing_notes": missing,
            "vibrato_rate": vibrato_rate,
            "score": score,
            "summary_hint": summary_hint,
            "verdict_counts": verdict_counts,
            "summary_codes": summary_codes,
        },
        "sample": {"times": st, "f0": sf},
        "user_warped": {"times": st, "f0": wf},
        "notes": notes_out,
    }


def compare(sample_data, user_data, sample_key=None):
    state = _reference_state(sample_data, sample_key)
    u_samples, u_sr = pitch_service.read_mono_wav(user_data, max_seconds=MAX_COMPARE_SECONDS)
    u_samples, u_sr = pitch_service.resample_16k(u_samples, u_sr)
    u_times, u_f0 = pitch_service.estimate_f0(u_samples, u_sr, hop=256)
    if not state["has_frames"] or not u_times:
        raise ValueError("empty contour")
    if not state["valid"]:
        return empty_result()
    u_a, u_b = onset_trim(u_samples, u_sr)
    if u_b <= u_a:
        return empty_result()
    u_keep = [i for i, t in enumerate(u_times) if u_a - 0.001 <= t <= u_b + 0.001]
    if not u_keep:
        return empty_result()
    s_times = state["times"]
    s_f0 = state["f0"]
    u_times = [u_times[i] for i in u_keep]
    u_f0 = [u_f0[i] for i in u_keep]
    start_off = round(u_a - state["onset_a"], 3)
    return compare_contours(s_times, s_f0, u_times, u_f0, start_off_ms=start_off * 1000.0)
