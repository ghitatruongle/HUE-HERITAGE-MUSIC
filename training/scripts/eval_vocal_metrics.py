import argparse
import json
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


def find_lyrics(path, lyrics_dir):
    stem = os.path.splitext(os.path.basename(path))[0]
    candidates = []
    if lyrics_dir:
        candidates.append(os.path.join(lyrics_dir, stem + ".lyrics.txt"))
    candidates.append(os.path.join(os.path.dirname(path), stem + ".lyrics.txt"))
    for candidate in candidates:
        if os.path.exists(candidate):
            with open(candidate, "r", encoding="utf-8") as handle:
                return handle.read()
    return None


def normalize_text(text):
    text = TAG_PATTERN.sub(" ", text)
    text = unicodedata.normalize("NFC", text)
    text = text.lower()
    text = re.sub(r"[^\w\sÀ-ỹà-ỹ]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            cost = 0 if ca == cb else 1
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost))
        previous = current
    return previous[-1]


def wer_per(reference_text, hypothesis_text):
    ref_words = reference_text.split()
    hyp_words = hypothesis_text.split()
    if not ref_words:
        return float("nan"), float("nan")
    wer = levenshtein(ref_words, hyp_words) / max(len(ref_words), 1)
    ref_chars = reference_text.replace(" ", "")
    hyp_chars = hypothesis_text.replace(" ", "")
    per = levenshtein(ref_chars, hyp_chars) / max(len(ref_chars), 1)
    return round(wer * 100.0, 2), round(per * 100.0, 2)


def praat_voice_metrics(y, sr):
    sound = parselmouth.Sound(y.astype(np.float64), sampling_frequency=sr)
    harmonicity = sound.to_harmonicity_cc(
        time_step=0.01, minimum_pitch=75.0, silence_threshold=0.1, periods_per_window=4.5
    )
    hnr_db = call(harmonicity, "Get mean", 0, 0)
    point_process = call(sound, "To PointProcess (periodic, cc)", 75.0, 500.0)
    jitter = call(point_process, "Get jitter (local)", 0, 0, 0.0001, 0.02, 1.3)
    shimmer = call([sound, point_process], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6)
    return float(hnr_db), float(jitter) * 100.0, float(shimmer) * 100.0


def whisper_transcribe(path, model_size, language):
    from faster_whisper import WhisperModel

    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    segments, info = model.transcribe(path, language=language, beam_size=5, vad_filter=False)
    text = " ".join(segment.text.strip() for segment in segments)
    return text.strip()


def chroma_adherence(y, sr, reference=None):
    chroma = librosa.feature.chroma_cens(y=y, sr=sr)
    mean_chroma = chroma.mean(axis=1)
    if reference is not None:
        ref_y, ref_sr = librosa.load(reference, sr=sr, mono=True)
        ref_mean = librosa.feature.chroma_cens(y=ref_y, sr=ref_sr).mean(axis=1)
        classes = list(np.argsort(ref_mean)[::-1][:5])
    else:
        classes = list(np.argsort(mean_chroma)[::-1][:5])
    total = mean_chroma.sum()
    if total <= 0:
        return float("nan")
    return round(float(mean_chroma[classes].sum() / total * 100.0), 2)


def analyze(path, args, whisper_model):
    y, sr = librosa.load(path, sr=44100, mono=True)
    result = {"file": os.path.basename(path)}

    try:
        hnr_db, jitter_pct, shimmer_pct = praat_voice_metrics(y, sr)
        result["hnr_db"] = round(hnr_db, 2)
        result["jitter_pct"] = round(jitter_pct, 3)
        result["shimmer_pct"] = round(shimmer_pct, 3)
    except Exception as exc:
        result["hnr_db"] = None
        result["praat_error"] = str(exc)

    try:
        if whisper_model is None:
            whisper_model = WhisperModelCache(args.whisper_model, args.language)
        transcript = whisper_model.transcribe(path)
        result["transcript"] = transcript
        lyrics = find_lyrics(path, args.lyrics_dir)
        if lyrics:
            ref_norm = normalize_text(lyrics)
            hyp_norm = normalize_text(transcript)
            wer, per = wer_per(ref_norm, hyp_norm)
            result["wer_pct"] = wer
            result["per_pct"] = per
        else:
            result["wer_pct"] = None
            result["per_pct"] = None
            result["lyrics_note"] = "no lyrics file found"
    except Exception as exc:
        result["whisper_error"] = str(exc)

    result["chroma_scale_pct_mix"] = chroma_adherence(y, sr, args.reference)
    return result


class WhisperModelCache:
    def __init__(self, model_size, language):
        from faster_whisper import WhisperModel

        self._model = WhisperModel(model_size, device="cpu", compute_type="int8")
        self._language = language

    def transcribe(self, path):
        segments, info = self._model.transcribe(
            path, language=self._language, beam_size=5, vad_filter=False
        )
        return " ".join(segment.text.strip() for segment in segments).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", nargs="+", required=True)
    parser.add_argument("--lyrics_dir", default=None)
    parser.add_argument("--reference", default=None)
    parser.add_argument("--whisper_model", default="small")
    parser.add_argument("--language", default="vi")
    parser.add_argument("--out_json", default=None)
    args = parser.parse_args()

    files = list_audio(args.input)
    if not files:
        print("[ERROR] No audio files found in input")
        sys.exit(1)

    whisper_model = WhisperModelCache(args.whisper_model, args.language)
    rows = []
    for path in files:
        print(f"[ANALYZE] {path}", flush=True)
        rows.append(analyze(path, args, whisper_model))

    for row in rows:
        print(
            f"{row['file']}: HNR={row.get('hnr_db')} dB, WER={row.get('wer_pct')}%, "
            f"PER={row.get('per_pct')}%, ChromaScale(mix)={row.get('chroma_scale_pct_mix')}%"
        )

    if args.out_json:
        with open(args.out_json, "w", encoding="utf-8") as handle:
            json.dump(rows, handle, ensure_ascii=False, indent=2)
        print(f"\n[SAVED] {args.out_json}")


if __name__ == "__main__":
    main()
