from __future__ import annotations

import json
import threading
import wave
from pathlib import Path
from typing import List, Optional, Tuple

from ..config import settings
from ..database.models import HeritageItem
from ..services import pitch_service
from ..storage import manager

SECTION_MIN_SECONDS = 2.0
SECTION_TARGET_MAX = 25.0
SECTION_HARD_MAX = 35.0
MAX_SECTIONS = 16
CONTOUR_HOP = 512
CONTOUR_MAX_POINTS = 400
SILENCE_GAP_SECONDS = 0.7
SECTION_SR = 16000


def lessons_dir():
    d = settings.storage_dir / "analysis" / "lessons"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _audio_path(item: HeritageItem):
    if not item.filename or not manager.safe_original_name(item.filename):
        return None
    p = manager.original_dir() / item.filename
    return p if p.exists() else None


def _write_wav16(path, samples, sr):
    import os
    import tempfile

    samples, sr = pitch_service.resample_16k(samples, sr)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), suffix=".part")
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        with wave.open(str(tmp), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            try:
                import numpy as _np

                arr = _np.clip(_np.asarray(samples, dtype=_np.float64), -1.0, 1.0)
                frames = (arr * 32767.0).astype("<i2").tobytes()
            except Exception:
                frames = bytearray()
                for s in samples:
                    v = int(max(-1.0, min(1.0, float(s))) * 32767.0)
                    frames += v.to_bytes(2, "little", signed=True)
                frames = bytes(frames)
            w.writeframes(frames)
        tmp.replace(path)
    except Exception:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise


def _wav_sample_rate(path) -> Optional[int]:
    try:
        with wave.open(str(path), "rb") as w:
            return w.getframerate()
    except Exception:
        return None


def _frame_rms_voiced(samples, sr):
    import numpy as np

    arr = np.asarray(samples, dtype=np.float64)
    hop = max(1, int(sr * 0.02))
    n = len(arr) // hop
    if n < 2:
        return [], 0.02
    rms = np.sqrt(np.mean((arr[: n * hop].reshape(n, hop)) ** 2, axis=1))
    peak = float(rms.max())
    if peak <= 0.0:
        return [], 0.02
    thr = max(peak * 0.08, 1e-4)
    return (rms > thr).tolist(), 0.02


def _split_sections(samples, sr) -> List[Tuple[float, float]]:
    voiced, step = _frame_rms_voiced(samples, sr)
    total = round(len(samples) / sr, 2)
    if not voiced:
        return [(0.0, min(SECTION_HARD_MAX, total))] if total >= 1.0 else []
    min_gap = max(1, int(SILENCE_GAP_SECONDS / step))
    cuts = [0.0]
    run = 0
    for i, v in enumerate(voiced):
        if not v:
            run += 1
        else:
            if run >= min_gap:
                cuts.append(round((i - run / 2) * step, 2))
            run = 0
    cuts.append(total)
    merged = []
    for i in range(len(cuts) - 1):
        a, b = cuts[i], cuts[i + 1]
        if merged and b - a < SECTION_MIN_SECONDS:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    out = []
    for a, b in merged:
        if b - a <= SECTION_HARD_MAX:
            out.append((a, b))
            continue
        n_split = int((b - a) // SECTION_TARGET_MAX) + 1
        step_t = (b - a) / n_split
        for k in range(n_split):
            out.append((round(a + k * step_t, 2), round(a + (k + 1) * step_t, 2)))
    out = [(a, min(b, total)) for a, b in out if b - a >= SECTION_MIN_SECONDS]
    return out[:MAX_SECTIONS]


def _assign_lyrics(lines: List[str], sections: List[Tuple[float, float]]) -> List[str]:
    if not lines or not sections:
        return ["" for _ in sections]
    total = sum(b - a for a, b in sections) or 1.0
    result = []
    used = 0
    for idx, (a, b) in enumerate(sections):
        if idx == len(sections) - 1:
            take = lines[used:]
        else:
            want = int(round(len(lines) * (b - a) / total))
            take = lines[used:used + max(1, want)]
            used += max(1, want)
        result.append("\n".join(take) if take else "")
    return result


def _lesson_cache_path(item: HeritageItem):
    return lessons_dir() / f"{item.sha256 or item.id}.json"


def _downsample_contour(times, f0):
    n = len(times)
    if n <= CONTOUR_MAX_POINTS:
        return [round(t, 2) for t in times], [round(v, 1) for v in f0]
    step = n / CONTOUR_MAX_POINTS
    ot, of = [], []
    k = 0.0
    while int(k) < n and len(ot) < CONTOUR_MAX_POINTS:
        ot.append(round(times[int(k)], 2))
        of.append(round(f0[int(k)], 1))
        k += step
    return ot, of


def build_lesson(item: HeritageItem) -> dict:
    audio = _audio_path(item)
    if audio is None:
        raise ValueError("lesson audio missing")
    data = audio.read_bytes()
    samples, sr = pitch_service.read_mono_wav(data, max_seconds=300.0)
    samples, sr = pitch_service.resample_16k(samples, sr)
    sections = _split_sections(samples, sr)
    if not sections:
        raise ValueError("audio too short for lesson")
    times, f0 = pitch_service.estimate_f0(samples, sr, hop=CONTOUR_HOP)
    ct, cf = _downsample_contour(times, f0)
    lyrics_text = (item.lyrics_with_ornaments or item.lyrics or "").strip()
    lines = [ln.strip() for ln in lyrics_text.splitlines() if ln.strip()]
    lyrics_parts = _assign_lyrics(lines, sections)
    payload_sections = []
    sec_dir = lessons_dir() / (item.sha256 or item.id)
    sec_dir.mkdir(parents=True, exist_ok=True)
    for idx, (a, b) in enumerate(sections):
        wav_path = sec_dir / f"{idx:02d}.wav"
        if not wav_path.exists() or _wav_sample_rate(wav_path) != SECTION_SR:
            _write_wav16(wav_path, samples[int(a * sr):int(b * sr)], sr)
        payload_sections.append(
            {
                "index": idx,
                "start": a,
                "end": b,
                "duration": round(b - a, 2),
                "lyrics": lyrics_parts[idx],
            }
        )
    payload = {
        "id": item.id,
        "title": item.title,
        "contour": {"times": ct, "f0": cf},
        "sections": payload_sections,
        "sample_rate": sr,
    }
    import os
    import tempfile

    cache_path = _lesson_cache_path(item)
    fd, tmp_name = tempfile.mkstemp(dir=str(cache_path.parent), suffix=".part")
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        tmp.replace(cache_path)
    except Exception:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise
    return payload


_LESSON_BUILD_LOCKS: dict = {}
_LESSON_LOCKS_GUARD = threading.Lock()


def _try_cached_lesson(item: HeritageItem) -> Optional[dict]:
    cached = _lesson_cache_path(item)
    if cached.exists():
        try:
            data = json.loads(cached.read_text(encoding="utf-8"))
            sec_dir = lessons_dir() / (item.sha256 or item.id)
            sections = data.get("sections", [])
            if sections and all((sec_dir / f"{s['index']:02d}.wav").exists() for s in sections):
                first = sec_dir / f"{sections[0]['index']:02d}.wav"
                if _wav_sample_rate(first) == SECTION_SR:
                    return data
        except Exception:
            pass
    return None


def get_lesson(item: HeritageItem) -> Optional[dict]:
    data = _try_cached_lesson(item)
    if data is not None:
        return data
    sha = item.sha256 or item.id
    with _LESSON_LOCKS_GUARD:
        lock = _LESSON_BUILD_LOCKS.setdefault(sha, threading.Lock())
    with lock:
        data = _try_cached_lesson(item)
        if data is not None:
            return data
        return build_lesson(item)


def lesson_summary(item: HeritageItem) -> Optional[dict]:
    if _audio_path(item) is None:
        return None
    cache_ready = _lesson_cache_path(item).exists()
    sec_dir = lessons_dir() / (item.sha256 or item.id)
    count = 0
    if cache_ready and sec_dir.exists():
        try:
            count = len(list(sec_dir.glob("[0-9][0-9].wav")))
        except Exception:
            count = 0
    return {
        "id": item.id,
        "title": item.title,
        "type": item.type,
        "artist": item.artist,
        "mode_system": item.mode_system,
        "bpm": item.bpm,
        "has_ornaments": bool((item.lyrics_with_ornaments or "").strip()),
        "sections": count,
    }


def section_wav(item: HeritageItem, section_index: int) -> Optional[Path]:
    lesson = get_lesson(item)
    for s in lesson.get("sections", []):
        if s["index"] == section_index:
            wav_path = lessons_dir() / (item.sha256 or item.id) / f"{section_index:02d}.wav"
            if wav_path.exists():
                return wav_path
    return None
