import concurrent.futures

import pytest
from fastapi.testclient import TestClient

from app.database.crud import change_password_cas
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
        "password": "RaceFix#2026", "invite_code": "TESTINVITE"})
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


def test_change_password_cas_rejects_stale_old_hash(client):
    r = client.post("/api/auth/register", json={
        "username": "casuser", "email": "casuser@x.com",
        "password": "CasOld#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == "casuser").first()
        old_hash_snapshot = u.password_hash
        changed = change_password_cas(db, u.id, old_hash_snapshot, "CASNew#2026-hash")
        assert changed is not None
        stale = change_password_cas(db, u.id, old_hash_snapshot, "StaleWin#2026-hash")
        assert stale is None, "old_hash cũ (snapshot) phải bị CAS từ chối"
        fresh = change_password_cas(db, u.id, "CASNew#2026-hash", "CASNew2#2026-hash")
        assert fresh is not None
        epoch = db.query(User).filter(User.username == "casuser").first().token_epoch
        assert epoch == 2
    finally:
        db.close()


def test_change_password_concurrent_exactly_one_winner(client):
    r = client.post("/api/auth/register", json={
        "username": "raceuser", "email": "raceuser@x.com",
        "password": "RaceOld#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    tok = r.json()["token"]

    def attempt(i):
        cc = TestClient(create_app())
        rr = cc.post("/api/auth/change-password",
                     json={"old_password": "RaceOld#2026", "new_password": f"RaceNew{i}#2026"},
                     headers={"Authorization": f"Bearer {tok}"})
        return rr.status_code, f"RaceNew{i}#2026"

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(attempt, range(8)))
    codes = [s for s, _ in results]
    winners = [pw for s, pw in results if s == 200]
    assert codes.count(200) == 1, f"8 luồng đồng thời phải đúng 1 winner CAS, codes={codes}"
    assert all(s in (400, 401) for s in codes if s != 200), f"thua cuộc phải 400/401: {codes}"

    r_ok = client.post("/api/auth/login", json={"identifier": "raceuser", "password": winners[0]})
    assert r_ok.status_code == 200, "MK winner phải login được"
    r_old = client.post("/api/auth/login", json={"identifier": "raceuser", "password": "RaceOld#2026"})
    assert r_old.status_code == 401, "MK cũ phải chết"
    r_other = client.post("/api/auth/login", json={
        "identifier": "raceuser", "password": next(pw for s, pw in results if s != 200)})
    assert r_other.status_code == 401, "MK của luồng thua CAS không được thành MK thực"

    r_me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert r_me.status_code == 401, "token cũ phải chết sau epoch bump"
