import logging
import sys
import threading
import time
import types
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.ai import basic_pitch_amt as bp
from app.config import settings
from app.main import app


@pytest.fixture(autouse=True)
def _pristine_engine():
    bp._stalled = False
    bp._stalled_thread = None
    bp._stalled_tmp = None
    yield
    bp._stalled = False
    bp._stalled_thread = None
    bp._stalled_tmp = None


def _fake_predict_module(monkeypatch, seconds):
    inf = types.ModuleType("basic_pitch.inference")

    def slow_predict(path, model):
        time.sleep(seconds)
        return [], [], []

    inf.predict = slow_predict
    fake = types.ModuleType("basic_pitch")
    fake.inference = inf
    monkeypatch.setitem(sys.modules, "basic_pitch", fake)
    monkeypatch.setitem(sys.modules, "basic_pitch.inference", inf)


def test_lock_wait_timeout_fails_fast(monkeypatch):
    monkeypatch.setattr(bp, "_load", lambda: object(), raising=False)
    monkeypatch.setattr(settings, "basic_pitch_lock_wait_timeout", 0.5, raising=False)
    assert bp.LOCK.acquire(timeout=1.0)
    try:
        t0 = time.monotonic()
        with pytest.raises(bp.EngineBusy):
            bp.transcribe([0.0] * 64, 16000)
        assert time.monotonic() - t0 < 3.0
    finally:
        bp.LOCK.release()


def test_load_fast_path_does_not_block_on_predict_lock():
    bp.MODEL = object()
    try:
        assert bp.LOCK.acquire(timeout=1.0)
        try:
            t0 = time.monotonic()
            m = bp._load()
            assert m is bp.MODEL
            assert time.monotonic() - t0 < 0.5
        finally:
            bp.LOCK.release()
    finally:
        bp.MODEL = None


def test_predict_ok_under_fresh_engine(monkeypatch):
    _fake_predict_module(monkeypatch, 0.0)
    monkeypatch.setattr(bp, "_load", lambda: object(), raising=False)
    notes = bp.transcribe([0.0] * 64, 16000)
    assert notes == []


def test_transcribe_writes_valid_temp_wav(monkeypatch):
    import types as _types

    inf = _types.ModuleType("basic_pitch.inference")
    seen = {}

    def read_predict(path, model):
        import wave as _wave

        with _wave.open(path, "rb") as w:
            seen["frames"] = w.getnframes()
            seen["rate"] = w.getframerate()
            seen["channels"] = w.getnchannels()
            seen["sampwidth"] = w.getsampwidth()
        return [], [], []

    inf.predict = read_predict
    fake = _types.ModuleType("basic_pitch")
    fake.inference = inf
    monkeypatch.setitem(sys.modules, "basic_pitch", fake)
    monkeypatch.setitem(sys.modules, "basic_pitch.inference", inf)
    monkeypatch.setattr(bp, "_load", lambda: object(), raising=False)
    notes = bp.transcribe([0.0] * 1600, 16000)
    assert notes == []
    assert seen["frames"] == 1600
    assert seen["rate"] == 16000
    assert seen["channels"] == 1
    assert seen["sampwidth"] == 2


def test_engine_stall_poisons_then_selfheals(monkeypatch):
    _fake_predict_module(monkeypatch, 1.5)
    monkeypatch.setattr(bp, "_load", lambda: object(), raising=False)
    monkeypatch.setattr(settings, "basic_pitch_lock_wait_timeout", 5.0, raising=False)
    monkeypatch.setattr(settings, "basic_pitch_run_timeout", 0.3, raising=False)
    with pytest.raises(bp.EngineStalled):
        bp.transcribe([0.0] * 64, 16000)
    assert bp.status()["stalled"] is True
    tmp_path = bp._stalled_tmp
    assert tmp_path is not None
    with pytest.raises(bp.EngineBusy):
        bp.transcribe([0.0] * 64, 16000)
    if bp._stalled_thread is not None:
        bp._stalled_thread.join(3.0)
    bp._selfheal()
    assert bp.status()["stalled"] is False
    assert bp._stalled_tmp is None
    assert not Path(tmp_path).exists()


def test_inlock_recheck_blocks_second_predict_while_stalled_alive(monkeypatch):
    _fake_predict_module(monkeypatch, 0.0)
    monkeypatch.setattr(bp, "_load", lambda: object(), raising=False)
    monkeypatch.setattr(bp, "_selfheal", lambda: None, raising=False)
    zombie = threading.Thread(target=time.sleep, args=(2.0,), daemon=True)
    zombie.start()
    bp._stalled = True
    bp._stalled_thread = zombie
    try:
        with pytest.raises(bp.EngineBusy):
            bp.transcribe([0.0] * 64, 16000)
    finally:
        bp._stalled = False
        bp._stalled_thread = None
        zombie.join(3.0)


def test_transcribe_endpoint_503_when_engine_busy(monkeypatch):
    from app.services import media_pipeline

    def busy(*a, **k):
        raise bp.EngineBusy("basic-pitch engine busy (lock wait timeout)")

    monkeypatch.setattr(media_pipeline, "extract_notes", busy)
    client = TestClient(app)
    r = client.post(
        "/api/music/transcribe",
        files={"file": ("tone.wav", b"\x00" * 64, "audio/wav")},
        data={"bpm": "60"},
    )
    assert r.status_code == 503, r.text
    assert "busy" in r.json()["detail"]


def test_evaluate_endpoint_503_when_engine_busy(monkeypatch):
    from app.services import media_pipeline

    def busy(*a, **k):
        raise bp.EngineBusy("basic-pitch engine busy (lock wait timeout)")

    monkeypatch.setattr(media_pipeline, "extract_notes", busy)
    client = TestClient(app)
    r = client.post(
        "/api/music/evaluate",
        files={"file": ("tone.wav", b"\x00" * 64, "audio/wav")},
        data={"bpm": "60", "truth": "[]"},
    )
    assert r.status_code == 503, r.text
    assert "busy" in r.json()["detail"]


def test_pool_worker_survives_exception(caplog):
    from app.workers.pool import WorkerPool

    pool = WorkerPool("t-survive", 1)
    done = []
    with caplog.at_level(logging.ERROR, logger="app.workers.pool"):
        pool.submit(lambda: (_ for _ in ()).throw(RuntimeError("boom")))
        pool.submit(lambda: done.append(1))
        deadline = time.time() + 5
        while not done and time.time() < deadline:
            time.sleep(0.05)
    assert done == [1]
    assert any("task failed" in r.getMessage() for r in caplog.records)
    assert pool._started == 1


def test_pool_worker_survives_base_exception_and_logs(caplog):
    from app.workers.pool import WorkerPool

    pool = WorkerPool("t-nk3-baseexc", 1)
    done = []
    with caplog.at_level(logging.ERROR, logger="app.workers.pool"):
        pool.submit(lambda: (_ for _ in ()).throw(SystemExit(3)))
        pool.submit(lambda: done.append(1))
        deadline = time.time() + 5
        while not done and time.time() < deadline:
            time.sleep(0.05)
    assert done == [1]
    assert pool._started == 1
    assert any("BaseException" in r.getMessage() for r in caplog.records)
