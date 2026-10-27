import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path

from .config import BASE_DIR

LOG_DIR = BASE_DIR / "logs"
LOG_FILE = Path(os.environ.get("HUE_SECURITY_LOG") or (LOG_DIR / "security.log"))
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
