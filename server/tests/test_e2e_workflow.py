import io
import math
import struct
import wave
import uuid

from fastapi.testclient import TestClient

from server.app.main import app
from server.app.storage import manager


def make_test_wav(freq=440.0, duration=1.0, sr=16000):
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


def test_full_heritage_pipeline():
    client = TestClient(app)

    unique_title = "Nam Binh Test " + uuid.uuid4().hex[:8]
    wav_sample = make_test_wav(freq=440.0, duration=1.0, sr=16000)

    upload_resp = client.post(
        "/api/heritage/upload",
        files={"file": ("nam_binh.wav", wav_sample, "audio/wav")},
        data={
            "title": unique_title,
            "type": "Ca Hue",
            "artist": "Nghe Nhan Mau",
            "source": "Hue Heritage Archive",
            "license": "CC-BY-NC",
        },
    )
    assert upload_resp.status_code == 200
    item_data = upload_resp.json()
    item_id = item_data["id"]
    item_sha = item_data["sha256"]

    list_resp = client.get("/api/heritage?q=" + unique_title)
    assert list_resp.status_code == 200
    items = list_resp.json()
    assert any(i["id"] == item_id for i in items)

    audio_resp = client.get(f"/api/heritage/{item_id}/audio")
    assert audio_resp.status_code == 200
    assert len(audio_resp.content) == len(wav_sample)
    assert manager.sha256_bytes(audio_resp.content) == item_sha

    pitch_resp = client.post(
        "/api/music/analyze-pitch",
        files={"file": ("test_pitch.wav", wav_sample, "audio/wav")},
    )
    assert pitch_resp.status_code == 200
    p_data = pitch_resp.json()
    assert p_data["mean_f0"] > 0
    assert len(p_data["times"]) == len(p_data["f0"])

    user_singing_wav = make_test_wav(freq=445.0, duration=1.0, sr=16000)
    compare_resp = client.post(
        "/api/music/compare",
        files={
            "sample": ("sample.wav", wav_sample, "audio/wav"),
            "user": ("user.wav", user_singing_wav, "audio/wav"),
        },
    )
    assert compare_resp.status_code == 200
    c_data = compare_resp.json()
    assert "metrics" in c_data
    assert c_data["metrics"]["score"] > 0
    assert "sample" in c_data
    assert "user_warped" in c_data

    transcribe_resp = client.post(
        "/api/music/transcribe",
        files={"file": ("test_trans.wav", wav_sample, "audio/wav")},
        data={"bpm": "60", "heritage_id": item_id},
    )
    assert transcribe_resp.status_code == 200
    t_data = transcribe_resp.json()
    sha = t_data["sha"]
    assert len(sha) == 64
    assert len(t_data["notes"]) > 0

    midi_resp = client.get(f"/api/music/midi/{sha}")
    assert midi_resp.status_code == 200
    assert midi_resp.content.startswith(b"MThd")

    xml_resp = client.get(f"/api/music/musicxml/{sha}")
    assert xml_resp.status_code == 200
    assert b"<score-partwise" in xml_resp.content

    restore_resp = client.post(f"/api/music/restore-item/{item_id}")
    assert restore_resp.status_code == 200
    r_data = restore_resp.json()
    r_sha = r_data["sha"]

    download_restored_resp = client.get(f"/api/music/restored/{r_sha}")
    assert download_restored_resp.status_code == 200
    assert download_restored_resp.content.startswith(b"RIFF")

    inst_resp = client.post(f"/api/music/instruments-item/{item_id}")
    assert inst_resp.status_code == 200
    i_data = inst_resp.json()
    assert "segments" in i_data
    assert len(i_data["segments"]) > 0

    models_resp = client.get("/api/music/models")
    assert models_resp.status_code == 200
    m_data = models_resp.json()
    assert "base" in m_data
    assert "adapters" in m_data

    gen_resp = client.post(
        "/api/music/generate?prompt=Ca%20Hue%20Dan%20Tranh&duration=30&strength=0.8"
    )
    assert gen_resp.status_code == 200
    task_info = gen_resp.json()
    assert task_info["status"] in ("running", "blocked")
