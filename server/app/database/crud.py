from __future__ import annotations

import json
from datetime import datetime
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import or_
from .models import HeritageItem, AudioFile, User, Task


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


def list_items(db: Session, q: str = "", limit: int = 50):
    query = db.query(HeritageItem)
    if q:
        like = "%" + q + "%"
        conds = [getattr(HeritageItem, f).like(like) for f in SEARCH_FIELDS]
        query = query.filter(or_(*conds))
    return query.order_by(HeritageItem.created_at.desc()).limit(limit).all()


def get_creation_tunes(db: Session):
    return db.query(HeritageItem).filter(HeritageItem.featured_in_creation.is_(True)).order_by(HeritageItem.title.asc()).all()


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


def create_item(db: Session, title: str, type: str, sha256: str, filename: str, size: int, artist: str = "", **metadata):
    fields = {k: v for k, v in metadata.items() if k != "bpm"}
    item = HeritageItem(
        title=title, type=type, artist=artist, sha256=sha256, filename=filename, size=size,
        bpm=metadata.get("bpm"), **fields,
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


def list_users(db: Session):
    rows = db.query(User).order_by(User.created_at).all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "email": u.email,
            "role": u.role or "user",
            "created_at": str(u.created_at),
        }
        for u in rows
    ]


def create_user(db: Session, username: str, password_hash: str, email: str = ""):
    from sqlalchemy.exc import IntegrityError
    user = User(username=username, email=email, password_hash=password_hash)
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise
    db.refresh(user)
    return user


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
