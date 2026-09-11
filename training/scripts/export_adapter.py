import argparse
import shutil
from pathlib import Path

WEIGHTS = "adapter_model.safetensors"
CONFIG = "adapter_config.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--dst", required=True)
    args = ap.parse_args()
    src = Path(args.src)
    dst = Path(args.dst)
    if not (src / WEIGHTS).exists():
        raise SystemExit("no adapter found")
    if not (src / CONFIG).exists():
        raise SystemExit("missing adapter_config.json")
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / WEIGHTS, dst / WEIGHTS)
    shutil.copy2(src / CONFIG, dst / CONFIG)
    print(str(dst / WEIGHTS))


if __name__ == "__main__":
    main()
