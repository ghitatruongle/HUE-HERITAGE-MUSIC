import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path

from .config import BASE_DIR

LOG_DIR = BASE_DIR / "logs"
MAX_BYTES = 5 * 1024 * 1024
BACKUP_COUNT = 3

_logger: logging.Logger | None = None


def _get_logger() -> logging.Logger:
    global _logger
    if _logger is None:
        if os.environ.get("HUE_SECURITY_LOG"):
            target = Path(os.environ["HUE_SECURITY_LOG"])
        else:
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            target = LOG_DIR / "security.log"
        logger = logging.getLogger("hue_security")
        logger.setLevel(logging.INFO)
        handler = RotatingFileHandler(target, encoding="utf-8", maxBytes=MAX_BYTES, backupCount=BACKUP_COUNT)
        handler.setFormatter(logging.Formatter("%(asctime)s\t%(levelname)s\t%(message)s"))
        logger.addHandler(handler)
        logger.propagate = False
        _logger = logger
    return _logger


def security_event(event: str, **fields) -> None:
    parts = [event]
    for key, value in fields.items():
        parts.append(f"{key}={value}")
    _get_logger().info("\t".join(parts))


MAX_SCAN_LINES = 20000


def _log_files():
    if os.environ.get("HUE_SECURITY_LOG"):
        base = Path(os.environ["HUE_SECURITY_LOG"])
    else:
        base = LOG_DIR / "security.log"
    return [base] + [base.with_name(base.name + f".{i}") for i in (1, 2, 3)]


def _parse_line(line: str):
    parts = line.split("\t")
    if len(parts) < 3:
        return None
    fields = {}
    for p in parts[3:]:
        key, _, value = p.partition("=")
        if key:
            fields[key] = value
    return {"ts": parts[0], "level": parts[1], "event": parts[2], "fields": fields}


def read_events(limit: int = 100, offset: int = 0, event: str = "", q: str = "") -> dict:
    matched = []
    scanned = 0
    truncated = False
    for path in _log_files():
        if truncated:
            break
        if not path.exists():
            continue
        try:
            with path.open("r", encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for line in reversed(lines):
            scanned += 1
            if scanned > MAX_SCAN_LINES:
                truncated = True
                break
            line = line.strip()
            if not line:
                continue
            rec = _parse_line(line)
            if rec is None:
                continue
            if event and rec["event"] != event:
                continue
            if q and q.lower() not in line.lower():
                continue
            matched.append(rec)
    return {
        "total": len(matched),
        "truncated": truncated,
        "events": matched[max(0, int(offset)): max(0, int(offset)) + max(1, int(limit))],
    }
