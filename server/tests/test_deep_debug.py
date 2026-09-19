import io
import math
import struct
import wave
from pathlib import Path

from server.app.ai import lora_adapter
from server.app.services import pitch_service, midi_service
from server.app.audio_dsp import dtw_aligner, post_quantizer
from server.app.database import crud
from server.app.database.models import Task
from server.app.storage import manager


def make_test_wav(duration=20.0, sr=16000, freq=440.0):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        n = int(sr * duration)
        samples = [int(0.5 * 32767 * math.sin(2 * math.pi * freq * i / sr)) for i in range(n)]
        w.writeframes(struct.pack("<%dh" % n, *samples))
    return bio.getvalue()


def test_lora_adapter_detection():
    root = lora_adapter.lora_root()
    inst = root / "lora_instruments" / "epoch40"
    inst.mkdir(parents=True, exist_ok=True)
    (inst / "lokr_weights.safetensors").write_bytes(b"dummy_weights")
    cahue = root / "lora_cahue" / "final"
    cahue.mkdir(parents=True, exist_ok=True)
    (cahue / "adapter_model.safetensors").write_bytes(b"dummy_weights_2")

    adapters = lora_adapter.list_adapters()
    names = {a["name"] for a in adapters}
    assert "lora_instruments" in names
    ready_map = {a["name"]: a["ready"] for a in adapters}
    assert ready_map["lora_instruments"] is True
    assert ready_map["lora_cahue"] is True

    resolved_base = lora_adapter.resolve("lora_instruments")
    assert resolved_base is not None
    assert Path(resolved_base).exists()
    assert resolved_base.endswith(".safetensors")

    resolved_epoch = lora_adapter.resolve("lora_instruments/epoch40")
    assert resolved_epoch is not None
    assert "epoch40" in resolved_epoch

    assert lora_adapter.resolve("") is None
    assert lora_adapter.resolve("   ") is None
    assert lora_adapter.resolve("../../../etc/passwd") is None
    assert lora_adapter.resolve("lora_instruments/\0bad") is None
    assert lora_adapter.resolve("non_existent_xyz_adapter") is None


def test_read_mono_wav_max_seconds():
    data = make_test_wav(duration=20.0, sr=16000)
    samples_default, sr1 = pitch_service.read_mono_wav(data)
    assert sr1 == 16000
    assert len(samples_default) == 16000 * 15

    samples_20s, sr2 = pitch_service.read_mono_wav(data, max_seconds=25.0)
    assert sr2 == 16000
    assert len(samples_20s) == 16000 * 20

    samples_unlimited, sr3 = pitch_service.read_mono_wav(data, max_seconds=None)
    assert len(samples_unlimited) == 16000 * 20


def test_pitch_service_parabolic_refinement():
    samples = [math.sin(2 * math.pi * 440.0 * i / 16000) for i in range(2048)]
    times, f0s = pitch_service.estimate_f0(samples, 16000, frame=1024, hop=512)
    assert len(f0s) > 0
    for f in f0s:
        if f > 0:
            assert 400.0 <= f <= 480.0


def test_dtw_aligner_empty_and_guards():
    path, dist = dtw_aligner.dtw([], [])
    assert path == []
    assert dist == 0.0

    path2, dist2 = dtw_aligner.dtw([440.0], [])
    assert path2 == []
    assert dist2 == 0.0


def test_midi_service_edge_cases():
    b = midi_service.varlen(-100)
    assert len(b) == 1
    assert b[0] == 0

    notes = [
        {"midi": -5, "start": -1.0, "end": -0.5, "velocity": -10},
        {"midi": 200, "start": 0.0, "end": 0.5, "velocity": 200},
    ]
    raw = midi_service.write_midi(notes, bpm=120)
    assert raw.startswith(b"MThd")
    parsed = midi_service.read_midi(raw)
    assert len(parsed) == 2


def test_post_quantizer_missing_fields():
    notes = [
        {"midi": 60, "start": 0.05, "end": 0.95},
    ]
    res = post_quantizer.quantize(notes, bpm=60.0)
    assert len(res) == 1
    assert res[0]["freq"] == 0.0
    assert res[0]["velocity"] == 80


def test_crud_safe_task_to_dict():
    task = Task(id="test-1", kind="test", status="done", params_json="NOT_VALID_JSON", result_json="{bad_json")
    d = crud.task_to_dict(task)
    assert d["id"] == "test-1"
    assert d["params"] == {}
    assert d["result"] == {}


def test_storage_manager_null_byte_rejection():
    assert manager.safe_original_name("test\0audio.wav") is False
    assert manager.safe_original_name("valid.wav") is True
    assert manager.safe_original_name("") is False
    assert manager.safe_original_name("../escape.wav") is False


def test_musicxml_service_robustness():
    from server.app.services import musicxml_service
    notes = [
        {"midi": -10, "start": -2.0, "end": -1.0},
        {"midi": 150, "start": 1.0, "end": 2.5},
        {"midi": 60, "start": 2.5, "end": 2.0},
    ]
    xml = musicxml_service.build_musicxml(notes, bpm=60.0, title="")
    assert "score-partwise" in xml
    assert "Hue" in xml


def test_amt_service_close_bounds():
    from server.app.services import amt_service
    times = [0.0, 0.05, 0.1, 0.15, 0.2]
    f0 = [0.0, 220.0, 0.0, 220.0, 0.0]
    notes = amt_service.segment_notes(times, f0)
    assert isinstance(notes, list)


def test_generator_service_thread_safety():
    import threading
    from server.app.services import generator_service

    errors = []

    def writer():
        try:
            for i in range(50):
                generator_service.TASKS[f"thread_t_{i}"] = {
                    "id": f"thread_t_{i}",
                    "created_at": i,
                    "status": "done"
                }
        except Exception as e:
            errors.append(e)

    def reader():
        try:
            for i in range(50):
                generator_service.get_task(f"thread_t_{i}")
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=writer), threading.Thread(target=reader)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(errors) == 0


def test_instrument_service_duration_handling():
    from server.app.services import instrument_service
    wav = make_test_wav(duration=2.0, freq=440.0)
    res = instrument_service.detect(wav)
    assert res["duration"] > 0.0
    assert isinstance(res["segments"], list)
