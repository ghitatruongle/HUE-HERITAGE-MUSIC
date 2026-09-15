import argparse
import json
import wave
from pathlib import Path

try:
    import soundfile as sf
except Exception:
    sf = None


def scan_wav(path):
    if sf is not None:
        info = sf.info(str(path))
        return {"file": path.name, "seconds": round(info.duration, 2), "sr": info.samplerate, "channels": info.channels, "width": 0}
    with wave.open(str(path), "rb") as w:
        n = w.getnframes()
        sr = w.getframerate()
        ch = w.getnchannels()
        sw = w.getsampwidth()
    return {"file": path.name, "seconds": round(n / sr, 2), "sr": sr, "channels": ch, "width": sw}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    root = Path(args.dataset)
    if not root.is_dir():
        raise SystemExit("missing dataset dir")
    exts = {".wav", ".mp3", ".flac", ".m4a", ".ogg"}
    files = sorted([p for p in root.rglob("*") if p.suffix.lower() in exts and p.is_file()])
    items = []
    broken = []
    skipped = []
    for p in files:
        try:
            if p.suffix.lower() == ".wav":
                items.append(scan_wav(p))
            elif sf is not None:
                info = sf.info(str(p))
                items.append({"file": p.name, "seconds": round(info.duration, 2), "sr": info.samplerate, "channels": info.channels, "width": 0})
            else:
                skipped.append(p.name)
        except Exception:
            broken.append(p.name)
    meta = root / "metadata.json"
    report = {
        "dataset": str(root),
        "files": len(files),
        "wav_ok": len([i for i in items if i["seconds"] > 0]),
        "broken": broken,
        "skipped_no_decoder": skipped,
        "metadata": meta.exists(),
        "items": items,
    }
    out = Path(args.report)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"files": len(files), "broken": len(broken), "report": args.report}))


if __name__ == "__main__":
    main()
