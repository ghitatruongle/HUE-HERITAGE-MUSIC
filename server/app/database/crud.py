import json
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import or_
from .models import HeritageItem, AudioFile, User, Task


METADATA_FIELDS = [
    "genre", "composer", "performers", "artisans", "collector", "recorded_time",
    "location", "source", "license", "lyrics", "instruments", "tonal", "description", "notes",
]

SEARCH_FIELDS = [
    "title", "type", "genre", "artist", "composer", "performers", "artisans",
    "collector", "recorded_time", "location", "instruments", "description",
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


def get_user_by_id(db: Session, user_id: str):
    return db.get(User, user_id)


def create_user(db: Session, username: str, password_hash: str):
    from sqlalchemy.exc import IntegrityError
    user = User(username=username, password_hash=password_hash)
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise
    db.refresh(user)
    return user


def create_task(db: Session, kind: str, params: dict | None = None):
    task = Task(kind=kind, params_json=json.dumps(params or {}))
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def update_task(db: Session, task_id: str, status: str | None = None, result: dict | None = None, error: str | None = None, finished: bool = False):
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


def list_tasks(db: Session, kind: str = "", status: str = "", limit: int = 100):
    query = db.query(Task)
    if kind:
        query = query.filter(Task.kind == kind)
    if status:
        query = query.filter(Task.status == status)
    return query.order_by(Task.created_at.desc()).limit(limit).all()


def task_to_dict(task: Task):
    return {
        "id": task.id,
        "kind": task.kind,
        "status": task.status,
        "params": json.loads(task.params_json or "{}"),
        "result": json.loads(task.result_json or "{}"),
        "error": task.error or "",
        "created_at": str(task.created_at),
        "finished_at": str(task.finished_at) if task.finished_at else None,
    }
