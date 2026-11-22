import os
import subprocess
import sys
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parents[1]

PROBE = (
    "import sys; sys.path.insert(0, {server!r});"
    "from app.api.auth import AVATAR_MAX_BYTES, AVATAR_MAX_PIXELS;"
    "from app.services.compare_service import MAX_COMPARE_SECONDS;"
    "from app.audio_access import SIGNED_URL_TTL_SECONDS;"
    "from app.storage.manager import MAX_SIZE;"
    "from app.main import LARGE_BODY_LIMIT;"
    "from app.config import settings as s;"
    "print(s.thread_limiter_tokens, AVATAR_MAX_BYTES, AVATAR_MAX_PIXELS,"
    " MAX_COMPARE_SECONDS, SIGNED_URL_TTL_SECONDS, MAX_SIZE, LARGE_BODY_LIMIT)"
).format(server=str(SERVER_DIR))

FIELDS = [
    "thread_limiter_tokens",
    "avatar_max_bytes",
    "avatar_max_pixels",
    "compare_max_seconds",
    "signed_url_ttl_seconds",
    "heritage_upload_max_bytes",
    "large_body_limit",
]

DEFAULTS = ["192", "2097152", "40000000", "35.0", "21600", "52428800", "15728640"]


def _run(env_overrides: dict):
    env = dict(os.environ)
    env.update(env_overrides)
    return subprocess.run(
        [sys.executable, "-c", PROBE],
        capture_output=True,
        text=True,
        env=env,
        timeout=120,
    )


def test_env_tunables_default_values():
    r = _run({})
    assert r.returncode == 0, r.stderr
    got = r.stdout.split()
    assert got == DEFAULTS, f"default lệch: {got}"


def test_env_tunables_env_overrides_follow(monkeypatch):
    overrides = {
        "THREAD_LIMITER_TOKENS": "64",
        "AVATAR_MAX_BYTES": "1024",
        "AVATAR_MAX_PIXELS": "8000000",
        "COMPARE_MAX_SECONDS": "20.5",
        "SIGNED_URL_TTL_SECONDS": "600",
        "HERITAGE_UPLOAD_MAX_BYTES": "1048576",
        "LARGE_BODY_LIMIT": "10485760",
    }
    for k in overrides:
        monkeypatch.setenv(k, overrides[k])
    r = _run(overrides)
    assert r.returncode == 0, r.stderr
    got = r.stdout.split()
    assert got == [
        "64",
        "1024",
        "8000000",
        "20.5",
        "600",
        "1048576",
        "10485760",
    ], f"env override không ăn vào module: {got}"


def test_env_example_documents_new_knobs():
    text = (SERVER_DIR / ".env.example").read_text()
    for k in FIELDS:
        assert k.upper() in text, f".env.example thiếu {k.upper()}"
