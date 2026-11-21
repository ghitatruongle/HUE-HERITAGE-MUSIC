import argparse
import csv
import json
import math
import os
import re
import sys
import unicodedata

import numpy as np
import librosa
import parselmouth
from parselmouth.praat import call

AUDIO_EXTS = (".wav", ".mp3", ".flac", ".m4a", ".aiff", ".ogg")
TAG_PATTERN = re.compile(r"\[[^\]]*\]")
TRAIN_PATTERN = re.compile(r"cahue_train_(.+?)_(?:gen|cover)_ban\d+", re.IGNORECASE)
MOI_PATTERN = re.compile(r"cahue_moi_(.+?)_(?:gen|cover)_ban\d+", re.IGNORECASE)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DATASET_DIR = os.path.join(BASE_DIR, "datasets", "dot2_v2", "dot2.3", "ca_hue")
WHISPER_SR = 16000
CSV_FIELDS = [
    "file", "model", "lyrics_source", "separation", "duration_s",
    "vocal_energy_pct", "vocal_to_mix_db", "vocal_active_pct",
    "hnr_db", "jitter_pct", "shimmer_pct", "f0_median_hz",
    "cer_pct", "wer_pct", "asr_source", "cer_vocals_pct", "wer_vocals_pct", "cer_mix_pct", "wer_mix_pct",
    "ref_chars", "hyp_chars", "chroma_scale_pct_mix", "transcript", "error",
]


def list_audio(inputs, recursive):
    files = []
    for item in inputs:
        if os.path.isdir(item):
            if recursive:
                for root, _, names in os.walk(item):
                    for name in sorted(names):
                        if name.lower().endswith(AUDIO_EXTS):
                            files.append(os.path.join(root, name))
            else:
                for name in sorted(os.listdir(item)):
                    if name.lower().endswith(AUDIO_EXTS):
                        files.append(os.path.join(item, name))
        elif os.path.isfile(item):
            files.append(item)
    return sorted(dict.fromkeys(files))


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def load_lyrics_map(path):
    if not path:
        return {}
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    base = os.path.dirname(os.path.abspath(path))
    resolved = {}
    for key, value in data.items():
        if isinstance(value, dict):
            if value.get("lyrics"):
                resolved[key] = (value["lyrics"], "inline")
                continue
            value = value.get("lyrics_file") or ""
        candidate = value if os.path.isabs(value) else os.path.join(base, value)
        if value and os.path.isfile(candidate):
            resolved[key] = (read_text(candidate), candidate)
        else:
            resolved[key] = (value, "inline")
    return resolved


def find_lyrics(path, args, lyrics_map):
    stem = os.path.splitext(os.path.basename(path))[0]
    for key in sorted(lyrics_map, key=len, reverse=True):
        if key and key in stem:
            text, src = lyrics_map[key]
            return text, f"map:{key}:{os.path.basename(src)}"
    match = TRAIN_PATTERN.search(stem)
    if match:
        candidate = os.path.join(args.dataset_dir, match.group(1) + ".lyrics.txt")
        if os.path.isfile(candidate):
            return read_text(candidate), f"dataset:{os.path.basename(candidate)}"
    candidates = []
    if args.lyrics_dir:
        candidates.append(os.path.join(args.lyrics_dir, stem + ".lyrics.txt"))
        moi = MOI_PATTERN.search(stem)
        if moi:
            candidates.append(os.path.join(args.lyrics_dir, moi.group(1) + ".lyrics.txt"))
    candidates.append(os.path.join(os.path.dirname(path), stem + ".lyrics.txt"))
    for candidate in candidates:
        if os.path.isfile(candidate):
            return read_text(candidate), f"file:{os.path.basename(candidate)}"
    if args.lyrics_file:
        return read_text(args.lyrics_file), f"file:{os.path.basename(args.lyrics_file)}"
    return None, ""


def normalize_text(text):
    text = TAG_PATTERN.sub(" ", text)
    text = unicodedata.normalize("NFC", text).lower()
    text = re.sub(r"[^\w\s]", " ", text)
    text = text.replace("_", " ")
    return re.sub(r"\s+", " ", text).strip()


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def cer_wer(reference_text, hypothesis_text):
    ref_words = reference_text.split()
    hyp_words = hypothesis_text.split()
    ref_chars = reference_text.replace(" ", "")
    hyp_chars = hypothesis_text.replace(" ", "")
    if not ref_words:
        return None, None, 0, len(hyp_chars)
    wer = levenshtein(ref_words, hyp_words) / len(ref_words) * 100.0
    cer = levenshtein(ref_chars, hyp_chars) / max(len(ref_chars), 1) * 100.0
    return round(cer, 2), round(wer, 2), len(ref_chars), len(hyp_chars)


def _finite_round(value, digits):
    value = float(value)
    return round(value, digits) if math.isfinite(value) else None


def praat_voice_metrics(y, sr, min_pitch, max_pitch):
    sound = parselmouth.Sound(y.astype(np.float64), sampling_frequency=sr)
    harmonicity = sound.to_harmonicity_cc(
        time_step=0.01, minimum_pitch=min_pitch, silence_threshold=0.1, periods_per_window=4.5
    )
    hnr_db = call(harmonicity, "Get mean", 0, 0)
    pitch = sound.to_pitch(time_step=0.01, pitch_floor=min_pitch, pitch_ceiling=max_pitch)
    f0 = pitch.selected_array["frequency"]
    f0 = f0[f0 > 0]
    point_process = call(sound, "To PointProcess (periodic, cc)", min_pitch, max_pitch)
    jitter = call(point_process, "Get jitter (local)", 0, 0, 0.0001, 0.02, 1.3)
    shimmer = call([sound, point_process], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6)
    return {
        "hnr_db": _finite_round(hnr_db, 2),
        "jitter_pct": _finite_round(float(jitter) * 100.0, 3),
        "shimmer_pct": _finite_round(float(shimmer) * 100.0, 3),
        "f0_median_hz": _finite_round(float(np.median(f0)) if f0.size else float("nan"), 1),
    }


def chroma_adherence(y, sr, reference_classes):
    mean_chroma = librosa.feature.chroma_cens(y=y, sr=sr).mean(axis=1)
    classes = reference_classes if reference_classes is not None else list(np.argsort(mean_chroma)[::-1][:5])
    total = mean_chroma.sum()
    if total <= 0:
        return None
    return round(float(mean_chroma[classes].sum() / total * 100.0), 2)


def vocal_activity_pct(vocal_mono, sr, threshold_db):
    frame = int(sr * 0.05)
    if vocal_mono.size < frame:
        return 0.0
    rms = librosa.feature.rms(y=vocal_mono, frame_length=frame, hop_length=frame)[0]
    peak = float(rms.max())
    if peak <= 1e-9:
        return 0.0
    rel = 20.0 * np.log10(np.maximum(rms, 1e-12) / peak)
    return round(float((rel > threshold_db).mean() * 100.0), 2)


class VocalSeparator:
    def __init__(self, model_name, device):
        import torch
        from demucs.pretrained import get_model

        self.torch = torch
        self.model = get_model(model_name)
        self.model.eval()
        if device == "auto":
            device = "mps" if torch.backends.mps.is_available() else "cpu"
        self.device = device
        self.samplerate = int(self.model.samplerate)
        self.vocal_index = list(self.model.sources).index("vocals")

    def separate(self, path):
        from demucs.apply import apply_model

        torch = self.torch
        y, _ = librosa.load(path, sr=self.samplerate, mono=False)
        if y.ndim == 1:
            y = np.stack([y, y])
        y = y[:2]
        wav = torch.from_numpy(np.ascontiguousarray(y)).float()
        ref = wav.mean(0)
        mean, std = ref.mean(), ref.std().clamp_min(1e-8)
        with torch.no_grad():
            sources = apply_model(
                self.model, ((wav - mean) / std)[None], device=self.device,
                split=True, overlap=0.25, progress=False,
            )[0]
        sources = sources * std + mean
        vocals = sources[self.vocal_index].cpu().numpy()
        if self.device == "mps":
            torch.mps.empty_cache()
        return y, vocals, self.samplerate


class WhisperTranscriber:
    def __init__(self, model_size, language, device, compute_type, beam_size):
        from faster_whisper import WhisperModel

        self.model = WhisperModel(model_size, device=device, compute_type=compute_type)
        self.language = language
        self.beam_size = beam_size

    def transcribe(self, audio_16k):
        segments, _ = self.model.transcribe(
            audio_16k.astype(np.float32), language=self.language, beam_size=self.beam_size,
            vad_filter=False, condition_on_previous_text=False,
            no_speech_threshold=None, log_prob_threshold=None,
        )
        return " ".join(segment.text.strip() for segment in segments).strip()


def analyze(path, args, separator, transcriber, lyrics_map, reference_classes):
    row = {"file": os.path.basename(path), "model": os.path.basename(os.path.dirname(path))}
    errors = []
    if separator is not None:
        mix, vocals, sr = separator.separate(path)
        row["separation"] = args.demucs_model
    else:
        mix, sr = librosa.load(path, sr=44100, mono=False)
        if mix.ndim == 1:
            mix = np.stack([mix, mix])
        vocals = mix
        row["separation"] = "none"
    mix_mono = mix.mean(axis=0)
    vocal_mono = vocals.mean(axis=0)
    row["duration_s"] = round(mix_mono.size / sr, 2)

    mix_energy = float(np.sum(mix ** 2))
    vocal_energy = float(np.sum(vocals ** 2))
    row["vocal_energy_pct"] = round(vocal_energy / max(mix_energy, 1e-12) * 100.0, 2)
    row["vocal_to_mix_db"] = round(10.0 * math.log10(max(vocal_energy, 1e-12) / max(mix_energy, 1e-12)), 2)
    row["vocal_active_pct"] = vocal_activity_pct(vocal_mono, sr, args.activity_db)

    if args.stems_dir and separator is not None:
        import soundfile as sf

        stem_dir = os.path.join(args.stems_dir, row["model"]) if row["model"] else args.stems_dir
        os.makedirs(stem_dir, exist_ok=True)
        sf.write(os.path.join(stem_dir, os.path.splitext(row["file"])[0] + "_vocals.wav"), vocals.T, sr, subtype="PCM_16")

    try:
        row.update(praat_voice_metrics(vocal_mono, sr, args.min_pitch, args.max_pitch))
    except Exception as exc:
        errors.append(f"praat: {exc}")

    lyrics, source = find_lyrics(path, args, lyrics_map)
    row["lyrics_source"] = source or "none"
    if transcriber is not None:
        sources = []
        if args.asr_source in ("vocals", "both") and separator is not None:
            sources.append(("vocals", vocal_mono))
        if args.asr_source in ("mix", "both") or separator is None:
            sources.append(("mix", mix_mono))
        best = None
        for label, signal in sources:
            try:
                audio_16k = librosa.resample(signal.astype(np.float32), orig_sr=sr, target_sr=WHISPER_SR)
                transcript = transcriber.transcribe(audio_16k)
            except Exception as exc:
                errors.append(f"whisper[{label}]: {exc}")
                continue
            row[f"transcript_{label}"] = transcript
            if lyrics:
                cer, wer, ref_chars, hyp_chars = cer_wer(normalize_text(lyrics), normalize_text(transcript))
                row[f"cer_{label}_pct"] = cer
                row[f"wer_{label}_pct"] = wer
                if cer is not None and (best is None or cer < best[1]):
                    best = (label, cer, wer, ref_chars, hyp_chars, transcript)
            elif best is None:
                best = (label, None, None, None, None, transcript)
        if best is not None:
            label, cer, wer, ref_chars, hyp_chars, transcript = best
            row.update({"asr_source": label, "transcript": transcript})
            if cer is not None:
                row.update({"cer_pct": cer, "wer_pct": wer, "ref_chars": ref_chars, "hyp_chars": hyp_chars})

    row["chroma_scale_pct_mix"] = chroma_adherence(
        librosa.resample(mix_mono, orig_sr=sr, target_sr=22050), 22050, reference_classes
    )
    if errors:
        row["error"] = " | ".join(errors)
    return row


def summarize(rows):
    groups = {}
    for row in rows:
        groups.setdefault(row.get("model", ""), []).append(row)
    summary = []
    for model, items in sorted(groups.items()):
        entry = {"model": model, "files": len(items)}
        for key in ("cer_pct", "wer_pct", "cer_vocals_pct", "cer_mix_pct", "hnr_db", "jitter_pct", "shimmer_pct", "vocal_to_mix_db", "vocal_active_pct", "chroma_scale_pct_mix"):
            values = [r[key] for r in items if isinstance(r.get(key), (int, float))]
            entry[key] = round(float(np.mean(values)), 3) if values else None
        summary.append(entry)
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", nargs="+", required=True)
    parser.add_argument("--recursive", action="store_true", default=False)
    parser.add_argument("--lyrics_file", default=None)
    parser.add_argument("--lyrics_map", default=None)
    parser.add_argument("--lyrics_dir", default=None)
    parser.add_argument("--dataset_dir", default=DEFAULT_DATASET_DIR)
    parser.add_argument("--reference", default=None)
    parser.add_argument("--whisper_model", default="large-v3")
    parser.add_argument("--whisper_device", default="cpu")
    parser.add_argument("--whisper_compute_type", default="int8")
    parser.add_argument("--beam_size", type=int, default=5)
    parser.add_argument("--language", default="vi")
    parser.add_argument("--no_whisper", action="store_true", default=False)
    parser.add_argument("--asr_source", choices=["both", "vocals", "mix"], default="both")
    parser.add_argument("--demucs_model", default="htdemucs")
    parser.add_argument("--demucs_device", default="auto")
    parser.add_argument("--no_separation", action="store_true", default=False)
    parser.add_argument("--stems_dir", default=None)
    parser.add_argument("--min_pitch", type=float, default=75.0)
    parser.add_argument("--max_pitch", type=float, default=800.0)
    parser.add_argument("--activity_db", type=float, default=-35.0)
    parser.add_argument("--out_json", default=None)
    parser.add_argument("--out_csv", default=None)
    args = parser.parse_args()

    files = list_audio(args.input, args.recursive)
    if args.stems_dir:
        stems_abs = os.path.abspath(args.stems_dir) + os.sep
        files = [f for f in files if not os.path.abspath(f).startswith(stems_abs)]
    if not files:
        print("[ERROR] No audio files found in input")
        sys.exit(1)
    if args.lyrics_file and not os.path.isfile(args.lyrics_file):
        print(f"[ERROR] Lyrics file not found: {args.lyrics_file}")
        sys.exit(1)

    lyrics_map = load_lyrics_map(args.lyrics_map)
    reference_classes = None
    if args.reference:
        ref_y, ref_sr = librosa.load(args.reference, sr=22050, mono=True)
        reference_classes = list(np.argsort(librosa.feature.chroma_cens(y=ref_y, sr=ref_sr).mean(axis=1))[::-1][:5])

    separator = None if args.no_separation else VocalSeparator(args.demucs_model, args.demucs_device)
    transcriber = None if args.no_whisper else WhisperTranscriber(
        args.whisper_model, args.language, args.whisper_device, args.whisper_compute_type, args.beam_size
    )

    rows = []
    for path in files:
        print(f"[ANALYZE] {path}", flush=True)
        try:
            rows.append(analyze(path, args, separator, transcriber, lyrics_map, reference_classes))
        except Exception as exc:
            rows.append({"file": os.path.basename(path), "model": os.path.basename(os.path.dirname(path)), "error": str(exc)})

    for row in rows:
        print(
            f"{row.get('model', '')}/{row['file']}: CER={row.get('cer_pct')}% WER={row.get('wer_pct')}% "
            f"HNR={row.get('hnr_db')}dB vocal/mix={row.get('vocal_to_mix_db')}dB active={row.get('vocal_active_pct')}% "
            f"lyrics={row.get('lyrics_source')}" + (f" ERROR={row['error']}" if row.get("error") else "")
        )
    summary = summarize(rows)
    print("\n[SUMMARY BY MODEL]")
    for entry in summary:
        print(json.dumps(entry, ensure_ascii=False))

    if args.out_json:
        os.makedirs(os.path.dirname(os.path.abspath(args.out_json)), exist_ok=True)
        with open(args.out_json, "w", encoding="utf-8") as handle:
            json.dump({"files": rows, "summary": summary}, handle, ensure_ascii=False, indent=2)
        print(f"\n[SAVED] {args.out_json}")
    if args.out_csv:
        os.makedirs(os.path.dirname(os.path.abspath(args.out_csv)), exist_ok=True)
        with open(args.out_csv, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS, extrasaction="ignore")
            writer.writeheader()
            for row in rows:
                writer.writerow(row)
        print(f"[SAVED] {args.out_csv}")


if __name__ == "__main__":
    main()
