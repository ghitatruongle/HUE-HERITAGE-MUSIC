from ..database.session import SessionLocal
from ..database import crud
from ..services import instrument_service, media_pipeline
from ..storage import manager
from pathlib import Path

MAX_BYTES = manager.MAX_ANALYSIS_BYTES


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
    notes, used, _ = media_pipeline.extract_notes(data, bpm, params.get("engine", "basic_pitch"))
    digest, stem, _, _ = media_pipeline.write_artifacts(data, notes, bpm, path.stem)
    return {"kind": "transcribe", "engine": used, "sha": digest, "artifact": stem, "count": len(notes), "bpm": bpm}


def _restore(params):
    path = _safe_audio_path(params)
    report, _ = media_pipeline.restore_audio(path.read_bytes())
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
