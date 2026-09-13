import hashlib
from pathlib import Path
from ..config import settings

ALLOWED_EXT = {".wav", ".mp3", ".flac", ".m4a", ".ogg"}
MAX_SIZE = 50 * 1024 * 1024


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


def save_original(data: bytes, filename: str):
    ext = Path(filename).suffix.lower()
    digest = sha256_bytes(data)
    dest = original_dir() / (digest + ext)
    if dest.exists():
        return dest, digest, False
    dest.write_bytes(data)
    return dest, digest, True


def safe_original_name(filename: str) -> bool:
    name = Path(filename).name
    return name == filename and name not in ("", ".", "..") and "/" not in filename and "\\" not in filename
