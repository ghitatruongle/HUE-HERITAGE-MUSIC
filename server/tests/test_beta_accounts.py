import secrets

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import create_app
from app.api import auth as auth_api
from app.database.models import User, InviteCode
from app.database.session import SessionLocal


@pytest.fixture(autouse=True)
def _wipe_users():
    db = SessionLocal()
    try:
        db.query(InviteCode).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    with auth_api._auth_failures_lock:
        auth_api._auth_failures.clear()
    yield


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    return TestClient(create_app())


def _register(client, username, password="secret123"):
    r = client.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": password,
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_change_password_flow(client):
    body = _register(client, "chpwd1")
    token = body["token"]

    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "secret123", "new_password": "newpass99"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 200
    new_token = r.json()["token"]

    old_still = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert old_still.status_code == 401

    ok = client.post("/api/auth/login", json={"identifier": "chpwd1", "password": "newpass99"})
    assert ok.status_code == 200
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {new_token}"})
    assert me.status_code == 200

    wrong = client.post(
        "/api/auth/change-password",
        json={"old_password": "bad", "new_password": "another1"},
        headers={"Authorization": f"Bearer {new_token}"},
    )
    assert wrong.status_code == 401


def test_revoke_all_tokens(client):
    body = _register(client, "revoke1")
    token = body["token"]

    r = client.post("/api/auth/revoke-all", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    after = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert after.status_code == 401

    fresh = client.post("/api/auth/login", json={"identifier": "revoke1", "password": "secret123"})
    assert fresh.status_code == 200
    again = client.get("/api/auth/me", headers={"Authorization": f"Bearer {fresh.json()['token']}"})
    assert again.status_code == 200



def _admin_unlock(client2, admin_token, password="secret123"):
    r = client2.post(
        "/api/auth/admin-unlock",
        json={"password": password},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 200, r.text


def test_admin_disable_and_reset(client):
    _register(client, settings.admin_truong_username)
    client2 = TestClient(create_app())
    admin_token = client2.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]
    _admin_unlock(client2, admin_token)
    victim = _register(client2, "victim1")
    victim_token = victim["token"]
    victim_id = victim["id"]

    ok = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {victim_token}"})
    assert ok.status_code == 200

    off = client2.patch(
        f"/api/auth/users/{victim_id}/active",
        json={"active": False},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert off.status_code == 200

    blocked = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {victim_token}"})
    assert blocked.status_code in (401, 403)

    relogin = client2.post("/api/auth/login", json={"identifier": "victim1", "password": "secret123"})
    assert relogin.status_code == 403

    reset = client2.post(
        f"/api/auth/users/{victim_id}/reset-password",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert reset.status_code == 200
    temp = reset.json()["temp_password"]
    assert temp.startswith("hue-")

    still_disabled = client2.post("/api/auth/login", json={"identifier": "victim1", "password": temp})
    assert still_disabled.status_code == 403

    on = client2.patch(
        f"/api/auth/users/{victim_id}/active",
        json={"active": True},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert on.status_code == 200
    works = client2.post("/api/auth/login", json={"identifier": "victim1", "password": temp})
    assert works.status_code == 200


def test_cannot_disable_admin_truong(client):
    _register(client, settings.admin_truong_username)
    client2 = TestClient(create_app())
    admin_token = client2.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]
    _admin_unlock(client2, admin_token)
    admin_id = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {admin_token}"}).json()["id"]
    r = client2.patch(
        f"/api/auth/users/{admin_id}/active",
        json={"active": False},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 400


def test_no_default_invite_code_left():
    from app.config import Settings

    fresh = Settings(_env_file=None)
    assert fresh.invite_codes == ""
    assert fresh.token_ttl_hours == 24


def test_reserved_usernames_blocked(client):
    for name in ("admin", "administrator", "root", "system"):
        r = client.post(
            "/api/auth/register",
            json={"username": name, "email": f"x{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": "TESTINVITE"},
        )
        assert r.status_code == 400
        assert "reserved" in r.json()["detail"]


def test_identifier_wide_brute_force_cap(client):
    import time as _t

    from app.api import auth as auth_api

    _register(client, "capadmin")
    target = "capadmin"
    ip = "9.9.9.9"
    codes = []
    for i in range(25):
        # giả nhiều IP khác nhau — nhưng per-identifier cap vẫn phải chặn
        saved = auth_api._client_ip
        auth_api._client_ip = lambda req, _i=i: f"10.0.{i}.1"
        try:
            r = client.post("/api/auth/login", json={"identifier": target, "password": "wrongpass"})
            codes.append(r.status_code)
        finally:
            auth_api._client_ip = saved
    assert 429 in codes, codes
    assert codes[-1] == 429


def test_admin_delete_account_full_flow(client):
    _register(client, settings.admin_truong_username)
    client2 = TestClient(create_app())
    admin_token = client2.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]
    _admin_unlock(client2, admin_token)
    victim = _register(client2, "deleteme1")
    vid = victim["id"]
    vtok = victim["token"]

    assert client2.get("/api/auth/me", headers={"Authorization": f"Bearer {vtok}"}).status_code == 200

    r = client2.delete(f"/api/auth/users/{vid}", headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 200
    assert r.json()["username"] == "deleteme1"

    gone = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {vtok}"})
    assert gone.status_code == 401

    relogin = client2.post("/api/auth/login", json={"identifier": "deleteme1", "password": "secret123"})
    assert relogin.status_code == 401

    re_register = _register(client2, "deleteme1")
    assert re_register["role"] == "user"


def test_cannot_delete_admin_truong(client):
    _register(client, settings.admin_truong_username)
    client2 = TestClient(create_app())
    admin_token = client2.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]
    _admin_unlock(client2, admin_token)
    me = client2.get("/api/auth/me", headers={"Authorization": f"Bearer {admin_token}"}).json()
    r = client2.delete(f"/api/auth/users/{me['id']}", headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 400


def test_delete_requires_admin(client):
    victim = _register(client, "delme2")
    r = client.delete(f"/api/auth/users/{victim['id']}")
    assert r.status_code == 401


def test_parallel_change_password_all_old_tokens_die(client):
    import threading

    body = _register(client, "racepwd")
    tok = body["token"]

    outcomes = []
    lock = threading.Lock()

    def do_change(i):
        cc = TestClient(create_app())
        r = cc.post(
            "/api/auth/change-password",
            json={"old_password": "secret123", "new_password": f"racepass{i}xx"},
            headers={"Authorization": f"Bearer {tok}"},
        )
        with lock:
            outcomes.append((r.status_code, r.json().get("token", "")))

    threads = [threading.Thread(target=do_change, args=(i,)) for i in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    winners = [(code, new_tok) for code, new_tok in outcomes if code == 200]
    losers = [code for code, _ in outcomes if code != 200]
    assert len(winners) == 1, (
        f"CAS change-password: 5 luồng đồng thời phải đúng 1 winner "
        f"(stale old-hash bị từ chối 401), outcomes={outcomes}"
    )
    assert all(code in (400, 401) for code in losers), f"thua cuộc phải 400/401: {losers}"

    epochs = set()
    for _, new_tok in winners:
        r = client.get("/api/auth/me", headers={"Authorization": f"Bearer {new_tok}"})
        if r.status_code == 200:
            epochs.add(new_tok)
    surviving = len(epochs)
    assert surviving == 1, f"{surviving} token sống sót sau race (phải chỉ còn 1 token cuối)"
    r_old = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert r_old.status_code == 401, "token gốc phải chết sau epoch bump"
