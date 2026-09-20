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

os.makedirs("training/reports/dot2-old/dot2.2/csv", exist_ok=True)
os.makedirs("training/reports/dot2-old/dot2.2/bieu_do", exist_ok=True)

v0_dir = "training/logs/dot2-old/dot2.2/version_0"
ea2_2 = EventAccumulator(v0_dir)
ea2_2.Reload()

epoch_events = ea2_2.Scalars("train/epoch_loss")
step_loss_events = ea2_2.Scalars("train/loss")
step_lr_events = ea2_2.Scalars("train/lr")

t0 = epoch_events[0].wall_time

epoch_csv_path = "training/reports/dot2-old/dot2.2/csv/dot2_2_epoch_loss.csv"
with open(epoch_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["epoch", "loss", "thoi_gian", "giay_tu_khi_bat_dau"])
    for e in epoch_events:
        dt_str = datetime.datetime.fromtimestamp(e.wall_time).strftime("%Y-%m-%d %H:%M:%S")
        elapsed = int(e.wall_time - t0)
        writer.writerow([e.step, f"{e.value:.6f}", dt_str, elapsed])

step_csv_path = "training/reports/dot2-old/dot2.2/csv/dot2_2_step_loss_lr.csv"
with open(step_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["global_step", "loss", "learning_rate", "thoi_gian"])
    for l_ev, lr_ev in zip(step_loss_events, step_lr_events):
        dt_str = datetime.datetime.fromtimestamp(l_ev.wall_time).strftime("%Y-%m-%d %H:%M:%S")
        writer.writerow([l_ev.step, f"{l_ev.value:.6f}", f"{lr_ev.value:.6f}", dt_str])

checkpoints_data = []
for ep in range(10, 110, 10):
    match = [x for x in epoch_events if x.step == ep]
    if match:
        val = match[0].value
        note = ""
        if ep == 40:
            note = "diem_chuyen_giao"
        elif ep == 80:
            note = "vung_vang_du_doan"
        elif ep == 100:
            note = "final"
        checkpoints_data.append((ep, val, note))

ckpt_csv_path = "training/reports/dot2-old/dot2.2/csv/dot2_2_checkpoints.csv"
with open(ckpt_csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["epoch", "loss_trung_binh", "ghi_chu"])
    for ep, val, note in checkpoints_data:
        writer.writerow([ep, f"{val:.4f}", note])

min_ep_ev = min(epoch_events, key=lambda x: x.value)
summary_data = {
    "dot": "ĐỢT 2.2 Hòa tấu Nhã nhạc Cung đình Huế — LoKr (LyCORIS, DoRA)",
    "parent_checkpoint": "models/dot2-old/dot2.1/epoch40 (kế thừa tri thức Đàn Nguyệt & Kèn)",
    "thiet_bi": "Mac mini M4, 24GB unified memory (MPS)",
    "bat_dau": datetime.datetime.fromtimestamp(t0).strftime("%Y-%m-%d %H:%M:%S"),
    "ket_thuc": datetime.datetime.fromtimestamp(epoch_events[-1].wall_time).strftime("%Y-%m-%d %H:%M:%S"),
    "tong_thoi_gian_gio": round((epoch_events[-1].wall_time - t0) / 3600, 2),
    "tong_buoc": len(step_loss_events),
    "epochs": len(epoch_events),
    "loss_khoi_diem": round(epoch_events[0].value, 4),
    "loss_thap_nhat_theo_epoch": {
        "epoch": min_ep_ev.step,
        "loss": round(min_ep_ev.value, 4)
    },
    "loss_ket_thuc": round(epoch_events[-1].value, 4),
    "checkpoints": [{"epoch": ep, "loss": round(val, 4), "ghi_chu": note} for ep, val, note in checkpoints_data],
}

with open("training/reports/dot2-old/dot2.2/csv/dot2_2_tom_tat.json", "w", encoding="utf-8") as f:
    json.dump(summary_data, f, ensure_ascii=False, indent=2)

epochs_x = np.array([e.step for e in epoch_events])
loss_y = np.array([e.value for e in epoch_events])

window = 10
rolling_mean = np.convolve(loss_y, np.ones(window)/window, mode="valid")
rolling_x = epochs_x[window - 1:]

ckpt_x = np.array([ep for ep, _, _ in checkpoints_data])
ckpt_y = np.array([val for _, val, _ in checkpoints_data])

plt.figure(figsize=(14, 7), dpi=300)
plt.plot(epochs_x, loss_y, color="#a8dadc", alpha=0.7, linewidth=1.3, label="Loss từng epoch (Đợt 2.2)")
plt.plot(rolling_x, rolling_mean, color="#1d3557", linewidth=2.4, label=f"Trung bình trượt ({window} epoch)")
plt.scatter(ckpt_x, ckpt_y, color="#e63946", s=65, zorder=5, label="Checkpoint lưu mỗi 10 epoch")

ep69_val = [e.value for e in epoch_events if e.step == 69][0]
plt.annotate(
    f"Epoch 69 — Loss thấp nhất: {ep69_val:.4f}",
    xy=(69, ep69_val),
    xytext=(50, ep69_val - 0.025),
    arrowprops=dict(facecolor="#e63946", edgecolor="#e63946", arrowstyle="->", lw=1.5),
    color="#780000",
    fontsize=11,
    fontweight="bold"
)

ep80_val = [val for ep, val, _ in checkpoints_data if ep == 80][0]
plt.annotate(
    f"Epoch 80 (Vùng kỳ vọng vàng): {ep80_val:.4f}",
    xy=(80, ep80_val),
    xytext=(85, ep80_val + 0.02),
    arrowprops=dict(facecolor="#457b9d", edgecolor="#457b9d", arrowstyle="->", lw=1.5),
    color="#1d3557",
    fontsize=10,
    fontweight="bold"
)

plt.title("Biểu đồ 1 — Diễn biến Loss Huấn luyện LoKr Đợt 2.2 (Hòa tấu Nhã nhạc Cung đình Huế), 100 Epochs", fontsize=14, pad=15)
plt.xlabel("Epoch", fontsize=12)
plt.ylabel("Loss (Flow Matching MSE)", fontsize=12)
plt.grid(True, linestyle="--", alpha=0.4)
plt.legend(frameon=True, facecolor="white", edgecolor="#ddd", fontsize=11)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.2/bieu_do/bieu_do_1_loss_theo_epoch.png")
plt.close()

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6), dpi=300)
step_x = np.array([e.step for e in step_loss_events])
step_y = np.array([e.value for e in step_loss_events])
ax1.plot(step_x, step_y, marker="o", markersize=5, color="#1d3557", linewidth=1.6)
ax1.set_title("Loss theo từng bước tối ưu (Global Step)", fontsize=12)
ax1.set_xlabel("Global step", fontsize=11)
ax1.set_ylabel("Loss", fontsize=11)
ax1.grid(True, linestyle="--", alpha=0.4)

lr_x = np.array([e.step for e in step_lr_events])
lr_y = np.array([e.value for e in step_lr_events])
ax2.plot(lr_x, lr_y, marker="s", markersize=5, color="#e63946", linewidth=1.6)
ax2.set_title("Lộ trình Learning Rate (LR = 0.01 cố định bảo vệ parent weights)", fontsize=12)
ax2.set_xlabel("Global step", fontsize=11)
ax2.set_ylabel("Learning Rate", fontsize=11)
ax2.grid(True, linestyle="--", alpha=0.4)

fig.suptitle("Biểu đồ 2 — Diễn biến theo bước tối ưu (Đợt 2.2 Nhã nhạc Cung đình)", fontsize=14, y=0.98)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.2/bieu_do/bieu_do_2_buoc_toi_uu_lr.png")
plt.close()

plt.figure(figsize=(14, 6.5), dpi=300)
colors = ["#457b9d" if ep != 80 and ep != 40 else "#e63946" for ep, _, _ in checkpoints_data]
bars = plt.bar([str(ep) for ep, _, _ in checkpoints_data], ckpt_y, color=colors, width=0.6)

for bar, val in zip(bars, ckpt_y):
    yval = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2.0, yval + 0.002, f"{val:.4f}", ha="center", va="bottom", fontsize=10, fontweight="bold")

plt.ylim(0.14, 0.24)
plt.title("Biểu đồ 3 — So sánh Loss 10 Checkpoints lưu mỗi 10 Epochs (Đợt 2.2)\n(đỏ = epoch 40 & epoch 80, các mốc ứng viên trọng điểm)", fontsize=13, pad=15)
plt.xlabel("Epoch Checkpoint", fontsize=11)
plt.ylabel("Loss trung bình", fontsize=11)
plt.grid(axis="y", linestyle="--", alpha=0.4)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.2/bieu_do/bieu_do_3_checkpoints.png")
plt.close()

plt.figure(figsize=(15, 7.5), dpi=300)

ea1_dir = "training/logs/dot1/version_1"
if os.path.exists(ea1_dir):
    ea1 = EventAccumulator(ea1_dir)
    ea1.Reload()
    e1_events = ea1.Scalars("train/epoch_loss")
    plt.plot([e.step for e in e1_events[:100]], [e.value for e in e1_events[:100]], color="#f4a261", alpha=0.8, linewidth=1.5, label="Đợt 1: Ca Huế có hát (100 epochs đầu, scratch)")

ea2_1_dir = "training/logs/dot2-old/dot2.1/version_1"
if os.path.exists(ea2_1_dir):
    ea2_1 = EventAccumulator(ea2_1_dir)
    ea2_1.Reload()
    e2_1_events = ea2_1.Scalars("train/epoch_loss")
    plt.plot([e.step for e in e2_1_events[:100]], [e.value for e in e2_1_events[:100]], color="#2a9d8f", alpha=0.8, linewidth=1.5, label="Đợt 2.1: Solo Đàn Nguyệt & Kèn (100 epochs đầu, scratch)")

plt.plot(epochs_x, loss_y, color="#e63946", linewidth=2.2, label="Đợt 2.2: Hòa tấu Nhã nhạc Cung đình (100 epochs, nạp nối tiếp epoch40)")

plt.title("Biểu đồ 4 — Đối sánh Lộ trình Học tập Nối tiếp (Curriculum Learning) qua 3 Đợt", fontsize=14, pad=15)
plt.xlabel("Epoch", fontsize=12)
plt.ylabel("Loss (Flow Matching MSE)", fontsize=12)
plt.ylim(0.14, 0.28)
plt.grid(True, linestyle="--", alpha=0.4)
plt.legend(frameon=True, facecolor="white", edgecolor="#ddd", fontsize=11)
plt.tight_layout()
plt.savefig("training/reports/dot2-old/dot2.2/bieu_do/bieu_do_4_so_sanh_3_dot.png")
plt.close()

print("All charts and CSVs for Dot 2.2 generated successfully!")
