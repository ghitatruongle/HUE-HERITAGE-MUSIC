import argparse
import json
import time
from pathlib import Path


def need(mod):
    try:
        __import__(mod)
        return True
    except Exception:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--execute", action="store_true")
    args = ap.parse_args()
    cfg_path = Path(args.config).resolve()
    root = Path(__file__).resolve().parents[2]
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    errors = []
    for key in ("base_model", "dataset", "output"):
        if not str(cfg.get(key, "")).strip():
            errors.append(f"missing {key}")
    base = Path(cfg.get("base_model") or "missing")
    ds = Path(cfg.get("dataset") or "missing")
    out = Path(cfg.get("output") or "missing")
    if not base.is_absolute():
        base = root / base
    if not ds.is_absolute():
        ds = root / ds
    if not out.is_absolute():
        out = root / out
    if not errors and not ds.is_dir():
        errors.append("missing dataset")
    rank = cfg.get("rank")
    if isinstance(rank, bool) or not isinstance(rank, (int, float)) or rank <= 0:
        errors.append("bad rank")
    epochs = cfg.get("epochs")
    if isinstance(epochs, bool) or not isinstance(epochs, (int, float)) or epochs <= 0:
        errors.append("bad epochs")
    deps = {"torch": need("torch"), "peft": need("peft"), "diffusers": need("diffusers")}
    plan = {
        "base_model": str(base),
        "dataset": str(ds),
        "output": str(out),
        "rank": rank,
        "alpha": cfg.get("alpha"),
        "lr": cfg.get("lr"),
        "epochs": epochs,
        "errors": errors,
        "deps": deps,
        "time": time.time(),
    }
    print(json.dumps(plan, indent=2))
    if errors:
        raise SystemExit("invalid plan")
    if not args.execute:
        print("dry run only")
        return
    if not all(deps.values()):
        raise SystemExit("missing deps")
    if not base.exists():
        raise SystemExit("missing base weights")
    out.mkdir(parents=True, exist_ok=True)
    (out / "run.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")
    raise SystemExit("mac wiring pending")


if __name__ == "__main__":
    main()
