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
        if len(_hits) > 10000:
            for k in [k for k, q in _hits.items() if not q]:
                _hits.pop(k, None)
        return True


def reset() -> None:
    with _lock:
        _hits.clear()
