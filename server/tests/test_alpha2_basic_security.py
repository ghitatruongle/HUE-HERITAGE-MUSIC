import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User, PracticeSession
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture()
def sec_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-basic-sec-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(PracticeSession).delete()
        db.commit()
    finally:
        db.close()


@pytest.fixture()
def client(sec_env):
    return TestClient(create_app())


@pytest.fixture()
def user_token(client):
    r = client.post("/api/auth/register", json={
        "username": "secuser", "email": "secuser@x.com",
        "password": "DepCoDau#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client.post("/api/auth/login", json={"identifier": "secuser", "password": "DepCoDau#2026"})
    assert r.status_code == 200, r.text
    return r.json()["token"]


def test_login_unknown_user_401(client):
    r = client.post("/api/auth/login", json={"identifier": "khongtontai", "password": "sai123"})
    assert r.status_code == 401
    assert r.json()["detail"] == "wrong credentials"


def test_login_wrong_password_401(client, user_token):
    r = client.post("/api/auth/login", json={"identifier": "secuser", "password": "sai-mat-khau-999"})
    assert r.status_code == 401
    assert r.json()["detail"] == "wrong credentials"


def test_fake_token_401(client):
    r = client.get("/api/auth/me", headers={"Authorization": "Bearer abc.def.ghi"})
    assert r.status_code == 401
    assert r.json()["detail"] == "invalid token"


def test_garbage_long_token_401(client):
    r = client.get("/api/auth/me", headers={"Authorization": "Bearer " + "x" * 200})
    assert r.status_code == 401
    assert r.json()["detail"] == "invalid token"


def test_normal_user_admin_users_403(client, user_token):
    r = client.get("/api/auth/users", headers={"Authorization": f"Bearer {user_token}"})
    assert r.status_code == 403
    assert r.json()["detail"] == "admin truong only"


def test_normal_user_admin_stats_403(client, user_token):
    r = client.get("/api/admin/stats", headers={"Authorization": f"Bearer {user_token}"})
    assert r.status_code == 403


def test_sqli_login_bypass_401(client):
    r = client.post("/api/auth/login", json={"identifier": "' OR '1'='1", "password": "x"})
    assert r.status_code == 401
    assert r.json()["detail"] == "wrong credentials"


def test_sqli_search_no_500(client):
    r = client.get("/api/heritage", params={"q": "' OR 1=1--"})
    assert r.status_code == 200
    data = r.json()
    assert isinstance(data, (list, dict))


def test_xss_login_401_no_reflection(client):
    r = client.post("/api/auth/login", json={"identifier": "<script>alert(1)</script>", "password": "x"})
    assert r.status_code == 401
    assert "<script>" not in r.text


def test_path_traversal_no_sensitive_leak(client):
    for p in ("/api/heritage/../../../etc/passwd", "/..%2f..%2f.env", "/api/heritage%00"):
        r = client.get(p)
        body = r.text[:4000]
        assert "root:" not in body
        assert "SECRET" not in body
        assert "sqlite" not in body.lower()


def test_anonymous_lessons_list_ok(client):
    r = client.get("/api/lessons")
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_forged_signed_url_404_no_existence_leak(client):
    r = client.get("/api/lessons/khong-ton-tai/sections/0/sample.wav?e=9999999999&s=deadbeefdeadbeefdeadbeefdeadbeef")
    assert r.status_code == 404
    assert r.json()["detail"] == "lesson not found"


def test_upload_bad_magic_bytes_400(client, user_token):
    r = client.post(
        "/api/heritage/upload",
        files={"file": ("bad.wav", b"NOT A WAV AT ALL" * 10, "audio/wav")},
        headers={"Authorization": f"Bearer {user_token}"},
    )
    assert r.status_code == 400


def test_upload_without_token_401(client):
    r = client.post(
        "/api/heritage/upload",
        files={"file": ("x.wav", b"RIFF....WAVE" + b"\x00" * 200, "audio/wav")},
    )
    assert r.status_code == 401


def test_practice_without_token_401(client):
    r = client.post(
        "/api/lessons/abc/practice?section=0",
        files={"file": ("u.wav", b"RIFF....WAVE" + b"\x00" * 200, "audio/wav")},
    )
    assert r.status_code == 401


def test_csp_headers_complete(client):
    r = client.get("/health")
    csp = r.headers.get("content-security-policy", "")
    assert "default-src 'self'" in csp
    assert "frame-ancestors 'none'" in csp
    assert r.headers.get("x-content-type-options") == "nosniff"
    assert r.headers.get("x-frame-options") == "DENY"


def test_env_probe_no_secret_leak(client):
    for p in ("/.env", "/server/.env", "/.env.example"):
        r = client.get(p)
        if r.status_code == 200:
            assert "SECRET" not in r.text[:4000]
            assert "sqlite" not in r.text.lower()[:4000]
        else:
            assert r.status_code in (404, 400)
