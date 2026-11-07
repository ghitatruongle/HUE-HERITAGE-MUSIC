import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import settings
from app.services import compare_service, pitch_service

ONSET_TOL_MS = 50.0


def load_labels(labels_path):
    with open(labels_path, "r", encoding="utf-8") as f:
        raw = json.load(f)
    out = {}
    for k, v in raw.items():
        out[k] = [{"start": float(n["start"]), "end": float(n["end"])} for n in v]
    return out


def segment_wav(wav_bytes):
    samples, sr = pitch_service.read_mono_wav(wav_bytes, max_seconds=None)
    samples, sr = pitch_service.resample_16k(samples, sr)
    times, f0 = pitch_service.estimate_f0(samples, sr, hop=256)
    if not times:
        return [], [], f0
    smooth = pitch_service.smooth_series(f0, 7)
    notes = compare_service._reference_notes(times, smooth, f0)
    voiced = [t for t, v in zip(times, f0) if v > 0]
    span = (voiced[0], voiced[-1]) if voiced else (0.0, 0.0)
    return notes, span, f0


def onset_pr(pred, gt, onset_tol=ONSET_TOL_MS):
    pred_starts = sorted(n["start"] for n in pred)
    gt_starts = sorted(n["start"] for n in gt)
    matched = 0
    used = set()
    for g in gt_starts:
        for i, p in enumerate(pred_starts):
            if i in used:
                continue
            if abs(p - g) <= onset_tol / 1000.0:
                matched += 1
                used.add(i)
                break
    precision = matched / len(pred_starts) if pred_starts else 0.0
    recall = matched / len(gt_starts) if gt_starts else 0.0
    return precision, recall, matched, len(pred_starts), len(gt_starts)


def coverage(notes, span):
    if span[1] <= span[0]:
        return 0.0
    covered = sum(max(0.0, min(n["end"], span[1]) - max(n["start"], span[0])) for n in notes)
    return covered / (span[1] - span[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="thu muc chua file .wav + labels.json (hand-label)")
    ap.add_argument("--onset-tol-ms", type=float, default=ONSET_TOL_MS)
    args = ap.parse_args()

    d = Path(args.dir)
    labels = load_labels(d / "labels.json")
    total_p = []
    total_r = []
    total_cov = []
    rows = []
    for name, gt in sorted(labels.items()):
        wav_path = d / name
        if not wav_path.exists():
            rows.append((name, None, None, None, "MISSING WAV"))
            continue
        wav_bytes = wav_path.read_bytes()
        notes, span, _ = segment_wav(wav_bytes)
        p, r, m, np_, ng = onset_pr(notes, gt, args.onset_tol_ms)
        cov = coverage(notes, span)
        total_p.append(p)
        total_r.append(r)
        total_cov.append(cov)
        rows.append((name, round(p, 3), round(r, 3), round(cov, 3), f"pred={np_} gt={ng} matched={m}"))

    mode = settings.reference_segmentation
    print(f"REFERENCE_SEGMENTATION={mode}  onset_tol={args.onset_tol_ms}ms")
    for name, p, r, c, extra in rows:
        if p is None:
            print(f"  {name}: {extra}")
        else:
            print(f"  {name}: P={p} R={r} coverage={c} ({extra})")
    if not total_p:
        print("KHONG CO FILE NAO DUOC DO — kiem tra labels.json + file wav")
        sys.exit(1)
    n = len(total_p)
    print(f"OVERALL: P={sum(total_p)/n:.3f} R={sum(total_r)/n:.3f} coverage={sum(total_cov)/n:.3f} over {n} file")
    clean_ok = sum(total_r) / n >= 0.9
    print(f"ACCEPTANCE R>=0.90: {'PASS' if clean_ok else 'FAIL'}")
    sys.exit(0 if clean_ok else 1)


if __name__ == "__main__":
    main()
