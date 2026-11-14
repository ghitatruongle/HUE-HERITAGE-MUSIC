import pytest
from fastapi.testclient import TestClient

from app.main import app

PAYLOAD = "<svg onload=alert('M4')><script>alert('M4')</script>"


def test_spa_fallback_never_embeds_query_payload():
    client = TestClient(app)
    r = client.get("/", params={"q": PAYLOAD})
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
    assert PAYLOAD.lower() not in r.text.lower()
    assert "svg onload" not in r.text.lower()
    assert "content-security-policy" in {k.lower() for k in r.headers.keys()}


def test_spa_fallback_never_embeds_path_payload():
    client = TestClient(app)
    r = client.get(f"/hue/{PAYLOAD}")
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
    assert PAYLOAD.lower() not in r.text.lower()
    assert "svg onload" not in r.text.lower()
    assert "x-frame-options" in {k.lower() for k in r.headers.keys()}


def test_json_surfaces_carry_payload_as_inert_data_only():
    client = TestClient(app)
    r = client.get("/api/heritage", params={"q": PAYLOAD})
    assert r.status_code == 200
    assert "application/json" in r.headers.get("content-type", "")
    assert "text/html" not in r.headers.get("content-type", "")
