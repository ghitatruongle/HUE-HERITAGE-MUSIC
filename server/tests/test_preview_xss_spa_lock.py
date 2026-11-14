import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app

PAYLOAD = "<svg onload=alert('M4')><script>alert('M4')</script>"


@pytest.fixture()
def spa_env(monkeypatch, tmp_path):
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html><body>SPA PROBE</body></html>", encoding="utf-8")
    monkeypatch.setattr(settings, "web_dir", str(web), raising=False)
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 100000, raising=False)
    return TestClient(create_app())


def test_spa_fallback_never_embeds_query_payload(spa_env):
    r = spa_env.get("/", params={"q": PAYLOAD})
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
    assert PAYLOAD.lower() not in r.text.lower()
    assert "svg onload" not in r.text.lower()
    assert "content-security-policy" in {k.lower() for k in r.headers.keys()}


def test_spa_fallback_never_embeds_path_payload(spa_env):
    r = spa_env.get(f"/hue/{PAYLOAD}")
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
    assert PAYLOAD.lower() not in r.text.lower()
    assert "svg onload" not in r.text.lower()
    assert "x-frame-options" in {k.lower() for k in r.headers.keys()}


def test_json_surfaces_carry_payload_as_inert_data_only(spa_env):
    r = spa_env.get("/api/heritage", params={"q": PAYLOAD})
    assert r.status_code == 200
    assert "application/json" in r.headers.get("content-type", "")
    assert "text/html" not in r.headers.get("content-type", "")
