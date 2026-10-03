import argparse
import csv
import json
import math
import os
import sys

import numpy as np
import librosa
import soundfile as sf


AUDIO_EXTS = (".wav", ".mp3", ".flac", ".m4a", ".aiff", ".ogg")


def list_audio(inputs):
    files = []
    for item in inputs:
        if os.path.isdir(item):
            for name in sorted(os.listdir(item)):
                if name.lower().endswith(AUDIO_EXTS):
                    files.append(os.path.join(item, name))
        elif os.path.isfile(item):
            files.append(item)
    return files


def load_audio(path, sr=44100):
    y, file_sr = librosa.load(path, sr=sr, mono=True)
    return y, file_sr


def band_power_share(freqs, power, lo, hi, total):
    mask = (freqs >= lo) & (freqs <= hi)
    return float(power[mask].sum() / max(total, 1e-12) * 100.0)


def noise_700(y, sr, n_fft, hop, scale):
    spec = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
    freqs = np.linspace(0, sr / 2.0, spec.shape[0])
    target = 700.0
    idx = int(np.argmin(np.abs(freqs - target)))
    lo = max(0, idx - 2)
    hi = min(spec.shape[0], idx + 3)
    return float(spec[lo:hi].mean() * scale)


def onset_count(y, sr, delta):
    env = librosa.onset.onset_strength(y=y, sr=sr)
    times = librosa.onset.onset_detect(
        onset_envelope=env, sr=sr, backtrack=False, delta=delta, units="frames"
    )
    return int(len(times))


def chroma_stats(y, sr):
    chroma = librosa.feature.chroma_cens(y=y, sr=sr)
    mean_chroma = chroma.mean(axis=1)
    norm = np.linalg.norm(mean_chroma)
    return mean_chroma, (mean_chroma / norm if norm > 0 else mean_chroma)


def pentatonic_adherence(mean_chroma, scale_classes):
    total = mean_chroma.sum()
    if total <= 0 or not scale_classes:
        return float("nan")
    inside = mean_chroma[list(scale_classes)].sum()
    return float(inside / total * 100.0)


def top_scale_classes(mean_chroma, n=5):
    return list(np.argsort(mean_chroma)[::-1][:n])


def onset_envelope(y, sr):
    return librosa.onset.onset_strength(y=y, sr=sr)


def envelope_correlation(env_a, env_b):
    if len(env_a) > len(env_b):
        env_a = librosa.util.fix_length(env_a, size=len(env_b))
    elif len(env_b) > len(env_a):
        env_b = librosa.util.fix_length(env_b, size=len(env_a))
    if env_a.std() < 1e-9 or env_b.std() < 1e-9:
        return float("nan")
    return float(np.corrcoef(env_a, env_b)[0, 1] * 100.0)


def cosine_similarity(vec_a, vec_b):
    denom = np.linalg.norm(vec_a) * np.linalg.norm(vec_b)
    if denom < 1e-12:
        return float("nan")
    return float(np.dot(vec_a, vec_b) / denom * 100.0)


def max_jump(y):
    if len(y) < 2:
        return 0.0
    return float(np.abs(np.diff(y)).max())


def analyze_file(path, args, reference=None):
    y, sr = load_audio(path, sr=args.sample_rate)
    peak = float(np.abs(y).max())
    peak_db = 20.0 * math.log10(max(peak, 1e-12))
    rms = float(np.sqrt(np.mean(y ** 2)))
    rms_db = 20.0 * math.log10(max(rms, 1e-12))
    crest_db = peak_db - rms_db

    n_fft = args.n_fft
    hop = n_fft // 4
    spec = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
    power = spec ** 2
    freqs = np.linspace(0, sr / 2.0, spec.shape[0])
    total_power = power.sum()
    wood_pct = band_power_share(freqs, power, 200.0, 800.0, total_power)
    pluck_pct = band_power_share(freqs, power, 2000.0, 6000.0, total_power)

    centroid = float(librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=n_fft, hop_length=hop).mean())
    rolloff = float(librosa.feature.spectral_rolloff(y=y, sr=sr, roll_percent=0.85, n_fft=n_fft, hop_length=hop).mean())
    flatness = float(librosa.feature.spectral_flatness(y=y).mean())

    harm_spec, perc_spec = librosa.decompose.hpss(spec, margin=3.0)
    harm_energy = float((harm_spec ** 2).sum())
    perc_energy = float((perc_spec ** 2).sum())
    hpr_db = 10.0 * math.log10(max(harm_energy, 1e-12) / max(perc_energy, 1e-12))

    noise700 = noise_700(y, sr, args.noise700_nfft, args.noise700_nfft // 4, args.noise700_scale)

    transients = onset_count(y, sr, args.onset_delta)
    contrast = float(librosa.feature.spectral_contrast(y=y, sr=sr, n_fft=n_fft, hop_length=hop).mean())

    mean_chroma, unit_chroma = chroma_stats(y, sr)

    result = {
        "file": os.path.basename(path),
        "peak_db": round(peak_db, 2),
        "rms_db": round(rms_db, 2),
        "crest_db": round(crest_db, 2),
        "wood_pct": round(wood_pct, 2),
        "pluck_pct": round(pluck_pct, 2),
        "centroid_hz": round(centroid, 1),
        "rolloff_hz": round(rolloff, 1),
        "flatness": float(f"{flatness:.6f}"),
        "hpr_db": round(hpr_db, 2),
        "noise700": round(noise700, 2),
        "transients": transients,
        "spectral_contrast_db": round(contrast, 3),
        "max_jump": round(max_jump(y), 4),
    }

    if reference is not None:
        ref_y, ref_sr = reference["y"], reference["sr"]
        result["chroma_scale_pct"] = round(
            pentatonic_adherence(mean_chroma, reference["scale_classes"]), 2
        )
        result["chroma_cosine_vs_ref"] = round(
            cosine_similarity(unit_chroma, reference["unit_chroma"]), 2
        )
        env_a = onset_envelope(y, sr)
        env_b = reference["onset_env"]
        env_rate = sr / 512.0
        ref_env_rate = ref_sr / 512.0
        env_a = librosa.resample(env_a.astype(np.float32), orig_sr=env_rate, target_sr=20)
        env_b = librosa.resample(env_b.astype(np.float32), orig_sr=ref_env_rate, target_sr=20)
        result["rhythm_corr_pct"] = round(envelope_correlation(env_a, env_b), 2)
    else:
        result["chroma_scale_pct"] = round(
            pentatonic_adherence(mean_chroma, top_scale_classes(mean_chroma)), 2
        )
        result["chroma_cosine_vs_ref"] = float("nan")
        result["rhythm_corr_pct"] = float("nan")

    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", nargs="+", required=True)
    parser.add_argument("--reference", default=None)
    parser.add_argument("--out_json", default=None)
    parser.add_argument("--out_csv", default=None)
    parser.add_argument("--sample_rate", type=int, default=44100)
    parser.add_argument("--n_fft", type=int, default=4096)
    parser.add_argument("--noise700_nfft", type=int, default=2048)
    parser.add_argument("--noise700_scale", type=float, default=1.0)
    parser.add_argument("--onset_delta", type=float, default=0.07)
    args = parser.parse_args()

    files = list_audio(args.input)
    if not files:
        print("[ERROR] No audio files found in input")
        sys.exit(1)

    reference = None
    if args.reference:
        ref_y, ref_sr = load_audio(args.reference, sr=args.sample_rate)
        ref_mean_chroma, ref_unit_chroma = chroma_stats(ref_y, ref_sr)
        reference = {
            "y": ref_y,
            "sr": ref_sr,
            "unit_chroma": ref_unit_chroma,
            "scale_classes": top_scale_classes(ref_mean_chroma),
            "onset_env": onset_envelope(ref_y, ref_sr),
        }

    rows = []
    if reference is not None:
        rows.append(analyze_file(args.reference, args, reference=None))
    for path in files:
        print(f"[ANALYZE] {path}", flush=True)
        rows.append(analyze_file(path, args, reference=reference))

    if reference is not None and len(files) >= 2:
        pair_units = []
        for path in files:
            y, sr = load_audio(path, sr=args.sample_rate)
            _, unit = chroma_stats(y, sr)
            pair_units.append(unit)
        cross_seed = cosine_similarity(pair_units[0], pair_units[1])
        rows[-1]["cross_seed_note"] = f"cosine(first,last)={cross_seed:.2f}%"

    fields = [
        "file", "peak_db", "rms_db", "crest_db", "wood_pct", "pluck_pct",
        "centroid_hz", "rolloff_hz", "flatness", "hpr_db", "noise700",
        "transients", "spectral_contrast_db", "max_jump",
        "chroma_scale_pct", "chroma_cosine_vs_ref", "rhythm_corr_pct", "cross_seed_note",
    ]

    width = max(len(f) for f in fields)
    print("\n" + " | ".join(f"{f[:14]:>14}" for f in fields))
    for row in rows:
        print(" | ".join(f"{str(row.get(f, ''))[:14]:>14}" for f in fields))

    if args.out_json:
        with open(args.out_json, "w", encoding="utf-8") as handle:
            json.dump(rows, handle, ensure_ascii=False, indent=2)
        print(f"\n[SAVED] {args.out_json}")

    if args.out_csv:
        with open(args.out_csv, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for row in rows:
                writer.writerow(row)
        print(f"[SAVED] {args.out_csv}")


if __name__ == "__main__":
    main()
