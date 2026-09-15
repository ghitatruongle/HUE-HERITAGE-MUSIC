import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "server"))

from app.services import pitch_service, amt_service, amt_eval
from app.ai import basic_pitch_amt as bp_amt
from app.audio_dsp import post_quantizer


def run_engine(engine, data, bpm):
    samples, sr = pitch_service.read_mono_wav(data)
    engine_error = None
    if engine == "basic_pitch" and bp_amt.available():
        try:
            notes = bp_amt.transcribe(samples, sr)
            used = "basic_pitch"
        except Exception as e:
            notes = None
            engine_error = str(e)
    else:
        notes = None
        if engine == "basic_pitch":
            engine_error = "basic_pitch unavailable"
    if notes is None:
        times, f0s = pitch_service.estimate_f0(samples, sr)
        notes = amt_service.segment_notes(times, f0s)
        used = "dsp"
    notes = post_quantizer.quantize(notes, bpm)
    pred = [{"midi": n["midi"], "start": n["start"], "end": n["end"]} for n in notes]
    return pred, used, engine_error


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", required=True)
    ap.add_argument("--truth", required=True)
    ap.add_argument("--bpm", type=float, default=60.0)
    ap.add_argument("--engine", default="basic_pitch", choices=["basic_pitch", "dsp"])
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    items = json.loads(Path(args.truth).read_text(encoding="utf-8"))
    if not amt_eval.valid_truth(items):
        raise SystemExit("bad truth")
    data = Path(args.audio).read_bytes()
    pred, used, engine_error = run_engine(args.engine, data, args.bpm)
    grid = 60.0 / args.bpm / 4.0 if args.bpm > 0 else 0.0
    if grid > amt_eval.ONSET_TOL:
        print(json.dumps({"warning": "quantize grid %.3fs > onset tolerance %.3fs" % (grid, amt_eval.ONSET_TOL)}))
    report = amt_eval.evaluate(pred, items)
    report["audio"] = str(args.audio)
    report["bpm"] = args.bpm
    report["engine_requested"] = args.engine
    report["engine_used"] = used
    if engine_error:
        report["engine_error"] = engine_error
    report["timestamp"] = time.strftime("%Y-%m-%d %H:%M:%S")
    report["config"] = {"onset_tol": amt_eval.ONSET_TOL, "offset_ratio": amt_eval.OFFSET_RATIO, "offset_min": amt_eval.OFFSET_MIN}
    out = Path(args.report)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
