from ..database.session import SessionLocal
from ..database import crud
from ..services import pitch_service, amt_service, midi_service, musicxml_service
from ..services import restoration_service, instrument_service
from ..ai import basic_pitch_amt as bp_amt
from ..audio_dsp import post_quantizer
from ..storage import manager
from pathlib import Path

MAX_BYTES = 15 * 1024 * 1024


def _safe_audio_path(params: dict) -> Path:
    raw = params.get("audio_path") or ""
    if not raw:
        raise ValueError("audio_path required")
    path = Path(raw).resolve()
    roots = [
        manager.original_dir().resolve(),
        manager.temp_dir().resolve(),
        manager.restored_dir().resolve(),
        manager.generated_dir().resolve(),
    ]
    allowed = False
    for root in roots:
        try:
            path.relative_to(root)
            allowed = True
            break
        except ValueError:
            continue
    if not allowed:
        raise ValueError("audio_path outside allowed storage")
    if not path.is_file():
        raise ValueError("audio_path not found")
    return path


def _transcribe(params):
    path = _safe_audio_path(params)
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        raise ValueError("file too large")
    bpm = float(params.get("bpm", 60.0))
    samples, sr = pitch_service.read_mono_wav(data)
    used = "dsp"
    notes = None
    if params.get("engine", "basic_pitch") == "basic_pitch" and bp_amt.available():
        try:
            notes = bp_amt.transcribe(samples, sr)
            used = "basic_pitch"
        except Exception:
            notes = None
    if notes is None:
        times, f0s = pitch_service.estimate_f0(samples, sr)
        notes = amt_service.segment_notes(times, f0s)
    notes = post_quantizer.quantize(notes, bpm)
    digest = manager.sha256_bytes(data)
    stem = f"{digest}_{int(bpm)}"
    mid = manager.midi_dir() / (stem + ".mid")
    mid.write_bytes(midi_service.write_midi(notes, bpm))
    xm = manager.xml_dir() / (stem + ".musicxml")
    xm.write_text(musicxml_service.build_musicxml(notes, bpm, path.stem), encoding="utf-8")
    return {"kind": "transcribe", "engine": used, "sha": digest, "artifact": stem, "count": len(notes), "bpm": bpm}


def _restore(params):
    path = _safe_audio_path(params)
    data = path.read_bytes()
    out, report = restoration_service.restore(data)
    digest = manager.sha256_bytes(data)
    dest = manager.restored_dir() / (digest + "_restored.wav")
    if not dest.exists():
        dest.write_bytes(out)
    report["sha"] = digest
    return report


def _instruments(params):
    path = _safe_audio_path(params)
    return instrument_service.detect(path.read_bytes())


JOBS = {"transcribe": _transcribe, "restore": _restore, "instruments": _instruments}


def run(kind: str, params: dict):
    fn = JOBS.get(kind)
    if fn is None:
        raise ValueError("unknown kind: " + kind)
    return fn(params)


def run_job(task_id: str, kind: str, params: dict):
    db = SessionLocal()
    try:
        crud.update_task(db, task_id, status="running")
        result = run(kind, params)
        crud.update_task(db, task_id, status="done", result=result, finished=True)
        return result
    except Exception as e:
        crud.update_task(db, task_id, status="error", error=str(e), finished=True)
        raise
    finally:
        db.close()
