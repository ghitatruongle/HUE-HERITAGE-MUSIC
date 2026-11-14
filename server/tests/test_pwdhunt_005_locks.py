import pytest
from fastapi.testclient import TestClient

from app.api import auth as auth_api
from app.main import create_app
from app.database.session import SessionLocal
from app.database.models import User


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
        "password": "PwdHunt#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    TestClient(create_app())
    yield client
    db = SessionLocal()
    try:
        for name in ("ghitatruongle", "madeok01"):
            u = db.query(User).filter(User.username == name).first()
            if u is not None:
                db.delete(u)
        db.commit()
    finally:
        db.close()


def test_register_dup_username_still_runs_dummy_hash(client, monkeypatch):
    calls = {"n": 0}
    real_hash = auth_api.hash_password

    def counting_hash(password):
        calls["n"] += 1
        return real_hash(password)

    monkeypatch.setattr(auth_api, "hash_password", counting_hash)
    calls["n"] = 0
    r1 = client.post("/api/auth/register", json={
        "username": "constwork", "email": "constwork@x.com",
        "password": "ConstWork#2026", "invite_code": "TESTINVITE"})
    assert r1.status_code == 200, r1.text
    success_calls = calls["n"]

    calls["n"] = 0
    r2 = client.post("/api/auth/register", json={
        "username": "constwork", "email": "other@x.com",
        "password": "ConstWork#2026", "invite_code": "TESTINVITE"})
    assert r2.status_code == 409, r2.text
    assert calls["n"] >= 1, (
        "dup-username phải vẫn chạy hash (dummy work) để không tạo timing oracle enumeration"
    )
    assert calls["n"] == success_calls or calls["n"] >= 1

    calls["n"] = 0
    r3 = client.post("/api/auth/register", json={
        "username": "constwork2", "email": "constwork@x.com",
        "password": "ConstWork#2026", "invite_code": "TESTINVITE"})
    assert r3.status_code == 409, r3.text
    assert calls["n"] >= 1, "dup-email cũng phải chạy dummy hash"


def test_admin_create_requires_reauth_unlock_then_works(client):
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "PwdHunt#2026"})
    assert r.status_code == 200, r.text
    tok = r.json()["token"]
    ah = {"Authorization": f"Bearer {tok}"}

    r_no_unlock = client.post("/api/auth/users", json={
        "username": "reauthcheck", "email": "reauthcheck@x.com",
        "password": "AdminMade#2026"}, headers=ah)
    assert r_no_unlock.status_code == 403, r_no_unlock.text
    assert "reauth" in r_no_unlock.text.lower()

    for i in range(4):
        ru = client.post("/api/auth/admin-unlock", json={"password": f"WrongUnlock{i}#x"}, headers=ah)
        assert ru.status_code in (401, 429), ru.text

    r_unlock = client.post("/api/auth/admin-unlock", json={"password": "PwdHunt#2026"}, headers=ah)
    assert r_unlock.status_code == 200, r_unlock.text

    r_weak = client.post("/api/auth/users", json={
        "username": "weakmk01", "email": "weakmk01@x.com",
        "password": "short12"}, headers=ah)
    assert r_weak.status_code in (400, 422), r_weak.text

    r_ok = client.post("/api/auth/users", json={
        "username": "madeok01", "email": "madeok01@x.com",
        "password": "AdminMade#2026"}, headers=ah)
    assert r_ok.status_code == 200, r_ok.text
