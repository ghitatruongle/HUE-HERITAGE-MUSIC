import threading
import time
from collections import defaultdict, deque

_lock = threading.Lock()
_hits: dict = defaultdict(deque)


def hit_and_allow(key: str, limit: int, window_seconds: float = 60.0) -> bool:
    now = time.time()
    with _lock:
        queue = _hits[key]
        while queue and now - queue[0] > window_seconds:
            queue.popleft()
        if len(queue) >= limit:
            return False
        queue.append(now)
        return True


def reset() -> None:
    with _lock:
        _hits.clear()
