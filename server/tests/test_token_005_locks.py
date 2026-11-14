import time

import pytest
from fastapi.testclient import TestClient

from app.api import auth as auth_api
from app.audio_access import verify_path
from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture()
def client():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    app1 = create_app()
    client = TestClient(app1)
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "a@x.com",
        "password": "TokLock#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    TestClient(create_app())
    yield client
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == "ghitatruongle").first()
        if u is not None:
            db.delete(u)
        db.commit()
    finally:
        db.close()


def test_token_ttl_user_72h_admin_8h_exact(client, monkeypatch):
    monkeypatch.setattr(settings, "token_ttl_hours", 72)
    monkeypatch.setattr(settings, "admin_token_ttl_hours", 8)
    r = client.post("/api/auth/register", json={
        "username": "ttluser", "email": "ttluser@x.com",
        "password": "TtlUser#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    parts = r.json()["token"].split(".")
    ttl_h = (int(parts[1]) - time.time()) / 3600.0
    assert abs(ttl_h - 72) < 1 / 60, f"user TTL {ttl_h:.3f}h lệch 72h"

    ru = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "TokLock#2026"})
    assert ru.status_code == 200, ru.text
    admin_tok = ru.json()["token"]
    r_role = client.get("/api/auth/me", headers={"Authorization": f"Bearer {admin_tok}"})
    assert r_role.json()["role"] == "admin", "admin trưởng phải role admin trên DB test"
    parts_a = admin_tok.split(".")
    ttl_a = (int(parts_a[1]) - time.time()) / 3600.0
    assert abs(ttl_a - 8) < 1 / 60, f"admin TTL {ttl_a:.3f}h lệch 8h"


def test_cross_signing_token_sig_rejected_as_url_sig(client, monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    r = client.post("/api/auth/register", json={
        "username": "crosssig", "email": "crosssig@x.com",
        "password": "CrossSig#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    tok = r.json()["token"]
    uid, exp, epoch, sig = tok.split(".")
    r = client.post("/api/heritage/upload", files={"file": ("c.wav", b"RIFFWAVEfmt" + b"\x00" * 256, "audio/wav")},
                    data={"title": "cross", "type": "Ca Hue"},
                    headers={"Authorization": f"Bearer {tok}"})
    if r.status_code != 200:
        import io
        import math
        import wave

        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            frames = bytearray()
            for i in range(16000):
                v = int(6000 * math.sin(2 * math.pi * 440.0 * i / 16000))
                frames += v.to_bytes(2, "little", signed=True)
            w.writeframes(bytes(frames))
        r = client.post("/api/heritage/upload", files={"file": ("c.wav", buf.getvalue(), "audio/wav")},
                        data={"title": "cross", "type": "Ca Hue"},
                        headers={"Authorization": f"Bearer {tok}"})
    assert r.status_code == 200, r.text
    item_id = r.json()["id"]

    r_cross = client.get(f"/api/heritage/{item_id}/audio", params={"e": exp, "s": sig})
    assert r_cross.status_code == 401, f"token-sig dùng làm URL sig phải 401, got {r_cross.status_code}"

    r_url = client.get("/api/auth/me", headers={"Authorization": f"Bearer {exp}.{epoch}.{sig}"})
    assert r_url.status_code == 401, f"URL-sig dùng làm bearer phải 401, got {r_url.status_code}"

    assert not verify_path(f"/api/heritage/{item_id}/audio", int(exp), sig, scope="vis:public"), (
        "verify_path phải từ chối token-sig (payload HMAC khác format)"
    )
    assert verify_path.__module__ == "app.audio_access"


def test_admin_unlock_window_expires(client, monkeypatch):
    monkeypatch.setattr(settings, "admin_unlock_window_seconds", 1)
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "TokLock#2026"})
    assert r.status_code == 200, r.text
    ah = {"Authorization": f"Bearer {r.json()['token']}"}
    r = client.post("/api/auth/admin-unlock", json={"password": "TokLock#2026"}, headers=ah)
    assert r.status_code == 200, r.text
    r_now = client.post("/api/auth/users", json={
        "username": "inwindow", "email": "inwindow@x.com",
        "password": "TokAdm#2026"}, headers=ah)
    assert r_now.status_code == 200, f"trong window phải 200: {r_now.text}"
    time.sleep(1.15)
    r_after = client.post("/api/auth/users", json={
        "username": "outwindow", "email": "outwindow@x.com",
        "password": "TokAdm#2026"}, headers=ah)
    assert r_after.status_code == 403, f"hết window phải 403 reauth: {r_after.text}"
    assert "reauth" in r_after.text.lower()


def test_me_re_mint_sliding_token_killed_by_epoch(client):
    r = client.post("/api/auth/register", json={
        "username": "slideuser", "email": "slideuser@x.com",
        "password": "Slide#2026x", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    tok = r.json()["token"]
    r_me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert r_me.status_code == 200, r_me.text
    slid = r_me.json().get("token", "")
    assert slid, "/me phải re-mint token sliding"
    parts = slid.split(".")
    ttl_h = (int(parts[1]) - time.time()) / 3600.0
    assert 23.9 < ttl_h < 24.1, f"slid token TTL phải tính lại từ bây giờ: {ttl_h:.2f}h"
    r_use = client.get("/api/auth/me", headers={"Authorization": f"Bearer {slid}"})
    assert r_use.status_code == 200

    r_rev = client.post("/api/auth/revoke-all", headers={"Authorization": f"Bearer {slid}"})
    assert r_rev.status_code == 200, r_rev.text
    r_after = client.get("/api/auth/me", headers={"Authorization": f"Bearer {slid}"})
    assert r_after.status_code == 401, "token đã-slide phải chết sau revoke-all (epoch kill)"
    r_orig = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert r_orig.status_code == 401, "token gốc cũng phải chết"
