import json
import os
from pathlib import Path
import librosa
import numpy as np
import soundfile as sf

TARGET_RMS_DB = -20.0
PEAK_CEILING = 0.891
TARGET_SR = 44100

TRACKS = [
    {
        "id": "inst_001",
        "title": "Kim Tiền (Độc tấu Đàn Nguyệt)",
        "source": "/Users/songthani/hueheritagemusic/datasets/dot2-old/dot2.1/instruments/inst_001.mp3",
        "caption": "Solo Dan Nguyet moon lute piece Kim Tien, traditional Hue court music, Bac mode, rhythmic acoustic plucking, bright and elegant traditional melody, authentic Vietnamese heritage.",
        "bpm": 85,
        "keyscale": "Bac mode (Hue pentatonic)",
        "type": "Dan Nguyet"
    },
    {
        "id": "inst_002",
        "title": "Long Hổ (Độc tấu Đàn Nguyệt)",
        "source": "/Users/songthani/hueheritagemusic/datasets/dot2-old/dot2.1/instruments/inst_002.mp3",
        "caption": "Solo Dan Nguyet moon lute piece Long Ho, traditional Hue court music, vigorous and spirited acoustic plucking style, Bac mode pentatonic scale, authentic Vietnamese heritage.",
        "bpm": 90,
        "keyscale": "Bac mode (Hue pentatonic)",
        "type": "Dan Nguyet"
    },
    {
        "id": "inst_003",
        "title": "Lưu Thủy (Độc tấu Đàn Nguyệt)",
        "source": "/Users/songthani/hueheritagemusic/datasets/dot2-old/dot2.1/instruments/inst_003.mp3",
        "caption": "Solo Dan Nguyet moon lute piece Luu Thuy (Flowing Water), traditional Hue court music, flowing ornamental bends and tremolo techniques, elegant mood, authentic Vietnamese heritage.",
        "bpm": 78,
        "keyscale": "Bac mode (Hue pentatonic)",
        "type": "Dan Nguyet"
    },
    {
        "id": "inst_004",
        "title": "Xuân Phong (Độc tấu Đàn Nguyệt)",
        "source": "/Users/songthani/hueheritagemusic/datasets/dot2-old/dot2.1/instruments/inst_004.mp3",
        "caption": "Solo Dan Nguyet moon lute piece Xuan Phong (Spring Breeze), traditional Hue court music, lyrical and uplifting melody, crisp acoustic plucking, authentic Vietnamese heritage.",
        "bpm": 82,
        "keyscale": "Bac mode (Hue pentatonic)",
        "type": "Dan Nguyet"
    },
    {
        "id": "inst_005",
        "title": "Đăng Đàn Cung (Độc tấu Đàn Nguyệt)",
        "source": "/Users/songthani/hueheritagemusic/datasets/dot2-old/dot2.1/instruments/inst_005.mp3",
        "caption": "Solo Dan Nguyet moon lute piece Dang Dan Cung (Royal Hymn), solemn and dignified imperial Hue court melody, resonant ornamentation and deliberate phrasing, authentic Vietnamese heritage.",
        "bpm": 65,
        "keyscale": "Bac mode (Hue pentatonic)",
        "type": "Dan Nguyet"
    },
    {
        "id": "inst_006",
        "title": "Kèn Bóp Nhã Nhạc Cung Đình",
        "source": "/Users/songthani/Downloads/nha_nhac/Kèn Bóp - Nhã Nhạc Cung Đình Huế.mp3",
        "caption": "Solo Ken Bop double-reed shawm melody, traditional Hue royal court music, melodic ornamentation, expressive sustained tones, solemn courtly atmosphere, authentic Vietnamese heritage.",
        "bpm": 80,
        "keyscale": "Hue court ceremonial mode",
        "type": "Ken Bop"
    }
]

def normalize_audio(src_path):
    y, sr = librosa.load(src_path, sr=TARGET_SR, mono=False)
    if y.ndim == 1:
        y = np.stack([y, y], axis=0)
    mono = np.mean(y, axis=0)
    cur_rms = np.sqrt(np.mean(mono ** 2))
    target_rms = 10 ** (TARGET_RMS_DB / 20)
    gain = target_rms / (cur_rms + 1e-9)
    y_norm = y * gain
    peak = np.max(np.abs(y_norm))
    if peak > PEAK_CEILING:
        y_norm = y_norm * (PEAK_CEILING / peak)
    return y_norm.T, TARGET_SR

def process_dataset(dest_dir, include_ken=True):
    dest = Path(dest_dir)
    dest.mkdir(parents=True, exist_ok=True)
    metadata_entries = []
    
    tracks_to_process = TRACKS if include_ken else TRACKS[:5]
    
    for t in tracks_to_process:
        audio_norm, sr = normalize_audio(t["source"])
        out_wav = dest / f"{t['id']}.wav"
        sf.write(str(out_wav), audio_norm, sr, subtype="PCM_16")
        
        meta = {
            "caption": t["caption"],
            "bpm": t["bpm"],
            "keyscale": t["keyscale"],
            "language": "vi"
        }
        (dest / f"{t['id']}.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        (dest / f"{t['id']}.lyrics.txt").write_text("[Instrumental]\n", encoding="utf-8")
        
        metadata_entries.append({
            "audio": f"{t['id']}.wav",
            "title": t["title"],
            "type": t["type"],
            "bpm": t["bpm"],
            "tonal": t["keyscale"],
            "caption": t["caption"],
            "lyrics": "[Instrumental]"
        })
        
    (dest / "metadata.json").write_text(json.dumps({"entries": metadata_entries}, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Processed {len(metadata_entries)} tracks into {dest_dir}")

if __name__ == "__main__":
    process_dataset("/Users/songthani/hueheritagemusic/datasets/dot2_v2/dot2.1/instruments", include_ken=True)
    process_dataset("/Users/songthani/hueheritagemusic/datasets/dot2_v2/dot2.1/instruments_pure_dan_nguyet", include_ken=False)
