import io
import math
import wave

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture()
def up_client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-upload-lock-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "x@x.com",
        "password": "Upload#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    db = SessionLocal()
    try:
        u = db.query(User).filter_by(username="ghitatruongle").first()
        if u is not None:
            u.role = "admin"
            db.commit()
    finally:
        db.close()
    yield client
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _wav(seconds=1, freq=220):
    sr = 16000
    n = sr * seconds
    buf = io.BytesIO()
    w = wave.open(buf, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    frames = bytearray()
    for i in range(n):
        frames += int(9000 * math.sin(2 * math.pi * freq * i / sr)).to_bytes(2, "little", signed=True)
    w.writeframes(bytes(frames))
    w.close()
    return buf.getvalue()


def _login(client, identifier, password):
    r = client.post("/api/auth/login", json={"identifier": identifier, "password": password})
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_admin_flip_hides_item_dedup_owner_and_attacker_both_blocked(up_client):
    client = up_client
    ah = _login(client, "ghitatruongle", "Upload#2026")
    client.post("/api/auth/admin-unlock", json={"password": "Upload#2026"}, headers=ah)
    victim_h = client.post("/api/auth/register", json={
        "username": "victimown", "email": "v@x.com", "password": "Victim#2026", "invite_code": "TESTINVITE"}).json()["token"]
    vh = {"Authorization": f"Bearer {victim_h}"}
    attacker_h = client.post("/api/auth/register", json={
        "username": "attackown", "email": "a@x.com", "password": "Attack#2026", "invite_code": "TESTINVITE"}).json()["token"]
    sh = {"Authorization": f"Bearer {attacker_h}"}
    data = _wav(1, 440)
    r = client.post("/api/heritage/upload", headers=vh,
                    files={"file": ("own.wav", data, "audio/wav")}, data={"title": "OWN_ITEM"})
    assert r.status_code == 200, r.text[:120]
    own_id = r.json()["id"]
    r = client.patch(f"/api/admin/storage/{own_id}/visibility", headers=ah, json={"visibility": "admin_only"})
    assert r.status_code == 200, f"flip admin_only: {r.status_code} {r.text[:120]}"
    r = client.post("/api/heritage/upload", headers=vh,
                    files={"file": ("own.wav", data, "audio/wav")}, data={"title": "OWN_ITEM"})
    assert r.status_code == 404, (
        f"owner re-upload sau khi admin flip admin_only phải 404 (moderation semantics alpha1): {r.status_code} {r.text[:120]}")
    r = client.post("/api/heritage/upload", headers=sh,
                    files={"file": ("own.wav", data, "audio/wav")}, data={"title": "ATTACKER_DEDUP"})
    assert r.status_code == 404, f"attacker dedup item admin_only người khác phải 404 (NK1): {r.status_code} {r.text[:120]}"


def test_upload_traversal_and_bad_ext_and_body_limit(up_client):
    client = up_client
    h = _login(client, "ghitatruongle", "Upload#2026")
    for fn in ("../../evil.wav", "..\\..\\evil.wav", "NUL\x00.wav"):
        r = client.post("/api/heritage/upload", headers=h,
                        files={"file": (fn, _wav(1, 300), "audio/wav")}, data={"title": "trav"})
        assert r.status_code in (200, 400), f"traversal filename {fn!r} -> {r.status_code}"
        if r.status_code == 200:
            assert "text/html" not in r.headers.get("content-type", "")
    for fn, head in (("payload.exe", b"MZ" + b"x" * 64), ("shell.php", b"<?php" + b"x" * 64)):
        r = client.post("/api/heritage/upload", headers=h,
                        files={"file": (fn, head, "audio/wav")}, data={"title": "badext"})
        assert r.status_code == 400, f"bad ext {fn} phải 400 magic-byte: {r.status_code}"
    r = client.post("/api/auth/login", content='{"x": "' + "a" * (2 * 1024 * 1024) + '"}',
                    headers={"Content-Type": "application/json"})
    assert r.status_code == 413, f"JSON 2MB+ phải 413: {r.status_code}"


def test_signed_url_scope_flip_forged_expired(up_client):
    client = up_client
    ah = _login(client, "ghitatruongle", "Upload#2026")
    client.post("/api/auth/admin-unlock", json={"password": "Upload#2026"}, headers=ah)
    data = _wav(1, 520)
    r = client.post("/api/heritage/upload", headers=ah,
                    files={"file": ("scope.wav", data, "audio/wav")}, data={"title": "SCOPE_LOCK"})
    assert r.status_code == 200, r.text[:120]
    iid = r.json()["id"]
    r = client.patch(f"/api/admin/storage/{iid}/visibility", headers=ah, json={"visibility": "public"})
    assert r.status_code == 200, f"flip public (admin upload mặc định admin_only): {r.status_code}"
    r = client.get(f"/api/heritage/{iid}/audio-url", headers=ah)
    assert r.status_code == 200, r.text[:120]
    url = r.json()["url"]
    base, qs = url.split("?", 1)
    params = dict(p.split("=", 1) for p in qs.split("&"))
    r = client.get(url)
    assert r.status_code == 200, f"URL ký khi public → 200: {r.status_code}"
    r = client.patch(f"/api/admin/storage/{iid}/visibility", headers=ah, json={"visibility": "admin_only"})
    assert r.status_code == 200, f"flip: {r.status_code} {r.text[:120]}"
    print("DBG url=", url)
    r = client.get(f"{base}?e={params['e']}&s={params['s']}")
    print("DBG GET-old status=", r.status_code, "ct=", r.headers.get("content-type", ""))
    assert r.status_code == 401, f"URL cũ sau flip admin_only phải chết 401 (scope re-check): {r.status_code}"
    r = client.get(f"{base}?e={params['e']}&s={'0' * 32}")
    assert r.status_code == 401, "sig giả phải 401"
    r = client.get(f"{base}?e=1000000000&s={params['s']}")
    assert r.status_code == 401, "URL hết hạn phải 401"
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "Upload#2026"})
    assert r.status_code == 200
