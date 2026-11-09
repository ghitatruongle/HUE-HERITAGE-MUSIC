from __future__ import annotations

import logging
import queue
import threading


class WorkerPool:
    def __init__(self, name: str, size: int):
        self.name = name
        self._size = max(1, size)
        self._q: queue.Queue = queue.Queue()
        self._lock = threading.Lock()
        self._started = 0

    def submit(self, fn) -> None:
        self._q.put(fn)
        self._ensure_worker()

    def _ensure_worker(self) -> None:
        with self._lock:
            if self._started < self._size:
                self._started += 1
                threading.Thread(
                    target=self._worker, daemon=True, name=f"hue-{self.name}-{self._started}"
                ).start()

    def _worker(self) -> None:
        log = logging.getLogger(__name__)
        while True:
            fn = self._q.get()
            try:
                fn()
            except Exception:
                log.exception("hue-%s task failed", self.name)
            except BaseException:
                log.exception("hue-%s task raised BaseException — worker continues", self.name)
            finally:
                self._q.task_done()


_pools: dict = {}
_pools_lock = threading.Lock()


def get_pool(name: str, size: int) -> WorkerPool:
    with _pools_lock:
        pool = _pools.get(name)
        if pool is None:
            pool = WorkerPool(name, size)
            _pools[name] = pool
        return pool
