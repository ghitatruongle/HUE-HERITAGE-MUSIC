import os
import glob
import json
import numpy as np
import soundfile as sf
import librosa

src_dir = "/Users/songthani/Downloads/GHM1/all_nn"
dst_dir = "/Users/songthani/hueheritagemusic/datasets/dot2_v2/dot2.2/nha_nhac"
os.makedirs(dst_dir, exist_ok=True)

selected_tracks = [
    ("nhanhac_001", "Hòa tấu Bát âm_ Bản Lưu Thủy.wav", "Lưu Thủy (Hòa tấu Bát Âm)"),
    ("nhanhac_002", "Đăng Đàn Cung.wav", "Đăng Đàn Cung (Đại Nhạc)"),
    ("nhanhac_003", "Long Ngâm.wav", "Long Ngâm (Đại Nhạc)"),
    ("nhanhac_004", "Nam ai.wav", "Nam Ai (Tiểu Nhạc Điệu Oán)"),
    ("nhanhac_005", "Nam bằng.wav", "Nam Bằng (Tiểu Nhạc Điệu Bắc)"),
    ("nhanhac_006", "Phú lục địch.wav", "Phú Lục Địch (Tiểu Nhạc Sáo Trúc)"),
    ("nhanhac_007", "Du xuân.wav", "Du Xuân (Tiểu Nhạc Yến Tiệc)"),
    ("nhanhac_008", "Bông, mã, vũ, mang.wav", "Bông Mã Vũ Mang (Nhạc Lễ Cung Đình)"),
    ("nhanhac_009", "Tam luân cửu chuyển(1).wav", "Tam Luân Cửu Chuyển (Nhạc Tế Giao)"),
    ("nhanhac_010", "Thập thủ liên hoàn.wav", "Thập Thủ Liên Hoàn (Đại Nhạc Liên Khúc)"),
    ("nhanhac_011", "Phụng vũ.wav", "Phụng Vũ (Vũ Khúc Cung Đình)"),
    ("nhanhac_012", "Mã vũ Du xuân Tẩu mã.wav", "Mã Vũ - Du Xuân - Tẩu Mã (Liên Khúc Hòa Tấu)"),
]

target_sr = 44100
target_peak_db = -2.0
target_rms_db = -21.5

summary_report = []

for track_id, src_fn, title in selected_tracks:
    src_path = os.path.join(src_dir, src_fn)
    y, sr = sf.read(src_path)
    
    if sr != target_sr:
        if y.ndim > 1:
            channels = [librosa.resample(y[:, ch], orig_sr=sr, target_sr=target_sr) for ch in range(y.shape[1])]
            y = np.stack(channels, axis=1)
        else:
            y = librosa.resample(y, orig_sr=sr, target_sr=target_sr)
            
    if y.ndim > 1:
        y_mono = y.mean(axis=1)
    else:
        y_mono = y

    non_silent = librosa.effects.split(y_mono, top_db=45)
    if len(non_silent) > 0:
        start_idx = non_silent[0][0]
        end_idx = non_silent[-1][1]
        y = y[start_idx:end_idx]
        y_mono = y_mono[start_idx:end_idx]

    rms = np.sqrt(np.mean(y_mono**2))
    current_rms_db = 20 * np.log10(rms) if rms > 0 else -100
    rms_gain = 10 ** ((target_rms_db - current_rms_db) / 20)
    y = y * rms_gain
    
    max_peak = np.max(np.abs(y))
    target_peak = 10 ** (target_peak_db / 20)
    if max_peak > target_peak:
        peak_gain = target_peak / max_peak
        y = y * peak_gain

    y_mono_final = y.mean(axis=1) if y.ndim > 1 else y
    final_peak = np.max(np.abs(y))
    final_peak_db = 20 * np.log10(final_peak)
    final_rms = np.sqrt(np.mean(y_mono_final**2))
    final_rms_db = 20 * np.log10(final_rms)
    clips = np.sum(np.abs(y) >= 1.0)
    dur = len(y) / target_sr

    sub_len = min(len(y_mono_final), target_sr * 60)
    y_harm, y_perc = librosa.effects.hpss(y_mono_final[:sub_len])
    h_eng = np.sum(y_harm**2)
    p_eng = np.sum(y_perc**2)
    hpr_db = 10 * np.log10(h_eng / (p_eng + 1e-10))

    dst_wav = os.path.join(dst_dir, f"{track_id}.wav")
    sf.write(dst_wav, y, target_sr, subtype="PCM_16")

    summary_report.append({
        "id": track_id,
        "title": title,
        "original_file": src_fn,
        "duration_sec": round(dur, 1),
        "peak_db": round(final_peak_db, 2),
        "rms_db": round(final_rms_db, 2),
        "clips": int(clips),
        "hpr_db": round(hpr_db, 2),
        "out_file": f"{track_id}.wav"
    })

rep_path = os.path.join(dst_dir, "dataset_norm_report.json")
with open(rep_path, "w", encoding="utf-8") as f:
    json.dump(summary_report, f, indent=2, ensure_ascii=False)

print(json.dumps(summary_report, indent=2, ensure_ascii=False))
