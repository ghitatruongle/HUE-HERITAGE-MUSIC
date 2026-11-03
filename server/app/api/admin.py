from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func as sqlfunc
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import acquire_write_slot, get_db
from ..database import crud
from ..database.models import AudioFile, HeritageItem, InviteCode, Task, User
from .. import security_log
from .auth import require_admin, require_admin_fresh

router = APIRouter(prefix="/admin", tags=["admin"])


def _engine_online() -> bool:
    try:
        from ..ai import ace_step_engine

        return ace_step_engine.api_available()
    except Exception:
        return False


@router.get("/stats")
def admin_stats(admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
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
    generated_bytes = 0
    generated_dir = Path(settings.storage_dir) / "generated"
    if generated_dir.exists():
        try:
            generated_bytes = sum(f.stat().st_size for f in generated_dir.rglob("*") if f.is_file())
        except OSError:
            generated_bytes = 0
    return {
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


@router.get("/storage")
def admin_storage(
    q: str = "",
    limit: int = 100,
    admin_id: str = Depends(require_admin),
    db: Session = Depends(get_db),
):
    items = crud.list_items(db, q, max(1, min(limit, 200)))
    original_dir = Path(settings.storage_dir) / "heritage" / "original"
    rows = []
    for item in items:
        files = db.query(AudioFile).filter(AudioFile.item_id == item.id).all()
        derived = [f for f in files if f.kind != "original"]
        rows.append(
            {
                "id": item.id,
                "title": item.title,
                "filename": item.filename,
                "size": item.size,
                "created_at": str(item.created_at),
                "original_exists": (original_dir / item.filename).exists(),
                "derived_files": [{"kind": f.kind, "size": f.size} for f in derived],
                "derived_bytes": sum(f.size for f in derived),
            }
        )
    return {
        "items_total": db.query(HeritageItem).count(),
        "count": len(rows),
        "items": rows,
    }


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
    security_log.security_event("storage_item_deleted", admin=admin_id, item_id=item_id, title=item.title)
    return {"deleted": item_id, "title": item.title, "files_removed": removed}
