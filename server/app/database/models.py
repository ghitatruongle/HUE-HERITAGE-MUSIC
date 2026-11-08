import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Float, Text, DateTime, ForeignKey, Boolean, func, Index
from sqlalchemy.orm import Mapped, mapped_column
from .session import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    username: Mapped[str] = mapped_column(String(128), unique=True)
    email: Mapped[str] = mapped_column(String(256), unique=True, default="")
    password_hash: Mapped[str] = mapped_column(String(256), default="")
    role: Mapped[str] = mapped_column(String(16), default="user")
    active: Mapped[int] = mapped_column(Integer, default=1)
    token_epoch: Mapped[int] = mapped_column(Integer, default=0)
    must_change_password: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class HeritageItem(Base):
    __tablename__ = "heritage_items"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    title: Mapped[str] = mapped_column(String(256))
    type: Mapped[str] = mapped_column(String(128), default="")
    genre: Mapped[str] = mapped_column(String(128), default="")
    artist: Mapped[str] = mapped_column(String(256), default="")
    composer: Mapped[str] = mapped_column(String(256), default="")
    performers: Mapped[str] = mapped_column(String(512), default="")
    artisans: Mapped[str] = mapped_column(String(512), default="")
    collector: Mapped[str] = mapped_column(String(256), default="")
    recorded_time: Mapped[str] = mapped_column(String(128), default="")
    location: Mapped[str] = mapped_column(String(256), default="")
    source: Mapped[str] = mapped_column(String(256), default="")
    license: Mapped[str] = mapped_column(String(256), default="")
    lyrics: Mapped[str] = mapped_column(Text, default="")
    instruments: Mapped[str] = mapped_column(String(512), default="")
    bpm: Mapped[float] = mapped_column(Float, nullable=True)
    tonal: Mapped[str] = mapped_column(String(128), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    notes: Mapped[str] = mapped_column(Text, default="")
    mode_system: Mapped[str] = mapped_column(String(128), default="")
    verse_structure: Mapped[str] = mapped_column(String(128), default="")
    rhyme_guide: Mapped[str] = mapped_column(Text, default="")
    lyrics_with_ornaments: Mapped[str] = mapped_column(Text, default="")
    is_instrumental: Mapped[bool] = mapped_column(Boolean, default=False)
    audio_backing_path: Mapped[str] = mapped_column(String(512), default="")
    featured_in_creation: Mapped[bool] = mapped_column(Boolean, default=True)
    owner_user_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    visibility: Mapped[str] = mapped_column(String(16), default="public")
    sha256: Mapped[str] = mapped_column(String(64), unique=True)
    filename: Mapped[str] = mapped_column(String(256))
    size: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class AudioFile(Base):
    __tablename__ = "audio_files"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    item_id: Mapped[str] = mapped_column(String(36), ForeignKey("heritage_items.id"))
    kind: Mapped[str] = mapped_column(String(32), default="original")
    path: Mapped[str] = mapped_column(String(512))
    sha256: Mapped[str] = mapped_column(String(64))
    size: Mapped[int] = mapped_column(Integer, default=0)


class Task(Base):
    __tablename__ = "tasks"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    kind: Mapped[str] = mapped_column(String(64), default="generic")
    status: Mapped[str] = mapped_column(String(32), default="pending")
    params_json: Mapped[str] = mapped_column(Text, default="")
    result_json: Mapped[str] = mapped_column(Text, default="")
    error: Mapped[str] = mapped_column(Text, default="")
    user_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    finished_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)


class PracticeSession(Base):
    __tablename__ = "practice_sessions"
    __table_args__ = (Index("ix_practice_user_lesson", "user_id", "lesson_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    lesson_id: Mapped[str] = mapped_column(String(64), default="")
    section: Mapped[int] = mapped_column(Integer, default=0)
    score: Mapped[float] = mapped_column(Float, default=0.0)
    pitch_score: Mapped[float] = mapped_column(Float, default=0.0)
    rhythm_score: Mapped[float] = mapped_column(Float, default=0.0)
    stability_score: Mapped[float] = mapped_column(Float, default=0.0)
    reference: Mapped[str] = mapped_column(String(16), default="original")
    metrics_json: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class InviteCode(Base):
    __tablename__ = "invite_codes"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    code: Mapped[str] = mapped_column(String(128), unique=True)
    note: Mapped[str] = mapped_column(String(256), default="")
    used_by: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class CrashReport(Base):
    __tablename__ = "crash_reports"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    app_version: Mapped[str] = mapped_column(String(64), default="")
    platform: Mapped[str] = mapped_column(String(64), default="")
    summary: Mapped[str] = mapped_column(String(512), default="")
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
