import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "server"))

from app.services import pitch_service, amt_service, amt_eval
from app.audio_dsp import post_quantizer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", required=True)
    ap.add_argument("--truth", required=True)
    ap.add_argument("--bpm", type=float, default=60.0)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    items = json.loads(Path(args.truth).read_text(encoding="utf-8"))
    if not amt_eval.valid_truth(items):
        raise SystemExit("bad truth")
    data = Path(args.audio).read_bytes()
    samples, sr = pitch_service.read_mono_wav(data)
    times, f0s = pitch_service.estimate_f0(samples, sr)
    notes = post_quantizer.quantize(amt_service.segment_notes(times, f0s), args.bpm)
    pred = [{"midi": n["midi"], "start": n["start"], "end": n["end"]} for n in notes]
    grid = 60.0 / args.bpm / 4.0 if args.bpm > 0 else 0.0
    if grid > amt_eval.ONSET_TOL:
        print(json.dumps({"warning": "quantize grid %.3fs > onset tolerance %.3fs" % (grid, amt_eval.ONSET_TOL)}))
    report = amt_eval.evaluate(pred, items)
    report["audio"] = str(args.audio)
    report["bpm"] = args.bpm
    Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
