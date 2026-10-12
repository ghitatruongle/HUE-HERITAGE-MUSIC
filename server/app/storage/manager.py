import hashlib
from pathlib import Path
from ..config import settings

ALLOWED_EXT = {".wav", ".mp3", ".flac", ".m4a", ".ogg"}
MAX_SIZE = 50 * 1024 * 1024
MAX_ANALYSIS_BYTES = 15 * 1024 * 1024


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


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_sha256(value: str) -> bool:
    return len(value) == 64 and all(c in "0123456789abcdef" for c in value.lower())


def audio_magic_ok(ext: str, head: bytes) -> bool:
    ext = ext.lower()
    if ext == ".wav":
        return len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"WAVE"
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


def safe_original_name(filename: str) -> bool:
    if not filename or "\0" in filename or "/" in filename or "\\" in filename:
        return False
    name = Path(filename).name
    return name == filename and name not in ("", ".", "..")
