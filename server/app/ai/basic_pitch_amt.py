import logging
import math
import threading
import time
from pathlib import Path

from ..config import settings

MODEL = None
LOCK = threading.Lock()

_stalled = False
_stalled_thread = None
_stalled_tmp = None


class EngineBusy(Exception):
    pass


class EngineStalled(EngineBusy):
    pass


def available() -> bool:
    try:
        import basic_pitch
        return True
    except Exception:
        return False


def _candidates():
    import basic_pitch
    base = Path(basic_pitch.__file__).parent / "saved_models" / "icassp_2022"
    return [str(base / "nmp.tflite"), str(base / "nmp")]


def _load():
    global MODEL
    cached = MODEL
    if cached is not None:
        return cached
    if not LOCK.acquire(timeout=max(1.0, float(settings.basic_pitch_lock_wait_timeout))):
        logging.getLogger(__name__).warning(
            "basic-pitch load lock wait exceeded %.0fs", settings.basic_pitch_lock_wait_timeout
        )
        raise EngineBusy("basic-pitch engine busy (model load wait timeout)")
    try:
        if MODEL is not None:
            return MODEL
        from basic_pitch.inference import Model
        last_error = None
        for path in _candidates():
            try:
                MODEL = Model(path)
                return MODEL
            except Exception as e:
                last_error = e
        raise last_error or RuntimeError("no basic-pitch model candidates found")
    finally:
        LOCK.release()


def _selfheal():
    global _stalled, _stalled_thread, _stalled_tmp, MODEL
    if not _stalled:
        return
    t = _stalled_thread
    if t is not None and t.is_alive():
        raise EngineBusy("basic-pitch engine stalled earlier; waiting for stalled worker to exit")
    _stalled = False
    _stalled_thread = None
    MODEL = None
    if _stalled_tmp and Path(_stalled_tmp).exists():
        try:
            Path(_stalled_tmp).unlink()
        except OSError:
            pass
    _stalled_tmp = None
    logging.getLogger(__name__).warning("basic-pitch stalled worker exited; engine re-armed with fresh model")


def _predict_job(predict, path, model, box):
    try:
        box["events"] = predict(path, model)
    except Exception as e:
        box["error"] = e
    except BaseException as e:
        logging.getLogger(__name__).exception("basic-pitch helper terminated abnormally")
        box["error"] = RuntimeError(f"basic-pitch worker terminated: {e!r}")


def _freq_from_midi(midi: int) -> float:
    return round(440.0 * (2.0 ** ((midi - 69) / 12.0)), 1)


def velocity_from_amplitude(amplitude) -> int:
    return max(1, min(127, int(round(127.0 * float(amplitude)))))


def transcribe(samples, sr: int) -> list:
    global _stalled, _stalled_thread, _stalled_tmp
    import os
    import tempfile
    import wave
    import numpy as np
    import scipy.signal
    import scipy.signal.windows

    if not hasattr(scipy.signal, "gaussian"):
        scipy.signal.gaussian = scipy.signal.windows.gaussian

    log = logging.getLogger(__name__)
    _selfheal()
    model = _load()
    audio = np.clip(np.asarray(samples, dtype=np.float32), -1.0, 1.0)
    target_sr = 22050
    if sr != target_sr:
        try:
            import math as _math

            from scipy.signal import resample_poly as _resample_poly

            g = _math.gcd(target_sr, int(sr))
            audio = _resample_poly(audio.astype(np.float64), target_sr // g, int(sr) // g).astype(np.float32)
            sr = target_sr
        except Exception:
            pass
    pcm = (audio * 32767.0).astype("<i2")
    fd, tmp_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    with wave.open(tmp_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    if not LOCK.acquire(timeout=max(1.0, float(settings.basic_pitch_lock_wait_timeout))):
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        log.warning("basic-pitch lock wait exceeded %.0fs; failing fast", settings.basic_pitch_lock_wait_timeout)
        raise EngineBusy("basic-pitch engine busy (lock wait timeout)")
    stalled = False
    try:
        from basic_pitch.inference import predict

        if _stalled and _stalled_thread is not None and _stalled_thread.is_alive():
            raise EngineBusy("basic-pitch engine stalled earlier; waiting for stalled worker to exit")
        box = {}
        helper = threading.Thread(
            target=_predict_job, args=(predict, tmp_path, model, box), daemon=True, name="hue-basic-pitch"
        )
        started = time.monotonic()
        helper.start()
        helper.join(max(1.0, float(settings.basic_pitch_run_timeout)))
        if helper.is_alive():
            stalled = True
            _stalled = True
            _stalled_thread = helper
            _stalled_tmp = tmp_path
            log.error(
                "basic-pitch predict exceeded %.0fs — engine poisoned; fast-fail 503 until stalled worker exits",
                settings.basic_pitch_run_timeout,
            )
            raise EngineStalled("basic-pitch engine stalled (run timeout)")
        if box.get("error") is not None:
            raise box["error"]
        _, _, note_events = box["events"]
        log.info("basic-pitch predict ok in %.1fs", time.monotonic() - started)
    finally:
        LOCK.release()
        if not stalled and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
    notes = []
    for ev in note_events:
        start, end, midi, amplitude = float(ev[0]), float(ev[1]), int(ev[2]), float(ev[3])
        if end - start < 0.03:
            continue
        notes.append({
            "midi": midi,
            "freq": _freq_from_midi(midi),
            "start": round(start, 3),
            "end": round(end, 3),
            "velocity": velocity_from_amplitude(amplitude),
        })
    notes.sort(key=lambda n: (n["start"], n["midi"]))
    return notes


def status():
    return {"available": available(), "loaded": MODEL is not None, "name": "basic-pitch", "stalled": _stalled}
