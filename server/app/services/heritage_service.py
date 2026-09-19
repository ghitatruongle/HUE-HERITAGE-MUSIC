from pathlib import Path
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from ..database import crud
from ..storage import manager


def item_to_dict(item):
    return {
        "id": item.id,
        "title": item.title,
        "type": item.type,
        "genre": item.genre,
        "artist": item.artist,
        "composer": item.composer,
        "performers": item.performers,
        "artisans": item.artisans,
        "collector": item.collector,
        "recorded_time": item.recorded_time,
        "location": item.location,
        "source": item.source,
        "license": item.license,
        "lyrics": item.lyrics,
        "instruments": item.instruments,
        "bpm": item.bpm,
        "tonal": item.tonal,
        "description": item.description,
        "notes": item.notes,
        "mode_system": getattr(item, "mode_system", ""),
        "verse_structure": getattr(item, "verse_structure", ""),
        "rhyme_guide": getattr(item, "rhyme_guide", ""),
        "lyrics_with_ornaments": getattr(item, "lyrics_with_ornaments", ""),
        "is_instrumental": bool(getattr(item, "is_instrumental", False)),
        "audio_backing_path": getattr(item, "audio_backing_path", ""),
        "featured_in_creation": bool(getattr(item, "featured_in_creation", True)),
        "sha256": item.sha256,
        "filename": item.filename,
        "size": item.size,
        "created_at": str(item.created_at),
    }


def ingest_upload(db: Session, data: bytes, filename: str, title: str, type: str, artist: str = "", **metadata):
    path, digest, _ = manager.save_original(data, filename)
    existing = crud.get_by_sha(db, digest)
    if existing:
        return existing, False
    name = title if title else Path(filename).stem
    try:
        item = crud.create_item(db, name, type, digest, path.name, len(data), artist=artist, **metadata)
        crud.create_audio(db, item.id, "original", str(path), digest, len(data))
        return item, True
    except IntegrityError:
        db.rollback()
        existing = crud.get_by_sha(db, digest)
        if existing:
            return existing, False
        raise
