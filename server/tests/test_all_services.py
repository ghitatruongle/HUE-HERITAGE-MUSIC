import math
import struct
import io
import wave
import xml.etree.ElementTree as ET
from pathlib import Path

from fastapi.testclient import TestClient

from server.app.main import app
from server.app.audio_dsp import fft as dsp_fft
from server.app.audio_dsp import dtw_aligner, post_quantizer
from server.app.services import (
    pitch_service,
    compare_service,
    midi_service,
    musicxml_service,
    restoration_service,
    instrument_service,
)
from server.app.database.session import get_db, SessionLocal
from server.app.database import crud
from server.app.storage import manager


def make_sine_wav(freq=440.0, duration=1.0, sr=16000):
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    n = int(sr * duration)
    samples = []
    for i in range(n):
        t = i / sr
        val = int(math.sin(2 * math.pi * freq * t) * 16000)
        samples.append(val)
    w.writeframes(struct.pack("<%dh" % n, *samples))
    w.close()
    return bio.getvalue()


def test_fft_ifft():
    data = [1.0, 0.5, -0.5, -1.0, 0.0, 0.5, 0.2, -0.2]
    spec = dsp_fft.fft(data)
    rec = dsp_fft.ifft(spec)
    for a, b in zip(data, rec):
        assert abs(a - b.real) < 0.001


def test_dtw():
    a = [220.0, 220.0, 440.0, 440.0]
    b = [220.0, 440.0, 440.0]
    path, dist = dtw_aligner.dtw(a, b)
    assert len(path) > 0
    assert path[0] == [0, 0]
    assert path[-1] == [len(a) - 1, len(b) - 1]


def test_post_quantizer():
    notes = [
        {"midi": 60, "freq": 261.63, "start": 0.05, "end": 0.95, "velocity": 80},
        {"midi": 62, "freq": 293.66, "start": 1.05, "end": 1.95, "velocity": 80},
    ]
    quantized = post_quantizer.quantize(notes, bpm=60.0)
    assert len(quantized) == 2
    assert quantized[0]["start"] == 0.0


def test_pitch_service():
    wav_bytes = make_sine_wav(freq=440.0, duration=1.0, sr=16000)
    samples, sr = pitch_service.read_mono_wav(wav_bytes)
    assert sr == 16000
    assert len(samples) > 0
    times, f0s = pitch_service.estimate_f0(samples, sr, hop=512)
    assert len(times) == len(f0s)
    voiced = [f for f in f0s if f > 0]
    assert len(voiced) > 0
    mean_voiced = sum(voiced) / len(voiced)
    assert 400.0 < mean_voiced < 480.0


def test_compare_service():
    wav1 = make_sine_wav(freq=440.0, duration=1.0, sr=16000)
    wav2 = make_sine_wav(freq=445.0, duration=1.0, sr=16000)
    result = compare_service.compare(wav1, wav2)
    assert "metrics" in result
    assert "score" in result["metrics"]
    assert result["metrics"]["score"] > 0


def test_midi_service():
    notes = [
        {"midi": 60, "start": 0.0, "end": 0.5, "velocity": 80},
        {"midi": 64, "start": 0.5, "end": 1.0, "velocity": 80},
    ]
    midi_data = midi_service.write_midi(notes, bpm=120.0)
    assert midi_data.startswith(b"MThd")
    read_back = midi_service.read_midi(midi_data)
    assert len(read_back) == 2
    assert read_back[0]["midi"] == 60
    assert read_back[1]["midi"] == 64


def test_musicxml_service():
    notes = [
        {"midi": 60, "start": 0.0, "end": 1.0, "velocity": 80},
        {"midi": 62, "start": 1.0, "end": 2.0, "velocity": 80},
    ]
    xml_str = musicxml_service.build_musicxml(notes, bpm=60.0, title="Hue Song")
    assert "<score-partwise" in xml_str
    root = ET.fromstring(xml_str)
    assert root.tag == "score-partwise"


def test_restoration_service():
    wav_bytes = make_sine_wav(freq=440.0, duration=0.5, sr=16000)
    out_bytes, report = restoration_service.restore(wav_bytes)
    assert len(out_bytes) > 44
    assert out_bytes.startswith(b"RIFF")
    assert "dc_removed" in report
    assert "clicks_fixed" in report


def test_instrument_service():
    wav_bytes = make_sine_wav(freq=440.0, duration=1.0, sr=16000)
    result = instrument_service.detect(wav_bytes)
    assert "segments" in result
    assert len(result["segments"]) > 0


def test_storage_manager():
    data = b"hue_heritage_music_test"
    sha = manager.sha256_bytes(data)
    assert len(sha) == 64
    assert manager.original_dir().exists()
    assert manager.midi_dir().exists()
    assert manager.xml_dir().exists()


def test_database_crud():
    import uuid
    db = SessionLocal()
    try:
        unique_sha = "test_sha_" + uuid.uuid4().hex
        item = crud.create_item(
            db=db,
            title="Luu Thuy Kim Tien",
            type="Ca Hue",
            artist="Nghe Nhan",
            source="Vien Am Nhac",
            license="CC-BY",
            sha256=unique_sha,
            filename="test_audio.wav",
            size=1024,
        )
        assert item.id is not None
        fetched = crud.get_item(db, item.id)
        assert fetched is not None
        assert fetched.title == "Luu Thuy Kim Tien"
    finally:
        db.close()


def test_fastapi_endpoints():
    client = TestClient(app)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"

    resp_models = client.get("/api/music/models")
    assert resp_models.status_code == 200

    resp_heritage = client.get("/api/heritage")
    assert resp_heritage.status_code == 200
    assert isinstance(resp_heritage.json(), list)

    wav_bytes = make_sine_wav(freq=440.0, duration=0.5, sr=16000)
    resp_pitch = client.post(
        "/api/music/analyze-pitch",
        files={"file": ("test.wav", wav_bytes, "audio/wav")},
    )
    assert resp_pitch.status_code == 200
    assert "f0" in resp_pitch.json()

    resp_transcribe = client.post(
        "/api/music/transcribe",
        files={"file": ("test.wav", wav_bytes, "audio/wav")},
        data={"bpm": "60"},
    )
    assert resp_transcribe.status_code == 200
    assert "notes" in resp_transcribe.json()

    resp_empty = client.post(
        "/api/music/analyze-pitch",
        files={"file": ("empty.wav", b"", "audio/wav")},
    )
    assert resp_empty.status_code == 400

    resp_bad_ext = client.post(
        "/api/heritage/upload",
        files={"file": ("malicious.exe", b"test", "application/octet-stream")},
    )
    assert resp_bad_ext.status_code == 400


def test_math_edge_cases():
    from server.app.audio_dsp.dtw_aligner import to_semi
    from server.app.services.compare_service import to_cents
    from server.app.services.amt_service import freq_to_midi, cents_diff, median

    assert to_semi(0) == 0.0
    assert to_semi(-10) == 0.0
    assert to_cents(0) == 0.0
    assert to_cents(-5) == 0.0
    assert freq_to_midi(0) == 0
    assert freq_to_midi(-100) == 0
    assert cents_diff(0, 440) == 999999.0
    assert cents_diff(440, 0) == 999999.0
    assert median([]) == 0.0

    assert dsp_fft.fft([]) == []
    assert dsp_fft.ifft([]) == []
    spec_non_pow2 = dsp_fft.fft([1.0, 2.0, 3.0])
    assert len(spec_non_pow2) == 4
    rec_non_pow2 = dsp_fft.ifft(spec_non_pow2[:3])
    assert len(rec_non_pow2) == 3


def test_stereo_wav_reading():
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(16000)
    samples = [1000, -1000] * 1600
    w.writeframes(struct.pack("<%dh" % len(samples), *samples))
    w.close()
    data = bio.getvalue()

    mono_samples, sr = pitch_service.read_mono_wav(data)
    assert sr == 16000
    assert len(mono_samples) == 1600
    assert abs(mono_samples[0]) < 0.0001


def test_corrupted_midi():
    try:
        midi_service.read_midi(b"too_short")
        assert False
    except ValueError:
        assert True

    try:
        midi_service.read_midi(b"NOT_MTHD_HEADER_DATA")
        assert False
    except ValueError:
        assert True


def test_empty_musicxml():
    xml_str = musicxml_service.build_musicxml([], bpm=0, title="Empty")
    assert "<score-partwise" in xml_str
    root = ET.fromstring(xml_str)
    assert root.tag == "score-partwise"

