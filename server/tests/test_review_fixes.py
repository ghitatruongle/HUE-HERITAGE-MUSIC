import time
from collections import deque

from app.main import LARGE_BODY_PATHS
from app import rate_limit as rl


def test_evaluate_in_large_body_paths():
    assert "/api/music/evaluate" in LARGE_BODY_PATHS


def test_rate_limit_cleanup_removes_stale_keys():
    rl.reset()
    try:
        old = time.time() - 120
        for i in range(3):
            rl._hits[f"stale{i}"] = deque([old])
        for i in range(10000):
            rl._hits[f"k{i}"] = deque([old])
        assert rl.hit_and_allow("fresh", 5, 60.0) is True
        assert not any(k.startswith("stale") for k in rl._hits), "key stale phải bị dọn khi vượt ngưỡng"
        assert len(rl._hits) < 10000
    finally:
        rl.reset()
