from fastapi.testclient import TestClient

from server.app.config import settings
from server.app.main import app


def _register(client: TestClient, username: str) -> dict:
    r = client.post("/api/auth/register", json={
        "username": username,
        "email": f"{username}@gmail.com",
        "password": "password123",
        "invite_code": "QHH2026",
    })
    assert r.status_code == 200
    return r.json()


def test_me_requires_token():
    client = TestClient(app)
    r = client.get("/api/auth/me")
    assert r.status_code == 401


def test_me_returns_registered_user():
    client = TestClient(app)
    data = _register(client, "token_user_1")
    r = client.get("/api/auth/me", headers={"Authorization": "Bearer " + data["token"]})
    assert r.status_code == 200
    assert r.json()["username"] == "token_user_1"
    assert r.json()["email"] == "token_user_1@gmail.com"


def test_tampered_token_rejected():
    client = TestClient(app)
    data = _register(client, "token_user_2")
    token = data["token"]
    bad = token[:-4] + ("1111" if token[-4:] != "1111" else "2222")
    r = client.get("/api/auth/me", headers={"Authorization": "Bearer " + bad})
    assert r.status_code == 401


def test_expired_token_rejected(monkeypatch):
    monkeypatch.setattr(settings, "token_ttl_hours", -1)
    client = TestClient(app)
    data = _register(client, "token_user_3")
    r = client.get("/api/auth/me", headers={"Authorization": "Bearer " + data["token"]})
    assert r.status_code == 401
    monkeypatch.undo()
