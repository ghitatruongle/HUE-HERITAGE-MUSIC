from ..audio_dsp import features
from . import pitch_service

WIN = 1.0
HOP = 0.5
LABEL = "Nhận diện tự động – cần kiểm duyệt"


def classify(fe):
    if fe["rms"] < 0.005:
        return "Im lặng", 0.9
    if fe["zcr"] > 0.15 and fe["harmonic"] < 0.3:
        conf = 0.6 + min(0.3, (fe["zcr"] - 0.15) * 2 + (0.3 - fe["harmonic"]))
        return "Trống / gõ", round(min(0.9, conf), 2)
    if fe["harmonic"] >= 0.8 and fe["centroid"] < 1500:
        conf = 0.6 + min(0.3, (fe["harmonic"] - 0.8) * 2 + (1500 - fe["centroid"]) / 5000)
        return "Đàn tranh / dây", round(min(0.9, conf), 2)
    if fe["centroid"] >= 1000 and fe["decay"] >= 0.7 and fe["zcr"] < 0.15:
        conf = 0.55 + min(0.3, (fe["centroid"] - 1000) / 5000 + (0.15 - fe["zcr"]))
        return "Sáo / hơi", round(min(0.85, conf), 2)
    if fe["harmonic"] >= 0.5:
        return "Đàn nguyệt / tỳ bà", 0.55
    return "Chưa rõ", 0.4


def detect(data):
    samples, sr = pitch_service.read_mono_wav(data)
    win_n = int(sr * WIN)
    hop_n = int(sr * HOP)
    if hop_n <= 0:
        hop_n = 1
    if win_n <= 0:
        win_n = 1
    if len(samples) < win_n:
        samples = samples + [0.0] * (win_n - len(samples))
    segs = []
    pos = 0
    while pos + win_n <= len(samples):
        fe = features.window_features(samples[pos:pos + win_n], sr)
        label, conf = classify(fe)
        segs.append({
            "start": round(pos / sr, 2),
            "end": round((pos + win_n) / sr, 2),
            "instrument": label,
            "confidence": conf,
            "features": fe,
        })
        pos += hop_n
        if len(segs) > 120:
            break
    merged = []
    for s in segs:
        if merged and merged[-1]["instrument"] == s["instrument"]:
            merged[-1]["end"] = s["end"]
            merged[-1]["confidence"] = round((merged[-1]["confidence"] + s["confidence"]) / 2, 2)
        else:
            merged.append({k: s[k] for k in ("start", "end", "instrument", "confidence")})
    return {
        "label": LABEL,
        "sample_rate": sr,
        "duration": round(len(samples) / sr, 2),
        "segments": merged,
    }
