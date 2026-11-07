import threading

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from ..config import settings


class Base(DeclarativeBase):
    pass


engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False, "timeout": 30},
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=60,
)


@event.listens_for(engine, "connect")
def _set_sqlite_pragmas(dbapi_connection, connection_record):
    if not settings.database_url.startswith("sqlite"):
        return
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.execute("PRAGMA busy_timeout=30000")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

write_slot = threading.BoundedSemaphore(8)


def acquire_write_slot():
    write_slot.acquire()
    try:
        yield
    finally:
        write_slot.release()

MIGRATION_COLUMNS = {
    "users": {
        "password_hash": "VARCHAR(256) DEFAULT '' NOT NULL",
        "email": "VARCHAR(256) DEFAULT '' NOT NULL",
        "role": "VARCHAR(16) DEFAULT 'user' NOT NULL",
        "active": "INTEGER DEFAULT 1 NOT NULL",
        "token_epoch": "INTEGER DEFAULT 0 NOT NULL",
        "must_change_password": "INTEGER DEFAULT 0 NOT NULL",
    },
    "heritage_items": {
        "genre": "VARCHAR(128) DEFAULT '' NOT NULL",
        "composer": "VARCHAR(256) DEFAULT '' NOT NULL",
        "performers": "VARCHAR(512) DEFAULT '' NOT NULL",
        "artisans": "VARCHAR(512) DEFAULT '' NOT NULL",
        "collector": "VARCHAR(256) DEFAULT '' NOT NULL",
        "recorded_time": "VARCHAR(128) DEFAULT '' NOT NULL",
        "location": "VARCHAR(256) DEFAULT '' NOT NULL",
        "lyrics": "TEXT DEFAULT '' NOT NULL",
        "instruments": "VARCHAR(512) DEFAULT '' NOT NULL",
        "bpm": "FLOAT",
        "tonal": "VARCHAR(128) DEFAULT '' NOT NULL",
        "description": "TEXT DEFAULT '' NOT NULL",
        "notes": "TEXT DEFAULT '' NOT NULL",
        "mode_system": "VARCHAR(128) DEFAULT '' NOT NULL",
        "verse_structure": "VARCHAR(128) DEFAULT '' NOT NULL",
        "rhyme_guide": "TEXT DEFAULT '' NOT NULL",
        "lyrics_with_ornaments": "TEXT DEFAULT '' NOT NULL",
        "is_instrumental": "BOOLEAN DEFAULT 0 NOT NULL",
        "audio_backing_path": "VARCHAR(512) DEFAULT '' NOT NULL",
        "featured_in_creation": "BOOLEAN DEFAULT 1 NOT NULL",
        "owner_user_id": "VARCHAR(64)",
        "visibility": "VARCHAR(16) DEFAULT 'public' NOT NULL",
    },
    "tasks": {
        "user_id": "VARCHAR(64)",
    },
}


def init_db():
    from . import models
    Base.metadata.create_all(bind=engine)
    insp = inspect(engine)
    for table, cols in MIGRATION_COLUMNS.items():
        if table not in insp.get_table_names():
            continue
        existing = {c["name"] for c in insp.get_columns(table)}
        for col, ddl in cols.items():
            if col not in existing:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {col} {ddl}"))
    _enforce_admin_truong()


def _enforce_admin_truong():
    from ..config import settings
    with engine.begin() as conn:
        row = conn.execute(
            text("SELECT id, role FROM users WHERE username = :name"),
            {"name": settings.admin_truong_username},
        ).first()
        if row is not None and (row.role or "user") != "admin":
            conn.execute(
                text("UPDATE users SET role = 'admin', token_epoch = token_epoch + 1 WHERE id = :id"),
                {"id": row.id},
            )
        conn.execute(
            text("UPDATE users SET role = 'user' WHERE username <> :name AND (role IS NULL OR role <> 'user')"),
            {"name": settings.admin_truong_username},
        )


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
