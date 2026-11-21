import argparse
import csv
import datetime
import glob
import json
import math
import os
import re
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["font.sans-serif"] = ["Helvetica Neue", "Arial", "DejaVu Sans"]

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_LOG_CANDIDATES = [
    os.path.join(BASE_DIR, "training", "reports", "dot2_v2", "dot2.3", "logs"),
    os.path.join(BASE_DIR, "training", "logs", "dot2_v2", "dot2.3"),
    os.path.expanduser("~/ACE-Step-1.5/outputs/lokr_output_dot2_3_v2/logs"),
]
EPOCH_DIR = re.compile(r"^epoch(\d+)$")
MODEL_EPOCH = re.compile(r"ep(?:och)?(\d+)(_ema)?$")
SCORE_KEYS = [
    ("cer_pct", "vocal", "min"),
    ("wer_pct", "vocal", "min"),
    ("hnr_db", "vocal", "max"),
    ("vocal_to_mix_db", "vocal", None),
    ("vocal_active_pct", "vocal", None),
    ("chroma_cosine_vs_ref", "dsp", "max"),
    ("crest_db", "dsp", None),
    ("cross_seed_min", "dsp", "max"),
    ("listening_score", "listening", "max"),
]
CK_FIELDS = [
    "epoch", "loss_epoch", "ema", "learning_rate", "batch_size", "grad_accum", "max_epochs",
    "timestep_mode", "cfg_ratio", "compute_dtype", "fabric_precision", "parent_checkpoint",
    "parent_keys_matched", "preprocess_context", "num_samples", "lokr_dim", "lokr_alpha",
    "weight_decompose", "path",
]


def find_event_file(paths):
    files = []
    for path in paths:
        if not path:
            continue
        if os.path.isfile(path):
            files.append(path)
        elif os.path.isdir(path):
            files.extend(glob.glob(os.path.join(path, "**", "events.out.tfevents*"), recursive=True))
    return max(files, key=os.path.getmtime) if files else None


def load_scalars(event_file):
    from tensorboard.backend.event_processing.event_accumulator import EventAccumulator

    acc = EventAccumulator(event_file, size_guidance={"scalars": 0})
    acc.Reload()
    tags = set(acc.Tags().get("scalars", []))
    return {tag: acc.Scalars(tag) for tag in ("train/epoch_loss", "train/loss", "train/lr") if tag in tags}


def read_checkpoint_metadata(weights_path):
    from safetensors import safe_open

    with safe_open(weights_path, "pt") as handle:
        meta = handle.metadata() or {}
    parsed = {}
    for key in ("lokr_config", "run_metadata"):
        raw = meta.get(key)
        if raw:
            try:
                parsed[key] = json.loads(raw)
            except ValueError:
                parsed[key] = {}
    return parsed


def scan_checkpoints(models_dir):
    rows = []
    if not models_dir or not os.path.isdir(models_dir):
        return rows
    for name in os.listdir(models_dir):
        match = EPOCH_DIR.match(name)
        if not match:
            continue
        folder = os.path.join(models_dir, name)
        weights = os.path.join(folder, "lokr_weights.safetensors")
        if not os.path.isfile(weights):
            continue
        meta = read_checkpoint_metadata(weights)
        run = meta.get("run_metadata") or {}
        cfg = run.get("training_config") or {}
        lokr = meta.get("lokr_config") or {}
        rows.append({
            "epoch": int(match.group(1)),
            "path": folder,
            "ema": os.path.isfile(os.path.join(folder, "lokr_weights_ema.safetensors")),
            "learning_rate": cfg.get("learning_rate"),
            "batch_size": cfg.get("batch_size"),
            "grad_accum": cfg.get("gradient_accumulation_steps"),
            "max_epochs": cfg.get("max_epochs"),
            "timestep_mode": run.get("timestep_mode", "discrete (legacy)"),
            "cfg_ratio": run.get("cfg_ratio", 0.0),
            "compute_dtype": run.get("compute_dtype", "unknown"),
            "fabric_precision": run.get("fabric_precision", ""),
            "parent_checkpoint": run.get("parent_checkpoint", ""),
            "parent_keys_matched": run.get("parent_keys_matched", ""),
            "preprocess_context": run.get("preprocess_context", "unknown (legacy)"),
            "num_samples": run.get("num_samples"),
            "lokr_dim": lokr.get("linear_dim"),
            "lokr_alpha": lokr.get("linear_alpha"),
            "weight_decompose": lokr.get("weight_decompose"),
        })
    return sorted(rows, key=lambda r: r["epoch"])


def model_epoch(name):
    match = MODEL_EPOCH.search(str(name or ""))
    if not match:
        return None, False
    return int(match.group(1)), bool(match.group(2))


def load_json(path):
    if not path:
        return None
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, dict):
        return data.get("files", [])
    return data if isinstance(data, list) else []


def aggregate_by_model(rows, keys):
    groups = {}
    for row in rows or []:
        model = row.get("model")
        if not model or model == "reference":
            continue
        groups.setdefault(model, []).append(row)
    out = {}
    for model, items in groups.items():
        entry = {}
        for key in keys:
            values = [r[key] for r in items if isinstance(r.get(key), (int, float)) and math.isfinite(r[key])]
            if values:
                entry[key] = round(float(min(values) if key == "cross_seed_min" else np.mean(values)), 3)
        out[model] = entry
    return out


def load_listening(path):
    if not path:
        return {}
    out = {}
    with open(path, "r", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            model = (row.get("model") or "").strip()
            try:
                score = float(row.get("score", ""))
            except (TypeError, ValueError):
                continue
            if model:
                out[model] = {"listening_score": score, "listening_note": row.get("note", "")}
    return out


def build_scoreboard(vocal_rows, dsp_rows, listening):
    merged = {}
    for rows, src in ((vocal_rows, "vocal"), (dsp_rows, "dsp")):
        keys = [k for k, s, _ in SCORE_KEYS if s == src]
        for model, entry in aggregate_by_model(rows, keys).items():
            merged.setdefault(model, {}).update(entry)
    for model, entry in listening.items():
        merged.setdefault(model, {}).update(entry)
    for key, _, direction in SCORE_KEYS:
        if direction is None:
            continue
        candidates = [(m, e[key]) for m, e in merged.items() if isinstance(e.get(key), (int, float)) and m != "none"]
        for rank, (model, _) in enumerate(sorted(candidates, key=lambda x: x[1], reverse=(direction == "max")), 1):
            merged[model][f"rank_{key}"] = rank
    for model, entry in merged.items():
        ranks = [v for k, v in entry.items() if k.startswith("rank_")]
        entry["rank_mean"] = round(float(np.mean(ranks)), 2) if ranks else None
        entry["epoch"], entry["ema"] = model_epoch(model)
    return merged


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def fmt_time(ts):
    return datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def plot_epoch_loss(epoch_events, checkpoints, out_png, window):
    xs = np.array([e.step for e in epoch_events])
    ys = np.array([e.value for e in epoch_events])
    plt.figure(figsize=(14, 7), dpi=200)
    plt.plot(xs, ys, color="#a8dadc", linewidth=1.3, label="Loss từng epoch (Đợt 2.3)")
    if len(ys) >= window > 1:
        plt.plot(xs[window - 1:], np.convolve(ys, np.ones(window) / window, mode="valid"),
                 color="#1d3557", linewidth=2.4, label=f"Trung bình trượt ({window} epoch)")
    by_epoch = dict(zip(xs.tolist(), ys.tolist()))
    ck = [(c["epoch"], by_epoch[c["epoch"]]) for c in checkpoints if c["epoch"] in by_epoch]
    if ck:
        plt.scatter([e for e, _ in ck], [v for _, v in ck], color="#e63946", s=55, zorder=5, label="Checkpoint đã lưu")
    i_min = int(np.argmin(ys))
    span = float(ys.max() - ys.min()) or abs(float(ys[i_min])) or 1.0
    plt.annotate(f"Thấp nhất: epoch {xs[i_min]} = {ys[i_min]:.4f}", xy=(xs[i_min], ys[i_min]),
                 xytext=(xs[i_min], ys[i_min] + span * 0.15),
                 arrowprops=dict(arrowstyle="->", color="#e63946"), color="#780000", fontsize=10, fontweight="bold")
    plt.title("Biểu đồ 1 — Loss huấn luyện LoKr Đợt 2.3 (Ca Huế có hát)", fontsize=14, pad=12)
    plt.xlabel("Epoch")
    plt.ylabel("Loss (Flow Matching MSE)")
    plt.grid(True, linestyle="--", alpha=0.4)
    plt.legend(frameon=True, facecolor="white", edgecolor="#ddd")
    plt.tight_layout()
    plt.savefig(out_png)
    plt.close()


def plot_step_lr(loss_events, lr_events, lr_meta, out_png):
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6), dpi=200)
    ax1.plot([e.step for e in loss_events], [e.value for e in loss_events], color="#1d3557", linewidth=1.2)
    ax1.set_title("Loss theo bước tối ưu")
    ax1.set_xlabel("Global step")
    ax1.set_ylabel("Loss")
    ax1.grid(True, linestyle="--", alpha=0.4)
    if lr_events:
        ax2.plot([e.step for e in lr_events], [e.value for e in lr_events], color="#e63946", linewidth=1.4)
    ax2.set_title(f"Learning rate thực tế (LR cấu hình trong checkpoint: {lr_meta})")
    ax2.set_xlabel("Global step")
    ax2.set_ylabel("LR")
    ax2.grid(True, linestyle="--", alpha=0.4)
    fig.suptitle("Biểu đồ 2 — Bước tối ưu & lộ trình LR (Đợt 2.3)", fontsize=14)
    plt.tight_layout()
    plt.savefig(out_png)
    plt.close()


def plot_scoreboard(board, out_png):
    models = sorted(board, key=lambda m: (board[m].get("epoch") is None, board[m].get("epoch") or 0, bool(board[m].get("ema")), m))
    metrics = [
        ("cer_pct", "CER (%) — thấp là tốt"),
        ("hnr_db", "HNR giọng (dB) — cao là tốt"),
        ("chroma_cosine_vs_ref", "Chroma so với bản gốc (%) — cao là tốt"),
        ("cross_seed_min", "Cross-seed thấp nhất (%) — cao là tốt"),
        ("listening_score", "Điểm nghe thử — cao là tốt"),
    ]
    metrics = [(k, t) for k, t in metrics if any(isinstance(board[m].get(k), (int, float)) for m in models)]
    if not metrics:
        return False
    fig, axes = plt.subplots(len(metrics), 1, figsize=(14, 3.2 * len(metrics)), dpi=200, squeeze=False)
    for ax, (key, title) in zip(axes[:, 0], metrics):
        present = [isinstance(board[m].get(key), (int, float)) for m in models]
        values = [float(board[m][key]) if ok else 0.0 for m, ok in zip(models, present)]
        bars = ax.bar(models, values, color=["#adb5bd" if m == "none" else "#457b9d" for m in models])
        for bar, val, ok in zip(bars, values, present):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{val:.2f}" if ok else "n/a", ha="center", va="bottom", fontsize=8)
        ax.set_title(title, fontsize=11)
        ax.grid(axis="y", linestyle="--", alpha=0.4)
        ax.tick_params(axis="x", rotation=45, labelsize=8)
    fig.suptitle("Biểu đồ 3 — Bảng chấm điểm checkpoint Đợt 2.3", fontsize=14)
    plt.tight_layout()
    plt.savefig(out_png)
    plt.close()
    return True


def collect_warnings(checkpoints):
    warnings = []
    for c in checkpoints:
        if c["preprocess_context"] != "silence":
            warnings.append(f"epoch{c['epoch']}: preprocess_context={c['preprocess_context']} (nguy cơ rò rỉ context)")
        if c["compute_dtype"] not in ("bfloat16", "float32"):
            warnings.append(f"epoch{c['epoch']}: compute_dtype={c['compute_dtype']}")
        matched = str(c.get("parent_keys_matched") or "")
        if c.get("parent_checkpoint") and "/" in matched and matched.split("/")[0] != matched.split("/")[1]:
            warnings.append(f"epoch{c['epoch']}: parent keys {matched}")
    return warnings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs", nargs="*", default=None)
    ap.add_argument("--models_dir", default=os.path.join(BASE_DIR, "models", "dot2_v2", "dot2.3"))
    ap.add_argument("--vocal_json", default=None)
    ap.add_argument("--dsp_json", default=None)
    ap.add_argument("--listening_csv", default=None)
    ap.add_argument("--out", default=os.path.join(BASE_DIR, "training", "reports", "dot2_v2", "dot2.3"))
    ap.add_argument("--window", type=int, default=5)
    ap.add_argument("--title", default="ĐỢT 2.3 Ca Huế có hát — LoKr (LyCORIS, DoRA)")
    args = ap.parse_args()

    checkpoints = scan_checkpoints(args.models_dir)
    event_file = find_event_file(args.logs if args.logs else DEFAULT_LOG_CANDIDATES)
    scalars = load_scalars(event_file) if event_file else {}
    epoch_events = scalars.get("train/epoch_loss", [])
    loss_events = scalars.get("train/loss", [])
    lr_events = scalars.get("train/lr", [])
    vocal_rows = load_json(args.vocal_json)
    dsp_rows = load_json(args.dsp_json)
    listening = load_listening(args.listening_csv)
    if not checkpoints and not epoch_events and not loss_events and not (vocal_rows or dsp_rows or listening):
        print("[ERROR] Nothing to report: no checkpoints, no tfevents and no evaluation inputs")
        sys.exit(1)

    csv_dir = os.path.join(args.out, "csv")
    chart_dir = os.path.join(args.out, "bieu_do")
    os.makedirs(csv_dir, exist_ok=True)
    os.makedirs(chart_dir, exist_ok=True)
    outputs = []

    epoch_loss = {e.step: e.value for e in epoch_events}
    if epoch_events:
        t0 = epoch_events[0].wall_time
        path = os.path.join(csv_dir, "dot2_3_epoch_loss.csv")
        write_csv(path, ["epoch", "loss", "thoi_gian", "giay_tu_khi_bat_dau"],
                  [[e.step, f"{e.value:.6f}", fmt_time(e.wall_time), int(e.wall_time - t0)] for e in epoch_events])
        outputs.append(path)
        png = os.path.join(chart_dir, "bieu_do_1_loss_theo_epoch.png")
        plot_epoch_loss(epoch_events, checkpoints, png, args.window)
        outputs.append(png)
    if loss_events:
        lr_by_step = {e.step: e.value for e in lr_events}
        path = os.path.join(csv_dir, "dot2_3_step_loss_lr.csv")
        write_csv(path, ["global_step", "loss", "learning_rate", "thoi_gian"],
                  [[e.step, f"{e.value:.6f}", f"{lr_by_step[e.step]:.6g}" if e.step in lr_by_step else "", fmt_time(e.wall_time)]
                   for e in loss_events])
        outputs.append(path)
        png = os.path.join(chart_dir, "bieu_do_2_buoc_toi_uu_lr.png")
        plot_step_lr(loss_events, lr_events, checkpoints[-1]["learning_rate"] if checkpoints else "n/a", png)
        outputs.append(png)

    for c in checkpoints:
        c["loss_epoch"] = round(epoch_loss[c["epoch"]], 6) if c["epoch"] in epoch_loss else ""
    if checkpoints:
        path = os.path.join(csv_dir, "dot2_3_checkpoints.csv")
        write_csv(path, CK_FIELDS, [[c.get(k, "") for k in CK_FIELDS] for c in checkpoints])
        outputs.append(path)

    board = build_scoreboard(vocal_rows, dsp_rows, listening)
    if board:
        keys = ["epoch", "ema"] + [k for k, _, _ in SCORE_KEYS] + ["listening_note"]
        keys += [f"rank_{k}" for k, _, d in SCORE_KEYS if d] + ["rank_mean"]
        ordered = sorted(board, key=lambda m: (board[m].get("rank_mean") is None, board[m].get("rank_mean") or 0, m))
        path = os.path.join(csv_dir, "dot2_3_bang_cham_diem.csv")
        write_csv(path, ["model"] + keys, [[m] + [board[m].get(k, "") for k in keys] for m in ordered])
        outputs.append(path)
        png = os.path.join(chart_dir, "bieu_do_3_bang_cham_diem.png")
        if plot_scoreboard(board, png):
            outputs.append(png)

    warnings = collect_warnings(checkpoints)
    min_ev = min(epoch_events, key=lambda e: e.value) if epoch_events else None
    summary = {
        "dot": args.title,
        "nguon_tfevents": event_file or "",
        "bat_dau": fmt_time(epoch_events[0].wall_time) if epoch_events else "",
        "ket_thuc": fmt_time(epoch_events[-1].wall_time) if epoch_events else "",
        "tong_thoi_gian_gio": round((epoch_events[-1].wall_time - epoch_events[0].wall_time) / 3600, 2) if len(epoch_events) > 1 else None,
        "epochs_da_log": len(epoch_events),
        "tong_buoc": len(loss_events),
        "loss_khoi_diem": round(epoch_events[0].value, 4) if epoch_events else None,
        "loss_thap_nhat": {"epoch": min_ev.step, "loss": round(min_ev.value, 4)} if min_ev else None,
        "loss_ket_thuc": round(epoch_events[-1].value, 4) if epoch_events else None,
        "thong_so_that_tu_checkpoint": {k: checkpoints[-1].get(k) for k in CK_FIELDS if k not in ("path", "loss_epoch", "epoch")} if checkpoints else {},
        "checkpoints": [{"epoch": c["epoch"], "loss": c["loss_epoch"], "ema": c["ema"]} for c in checkpoints],
        "bang_cham_diem": board,
        "canh_bao": warnings,
    }
    path = os.path.join(csv_dir, "dot2_3_tom_tat.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
    outputs.append(path)

    for w in warnings:
        print(f"[WARN] {w}")
    for o in outputs:
        print(f"[SAVED] {o}")


if __name__ == "__main__":
    main()
