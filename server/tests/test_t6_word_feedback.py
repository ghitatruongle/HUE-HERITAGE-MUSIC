from app.services import lesson_service, compare_service
from tests.test_alpha2_learning import _tone_wav


def test_word_feedback_unit_windows_and_unclear():
    section = {
        "lyrics": "Câu một hai từ\nCâu hai",
        "line_times": [{"start": 0.0, "end": 2.0}, {"start": 2.0, "end": 3.0}],
    }
    times = [round(0.01 * i, 3) for i in range(300)]
    result = {
        "user_warped_full": {"times": times, "f0": [220.0] * 100 + [0.0] * 100 + [330.0] * 100},
        "sample": {"times": [round(0.01 * i, 3) for i in range(300)], "f0": [220.0] * 150 + [330.0] * 150},
        "notes": [],
    }
    words = lesson_service.word_feedback(section, result)
    assert len(words) == 6
    assert [w["text"] for w in words] == ["Câu", "một", "hai", "từ", "Câu", "hai"]
    assert [w["line"] for w in words] == [0, 0, 0, 0, 1, 1]
    assert all(w["end"] > w["start"] for w in words)
    assert all(w["verdict_code"] in ("ok", "minor", "off", "octave", "unclear") for w in words)
    assert all(w["err_cents"] is None for w in words if w["verdict_code"] == "unclear")
    voiced_words = [w for w in words if w["verdict_code"] == "ok"]
    unclear_words = [w for w in words if w["verdict_code"] == "unclear"]
    assert len(voiced_words) == 4
    assert len(unclear_words) == 2
    assert all(w["voiced_ratio"] >= 0.2 for w in voiced_words)
    assert all(w["voiced_ratio"] < 0.2 for w in unclear_words)


def test_word_feedback_empty_inputs():
    assert lesson_service.word_feedback(None, {}) == []
    assert lesson_service.word_feedback({"lyrics": "", "line_times": []}, {}) == []


def test_practice_response_carries_words(monkeypatch):
    from fastapi.testclient import TestClient
    from app.config import settings
    from app.main import create_app

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    audio = _tone_wav([220.0, 330.0], tone_len=2.0)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", audio, "audio/wav")},
        data={
            "title": "Bai T6 words",
            "type": "Ca Hue",
            "lyrics_with_ornaments": "Câu một\nCâu hai",
            "mode_system": "Nam",
        },
    )
    assert up.status_code == 200, up.text
    lid = up.json()["id"]
    user = _tone_wav([220.0, 330.0], tone_len=2.0)
    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", user, "audio/wav")})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body.get("words_alignment") == lesson_service.WORDS_ALIGNMENT
    words = body.get("words")
    assert isinstance(words, list)
    assert words
    assert all(w["end"] > w["start"] for w in words)
    assert all("voiced_ratio" in w and "err_cents" in w and "verdict_code" in w for w in words)
    assert sum(1 for w in words if w["verdict_code"] != "unclear") >= 1


def test_multi_section_words_not_all_unclear(monkeypatch):
    from fastapi.testclient import TestClient
    from app.config import settings
    from app.main import create_app

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    audio = _tone_wav([220.0, 262.0, 330.0, 392.0], tone_len=1.5, gap=1.0)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", audio, "audio/wav")},
        data={
            "title": "Bai T6 multi section",
            "type": "Ca Hue",
            "lyrics_with_ornaments": "Cau mot\nCau hai\nCau ba\nCau bon",
        },
    )
    assert up.status_code == 200, up.text
    lid = up.json()["id"]
    detail = client.get(f"/api/lessons/{lid}").json()
    sec1 = next(s for s in detail["sections"] if s["index"] == 1)
    assert sec1["start"] > 0
    user = _tone_wav([220.0, 262.0, 330.0, 392.0], tone_len=1.5, gap=1.0)
    r = client.post(f"/api/lessons/{lid}/practice?section=1", files={"file": ("u.wav", user, "audio/wav")})
    assert r.status_code == 200, r.text
    body = r.json()
    words = body.get("words") or []
    assert words
    assert any(w["voiced_ratio"] > 0 for w in words)
    assert any(w["verdict_code"] != "unclear" for w in words)
    assert all(w["start"] >= sec1["start"] - 0.01 for w in words)


def test_warped_full_only_for_lesson_practice(monkeypatch):
    from fastapi.testclient import TestClient
    from app.config import settings
    from app.main import create_app
    from app.services import scale_service

    scaled_take = _tone_wav(scale_service.SCALES["bac"]["frequencies"][:3], tone_len=0.9, gap=0.15)
    sp = scale_service.practice_scale("bac", scaled_take)
    assert "user_warped_full" not in sp

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    audio = _tone_wav([220.0, 330.0], tone_len=1.2)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", audio, "audio/wav")},
        data={"title": "Bai T6 warped flag", "type": "Ca Hue", "lyrics_with_ornaments": "Cau mot"},
    )
    assert up.status_code == 200, up.text
    lid = up.json()["id"]
    user = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", user, "audio/wav")})
    assert r.status_code == 200, r.text
    assert "user_warped_full" in r.json()


def test_words_not_returned_without_lyrics(monkeypatch):
    from fastapi.testclient import TestClient
    from app.config import settings
    from app.main import create_app

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", "dev-insecure-secret-key", raising=False)
    client = TestClient(create_app())
    audio = _tone_wav([262.0, 392.0], tone_len=1.2)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("lesson.wav", audio, "audio/wav")},
        data={"title": "Bai T6 no lyrics", "type": "Ca Hue"},
    )
    assert up.status_code == 200, up.text
    lid = up.json()["id"]
    user = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = client.post(f"/api/lessons/{lid}/practice?section=0", files={"file": ("u.wav", user, "audio/wav")})
    assert r.status_code == 200, r.text
    assert r.json().get("words") == []
