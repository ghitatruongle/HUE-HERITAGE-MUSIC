import math

from ..audio_dsp import dtw_aligner
from . import pitch_service, amt_service

MAX_POINTS = 300


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


def verdict(err):
    a = abs(err)
    if a <= 20:
        return "Chuẩn"
    if a <= 50:
        return "Lệch nhẹ"
    return "Lệch"


def onset_trim(samples, sr):
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
            "mean_abs_cents": 0.0,
            "median_cents": 0.0,
            "mean_offset_ms": 0.0,
            "start_offset_ms": 0.0,
            "pairs": 0,
            "dtw_distance": 0.0,
            "pitch_score": 0.0,
            "time_score": 0.0,
            "score": 0.0,
        },
        "sample": {"times": [], "f0": []},
        "user_warped": {"times": [], "f0": []},
        "notes": [],
    }


def compare(sample_data, user_data):
    s_samples, s_sr = pitch_service.read_mono_wav(sample_data)
    u_samples, u_sr = pitch_service.read_mono_wav(user_data)
    s_times, s_f0 = pitch_service.estimate_f0(s_samples, s_sr, hop=256)
    u_times, u_f0 = pitch_service.estimate_f0(u_samples, u_sr, hop=256)
    if not s_times or not u_times:
        raise ValueError("empty contour")
    s_a, s_b = onset_trim(s_samples, s_sr)
    u_a, u_b = onset_trim(u_samples, u_sr)
    if s_b <= s_a or u_b <= u_a:
        return empty_result()
    s_keep = [i for i, t in enumerate(s_times) if s_a - 0.001 <= t <= s_b + 0.001]
    u_keep = [i for i, t in enumerate(u_times) if u_a - 0.001 <= t <= u_b + 0.001]
    if not s_keep or not u_keep:
        return empty_result()
    s_times = [s_times[i] for i in s_keep]
    s_f0 = [s_f0[i] for i in s_keep]
    u_times = [u_times[i] for i in u_keep]
    u_f0 = [u_f0[i] for i in u_keep]
    start_off = round(u_a - s_a, 3)
    path, dist = dtw_aligner.dtw(s_f0, u_f0, band_ratio=1.0)
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
    mean_cents = round(sum(errs) / len(errs), 1) if errs else 0.0
    med_cents = round(sorted(errs)[len(errs) // 2], 1) if errs else 0.0
    mean_off = round(sum(offs) / len(offs), 3) if offs else 0.0
    if not errs:
        return empty_result()
    pitch_score = clamp_score(100 - mean_cents * 1.5)
    time_score = clamp_score(100 - (abs(start_off) * 1000 + mean_off * 1000) / 5)
    score = round(pitch_score * 0.7 + time_score * 0.3, 1)
    warped = []
    for i in range(len(s_times)):
        vs = [v for v in warp.get(i, []) if v > 0]
        warped.append(round(sum(vs) / len(vs), 1) if vs else 0.0)
    st, sf = downsample(s_times, s_f0)
    _, wf = downsample(s_times, warped)
    notes = []
    for nt in amt_service.segment_notes(u_times, u_f0):
        js = {j for j, t in enumerate(u_times) if nt["start"] <= t <= nt["end"]}
        st_win = [s_times[i] for i, j in path if j in js and s_f0[i] > 0]
        if not st_win:
            notes.append({"midi": nt["midi"], "start": nt["start"], "end": nt["end"], "err_cents": 0.0, "verdict": "Không rõ"})
            continue
        s_seg = [s_f0[k] for k, t in enumerate(s_times) if min(st_win) <= t <= max(st_win) and s_f0[k] > 0]
        if not s_seg:
            notes.append({"midi": nt["midi"], "start": nt["start"], "end": nt["end"], "err_cents": 0.0, "verdict": "Không rõ"})
            continue
        s_med = sorted(s_seg)[len(s_seg) // 2]
        err = round(to_cents(nt["freq"]) - to_cents(s_med), 1)
        notes.append({"midi": nt["midi"], "start": nt["start"], "end": nt["end"], "err_cents": err, "verdict": verdict(err)})
    return {
        "metrics": {
            "mean_abs_cents": mean_cents,
            "median_cents": med_cents,
            "mean_offset_ms": round(mean_off * 1000, 1),
            "start_offset_ms": round(start_off * 1000, 1),
            "pairs": len(errs),
            "dtw_distance": dist,
            "pitch_score": pitch_score,
            "time_score": time_score,
            "score": score,
        },
        "sample": {"times": st, "f0": sf},
        "user_warped": {"times": st, "f0": wf},
        "notes": notes,
    }
