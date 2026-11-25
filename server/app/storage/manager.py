import hashlib
from pathlib import Path
from fastapi import HTTPException
from ..config import settings

ALLOWED_EXT = {".wav", ".mp3", ".flac", ".m4a", ".ogg"}
MAX_SIZE = max(1, int(settings.heritage_upload_max_bytes))
MAX_ANALYSIS_BYTES = max(1, int(settings.large_body_limit))


async def read_upload_limited(file, max_bytes: int, chunk_size: int = 1024 * 1024) -> bytes:
    chunks = []
    total = 0
    while True:
        step = min(chunk_size, max_bytes + 1 - total)
        chunk = await file.read(step)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(status_code=413, detail="file too large")
        chunks.append(chunk)
    data = b"".join(chunks)
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    return data


def original_dir() -> Path:
    d = settings.storage_dir / "heritage" / "original"
    d.mkdir(parents=True, exist_ok=True)
    return d


def temp_dir() -> Path:
    d = settings.storage_dir / "temp"
    d.mkdir(parents=True, exist_ok=True)
    return d


def midi_dir() -> Path:
    d = settings.storage_dir / "heritage" / "midi"
    d.mkdir(parents=True, exist_ok=True)
    return d


def xml_dir() -> Path:
    d = settings.storage_dir / "heritage" / "musicxml"
    d.mkdir(parents=True, exist_ok=True)
    return d


def restored_dir() -> Path:
    d = settings.storage_dir / "heritage" / "restored"
    d.mkdir(parents=True, exist_ok=True)
    return d


def generated_dir() -> Path:
    d = settings.storage_dir / "generated"
    d.mkdir(parents=True, exist_ok=True)
    return d


def lesson_samples_dir(item_sha: str) -> Path:
    import re

    safe = item_sha or ""
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", safe):
        raise ValueError("bad lesson sample key")
    d = settings.storage_dir / "heritage" / "lesson_samples" / safe
    d.mkdir(parents=True, exist_ok=True)
    return d


def lesson_sample_path(item_sha: str, section: int) -> Path:
    return lesson_samples_dir(item_sha) / f"{int(section):02d}.wav"


def save_lesson_sample(item_sha: str, section: int, data: bytes) -> Path:
    if not data or len(data) > MAX_ANALYSIS_BYTES:
        raise ValueError("sample too large")
    if not audio_magic_ok(".wav", data[:12]):
        raise ValueError("not a wav file")
    dest = lesson_sample_path(item_sha, section)
    import os
    import tempfile

    fd, tmp = tempfile.mkstemp(dir=lesson_samples_dir(item_sha), suffix=".part")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, dest)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return dest


def delete_lesson_sample(item_sha: str, section: int) -> bool:
    path = lesson_sample_path(item_sha, section)
    if path.exists():
        path.unlink()
        return True
    return False


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_sha256(value: str) -> bool:
    return len(value) == 64 and all(c in "0123456789abcdef" for c in value.lower())


def audio_magic_ok(ext: str, head: bytes) -> bool:
    ext = ext.lower()
    if ext == ".wav":
        if len(head) < 12 or head[:4] != b"RIFF" or head[8:12] != b"WAVE":
            return False
        if head[4:8] == b"\x00\x00\x00\x00":
            return False
        return True
    if ext == ".flac":
        return head[:4] == b"fLaC"
    if ext == ".ogg":
        return head[:4] == b"OggS"
    if ext == ".m4a":
        return len(head) >= 8 and head[4:8] == b"ftyp"
    if ext == ".mp3":
        return head[:3] == b"ID3" or (len(head) >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0)
    return True


def save_original(data: bytes, filename: str):
    import os
    import tempfile
    ext = Path(filename).suffix.lower()
    digest = sha256_bytes(data)
    dest = original_dir() / (digest + ext)
    if dest.exists():
        return dest, digest, False
    fd, tmp = tempfile.mkstemp(dir=original_dir(), suffix=".part")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, dest)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return dest, digest, True


COMPARE_BODY_LIMIT = 2 * MAX_ANALYSIS_BYTES + 2 * 1024 * 1024


def content_length_exceeds(request, max_bytes: int) -> bool:
    try:
        raw = request.headers.get("content-length")
        return bool(raw) and raw.strip().isdigit() and int(raw) > max_bytes
    except Exception:
        return False


def safe_original_name(filename: str) -> bool:
    if not filename or "\0" in filename or "/" in filename or "\\" in filename:
        return False
    name = Path(filename).name
    return name == filename and name not in ("", ".", "..")
