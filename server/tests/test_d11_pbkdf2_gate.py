import os
import threading
import time

import pytest

from app.api import auth


def test_pbkdf2_gate_exists_bounded():
    v = auth._PBKDF2_GATE._value
    assert 2 <= v <= 8


def test_pbkdf2_gate_limits_concurrency(monkeypatch):
    peak = {"n": 0}
    cur = {"n": 0}
    lock = threading.Lock()

    real = auth.hashlib.pbkdf2_hmac

    def slow(*a, **k):
        with lock:
            cur["n"] += 1
            peak["n"] = max(peak["n"], cur["n"])
        time.sleep(0.05)
        with lock:
            cur["n"] -= 1
        return b"00" * 32

    monkeypatch.setattr(auth.hashlib, "pbkdf2_hmac", slow)
    limit = max(2, min(8, (os.cpu_count() or 4)))
    threads = [threading.Thread(target=auth.hash_password, args=("GateTest#2026",)) for _ in range(24)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    monkeypatch.undo()
    assert peak["n"] <= limit, f"PBKDF2 đồng thời peak={peak['n']} vượt gate {limit}"
    assert peak["n"] >= 2
