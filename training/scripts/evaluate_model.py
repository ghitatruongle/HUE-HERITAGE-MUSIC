import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()
    root = Path(args.adapter)
    w = root / "adapter_model.safetensors"
    c = root / "adapter_config.json"
    size = w.stat().st_size if w.exists() else 0
    ready = w.exists() and c.exists() and size > 0
    report = {
        "adapter": str(args.adapter),
        "ready": ready,
        "size": size,
    }
    Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
