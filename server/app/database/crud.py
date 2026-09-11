from sqlalchemy.orm import Session
from sqlalchemy import or_
from .models import HeritageItem, AudioFile


def get_item(db: Session, item_id: str):
    return db.get(HeritageItem, item_id)


def get_by_sha(db: Session, sha: str):
    return db.query(HeritageItem).filter(HeritageItem.sha256 == sha).first()


def list_items(db: Session, q: str = "", limit: int = 50):
    query = db.query(HeritageItem)
    if q:
        like = "%" + q + "%"
        query = query.filter(or_(HeritageItem.title.like(like), HeritageItem.artist.like(like), HeritageItem.type.like(like)))
    return query.order_by(HeritageItem.created_at.desc()).limit(limit).all()


def create_item(db: Session, title: str, type: str, artist: str, source: str, license: str, sha256: str, filename: str, size: int):
    item = HeritageItem(title=title, type=type, artist=artist, source=source, license=license, sha256=sha256, filename=filename, size=size)
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
