import asyncio
import threading
import weakref

from ..config import settings

_LOCK = threading.Lock()
_INFLIGHT: dict = {}
_DSP_SEMS_LOCK = threading.Lock()
_DSP_SEMS: weakref.WeakKeyDictionary = weakref.WeakKeyDictionary()

HEAVY_INFLIGHT_PER_USER = 2


def _dsp_semaphore():
    loop = asyncio.get_running_loop()
    cap = max(1, int(settings.worker_threads))
    with _DSP_SEMS_LOCK:
        entry = _DSP_SEMS.get(loop)
        if entry is None or entry[0] != cap:
            entry = (cap, asyncio.Semaphore(cap))
            _DSP_SEMS[loop] = entry
        return entry[1]


async def run_dsp(fn, *args, **kwargs):
    sem = _dsp_semaphore()
    async with sem:
        return await asyncio.to_thread(fn, *args, **kwargs)


def user_key(prefix: str, user_id) -> str:
    if not user_id:
        return ""
    return f"{prefix}:{user_id}"


def try_acquire(key: str, limit: int | None = None) -> bool:
    if not key:
        return True
    if limit is None:
        limit = max(1, int(getattr(settings, "heavy_inflight_per_user", HEAVY_INFLIGHT_PER_USER)))
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
