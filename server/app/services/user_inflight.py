import threading

_LOCK = threading.Lock()
_INFLIGHT: dict = {}

HEAVY_INFLIGHT_PER_USER = 2


def user_key(prefix: str, user_id) -> str:
    if not user_id:
        return ""
    return f"{prefix}:{user_id}"


def try_acquire(key: str, limit: int = HEAVY_INFLIGHT_PER_USER) -> bool:
    if not key:
        return True
    with _LOCK:
        current = _INFLIGHT.get(key, 0)
        if current >= limit:
            return False
        _INFLIGHT[key] = current + 1
        return True


def release(key: str) -> None:
    if not key:
        return
    with _LOCK:
        remaining = _INFLIGHT.get(key, 0) - 1
        if remaining <= 0:
            _INFLIGHT.pop(key, None)
        else:
            _INFLIGHT[key] = remaining


def reset() -> None:
    with _LOCK:
        _INFLIGHT.clear()


def current(key: str) -> int:
    with _LOCK:
        return _INFLIGHT.get(key, 0)
