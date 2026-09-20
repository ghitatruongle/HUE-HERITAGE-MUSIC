import os
import json
import csv
import datetime
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from tensorboard.backend.event_processing.event_accumulator import EventAccumulator

plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["font.sans-serif"] = ["Helvetica Neue", "Arial", "DejaVu Sans"]

os.makedirs("training/reports/dot2-old/dot2.1/csv", exist_ok=True)
os.makedirs("training/reports/dot2-old/dot2.1/bieu_do", exist_ok=True)

v0_dir = "training/logs/dot2-old/dot2.1/version_0"
v1_dir = "training/logs/dot2-old/dot2.1/version_1"

ea0 = EventAccumulator(v0_dir)
ea0.Reload()

ea1 = EventAccumulator(v1_dir)
ea1.Reload()

v1_epoch_events = ea1.Scalars("train/epoch_loss")
v1_step_loss_events = ea1.Scalars("train/loss")
v1_step_lr_events = ea1.Scalars("train/lr")

t0 = v1_epoch_events[0].wall_time

epoch_csv_path = "training/reports/dot2-old/dot2.1/csv/dot2_1_epoch_loss.csv"
with open(epoch_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["epoch", "loss", "thoi_gian", "giay_tu_khi_bat_dau"])
    for e in v1_epoch_events:
        dt_str = datetime.datetime.fromtimestamp(e.wall_time).strftime("%Y-%m-%d %H:%M:%S")
        elapsed = int(e.wall_time - t0)
        writer.writerow([e.step, f"{e.value:.6f}", dt_str, elapsed])

step_csv_path = "training/reports/dot2-old/dot2.1/csv/dot2_1_step_loss_lr.csv"
with open(step_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["global_step", "loss", "learning_rate", "thoi_gian"])
    for l_ev, lr_ev in zip(v1_step_loss_events, v1_step_lr_events):
        dt_str = datetime.datetime.fromtimestamp(l_ev.wall_time).strftime("%Y-%m-%d %H:%M:%S")
        writer.writerow([l_ev.step, f"{l_ev.value:.6f}", f"{lr_ev.value:.6f}", dt_str])

checkpoints_data = []
for ep in range(10, 160, 10):
    match = [x for x in v1_epoch_events if x.step == ep]
    if match:
        val = match[0].value
        note = ""
        if ep == 110:
            note = "THẤP NHẤT"
        elif ep == 150:
            note = "final"
        checkpoints_data.append((ep, val, note))

ckpt_csv_path = "training/reports/dot2-old/dot2.1/csv/dot2_1_checkpoints.csv"
with open(ckpt_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["epoch", "loss_trung_binh", "ghi_chu"])
    for ep, val, note in checkpoints_data:
        writer.writerow([ep, f"{val:.4f}", note])

v0_csv_path = "training/reports/dot2-old/dot2.1/csv/dot2_1_version_0_oom.csv"
with open(v0_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["epoch", "loss", "thoi_gian", "ghi_chu"])
    if ea0.Scalars("train/epoch_loss"):
        e0 = ea0.Scalars("train/epoch_loss")[0]
        dt0_str = datetime.datetime.fromtimestamp(e0.wall_time).strftime("%Y-%m-%d %H:%M:%S")
        writer.writerow([e0.step, f"{e0.value:.6f}", dt0_str, "Gãy ở Epoch 2 do tràn bộ nhớ trần MPS (mặc định 70% ~30GB) trước khi vá PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0"])

min_ep_ev = min(v1_epoch_events, key=lambda x: x.value)
summary_data = {
    "dot": "ĐỢT 2.1 Solo Nhạc cụ (Đàn Nguyệt & Kèn) — LoKr (LyCORIS, DoRA)",
    "model_goc": "acestep-v15-base (2B DiT sạch)",
    "thiet_bi": "Mac mini M4, 24GB unified memory (MPS)",
    "bat_dau": datetime.datetime.fromtimestamp(t0).strftime("%Y-%m-%d %H:%M:%S"),
    "ket_thuc": datetime.datetime.fromtimestamp(v1_epoch_events[-1].wall_time).strftime("%Y-%m-%d %H:%M:%S"),
    "tong_thoi_gian_gio": round((v1_epoch_events[-1].wall_time - t0) / 3600, 2),
    "tong_buoc": len(v1_epoch_events) * 2,
    "epochs": len(v1_epoch_events),
    "loss_khoi_diem": round(v1_epoch_events[0].value, 4),
    "loss_thap_nhat_theo_epoch": {
        "epoch": min_ep_ev.step,
        "loss": round(min_ep_ev.value, 4)
    },
    "loss_ket_thuc": round(v1_epoch_events[-1].value, 4),
    "checkpoints": [{"epoch": ep, "loss": round(val, 4)} for ep, val, _ in checkpoints_data],
    "ghi_chu": "version_0 gãy ở epoch 2 do MPS out of memory (trần watermark 70%); version_1 áp dụng PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0 và torch.mps.empty_cache(), hoàn thành trọn vẹn 150/150 epochs không lỗi."
}

with open("training/reports/dot2-old/dot2.1/csv/dot2_1_tom_tat.json", "w", encoding="utf-8") as f:
    json.dump(summary_data, f, ensure_ascii=False, indent=2)

epochs_x = np.array([e.step for e in v1_epoch_events])
loss_y = np.array([e.value for e in v1_epoch_events])

window = 15
rolling_mean = np.convolve(loss_y, np.ones(window)/window, mode="valid")
rolling_x = epochs_x[window - 1:]

ckpt_x = np.array([ep for ep, _, _ in checkpoints_data])
ckpt_y = np.array([val for _, val, _ in checkpoints_data])

plt.figure(figsize=(14, 7), dpi=300)
plt.plot(epochs_x, loss_y, color="#90b4ce", alpha=0.6, linewidth=1.2, label="Loss từng epoch")
plt.plot(rolling_x, rolling_mean, color="#1d3557", linewidth=2.4, label=f"Trung bình trượt ({window} epoch)")
plt.scatter(ckpt_x, ckpt_y, color="#c1121f", s=55, zorder=5, label="Checkpoint lưu mỗi 10 epoch")

ep110_val = [val for ep, val, _ in checkpoints_data if ep == 110][0]
plt.annotate(
    f"Epoch 110 — loss thấp nhất\ntrong các checkpoint: {ep110_val:.4f}",
    xy=(110, ep110_val),
    xytext=(90, ep110_val - 0.025),
    arrowprops=dict(facecolor="#c1121f", edgecolor="#c1121f", arrowstyle="->", lw=1.5),
    color="#780000",
    fontsize=11,
    fontweight="bold"
)

ep150_val = [val for ep, val, _ in checkpoints_data if ep == 150][0]
plt.annotate(
    f"Epoch 150 (final): {ep150_val:.4f}",
    xy=(150, ep150_val),
    xytext=(125, ep150_val + 0.02),
    arrowprops=dict(facecolor="#1d3557", edgecolor="#1d3557", arrowstyle="->", lw=1.5),
    color="#1d3557",
    fontsize=10,
    fontweight="bold"
)

plt.title("Biểu đồ 1 — Loss huấn luyện LoKr Đợt 2.1 (Solo Nhạc cụ: Đàn Nguyệt & Kèn), 150 epochs trong 5h53p", fontsize=14, pad=15)
plt.xlabel("Epoch", fontsize=12)
plt.ylabel("Loss", fontsize=12)
plt.grid(True, linestyle="--", alpha=0.4)
plt.legend(frameon=True, facecolor="white", edgecolor="#ddd", fontsize=11)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.1/bieu_do/bieu_do_1_loss_theo_epoch.png")
plt.close()

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6), dpi=300)

step_x = np.array([e.step for e in v1_step_loss_events])
step_y = np.array([e.value for e in v1_step_loss_events])
ax1.plot(step_x, step_y, marker="o", markersize=4, color="#1d3557", linewidth=1.5)
ax1.set_title("Loss theo từng bước tối ưu (log mỗi 10 bước)", fontsize=12)
ax1.set_xlabel("Global step", fontsize=11)
ax1.set_ylabel("Loss", fontsize=11)
ax1.grid(True, linestyle="--", alpha=0.4)

lr_x = np.array([e.value for e in v1_step_lr_events])
lr_y = np.array([e.step for e in v1_step_lr_events])
ax2.plot(lr_x, lr_y, marker="s", markersize=4, color="#c1121f", linewidth=1.5)
ax2.set_title("Lộ trình learning rate: warmup lên 0,03", fontsize=12)
ax2.set_xlabel("Learning rate", fontsize=11)
ax2.set_ylabel("Global step", fontsize=11)
ax2.grid(True, linestyle="--", alpha=0.4)

fig.suptitle("Biểu đồ 2 — Diễn biến chi tiết theo bước tối ưu (Đợt 2.1 Solo Nhạc cụ)", fontsize=14, y=0.98)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.1/bieu_do/bieu_do_2_buoc_toi_uu_lr.png")
plt.close()

plt.figure(figsize=(15, 7), dpi=300)
colors = ["#457b9d" if ep != 110 else "#c1121f" for ep, _, _ in checkpoints_data]
bars = plt.bar([str(ep) for ep, _, _ in checkpoints_data], ckpt_y, color=colors, width=0.65)

for bar, val in zip(bars, ckpt_y):
    yval = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2.0, yval + 0.002, f"{val:.4f}", ha="center", va="bottom", fontsize=10, fontweight="bold")

plt.ylim(0.15, 0.22)
plt.title("Biểu đồ 3 — So sánh loss 15 checkpoint lưu mỗi 10 epochs (Đợt 2.1)\n(đỏ = epoch 110, ứng viên loss thấp nhất 0,1781)", fontsize=13, pad=15)
plt.xlabel("Epoch checkpoint", fontsize=11)
plt.ylabel("Loss trung bình", fontsize=11)
plt.grid(axis="y", linestyle="--", alpha=0.4)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.1/bieu_do/bieu_do_3_checkpoints.png")
plt.close()

plt.figure(figsize=(14, 7), dpi=300)
plt.plot(epochs_x, loss_y, color="#1d3557", linewidth=1.6, label="version_1 — lần chính thức (bf16-mixed, watermark=0.0, 150/150 epochs)")
if ea0.Scalars("train/epoch_loss"):
    e0_ev = ea0.Scalars("train/epoch_loss")[0]
    plt.scatter([e0_ev.step], [e0_ev.value], marker="x", color="#c1121f", s=180, linewidths=3, label="version_0 — gãy ở epoch 2 (MPS watermark cap ~30GB, OOM)", zorder=10)
    plt.annotate(
        "epoch 2 = Crash OOM (trước khi vá)\nMPS backend out of memory",
        xy=(e0_ev.step, e0_ev.value),
        xytext=(e0_ev.step + 8, e0_ev.value + 0.04),
        arrowprops=dict(facecolor="#c1121f", edgecolor="#c1121f", arrowstyle="->", lw=1.5),
        color="#780000",
        fontsize=11,
        fontweight="bold"
    )

plt.title("Biểu đồ 4 — Bối cảnh thực nghiệm Đợt 2.1: hai lần chạy\n(lần đầu gãy vì MPS watermark cap ở epoch 2, lần hai hoàn tất toàn bộ 150 epochs sau khi dỡ trần)", fontsize=13, pad=15)
plt.xlabel("Epoch", fontsize=11)
plt.ylabel("Loss", fontsize=11)
plt.ylim(0.14, 0.30)
plt.grid(True, linestyle="--", alpha=0.4)
plt.legend(frameon=True, facecolor="white", edgecolor="#ddd", fontsize=11)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.1/bieu_do/bieu_do_4_boi_canh_hai_lane_chay.png")
plt.close()
