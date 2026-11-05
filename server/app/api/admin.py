import time
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func as sqlfunc
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import acquire_write_slot, get_db
from ..database import crud
from ..database.models import AudioFile, HeritageItem, InviteCode, Task, User
from .. import security_log
from .auth import require_admin, require_admin_fresh

router = APIRouter(prefix="/admin", tags=["admin"])

STATS_TTL_SECONDS = 30.0
GENERATED_TTL_SECONDS = 60.0
_stats_cache: dict = {"data": None, "ts": 0.0, "generated": None, "generated_ts": 0.0}


def invalidate_stats_cache() -> None:
    _stats_cache["data"] = None
    _stats_cache["generated"] = None


def _engine_online() -> bool:
    try:
        from ..ai import ace_step_engine

        return ace_step_engine.api_available()
    except Exception:
        return False


def _scan_generated_bytes() -> int:
    generated_dir = Path(settings.storage_dir) / "generated"
    if not generated_dir.exists():
        return 0
    try:
        return sum(f.stat().st_size for f in generated_dir.rglob("*") if f.is_file())
    except OSError:
        return 0


@router.get("/stats")
def admin_stats(refresh: int = 0, admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    now = time.time()
    if not refresh and _stats_cache["data"] is not None and now - _stats_cache["ts"] < STATS_TTL_SECONDS:
        return _stats_cache["data"]
    users_total = db.query(User).count()
    users_active = db.query(User).filter(User.active == 1).count()
    invites_total = db.query(InviteCode).count()
    invites_unused = db.query(InviteCode).filter(InviteCode.used_by.is_(None)).count()
    items_total = db.query(HeritageItem).count()
    items_bytes = db.query(sqlfunc.coalesce(sqlfunc.sum(HeritageItem.size), 0)).scalar() or 0
    derived_files = db.query(AudioFile).filter(AudioFile.kind != "original").count()
    derived_bytes = (
        db.query(sqlfunc.coalesce(sqlfunc.sum(AudioFile.size), 0))
        .filter(AudioFile.kind != "original")
        .scalar()
        or 0
    )
    tasks_by_status = {row[0] or "unknown": row[1] for row in db.query(Task.status, sqlfunc.count()).group_by(Task.status).all()}
    tasks_by_kind = {row[0] or "unknown": row[1] for row in db.query(Task.kind, sqlfunc.count()).group_by(Task.kind).all()}
    generated_bytes = _stats_cache["generated"]
    if generated_bytes is None or now - _stats_cache["generated_ts"] > GENERATED_TTL_SECONDS:
        generated_bytes = _scan_generated_bytes()
        _stats_cache["generated"] = generated_bytes
        _stats_cache["generated_ts"] = now
    payload = {
        "users": {"total": users_total, "active": users_active},
        "invites": {"total": invites_total, "unused": invites_unused},
        "storage": {
            "items_total": items_total,
            "items_bytes": items_bytes,
            "derived_files": derived_files,
            "derived_bytes": derived_bytes,
            "generated_bytes": generated_bytes,
        },
        "tasks": {"by_status": tasks_by_status, "by_kind": tasks_by_kind},
        "engine_online": _engine_online(),
    }
    _stats_cache["data"] = payload
    _stats_cache["ts"] = now
    return payload


def _admin_user(db: Session, admin_id: str):
    return crud.get_user_by_id(db, admin_id)


@router.get("/storage")
def admin_storage(
    q: str = "",
    limit: int = 100,
    offset: int = 0,
    admin_id: str = Depends(require_admin),
    db: Session = Depends(get_db),
):
    admin_user = _admin_user(db, admin_id)
    lim = max(1, min(limit, 200))
    items = crud.list_items(db, q, lim, offset=max(0, offset), viewer=admin_user)
    total = crud.count_items(db, q, viewer=admin_user)
    item_ids = [i.id for i in items]
    files_map: dict = {}
    if item_ids:
        for f in db.query(AudioFile).filter(AudioFile.item_id.in_(item_ids)).all():
            files_map.setdefault(f.item_id, []).append(f)
    owner_ids = {i.owner_user_id for i in items if getattr(i, "owner_user_id", None)}
    owner_map: dict = {}
    if owner_ids:
        for u in db.query(User).filter(User.id.in_(owner_ids)).all():
            owner_map[u.id] = u.username
    original_dir = Path(settings.storage_dir) / "heritage" / "original"
    rows = []
    for item in items:
        files = files_map.get(item.id, [])
        derived = [f for f in files if f.kind != "original"]
        rows.append(
            {
                "id": item.id,
                "title": item.title,
                "filename": item.filename,
                "size": item.size,
                "created_at": str(item.created_at),
                "original_exists": (original_dir / item.filename).exists(),
                "visibility": getattr(item, "visibility", None) or "public",
                "owner_username": owner_map.get(getattr(item, "owner_user_id", None), ""),
                "derived_files": [{"kind": f.kind, "size": f.size} for f in derived],
                "derived_bytes": sum(f.size for f in derived),
            }
        )
    return {
        "items_total": total,
        "count": len(rows),
        "items": rows,
    }


class VisibilityRequest(BaseModel):
    visibility: str


@router.patch("/storage/{item_id}/visibility")
def admin_set_visibility(
    item_id: str,
    req: VisibilityRequest,
    admin_id: str = Depends(require_admin_fresh),
    db: Session = Depends(get_db),
    _write_slot: None = Depends(acquire_write_slot),
):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="item not found")
    vis = req.visibility.strip()
    if vis not in ("public", "admin_only"):
        raise HTTPException(status_code=400, detail="visibility must be public or admin_only")
    old = getattr(item, "visibility", None) or "public"
    item.visibility = vis
    db.commit()
    db.refresh(item)
    invalidate_stats_cache()
    security_log.security_event(
        "admin_visibility_changed", admin=admin_id, item_id=item_id, title=item.title, old=old, new=vis
    )
    return {"id": item.id, "title": item.title, "visibility": item.visibility}


@router.delete("/storage/{item_id}")
def admin_delete_storage_item(
    item_id: str,
    admin_id: str = Depends(require_admin_fresh),
    db: Session = Depends(get_db),
    _write_slot: None = Depends(acquire_write_slot),
):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="item not found")
    from ..services import lesson_service

    storage_root = Path(settings.storage_dir).resolve()
    removed = []
    files = db.query(AudioFile).filter(AudioFile.item_id == item.id).all()
    for f in files:
        p = Path(f.path)
        try:
            if p.exists() and p.resolve().is_relative_to(storage_root):
                p.unlink()
                removed.append(f.kind)
        except OSError:
            pass
    try:
        cache_file = lesson_service._lesson_cache_path(item)
        if cache_file.exists():
            cache_file.unlink()
            removed.append("lesson_cache")
        section_dir = lesson_service.lessons_dir() / (item.sha256 or item.id)
        if section_dir.exists():
            import shutil

            shutil.rmtree(section_dir, ignore_errors=True)
            removed.append("lesson_sections")
    except Exception:
        pass
    db.query(AudioFile).filter(AudioFile.item_id == item.id).delete()
    crud.delete_heritage_item(db, item_id)
    invalidate_stats_cache()
    security_log.security_event("storage_item_deleted", admin=admin_id, item_id=item_id, title=item.title)
    return {"deleted": item_id, "title": item.title, "files_removed": removed}


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
            if f.is_file() and now - f.stat().st_mtime > retention_days * 86400:
                size = f.stat().st_size
                f.unlink()
                freed += size
                count += 1
        except OSError:
            pass
    return {"files": count, "bytes": freed}


@router.post("/maintenance/cleanup")
def admin_cleanup(
    admin_id: str = Depends(require_admin_fresh),
    db: Session = Depends(get_db),
    _write_slot: None = Depends(acquire_write_slot),
):
    storage_root = Path(settings.storage_dir)
    details = {
        "generated": _cleanup_dir(storage_root / "generated", settings.generated_retention_days),
        "practice_midi": _cleanup_dir(storage_root / "heritage" / "midi", settings.practice_midi_retention_days),
        "analysis": _cleanup_dir(
            storage_root / "analysis", settings.analysis_retention_days, exclude_subdirs={"lessons"}
        ),
        "lesson_cache": _cleanup_dir(storage_root / "analysis" / "lessons", settings.lesson_cache_retention_days),
    }
    tasks_deleted = crud.prune_old_tasks(db, settings.task_retention_days)
    details["tasks"] = {"deleted": tasks_deleted}
    freed_bytes = sum(v["bytes"] for k, v in details.items() if k != "tasks")
    invalidate_stats_cache()
    security_log.security_event(
        "admin_cleanup_run", admin=admin_id, freed_bytes=freed_bytes, tasks_deleted=tasks_deleted
    )
    return {"freed_bytes": freed_bytes, "details": details}


@router.get("/learning/stats")
def admin_learning_stats(admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    return crud.learning_stats(db)


@router.get("/security/events")
def admin_security_events(
    limit: int = 100,
    offset: int = 0,
    event: str = "",
    q: str = "",
    admin_id: str = Depends(require_admin),
):
    lim = max(1, min(limit, 500))
    return security_log.read_events(limit=lim, offset=max(0, offset), event=event.strip(), q=q.strip())


def _parse_log_ts(value: str):
    try:
        return datetime.strptime(value.strip(), "%Y-%m-%d %H:%M:%S,%f")
    except (ValueError, TypeError):
        return None


@router.get("/security/summary")
def admin_security_summary(admin_id: str = Depends(require_admin)):
    data = security_log.read_events(limit=5000, offset=0)
    cutoff = datetime.now() - timedelta(hours=24)
    counts: dict = {}
    last_admin_login = None
    for rec in data["events"]:
        ts = _parse_log_ts(rec["ts"])
        if ts is not None and ts >= cutoff:
            counts[rec["event"]] = counts.get(rec["event"], 0) + 1
        if rec["event"] == "admin_login" and last_admin_login is None:
            last_admin_login = {"ts": rec["ts"], "fields": rec["fields"]}
    return {
        "window_hours": 24,
        "scanned_total": data["total"],
        "truncated": data["truncated"],
        "counts": counts,
        "last_admin_login": last_admin_login,
    }
