import io
import wave

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import AudioFile, HeritageItem, User
from app.database.session import SessionLocal
from app.main import create_app


def _wav_bytes(seconds=1, sr=8000):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"\x00\x40" * (sr * seconds))
    return bio.getvalue()


@pytest.fixture()
def scope_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-beta3-scope-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(AudioFile).delete()
        db.query(HeritageItem).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    app1 = create_app()
    client = TestClient(app1)
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "a@x.com",
        "password": "ScopeAdmin#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    noauth = TestClient(create_app())
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "ScopeAdmin#2026"})
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    client.headers.update({"Authorization": f"Bearer {token}"})
    r = client.post("/api/auth/admin-unlock", json={"password": "ScopeAdmin#2026"})
    assert r.status_code == 200, r.text
    yield client, noauth
    db = SessionLocal()
    try:
        db.query(AudioFile).delete()
        db.query(HeritageItem).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _upload(client, title):
    r = client.post("/api/heritage/upload", files={"file": (f"{title}.wav", _wav_bytes(), "audio/wav")},
                    data={"title": title, "type": "Ca Hue"})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _sign(client, iid):
    r = client.get("/api/music/play-url", params={"path": f"/api/heritage/{iid}/audio"})
    assert r.status_code == 200, r.text
    return r.json()["url"]


def test_admin_signed_url_on_admin_only_item_serves_guest_by_design(scope_env):
    client, noauth = scope_env
    iid = _upload(client, "Beta3AdminOnly")
    client.patch(f"/api/admin/storage/{iid}/visibility", json={"visibility": "admin_only"})
    url = _sign(client, iid)
    r = noauth.get(url)
    assert r.status_code == 200, f"admin ký URL trên item admin_only là chia sẻ chủ ý: {r.status_code}"


def test_public_signed_url_still_serves_guest(scope_env):
    client, noauth = scope_env
    iid = _upload(client, "Beta3Public")
    r = client.patch(f"/api/admin/storage/{iid}/visibility", json={"visibility": "public"})
    assert r.status_code == 200, r.text
    url = _sign(client, iid)
    r = noauth.get(url)
    assert r.status_code == 200, f"signed URL public phải sống cho guest: {r.status_code}"


def test_flip_public_to_admin_only_kills_old_url(scope_env):
    client, noauth = scope_env
    iid = _upload(client, "Beta3FlipKill")
    r = client.patch(f"/api/admin/storage/{iid}/visibility", json={"visibility": "public"})
    assert r.status_code == 200, r.text
    url = _sign(client, iid)
    assert noauth.get(url).status_code == 200
    client.patch(f"/api/admin/storage/{iid}/visibility", json={"visibility": "admin_only"})
    assert noauth.get(url).status_code == 401


def test_admin_scope_url_dies_after_flip_to_public(scope_env):
    client, noauth = scope_env
    iid = _upload(client, "Beta3AdminScope")
    client.patch(f"/api/admin/storage/{iid}/visibility", json={"visibility": "admin_only"})
    url = _sign(client, iid)
    client.patch(f"/api/admin/storage/{iid}/visibility", json={"visibility": "public"})
    assert noauth.get(url).status_code == 401
