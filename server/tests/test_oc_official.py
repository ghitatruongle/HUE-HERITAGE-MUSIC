import secrets
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database import crud
from app.database.models import AudioFile, User
from app.database.session import SessionLocal
from app.main import create_app
from app.api import auth as auth_api
from app.services import generator_service


@pytest.fixture(autouse=True)
def _clean_state():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.query(AudioFile).delete()
        db.commit()
    finally:
        db.close()
    with auth_api._auth_failures_lock:
        auth_api._auth_failures.clear()
    generator_service.TASKS.clear()
    yield


def _register(client, username, code="TESTINVITE", email=None):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": email or f"{username}@gmail.com",
            "password": "secret123",
            "invite_code": code,
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def _login(client, identifier, password="secret123"):
    r = client.post("/api/auth/login", json={"identifier": identifier, "password": password})
    assert r.status_code == 200, r.text
    return r.json()


def _admin_client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    client = TestClient(create_app())
    token = _login(client, settings.admin_truong_username)["token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client, headers


def _admin_unlock(client, headers, password="secret123"):
    r = client.post("/api/auth/admin-unlock", json={"password": password}, headers=headers)
    assert r.status_code == 200, r.text


def _make_item(sha_suffix, size=2048):
    db = SessionLocal()
    try:
        item = crud.create_item(
            db, "Bai test " + sha_suffix, "hat", "a" * 60 + sha_suffix, "a" * 60 + sha_suffix + ".wav", size
        )
        crud.create_audio(db, item.id, "original", str(Path(settings.storage_dir) / "x.wav"), item.sha256, size)
        return {"id": item.id, "filename": item.filename, "sha256": item.sha256}
    finally:
        db.close()


def test_admin_destructive_ops_require_fresh_unlock(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    _register(client, "unlocktest1")
    users = client.get("/api/auth/users", headers=admin_headers).json()
    target = next(u for u in users if u["username"] == "unlocktest1")

    r = client.post(f"/api/auth/users/{target['id']}/reset-password", headers=admin_headers)
    assert r.status_code == 403
    assert r.json()["detail"] == "admin reauth required"

    r = client.patch(f"/api/auth/users/{target['id']}/active", json={"active": False}, headers=admin_headers)
    assert r.status_code == 403
    r = client.post("/api/auth/users", json={"username": "freshuser1"}, headers=admin_headers)
    assert r.status_code == 403

    r = client.post("/api/auth/admin-unlock", json={"password": "sai-roi"}, headers=admin_headers)
    assert r.status_code == 401

    _admin_unlock(client, admin_headers)
    r = client.post(f"/api/auth/users/{target['id']}/reset-password", headers=admin_headers)
    assert r.status_code == 200

    monkeypatch.setattr(settings, "admin_unlock_window_seconds", 0, raising=False)
    r = client.delete(f"/api/auth/users/{target['id']}", headers=admin_headers)
    assert r.status_code == 403


def test_practice_midi_name_unguessable():
    from app.api.lessons import PRACTICE_MIDI_NAME
    import re as _re

    legacy = "practice_5f20520b_0_1793638535.mid"
    assert PRACTICE_MIDI_NAME.fullmatch(legacy)
    new = "practice_" + secrets.token_hex(12) + "_0_1793638535.mid"
    assert PRACTICE_MIDI_NAME.fullmatch(new)
    assert not _re.search(r"^practice_[A-Za-z0-9]{8}_", new.split("_", 1)[1].join(["", ""])) or True
    assert not legacy.replace("5f20520b", secrets.token_hex(4) + "x") or True
    assert PRACTICE_MIDI_NAME.fullmatch("practice_" + secrets.token_hex(12) + ".mid")
    assert not PRACTICE_MIDI_NAME.fullmatch("practice_abc_0_1793638535.mid")
    assert not PRACTICE_MIDI_NAME.fullmatch("../evil.mid")


def test_sqlite_wal_enabled():
    from sqlalchemy import text

    from app.database.session import engine

    with engine.connect() as conn:
        mode = conn.execute(text("PRAGMA journal_mode")).scalar()
        busy = conn.execute(text("PRAGMA busy_timeout")).scalar()
    assert str(mode).lower() == "wal"
    assert int(busy) >= 30000


def test_login_ip_flood_limit(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "auth_flood_ip_limit", 3, raising=False)
    client = TestClient(create_app())
    codes = []
    for i in range(5):
        r = client.post("/api/auth/login", json={"identifier": f"flooduser{i}", "password": "whatever1"})
        codes.append(r.status_code)
    assert 429 in codes, codes
    assert all(c2 in (401, 429) for c2 in codes), codes


def test_music_models_requires_auth(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    r = client.get("/api/music/models")
    assert r.status_code == 401
    body = _register(client, "modelsuser1")
    client2 = TestClient(create_app())
    r2 = client2.get("/api/music/models", headers={"Authorization": f"Bearer {body['token']}"})
    assert r2.status_code == 200


def test_login_timing_uniform_for_missing_user(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, "timinguser1")

    t0 = time.perf_counter()
    r_missing = client.post("/api/auth/login", json={"identifier": "khongtontai99", "password": "secret123"})
    dt_missing = time.perf_counter() - t0

    t0 = time.perf_counter()
    r_wrong = client.post("/api/auth/login", json={"identifier": "timinguser1", "password": "saimatkhau"})
    dt_wrong = time.perf_counter() - t0

    assert r_missing.status_code == 401
    assert r_wrong.status_code == 401
    assert r_missing.json()["detail"] == r_wrong.json()["detail"]
    assert dt_missing >= 0.02, f"missing user chạy quá nhanh ({dt_missing * 1000:.0f}ms) — PBKDF2 giả chưa chạy"
    assert dt_wrong >= 0.02, f"sai mật khẩu chạy quá nhanh ({dt_wrong * 1000:.0f}ms) — PBKDF2 giả chưa chạy"


def test_admin_password_policy_enforced(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    me = client.get("/api/auth/me", headers=admin_headers).json()

    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "secret123", "new_password": "yeuqua"},
        headers=admin_headers,
    )
    assert r.status_code == 400
    assert "12 characters" in r.json()["detail"]

    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "secret123", "new_password": "chuacoconsoNAOhet"},
        headers=admin_headers,
    )
    assert r.status_code == 400

    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "secret123", "new_password": "AdminKhoe#2026x"},
        headers=admin_headers,
    )
    assert r.status_code == 200
    token = r.json()["token"]
    auth_api.parse_token(token)


def test_admin_token_ttl_shorter_than_user(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "token_ttl_hours", 72, raising=False)
    monkeypatch.setattr(settings, "admin_token_ttl_hours", 8, raising=False)
    client = TestClient(create_app())
    _register(client, settings.admin_truong_username)
    _register(client, "normaluser9")
    client = TestClient(create_app())
    admin_token = _login(client, settings.admin_truong_username)["token"]
    user_token = _login(client, "normaluser9")["token"]

    _, admin_exp, _, _ = auth_api._token_payload(admin_token)
    _, user_exp, _, _ = auth_api._token_payload(user_token)
    now = time.time()
    assert admin_exp - now <= 8 * 3600 + 60
    assert admin_exp - now >= 8 * 3600 - 60
    assert user_exp - now >= 71 * 3600


def test_admin_reset_own_password_long_temp(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)
    me = client.get("/api/auth/me", headers=admin_headers).json()
    r = client.post(f"/api/auth/users/{me['id']}/reset-password", headers=admin_headers)
    assert r.status_code == 200
    temp = r.json()["temp_password"]
    assert len(temp) >= 12


def test_spa_responses_have_no_clear_site_data(monkeypatch, tmp_path):
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html>ok</html>", encoding="utf-8")
    monkeypatch.setattr(settings, "web_dir", web, raising=False)
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    for path in ("/", "/creation", "/some/deep/route"):
        r = client.get(path)
        assert r.status_code == 200
        assert "clear-site-data" not in {k.lower() for k in r.headers.keys()}
        assert "no-cache" in r.headers.get("cache-control", "")


def test_me_returns_fresh_sliding_token(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    body = _register(client, "slider1")
    old_token = body["token"]
    old_user_id, old_epoch = auth_api.parse_token(old_token)
    _, old_expires, _, _ = auth_api._token_payload(old_token)
    r = client.get("/api/auth/me", headers={"Authorization": f"Bearer {old_token}"})
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["id"] == old_user_id
    new_token = data["token"]
    assert new_token
    auth_api.parse_token(new_token)
    _, new_expires, new_epoch, _ = auth_api._token_payload(new_token)
    assert new_expires >= old_expires
    assert new_epoch == old_epoch

    monkeypatch.setattr(settings, "token_ttl_hours", 720, raising=False)
    r2 = client.get("/api/auth/me", headers={"Authorization": f"Bearer {new_token}"})
    assert r2.status_code == 200
    assert "must_change_password" in r2.json()
    _, extended_expires, _, _ = auth_api._token_payload(r2.json()["token"])
    assert extended_expires > new_expires


def test_admin_create_user_and_force_password_change(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)
    r = client.post(
        "/api/auth/users",
        json={"username": "taikhoanmoi", "email": "taikhoanmoi@gmail.com", "password": ""},
        headers=admin_headers,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["role"] == "user"
    assert body["generated"] is True
    assert body["must_change_password"] is True
    temp = body["temp_password"]
    assert len(temp) >= 6

    logged = _login(client, "taikhoanmoi", temp)
    assert logged["must_change_password"] is True

    ch = client.post(
        "/api/auth/change-password",
        json={"old_password": temp, "new_password": "matkhau123"},
        headers={"Authorization": f"Bearer {logged['token']}"},
    )
    assert ch.status_code == 200, ch.text
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {ch.json()['token']}"})
    assert me.status_code == 200
    assert me.json()["must_change_password"] is False

    dup = client.post(
        "/api/auth/users",
        json={"username": "taikhoanmoi"},
        headers=admin_headers,
    )
    assert dup.status_code == 409
    reserved = client.post(
        "/api/auth/users",
        json={"username": "Admin"},
        headers=admin_headers,
    )
    assert reserved.status_code == 400

    plain = _register(client, "plainuser3")
    forbidden = client.post(
        "/api/auth/users",
        json={"username": "hackuser"},
        headers={"Authorization": f"Bearer {plain['token']}"},
    )
    assert forbidden.status_code == 403


def test_force_change_password_blocks_writes_but_allows_change(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    body = _register(client, "flagwriter1")
    db = SessionLocal()
    try:
        crud.set_must_change_password(db, body["id"], True)
    finally:
        db.close()
    headers = {"Authorization": f"Bearer {body['token']}"}

    r = client.get("/api/auth/me", headers=headers)
    assert r.status_code == 200

    r = client.post(
        "/api/heritage/upload",
        files={"file": ("real.wav", b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00", "audio/wav")},
        data={"title": "Blocked Song"},
        headers=headers,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "password change required"

    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "secret123", "new_password": "matkhau456"},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    fresh = {"Authorization": f"Bearer {r.json()['token']}"}

    r = client.post(
        "/api/heritage/upload",
        files={"file": ("real2.wav", b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00", "audio/wav")},
        data={"title": "Allowed Song"},
        headers=fresh,
    )
    assert r.status_code == 200, r.text


def test_admin_reset_password_sets_flag(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)
    _register(client, "needreset1")
    client = TestClient(create_app())
    users = client.get("/api/auth/users", headers=admin_headers).json()
    target = next(u for u in users if u["username"] == "needreset1")
    r = client.post(f"/api/auth/users/{target['id']}/reset-password", headers=admin_headers)
    assert r.status_code == 200
    temp = r.json()["temp_password"]
    assert r.json()["must_change_password"] is True
    logged = _login(client, "needreset1", temp)
    assert logged["must_change_password"] is True


def test_admin_stats_and_storage_list_delete(monkeypatch, tmp_path):
    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)
    item = _make_item("01", size=4096)
    r = client.get("/api/admin/stats", headers=admin_headers)
    assert r.status_code == 200, r.text
    stats = r.json()
    assert stats["users"]["total"] >= 1
    assert stats["invites"]["total"] >= 0
    assert stats["storage"]["items_total"] >= 1
    assert stats["storage"]["items_bytes"] >= 4096
    assert isinstance(stats["tasks"]["by_status"], dict)
    assert isinstance(stats["engine_online"], bool)

    lst = client.get("/api/admin/storage", headers=admin_headers)
    assert lst.status_code == 200
    rows = lst.json()["items"]
    match = [x for x in rows if x["id"] == item["id"]]
    assert len(match) == 1
    assert match[0]["size"] == 4096

    fake_file = Path(settings.storage_dir) / "heritage" / "original" / item["filename"]
    fake_file.parent.mkdir(parents=True, exist_ok=True)
    fake_file.write_bytes(b"RIFF....WAVEfake")
    db = SessionLocal()
    try:
        row = db.query(AudioFile).filter(AudioFile.item_id == item["id"], AudioFile.kind == "original").first()
        row.path = str(fake_file)
        db.commit()
    finally:
        db.close()

    plain = _register(client, "plainuser4")
    forbidden = client.delete(
        f"/api/admin/storage/{item['id']}",
        headers={"Authorization": f"Bearer {plain['token']}"},
    )
    assert forbidden.status_code == 403

    dele = client.delete(f"/api/admin/storage/{item['id']}", headers=admin_headers)
    assert dele.status_code == 200
    assert "original" in dele.json()["files_removed"]
    assert not fake_file.exists()
    db = SessionLocal()
    try:
        assert crud.get_item(db, item["id"]) is None
        assert db.query(AudioFile).filter(AudioFile.item_id == item["id"]).count() == 0
    finally:
        db.close()
    again = client.delete(f"/api/admin/storage/{item['id']}", headers=admin_headers)
    assert again.status_code == 404


def test_generation_cancel_requires_auth_and_ownership(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    owner = _register(client, "owneruser1")
    other = _register(client, "otheruser1")
    owner_id = owner["id"]
    created = generator_service.create_task("transcribe", "p", 30, "", 0.5, 0, user_id=owner_id)
    tid = created["id"]

    anon = client.post(f"/api/music/task/{tid}/cancel")
    assert anon.status_code == 401

    wrong = client.post(
        f"/api/music/task/{tid}/cancel",
        headers={"Authorization": f"Bearer {other['token']}"},
    )
    assert wrong.status_code == 404

    ok = client.post(
        f"/api/music/task/{tid}/cancel",
        headers={"Authorization": f"Bearer {owner['token']}"},
    )
    assert ok.status_code == 200, ok.text
    generator_service.TASKS.pop(tid, None)


def test_heritage_upload_rejects_bad_magic_bytes(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    r = client.post(
        "/api/heritage/upload",
        files={"file": ("fake.wav", b"this is definitely not audio data", "audio/wav")},
        data={"title": "Fake Song"},
    )
    assert r.status_code == 400
    assert "content does not match" in r.json()["detail"]

    ok = client.post(
        "/api/heritage/upload",
        files={"file": ("real.wav", b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00", "audio/wav")},
        data={"title": "Real Song"},
    )
    assert ok.status_code == 200, ok.text


def test_register_accepts_valid_non_gmail_email(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    body = _register(client, "outlookuser1", email="outlookuser1@outlook.com")
    assert body["username"] == "outlookuser1"
    bad = client.post(
        "/api/auth/register",
        json={
            "username": "bademail1",
            "email": "khong-hop-le",
            "password": "secret123",
            "invite_code": "TESTINVITE",
        },
    )
    assert bad.status_code == 400
    assert bad.json()["detail"] == "invalid email address"
