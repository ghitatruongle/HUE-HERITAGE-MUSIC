import math
import threading
from pathlib import Path

MODEL = None
LOCK = threading.Lock()


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
    with LOCK:
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
        raise last_error


def _freq_from_midi(midi: int) -> float:
    return round(440.0 * (2.0 ** ((midi - 69) / 12.0)), 1)


def transcribe(samples, sr: int) -> list:
    import os
    import tempfile
    import wave
    import numpy as np
    import scipy.signal
    import scipy.signal.windows

    if not hasattr(scipy.signal, "gaussian"):
        scipy.signal.gaussian = scipy.signal.windows.gaussian
    from basic_pitch.inference import predict

    model = _load()
    audio = np.clip(np.asarray(samples, dtype=np.float32), -1.0, 1.0)
    pcm = (audio * 32767.0).astype("<i2")
    fd, tmp_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        with wave.open(tmp_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes(pcm.tobytes())
        _, _, note_events = predict(tmp_path, model)
    finally:
        os.unlink(tmp_path)
    notes = []
    for ev in note_events:
        start, end, midi, velocity = float(ev[0]), float(ev[1]), int(ev[2]), int(ev[3])
        if end - start < 0.03:
            continue
        notes.append({
            "midi": midi,
            "freq": _freq_from_midi(midi),
            "start": round(start, 3),
            "end": round(end, 3),
            "velocity": max(1, min(127, velocity)),
        })
    notes.sort(key=lambda n: (n["start"], n["midi"]))
    return notes


def status():
    return {"available": available(), "loaded": MODEL is not None, "name": "basic-pitch"}
