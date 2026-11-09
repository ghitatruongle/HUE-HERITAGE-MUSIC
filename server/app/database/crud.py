from __future__ import annotations

import json
import threading

from sqlalchemy import exc  # noqa: F401 — dùng exc.IntegrityError ở record_artifact_owner
from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import func, or_
from .models import HeritageItem, AudioFile, User, Task, PracticeSession, CrashReport, ArtifactOwner


METADATA_FIELDS = [
    "genre", "composer", "performers", "artisans", "collector", "recorded_time",
    "location", "source", "license", "lyrics", "instruments", "tonal", "description", "notes",
    "mode_system", "verse_structure", "rhyme_guide", "lyrics_with_ornaments",
    "is_instrumental", "audio_backing_path", "featured_in_creation",
]

SEARCH_FIELDS = [
    "title", "type", "genre", "artist", "composer", "performers", "artisans",
    "collector", "recorded_time", "location", "instruments", "description",
    "mode_system", "verse_structure",
]


def get_item(db: Session, item_id: str):
    return db.get(HeritageItem, item_id)


def get_by_sha(db: Session, sha: str):
    return db.query(HeritageItem).filter(HeritageItem.sha256 == sha).first()


def is_admin_user(user) -> bool:
    if user is None:
        return False
    if (user.role or "user") != "admin":
        return False
    from ..config import settings

    return user.username == settings.admin_truong_username


def _visibility_filter(viewer):
    if is_admin_user(viewer):
        return None
    return or_(HeritageItem.visibility.is_(None), HeritageItem.visibility == "public")


def can_view_item(item, viewer) -> bool:
    if item is None:
        return False
    if is_admin_user(viewer):
        return True
    return (getattr(item, "visibility", None) or "public") == "public"


def _search_filter(q: str):
    if not q:
        return None
    like = "%" + q + "%"
    return or_(*[getattr(HeritageItem, f).like(like) for f in SEARCH_FIELDS])


def _clamp_offset(offset: int) -> int:
    return max(0, min(int(offset), 10**9))


def list_items(db: Session, q: str = "", limit: int = 50, offset: int = 0, viewer=None):
    query = db.query(HeritageItem)
    vf = _visibility_filter(viewer)
    if vf is not None:
        query = query.filter(vf)
    sf = _search_filter(q)
    if sf is not None:
        query = query.filter(sf)
    return (
        query.order_by(HeritageItem.created_at.desc())
        .offset(_clamp_offset(offset))
        .limit(max(1, int(limit)))
        .all()
    )


def count_items(db: Session, q: str = "", viewer=None) -> int:
    query = db.query(HeritageItem)
    vf = _visibility_filter(viewer)
    if vf is not None:
        query = query.filter(vf)
    sf = _search_filter(q)
    if sf is not None:
        query = query.filter(sf)
    return query.count()


def get_creation_tunes(db: Session, viewer=None):
    query = db.query(HeritageItem).filter(HeritageItem.featured_in_creation.is_(True))
    vf = _visibility_filter(viewer)
    if vf is not None:
        query = query.filter(vf)
    return query.order_by(HeritageItem.title.asc()).all()


def update_item_metadata(db: Session, item_id: str, **fields):
    item = db.get(HeritageItem, item_id)
    if not item:
        return None
    for k, v in fields.items():
        if hasattr(item, k) and v is not None:
            setattr(item, k, v)
    db.commit()
    db.refresh(item)
    return item


def create_item(db: Session, title: str, type: str, sha256: str, filename: str, size: int, artist: str = "", owner_user_id: Optional[str] = None, visibility: str = "public", **metadata):
    fields = {k: v for k, v in metadata.items() if k != "bpm"}
    item = HeritageItem(
        title=title, type=type, artist=artist, sha256=sha256, filename=filename, size=size,
        bpm=metadata.get("bpm"),
        owner_user_id=owner_user_id,
        visibility=visibility if visibility in ("public", "admin_only") else "public",
        **fields,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def create_audio(db: Session, item_id: str, kind: str, path: str, sha256: str, size: int):
    audio = AudioFile(item_id=item_id, kind=kind, path=path, sha256=sha256, size=size)
    db.add(audio)
    db.commit()
    db.refresh(audio)
    return audio


def has_audio(db: Session, item_id: str, kind: str, path: str):
    return db.query(AudioFile).filter(AudioFile.item_id == item_id, AudioFile.kind == kind, AudioFile.path == path).first() is not None


def get_user(db: Session, username: str):
    return db.query(User).filter(User.username == username).first()


def get_user_by_email(db: Session, email: str):
    return db.query(User).filter(User.email == email).first()


def get_user_by_identifier(db: Session, identifier: str):
    val = identifier.strip()
    if "@" in val:
        return get_user_by_email(db, val.lower())
    return get_user(db, val)


def get_user_by_id(db: Session, user_id: str):
    return db.get(User, user_id)


def list_users(db: Session, limit: int = 0, offset: int = 0):
    base = db.query(User).order_by(User.created_at)
    total = base.count()
    query = base
    if offset and int(offset) > 0:
        query = query.offset(_clamp_offset(offset))
    if limit and int(limit) > 0:
        query = query.limit(max(1, int(limit)))
    rows = query.all()
    return total, [
        {
            "id": u.id,
            "username": u.username,
            "email": u.email,
            "role": u.role or "user",
            "active": (u.active if u.active is not None else 1) == 1,
            "must_change_password": bool(getattr(u, "must_change_password", 0)),
            "created_at": str(u.created_at),
        }
        for u in rows
    ]


def bump_token_epoch(db: Session, user_id: str) -> int:
    """Tăng epoch NGUYÊN TỬ (UPDATE trong SQL) — race giữa các luồng không mất increments."""
    from sqlalchemy import update

    result = db.execute(
        update(User).where(User.id == user_id).values(token_epoch=User.token_epoch + 1)
    )
    db.commit()
    if result.rowcount == 0:
        return 0
    db.expire_all()
    user = db.get(User, user_id)
    return user.token_epoch if user else 0


def delete_user_everything(db: Session, user_id: str):
    """Xóa tài khoản + gỡ user_id khỏi task (dữ liệu di sản dùng chung giữ nguyên)."""
    from ..database.models import Task
    user = db.get(User, user_id)
    if not user:
        return False
    db.query(Task).filter(Task.user_id == user_id).update({Task.user_id: None})
    db.query(PracticeSession).filter(PracticeSession.user_id == user_id).delete()
    db.delete(user)
    db.commit()
    return True


def _utf8_safe(value: str) -> str:
    return (value or "").encode("utf-8", "replace").decode("utf-8")


def create_crash_report(db: Session, user_id: Optional[str], app_version: str, platform: str, summary: str, detail: str) -> str:
    row = CrashReport(
        user_id=user_id,
        app_version=_utf8_safe(app_version)[:64],
        platform=_utf8_safe(platform)[:64],
        summary=_utf8_safe(summary)[:500],
        detail=_utf8_safe(detail),
    )
    db.add(row)
    db.commit()
    return row.id


def list_crash_reports(db: Session, limit: int = 100, offset: int = 0):
    return (
        db.query(CrashReport)
        .order_by(CrashReport.created_at.desc())
        .offset(max(0, offset))
        .limit(max(1, min(500, limit)))
        .all()
    )


def clear_crash_reports(db: Session) -> int:
    deleted = db.query(CrashReport).delete()
    db.commit()
    return deleted


def prune_old_crash_reports(db: Session, retention_days: int) -> int:
    if retention_days <= 0:
        return 0
    cutoff = datetime.utcnow() - timedelta(days=retention_days)
    deleted = db.query(CrashReport).filter(CrashReport.created_at < cutoff).delete()
    db.commit()
    return deleted


def user_storage_bytes(db: Session, user_id: Optional[str]) -> int:
    if not user_id:
        return 0
    total = (
        db.query(func.coalesce(func.sum(AudioFile.size), 0))
        .join(HeritageItem, HeritageItem.id == AudioFile.item_id)
        .filter(HeritageItem.owner_user_id == user_id)
        .filter(AudioFile.kind == "original")
        .scalar()
    )
    return int(total or 0)


def set_user_active(db: Session, user_id: str, active: bool):
    user = db.get(User, user_id)
    if not user:
        return None
    user.active = 1 if active else 0
    db.commit()
    db.refresh(user)
    return user


def reset_user_password(db: Session, user_id: str, password_hash: str):
    user = db.get(User, user_id)
    if not user:
        return None
    user.password_hash = password_hash
    db.commit()
    db.refresh(user)
    return user


def create_user(db: Session, username: str, password_hash: str, email: str = "", must_change_password: bool = False):
    from sqlalchemy.exc import IntegrityError
    safe_email = email.strip() or f"{username}@no-email.local"
    user = User(username=username, email=safe_email, password_hash=password_hash, must_change_password=1 if must_change_password else 0)
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise
    db.refresh(user)
    return user


def set_must_change_password(db: Session, user_id: str, flag: bool):
    user = db.get(User, user_id)
    if not user:
        return None
    user.must_change_password = 1 if flag else 0
    db.commit()
    db.refresh(user)
    return user


def delete_heritage_item(db: Session, item_id: str):
    item = db.get(HeritageItem, item_id)
    if not item:
        return None
    db.delete(item)
    db.commit()
    return item


def update_user_password(db: Session, user_id: str, password_hash: str):
    user = db.get(User, user_id)
    if not user:
        return None
    user.password_hash = password_hash
    db.commit()
    db.refresh(user)
    return user


def create_invite_code(db: Session, code: str, note: str = ""):
    from ..database.models import InviteCode
    row = InviteCode(code=code, note=note)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def get_invite_code(db: Session, code: str):
    from ..database.models import InviteCode
    return db.query(InviteCode).filter(InviteCode.code == code).first()


def mark_invite_used(db: Session, code: str, user_id: str) -> bool:
    from ..database.models import InviteCode
    from sqlalchemy import update
    from datetime import datetime
    result = db.execute(
        update(InviteCode)
        .where(InviteCode.code == code, InviteCode.used_by.is_(None))
        .values(used_by=user_id, used_at=datetime.now())
    )
    db.commit()
    return result.rowcount > 0


def unused_invite_codes(db: Session):
    from ..database.models import InviteCode
    return [row.code for row in db.query(InviteCode).filter(InviteCode.used_by.is_(None)).all()]


def create_task(db: Session, kind: str, params: Optional[dict] = None, user_id: Optional[str] = None):
    task = Task(kind=kind, params_json=json.dumps(params or {}), user_id=user_id)
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def update_task(db: Session, task_id: str, status: Optional[str] = None, result: Optional[dict] = None, error: Optional[str] = None, finished: bool = False):
    task = db.get(Task, task_id)
    if not task:
        return None
    if status is not None:
        task.status = status
    if result is not None:
        task.result_json = json.dumps(result)
    if error is not None:
        task.error = error
    if finished:
        task.finished_at = datetime.now()
    db.commit()
    db.refresh(task)
    return task


def get_task(db: Session, task_id: str):
    return db.get(Task, task_id)


def list_tasks(db: Session, kind: str = "", status: str = "", limit: int = 100, user_id: Optional[str] = None):
    query = db.query(Task)
    if kind:
        query = query.filter(Task.kind == kind)
    if status:
        query = query.filter(Task.status == status)
    if user_id is not None:
        query = query.filter(Task.user_id == user_id)
    return query.order_by(Task.created_at.desc()).limit(limit).all()


def fail_stale_running_tasks(db: Session, reason: str = "interrupted by server restart"):
    stale = db.query(Task).filter(Task.status == "running").all()
    for task in stale:
        task.status = "error"
        task.error = reason
        task.finished_at = datetime.now()
    db.commit()
    return len(stale)


def prune_old_tasks(db: Session, days: int = 30) -> int:
    if days <= 0:
        return 0
    from datetime import timedelta

    cutoff = datetime.now() - timedelta(days=int(days))
    query = db.query(Task).filter(Task.finished_at.isnot(None), Task.finished_at < cutoff)
    count = query.count()
    if count:
        query.delete(synchronize_session=False)
        db.commit()
    return count


def create_practice_session(
    db: Session,
    user_id: Optional[str],
    lesson_id: str,
    section: int,
    score: float,
    pitch_score: float,
    rhythm_score: float,
    stability_score: float,
    reference: str = "original",
    metrics: Optional[dict] = None,
    user_midi: str = "",
):
    row = PracticeSession(
        user_id=user_id,
        lesson_id=lesson_id,
        section=int(section),
        score=float(score or 0.0),
        pitch_score=float(pitch_score or 0.0),
        rhythm_score=float(rhythm_score or 0.0),
        stability_score=float(stability_score or 0.0),
        reference=reference or "original",
        metrics_json=json.dumps(metrics or {}),
        user_midi=user_midi or "",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def get_practice_session_by_midi(db: Session, midi_name: str):
    return db.query(PracticeSession).filter(PracticeSession.user_midi == midi_name).first()


_artifact_owner_lock = threading.Lock()


def record_artifact_owner(db: Session, sha256: str, user_id: Optional[str], kind: str = ""):
    with _artifact_owner_lock:
        row = db.get(ArtifactOwner, sha256)
        if row is not None:
            if user_id and not row.user_id:
                row.user_id = user_id
                row.kind = kind or row.kind
                db.commit()
            return row
        row = ArtifactOwner(sha256=sha256, user_id=user_id, kind=kind)
        try:
            db.add(row)
            db.commit()
            return row
        except exc.IntegrityError:
            db.rollback()
            row = db.get(ArtifactOwner, sha256)
            if row is not None:
                if user_id and not row.user_id:
                    row.user_id = user_id
                    row.kind = kind or row.kind
                    db.commit()
                return row
            raise


def get_artifact_owner(db: Session, sha256: str):
    return db.get(ArtifactOwner, sha256)


def list_practice_sessions(db: Session, user_id: str, lesson_id: Optional[str] = None, limit: int = 100):
    query = db.query(PracticeSession).filter(PracticeSession.user_id == user_id)
    if lesson_id:
        query = query.filter(PracticeSession.lesson_id == lesson_id)
    return query.order_by(PracticeSession.created_at.desc(), PracticeSession.id.desc()).limit(max(1, min(int(limit), 500))).all()


def practice_session_to_dict(row: PracticeSession) -> dict:
    return {
        "id": row.id,
        "user_id": row.user_id,
        "lesson_id": row.lesson_id,
        "section": row.section,
        "score": row.score,
        "pitch_score": row.pitch_score,
        "rhythm_score": row.rhythm_score,
        "stability_score": row.stability_score,
        "reference": row.reference,
        "metrics": _safe_json_loads(row.metrics_json),
        "created_at": str(row.created_at),
    }


def learning_stats(db: Session, limit: int = 50) -> dict:
    from datetime import timedelta, timezone
    from sqlalchemy import func as _func

    total = db.query(PracticeSession).count()
    active_users = db.query(PracticeSession.user_id).filter(PracticeSession.user_id.isnot(None)).distinct().count()
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=7)
    recent = db.query(PracticeSession).filter(PracticeSession.created_at >= cutoff).count()
    rows = (
        db.query(
            PracticeSession.lesson_id,
            _func.count(PracticeSession.id),
            _func.avg(PracticeSession.score),
        )
        .group_by(PracticeSession.lesson_id)
        .order_by(_func.count(PracticeSession.id).desc())
        .limit(max(1, min(int(limit), 200)))
        .all()
    )
    hardest = (
        db.query(
            PracticeSession.lesson_id,
            _func.avg(PracticeSession.score),
        )
        .group_by(PracticeSession.lesson_id)
        .having(_func.count(PracticeSession.id) >= 3)
        .order_by(_func.avg(PracticeSession.score).asc())
        .limit(5)
        .all()
    )
    return {
        "total_sessions": total,
        "active_users": active_users,
        "sessions_last_7d": recent,
        "by_lesson": [
            {"lesson_id": lid, "sessions": cnt, "avg_score": round(float(avg or 0.0), 1)}
            for lid, cnt, avg in rows
        ],
        "hardest_lessons": [
            {"lesson_id": lid, "avg_score": round(float(avg or 0.0), 1)}
            for lid, avg in hardest
        ],
    }


def _safe_json_loads(val: str) -> dict:
    if not val:
        return {}
    try:
        data = json.loads(val)
        return data if isinstance(data, dict) else {"data": data}
    except Exception:
        return {}


def task_to_dict(task: Task):
    return {
        "id": task.id,
        "kind": task.kind,
        "status": task.status,
        "params": _safe_json_loads(task.params_json),
        "result": _safe_json_loads(task.result_json),
        "error": task.error or "",
        "user_id": task.user_id,
        "created_at": str(task.created_at),
        "finished_at": str(task.finished_at) if task.finished_at else None,
    }
