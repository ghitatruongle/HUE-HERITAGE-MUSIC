from __future__ import annotations

import shutil
import time
from pathlib import Path

from sqlalchemy.orm import Session

from ..config import settings
from ..database import crud
from ..database.models import HeritageItem


def _cleanup_dir(dir_path: Path, retention_days: int, exclude_subdirs: set | None = None) -> dict:
    freed = 0
    count = 0
    if retention_days <= 0 or not dir_path.exists():
        return {"files": count, "bytes": freed}
    skip = exclude_subdirs or set()
    now = time.time()
    for f in dir_path.rglob("*"):
        try:
            rel = f.relative_to(dir_path)
            if skip and len(rel.parts) > 1 and rel.parts[0] in skip:
                continue
            if f.is_file() and f.name != ".gitkeep" and now - f.stat().st_mtime > retention_days * 86400:
                size = f.stat().st_size
                f.unlink()
                freed += size
                count += 1
        except OSError:
            pass
    return {"files": count, "bytes": freed}


def _cleanup_orphan_lesson_samples(db: Session) -> dict:
    freed = 0
    count = 0
    root = Path(settings.storage_dir) / "heritage" / "lesson_samples"
    if not root.exists():
        return {"dirs": count, "bytes": freed}
    for d in root.iterdir():
        try:
            if not d.is_dir():
                continue
            if d.name in {row for (row,) in db.query(HeritageItem.sha256).all()}:
                continue
            size = sum(f.stat().st_size for f in d.rglob("*") if f.is_file())
            shutil.rmtree(d, ignore_errors=True)
            freed += size
            count += 1
        except OSError:
            pass
    return {"dirs": count, "bytes": freed}


def run_storage_cleanup(db: Session) -> dict:
    storage_root = Path(settings.storage_dir)
    return {
        "generated": _cleanup_dir(storage_root / "generated", settings.generated_retention_days),
        "practice_midi": _cleanup_dir(storage_root / "heritage" / "midi", settings.practice_midi_retention_days),
        "analysis": _cleanup_dir(
            storage_root / "analysis", settings.analysis_retention_days, exclude_subdirs={"lessons"}
        ),
        "lesson_cache": _cleanup_dir(storage_root / "analysis" / "lessons", settings.lesson_cache_retention_days),
        "restored": _cleanup_dir(storage_root / "heritage" / "restored", settings.restored_retention_days),
        "musicxml": _cleanup_dir(storage_root / "heritage" / "musicxml", settings.musicxml_retention_days),
        "lesson_samples_orphan": _cleanup_orphan_lesson_samples(db),
    }


def _prune_ghost_audio_rows(db: Session) -> dict:
    from ..database.models import AudioFile

    removed = 0
    rows = db.query(AudioFile).filter(AudioFile.kind != "original").all()
    for row in rows:
        try:
            if not Path(row.path).exists():
                db.delete(row)
                removed += 1
        except OSError:
            continue
    if removed:
        db.commit()
    return {"rows": removed}


def run_db_prune(db: Session) -> dict:
    return {
        "tasks": {"deleted": crud.prune_old_tasks(db, settings.task_retention_days)},
        "crash_reports": {"deleted": crud.prune_old_crash_reports(db, settings.crash_report_retention_days)},
        "ghost_audio_rows": _prune_ghost_audio_rows(db),
    }


def run_maintenance(db: Session) -> dict:
    details = run_storage_cleanup(db)
    details.update(run_db_prune(db))
    freed_bytes = sum(v.get("bytes", 0) for v in details.values() if isinstance(v, dict))
    return {"freed_bytes": freed_bytes, "details": details}
