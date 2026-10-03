import os
import json
import numpy as np
import soundfile as sf
import librosa
from scipy.signal import butter, sosfiltfilt

src_dir = "/Users/songthani/Downloads/GHM1/all_ch"
dst_dir = "/Users/songthani/hueheritagemusic/datasets/dot2_v2/dot2.3/ca_hue"
downloads_preview_dir = "/Users/songthani/Downloads/dot2_v2/dot2.3_ca_hue_da_loc_am"

os.makedirs(dst_dir, exist_ok=True)
os.makedirs(downloads_preview_dir, exist_ok=True)

selected_tracks = [
    ("cahue_001", "Cổ Bản (lời cổ).wav", "Cổ Bản (Điệu Bắc Lời Cổ)"),
    ("cahue_002", "Dân ca Bình - Trị - Thiên_ Lý Hoài Nam - Lý Ngựa Ô.wav", "Lý Hoài Nam - Lý Ngựa Ô (Dân Ca Bình Trị Thiên)"),
    ("cahue_003", "Dân ca Bình - Trị - Thiên_ Lý Mười Thương.wav", "Lý Mười Thương (Dân Ca Huế)"),
    ("cahue_004", "Hành Vân (lời cổ).wav", "Hành Vân (Điệu Bắc Lời Cổ)"),
    ("cahue_005", "Hầu Văn.wav", "Hầu Văn (Hát Văn Xứ Huế)"),
    ("cahue_006", "Hò Giã Gạo (Hò đối đáp).wav", "Hò Giã Gạo (Hò Đối Đáp Nam Nữ)"),
    ("cahue_007", "Hò Mái Nhì, Nam Bình.wav", "Hò Mái Nhì - Nam Bình (Linh Hồn Ca Huế)"),
    ("cahue_008", "KHÚC CA NAM BÌNH.wav", "Khúc Ca Nam Bình (Điệu Nam)"),
    ("cahue_009", "Nam Bình - Nước Non Ngàn Dặm.wav", "Nam Bình - Nước Non Ngàn Dặm"),
    ("cahue_010", "Nam Xuân (lời cổ).wav", "Nam Xuân (Điệu Nam Xuân Lời Cổ)"),
    ("cahue_011", "Quả Phụ - Tương Tư (lời cổ).wav", "Quả Phụ - Tương Tư (Điệu Nam Lời Cổ)"),
]

target_sr = 44100
target_peak_db = -2.0
target_rms_db = -21.5

summary_report = []

sos_hp = butter(4, 30.0, btype="highpass", fs=target_sr, output="sos")

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
        for ch in range(y.shape[1]):
            y[:, ch] = sosfiltfilt(sos_hp, y[:, ch])
        y_mono = y.mean(axis=1)
    else:
        y = sosfiltfilt(sos_hp, y)
        y_mono = y

    y = y - np.mean(y, axis=0, keepdims=True)
    y_mono = y_mono - np.mean(y_mono)

    non_silent = librosa.effects.split(y_mono, top_db=45)
    if len(non_silent) > 0:
        start_idx = non_silent[0][0]
        end_idx = non_silent[-1][1]
        y = y[start_idx:end_idx]
        y_mono = y_mono[start_idx:end_idx]

    rms = np.sqrt(np.mean(y_mono ** 2))
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
    final_peak_db = 20 * np.log10(final_peak + 1e-9)
    final_rms = np.sqrt(np.mean(y_mono_final ** 2))
    final_rms_db = 20 * np.log10(final_rms + 1e-9)
    final_crest = final_peak_db - final_rms_db
    clips = np.sum(np.abs(y) >= 0.999)
    dur = len(y) / target_sr

    sub_len = min(len(y_mono_final), target_sr * 60)
    y_harm, y_perc = librosa.effects.hpss(y_mono_final[:sub_len])
    h_eng = np.sum(y_harm ** 2)
    p_eng = np.sum(y_perc ** 2)
    hpr_db = 10 * np.log10(h_eng / (p_eng + 1e-10))

    dst_wav = os.path.join(dst_dir, f"{track_id}.wav")
    sf.write(dst_wav, y, target_sr, subtype="PCM_16")

    preview_name = f"{track_id}_{title.replace(' ', '_').replace('-', '_')}.wav"
    preview_wav = os.path.join(downloads_preview_dir, preview_name)
    sf.write(preview_wav, y, target_sr, subtype="PCM_16")

    summary_report.append({
        "id": track_id,
        "title": title,
        "original_file": src_fn,
        "duration_sec": round(dur, 1),
        "duration_str": f"{int(dur // 60)}m{int(dur % 60):02d}s",
        "peak_db": round(final_peak_db, 2),
        "rms_db": round(final_rms_db, 2),
        "crest_db": round(final_crest, 2),
        "clips": int(clips),
        "hpr_db": round(hpr_db, 2),
        "out_file": f"{track_id}.wav",
        "preview_file": preview_name
    })

rep_path = os.path.join(dst_dir, "dataset_norm_report.json")
with open(rep_path, "w", encoding="utf-8") as f:
    json.dump(summary_report, f, indent=2, ensure_ascii=False)

print(json.dumps(summary_report, indent=2, ensure_ascii=False))
