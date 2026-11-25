import json
import os
import tempfile
from pathlib import Path

from ..ai import basic_pitch_amt as bp_amt
from ..audio_dsp import post_quantizer
from ..storage import manager
from . import amt_service, midi_service, musicxml_service, pitch_service, restoration_service

VALID_ENGINES = ("basic_pitch", "dsp")


def extract_notes(data, bpm, engine="basic_pitch"):
    samples, sr = pitch_service.read_mono_wav(data, max_seconds=300.0)
    used = "dsp"
    engine_error = None
    notes = None
    if engine == "basic_pitch" and bp_amt.available():
        try:
            notes = bp_amt.transcribe(samples, sr)
            used = "basic_pitch"
        except bp_amt.EngineBusy:
            raise
        except Exception as e:
            notes = None
            engine_error = str(e)
    elif engine == "basic_pitch":
        engine_error = "basic_pitch unavailable"
    if notes is None:
        times, f0s = pitch_service.estimate_f0(samples, sr)
        notes = amt_service.segment_notes(times, f0s)
    return post_quantizer.quantize(notes, bpm), used, engine_error


def _atomic_write_bytes(dest: Path, data: bytes) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(dest.parent), suffix=".part")
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, dest)
    except Exception:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise


def write_artifacts(data, notes, bpm, source_stem, digest=None):
    if digest is None:
        digest = manager.sha256_bytes(data)
    stem = f"{digest}_{int(bpm)}"
    mid = manager.midi_dir() / (stem + ".mid")
    _atomic_write_bytes(mid, midi_service.write_midi(notes, bpm))
    xm = manager.xml_dir() / (stem + ".musicxml")
    _atomic_write_bytes(xm, musicxml_service.build_musicxml(notes, bpm, source_stem).encode("utf-8"))
    return digest, stem, mid, xm


def notes_cache_path(digest, bpm, engine=""):
    if not manager.is_sha256(str(digest)):
        raise ValueError("bad digest")
    if engine and engine not in VALID_ENGINES:
        raise ValueError("bad engine")
    tag = f"{bpm:g}"
    if engine:
        tag += f"_{engine}"
    root = manager.midi_dir().resolve()
    path = (root / f"{digest}_{tag}.notes.json").resolve()
    if not path.is_relative_to(root):
        raise ValueError("bad cache path")
    return path


def load_cached_notes(digest, bpm, engine):
    path = notes_cache_path(digest, bpm, engine)
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    notes = payload.get("notes")
    if not isinstance(notes, list):
        return None
    return notes, str(payload.get("engine") or engine or "cache"), payload.get("engine_error")


def save_cached_notes(digest, bpm, engine, notes, used, engine_error):
    import logging
    import os
    import tempfile
    from pathlib import Path

    try:
        path = notes_cache_path(digest, bpm, engine)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), suffix=".part")
        os.close(fd)
        tmp = Path(tmp_name)
        try:
            tmp.write_text(
                json.dumps({"notes": notes, "engine": used, "engine_error": engine_error}, ensure_ascii=False),
                encoding="utf-8",
            )
            tmp.replace(path)
        except Exception:
            try:
                tmp.unlink()
            except OSError:
                pass
            raise
    except Exception:
        logging.getLogger(__name__).warning("transcribe notes cache save failed", exc_info=True)


def restore_audio(data):
    out, report = restoration_service.restore(data)
    digest = manager.sha256_bytes(data)
    dest = manager.restored_dir() / (digest + "_restored.wav")
    if not dest.exists():
        _atomic_write_bytes(dest, out)
    report["sha"] = digest
    return report, dest
