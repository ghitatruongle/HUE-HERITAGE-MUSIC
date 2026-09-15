from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from ..config import settings


class Base(DeclarativeBase):
    pass


engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False, "timeout": 30},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

MIGRATION_COLUMNS = {
    "users": {"password_hash": "VARCHAR(256) DEFAULT '' NOT NULL"},
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


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
