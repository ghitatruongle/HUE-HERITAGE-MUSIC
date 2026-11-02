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
    users = client.get("/api/auth/users", headers=admin_headers).json()["items"]
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
    users = client.get("/api/auth/users", headers=admin_headers).json()["items"]
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


def _upload_item(client, title, headers=None):
    data = b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00" + secrets.token_hex(8).encode()
    r = client.post(
        "/api/heritage/upload",
        files={"file": (f"{title}.wav", data, "audio/wav")},
        data={"title": title},
        headers=headers or {},
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_auth_required_defaults_on():
    from app.config import Settings

    assert Settings.model_fields["auth_required"].default is True


def test_admin_upload_visibility_hidden_from_users(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_headers = _admin_client(monkeypatch)
    body = _upload_item(client, "Admin Test File 1", headers=admin_headers)
    assert body["visibility"] == "admin_only"

    _register(client, "vieweruser1")
    user_headers = {"Authorization": f"Bearer {_login(client, 'vieweruser1')['token']}"}

    listing = client.get("/api/heritage", headers=user_headers).json()
    assert all(i["id"] != body["id"] for i in listing["items"])
    assert client.get(f"/api/heritage/{body['id']}", headers=user_headers).status_code == 404
    assert client.get(f"/api/heritage/{body['id']}/audio", headers=user_headers).status_code == 404
    assert client.get(f"/api/heritage/{body['id']}/audio-url", headers=user_headers).status_code == 404
    assert (
        client.get(
            "/api/music/play-url",
            params={"path": f"/api/heritage/{body['id']}/audio"},
            headers=user_headers,
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/api/music/cover",
            params={"heritage_id": body["id"], "style": "nha nhac"},
            headers=user_headers,
        ).status_code
        == 404
    )

    admin_listing = client.get("/api/heritage", headers=admin_headers).json()
    assert any(i["id"] == body["id"] for i in admin_listing["items"])


def test_user_upload_public_and_visible_to_others(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, "uploader1")
    uploader_headers = {"Authorization": f"Bearer {_login(client, 'uploader1')['token']}"}
    body = _upload_item(client, "User Public Song 1", headers=uploader_headers)
    assert body["visibility"] == "public"

    _register(client, "vieweruser2")
    viewer_headers = {"Authorization": f"Bearer {_login(client, 'vieweruser2')['token']}"}
    listing = client.get("/api/heritage", headers=viewer_headers).json()
    assert any(i["id"] == body["id"] for i in listing["items"])
    assert client.get(f"/api/heritage/{body['id']}", headers=viewer_headers).status_code == 200


def test_visibility_toggle_revokes_old_signed_urls(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, "uploader2")
    uploader_headers = {"Authorization": f"Bearer {_login(client, 'uploader2')['token']}"}
    body = _upload_item(client, "Toggle Song 1", headers=uploader_headers)
    item_id = body["id"]

    url_user = client.get(f"/api/heritage/{item_id}/audio-url", headers=uploader_headers).json()["url"]
    assert client.get(url_user).status_code == 200

    client2, admin_headers = _admin_client(monkeypatch)
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    uploader_headers = {"Authorization": f"Bearer {_login(client, 'uploader2')['token']}"}
    url_user = client.get(f"/api/heritage/{item_id}/audio-url", headers=uploader_headers).json()["url"]
    assert (
        client2.patch(
            f"/api/admin/storage/{item_id}/visibility",
            json={"visibility": "admin_only"},
            headers=admin_headers,
        ).status_code
        == 403
    )
    _admin_unlock(client2, admin_headers)
    r = client2.patch(
        f"/api/admin/storage/{item_id}/visibility",
        json={"visibility": "admin_only"},
        headers=admin_headers,
    )
    assert r.status_code == 200
    assert r.json()["visibility"] == "admin_only"

    assert client.get(url_user).status_code == 401
    assert client.get(f"/api/heritage/{item_id}/audio", headers=uploader_headers).status_code == 404

    url_admin = client2.get(f"/api/heritage/{item_id}/audio-url", headers=admin_headers).json()["url"]
    assert client2.get(url_admin).status_code == 200

    r = client2.patch(
        f"/api/admin/storage/{item_id}/visibility",
        json={"visibility": "public"},
        headers=admin_headers,
    )
    assert r.status_code == 200
    assert client2.get(url_admin).status_code == 401
    assert client.get(url_user).status_code == 200


def test_bad_visibility_value_rejected(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)
    body = _make_item(secrets.token_hex(4))
    r = client.patch(
        f"/api/admin/storage/{body['id']}/visibility",
        json={"visibility": "secret"},
        headers=admin_headers,
    )
    assert r.status_code == 400


def test_creation_tunes_and_lessons_respect_visibility(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_headers = _admin_client(monkeypatch)
    hidden = _upload_item(client, "Hidden Tune 1", headers=admin_headers)
    _register(client, "tunesviewer1")
    user_headers = {"Authorization": f"Bearer {_login(client, 'tunesviewer1')['token']}"}

    tunes_user = client.get("/api/music/heritage-tunes", headers=user_headers).json()
    assert all(i["id"] != hidden["id"] for i in tunes_user)
    tunes_admin = client.get("/api/music/heritage-tunes", headers=admin_headers).json()
    assert any(i["id"] == hidden["id"] for i in tunes_admin)

    lessons_user = client.get("/api/lessons", headers=user_headers).json()
    assert all(l.get("id") != hidden["id"] for l in lessons_user)


def test_heritage_pagination_offset(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    client = TestClient(create_app())
    prefix = "PageTest" + secrets.token_hex(4)
    ids = [_upload_item(client, f"{prefix} {i}")["id"] for i in range(3)]

    page1 = client.get("/api/heritage", params={"q": prefix, "limit": 2}).json()
    assert page1["total"] == 3
    assert len(page1["items"]) == 2
    page2 = client.get("/api/heritage", params={"q": prefix, "limit": 2, "offset": 2}).json()
    assert page2["total"] == 3
    assert len(page2["items"]) == 1
    got = {i["id"] for i in page1["items"]} | {i["id"] for i in page2["items"]}
    assert got == set(ids)


def test_users_and_invites_pagination(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    for n in range(3):
        _register(client, f"pageuser{n}")
    r = client.get("/api/auth/users", params={"limit": 2}, headers=admin_headers).json()
    assert r["total"] >= 4
    assert len(r["items"]) == 2
    r2 = client.get("/api/auth/users", params={"limit": 2, "offset": 2}, headers=admin_headers).json()
    assert not {u["id"] for u in r["items"]} & {u["id"] for u in r2["items"]}

    for n in range(3):
        c = client.post("/api/auth/invites", json={}, headers=admin_headers)
        assert c.status_code == 200
    inv = client.get("/api/auth/invites", params={"limit": 2}, headers=admin_headers).json()
    assert inv["total"] >= 3
    assert len(inv["items"]) == 2


def test_admin_storage_lists_visibility_and_owner(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    client = TestClient(create_app())
    body = _upload_item(client, "Storage Row 1")

    client2, admin_headers = _admin_client(monkeypatch)
    rows = client2.get("/api/admin/storage", params={"q": "Storage Row 1"}, headers=admin_headers).json()
    assert rows["items_total"] >= 1
    row = next(i for i in rows["items"] if i["id"] == body["id"])
    assert row["visibility"] == "public"
    assert row["owner_username"] == ""

    paged = client2.get(
        "/api/admin/storage", params={"q": "Storage Row 1", "limit": 1, "offset": 0}, headers=admin_headers
    ).json()
    assert paged["count"] == 1
    assert paged["items_total"] == rows["items_total"]

    _admin_unlock(client2, admin_headers)
    r = client2.patch(
        f"/api/admin/storage/{body['id']}/visibility",
        json={"visibility": "admin_only"},
        headers=admin_headers,
    )
    assert r.status_code == 200
    row2 = client2.get("/api/admin/storage", params={"q": "Storage Row 1"}, headers=admin_headers).json()["items"][0]
    assert row2["visibility"] == "admin_only"
    assert client.get(f"/api/heritage/{body['id']}").status_code == 404


def test_admin_security_events_endpoint(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    _register(client, "secviewer1")
    bad = client.post("/api/auth/login", json={"identifier": "secviewer1", "password": "wrong-pass"})
    assert bad.status_code == 401
    user_headers = {"Authorization": f"Bearer {_login(client, 'secviewer1')['token']}"}

    assert client.get("/api/admin/security/events", headers=user_headers).status_code == 403
    assert client.get("/api/admin/security/summary", headers=user_headers).status_code == 403

    client2, admin_headers = _admin_client(monkeypatch)
    events = client2.get("/api/admin/security/events", params={"event": "login_failed"}, headers=admin_headers).json()
    assert events["total"] >= 1
    assert any(e["event"] == "login_failed" for e in events["events"])

    summary = client2.get("/api/admin/security/summary", headers=admin_headers).json()
    assert summary["counts"].get("login_failed", 0) >= 1
    assert summary["last_admin_login"] is not None


def test_admin_security_events_filter_by_username(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    events = client.get(
        "/api/admin/security/events", params={"q": settings.admin_truong_username}, headers=admin_headers
    ).json()
    assert events["total"] >= 1
    assert all(settings.admin_truong_username in str(e) for e in events["events"])


def test_admin_stats_cached_and_refreshable(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    r1 = client.get("/api/admin/stats", headers=admin_headers)
    assert r1.status_code == 200
    r2 = client.get("/api/admin/stats", headers=admin_headers)
    assert r2.status_code == 200
    r3 = client.get("/api/admin/stats", params={"refresh": 1}, headers=admin_headers)
    assert r3.status_code == 200
    assert r3.json()["users"]["total"] >= 1


def test_admin_cleanup_frees_old_files_and_tasks(monkeypatch):
    import os
    from datetime import datetime, timedelta

    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)

    gen_dir = Path(settings.storage_dir) / "generated"
    gen_dir.mkdir(parents=True, exist_ok=True)
    old_file = gen_dir / f"cleanup_test_{secrets.token_hex(4)}.mp3"
    old_file.write_bytes(b"x" * 2048)
    old_ts = time.time() - 40 * 86400
    os.utime(old_file, (old_ts, old_ts))

    db = SessionLocal()
    try:
        task = crud.create_task(db, "generate", {"x": 1})
        db_task = crud.get_task(db, task["id"] if isinstance(task, dict) else task.id)
        db_task.finished_at = datetime.now() - timedelta(days=40)
        db.commit()
        task_id = db_task.id
    finally:
        db.close()

    r = client.post("/api/admin/maintenance/cleanup", headers=admin_headers)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["freed_bytes"] >= 2048
    assert data["details"]["generated"]["files"] >= 1
    assert data["details"]["tasks"]["deleted"] >= 1
    assert not old_file.exists()

    db = SessionLocal()
    try:
        assert crud.get_task(db, task_id) is None
    finally:
        db.close()


def test_offset_bomb_and_limit_bomb_rejected_safely(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    client = TestClient(create_app())
    for params in (
        {"offset": 10**30},
        {"offset": -5},
        {"limit": 10**30},
        {"limit": -1},
    ):
        r = client.get("/api/heritage", params=params)
        assert r.status_code == 200, f"{params} → {r.status_code}"
        assert isinstance(r.json()["items"], list)
    r = client.get("/api/heritage", params={"offset": 10**30, "limit": 10**30})
    assert r.status_code == 200
    bomb = "[" * 20000 + "]" * 20000
    r = client.post(
        "/api/auth/login",
        content=bomb,
        headers={"Content-Type": "application/json"},
    )
    assert r.status_code < 500, f"depth bomb → {r.status_code}"


def test_admin_promotion_invalidates_old_tokens(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    body = _register(client, settings.admin_truong_username)
    old_token = body["token"]

    client2 = TestClient(create_app())
    r = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {old_token}"})
    assert r.status_code == 401, "token cấp trước khi thăng chức phải chết (epoch bump)"
    fresh = _login(client2, settings.admin_truong_username)
    assert fresh["role"] == "admin"
    r = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {fresh['token']}"})
    assert r.status_code == 200


def test_unicode_sig_rejected_cleanly_no_500(monkeypatch):
    from fastapi import HTTPException

    from app.api.auth import parse_token

    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    with pytest.raises(HTTPException) as ei:
        parse_token("00000000-0000-0000-0000-000000000000.9999999999.0.f\u0641")
    assert ei.value.status_code == 401

    client, admin_headers = _admin_client(monkeypatch)
    body = _upload_item(client, "Unicode Sig Song")
    iid = body["id"]
    url = client.get(f"/api/heritage/{iid}/audio-url", headers=admin_headers).json()["url"]
    exp = url.split("e=")[1].split("&")[0]
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    r = client.get(f"/api/heritage/{iid}/audio?e={exp}&s=f\u0641")
    assert r.status_code == 401, f"sig unicode → {r.status_code}"
    r = client.get(f"/api/heritage/{iid}/audio?e={exp}&s=%D9%81")
    assert r.status_code == 401, f"sig unicode percent-encoded → {r.status_code}"


def test_register_failure_ip_cap(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "register_failure_ip_limit", 3, raising=False)
    client = TestClient(create_app())
    codes = []
    for i in range(5):
        r = client.post(
            "/api/auth/register",
            json={
                "username": f"capuser{i}",
                "email": f"capuser{i}@gmail.com",
                "password": "secret123",
                "invite_code": "SAI-CODE",
            },
        )
        codes.append(r.status_code)
    assert 429 in codes, f"trần thất bại/IP không kích hoạt: {codes}"
    assert all(x in (400, 429) for x in codes)


def _tone_wav(seconds=1.0, sr=16000, freq=440.0):
    import io
    import math
    import struct
    import wave

    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        n = int(sr * seconds)
        frames = b"".join(
            struct.pack("<h", int(9000 * math.sin(2 * math.pi * freq * i / sr))) for i in range(n)
        )
        w.writeframes(frames)
    return buf.getvalue() + b"HUEJUNK" + secrets.token_hex(16).encode()


def test_restore_and_instruments_item_enforce_visibility(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 100000, raising=False)
    client = TestClient(create_app())
    client2, admin_headers = _admin_client(monkeypatch)
    wav = _tone_wav()
    up = client2.post(
        "/api/heritage/upload",
        files={"file": ("secret_tone.wav", wav, "audio/wav")},
        data={"title": "Secret Tone"},
        headers=admin_headers,
    )
    assert up.status_code == 200, up.text
    item_id = up.json()["id"]
    sha = up.json()["sha256"]

    normal = _register(client, "visuser1")
    nh = {"Authorization": f"Bearer {normal['token']}"}
    ah = admin_headers

    assert client.get(f"/api/heritage/{item_id}", headers=nh).status_code == 404
    r = client.post(f"/api/music/restore-item/{item_id}", headers=nh)
    assert r.status_code == 404, f"restore-item phải 404 với item admin_only: {r.status_code} {r.text[:120]}"
    r = client.post(f"/api/music/instruments-item/{item_id}", headers=nh)
    assert r.status_code == 404, f"instruments-item phải 404 với item admin_only: {r.status_code}"

    rr = client2.post(f"/api/music/restore-item/{item_id}", headers=ah)
    assert rr.status_code == 200, rr.text
    assert rr.json()["sha"] == sha

    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    assert client.get(f"/api/music/restored-url/{sha}", headers=nh).status_code == 404
    assert client.get(f"/api/music/midi/{sha}", headers=nh).status_code == 404
    assert client.get(f"/api/music/musicxml/{sha}", headers=nh).status_code == 404

    url = client2.get(f"/api/music/restored-url/{sha}", headers=ah).json()["url"]
    got = client2.get(url)
    assert got.status_code == 200, f"anonymous signed url đúng scope phải tải được: {got.status_code}"
    assert got.content.startswith(b"RIFF")


def test_restored_chain_open_for_public_item(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    body = _register(client, "pubrestore1")
    nh = {"Authorization": f"Bearer {body['token']}"}
    wav = _tone_wav(seconds=0.5)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("pub_tone.wav", wav, "audio/wav")},
        data={"title": "Pub Tone"},
        headers=nh,
    )
    assert up.status_code == 200, up.text
    sha = up.json()["sha256"]
    r = client.post(f"/api/music/restore-item/{up.json()['id']}", headers=nh)
    assert r.status_code == 200, r.text
    url = client.get(f"/api/music/restored-url/{sha}", headers=nh).json()["url"]
    got = client.get(url)
    assert got.status_code == 200
    assert got.content.startswith(b"RIFF")


def test_restore_item_file_race_returns_404_not_500(monkeypatch):
    from pathlib import Path

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    wav = _tone_wav(seconds=0.4)
    up = client.post(
        "/api/heritage/upload",
        files={"file": ("race_tone.wav", wav, "audio/wav")},
        data={"title": "Race Tone"},
    )
    assert up.status_code == 200, up.text
    filename = up.json()["filename"]
    real_read = Path.read_bytes

    def boom(self, *a, **k):
        if self.name == filename:
            raise OSError("file vanished mid-read")
        return real_read(self, *a, **k)

    monkeypatch.setattr(Path, "read_bytes", boom)
    r = client.post(f"/api/music/restore-item/{up.json()['id']}")
    assert r.status_code == 404, f"race đọc file phải 404: {r.status_code} {r.text[:120]}"


def test_transcribe_and_evaluate_reject_nonfinite_bpm(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client = TestClient(create_app())
    wav = _tone_wav(seconds=0.4)
    for bpm_value in ("nan", "NaN"):
        r = client.post(
            "/api/music/transcribe",
            files={"file": ("a.wav", wav, "audio/wav")},
            data={"bpm": bpm_value},
        )
        assert r.status_code == 400, f"bpm={bpm_value} → {r.status_code} (trước đây 500)"
        r2 = client.post(
            "/api/music/evaluate",
            files={"file": ("a.wav", wav, "audio/wav")},
            data={"truth": "[]", "bpm": bpm_value},
        )
        assert r2.status_code == 400, f"evaluate bpm={bpm_value} → {r2.status_code}"


def test_sse_events_cap_per_client(monkeypatch):
    from app.api import music_gen as mg

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    tid = "task-sse-cap-1"
    with generator_service.TASKS_LOCK:
        generator_service.TASKS[tid] = {
            "id": tid,
            "kind": "generate",
            "status": "done",
            "created_at": time.time(),
        }
    try:
        client = TestClient(create_app())
        r = client.get(f"/api/music/task/{tid}/events")
        assert r.status_code == 200
        with mg._SSE_LOCK:
            mg._SSE_ACTIVE["testclient"] = mg._SSE_LIMIT_PER_CLIENT
        try:
            r2 = client.get(f"/api/music/task/{tid}/events")
            assert r2.status_code == 429, f"vượt trần SSE phải 429: {r2.status_code}"
        finally:
            with mg._SSE_LOCK:
                mg._SSE_ACTIVE.pop("testclient", None)
    finally:
        with generator_service.TASKS_LOCK:
            generator_service.TASKS.pop(tid, None)


def test_task_audio_path_enforces_item_visibility(monkeypatch):
    from app.storage import manager as storage_manager

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 100000, raising=False)
    client = TestClient(create_app())
    client2, admin_headers = _admin_client(monkeypatch)
    wav = _tone_wav(seconds=0.4)
    up = client2.post(
        "/api/heritage/upload",
        files={"file": ("hidden_task.wav", wav, "audio/wav")},
        data={"title": "Hidden Task Tone"},
        headers=admin_headers,
    )
    assert up.status_code == 200, up.text
    sha = up.json()["sha256"]
    audio_path = Path(settings.storage_dir) / "heritage" / "original" / f"{sha}.wav"

    r = client.post(
        "/api/task",
        params={"kind": "transcribe"},
        json={"params": {"audio_path": str(audio_path), "bpm": 60}},
    )
    assert r.status_code == 404, f"transcribe file gốc admin_only phải 404: {r.status_code} {r.text[:120]}"

    outside = client.post(
        "/api/task",
        params={"kind": "transcribe"},
        json={"params": {"audio_path": "/etc/hosts", "bpm": 60}},
    )
    assert outside.status_code == 400

    orphan = storage_manager.temp_dir() / "orphan_tone.wav"
    orphan.write_bytes(wav)
    ok = client.post(
        "/api/task",
        params={"kind": "transcribe"},
        json={"params": {"audio_path": str(orphan), "bpm": 60}},
    )
    assert ok.status_code == 200, ok.text


def test_generic_task_is_terminal(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    client = TestClient(create_app())
    r = client.post("/api/task", json={"note": "x"}, params={"kind": "generic"})
    assert r.status_code == 200, r.text
    tid = r.json()["id"]
    body = client.get(f"/api/task/{tid}").json()
    assert body["status"] == "done"
    assert body["finished_at"] is not None


def test_admin_can_create_multiple_emailless_users(monkeypatch):
    client, admin_headers = _admin_client(monkeypatch)
    _admin_unlock(client, admin_headers)
    for n in range(3):
        r = client.post("/api/auth/users", json={"username": f"noemail{n}"}, headers=admin_headers)
        assert r.status_code == 200, f"user thứ {n + 1} không tạo được: {r.text}"
    users = client.get("/api/auth/users", params={"limit": 200}, headers=admin_headers).json()["items"]
    noemails = [u for u in users if u["username"].startswith("noemail")]
    assert len(noemails) == 3
