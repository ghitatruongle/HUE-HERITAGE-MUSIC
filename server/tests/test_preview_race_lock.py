import concurrent.futures
import time

from fastapi.testclient import TestClient

from app.main import app
from app.database.session import SessionLocal
from app.database.models import User


def _register(client, username, password="secret123"):
    r = client.post("/api/auth/register", json={
        "username": username, "email": f"{username}@gmail.com",
        "password": password, "invite_code": "TESTINVITE",
    })
    assert r.status_code in (200, 409), r.text
    return r.status_code


def test_concurrent_duplicate_register_creates_exactly_one_user():
    client = TestClient(app)
    stamp = str(int(time.time()))[-8:]
    uname = f"race{stamp}"

    def reg(i):
        try:
            r = client.post("/api/auth/register", json={
                "username": uname, "email": f"race{stamp}@gmail.com",
                "password": "secret123", "invite_code": "TESTINVITE",
            })
            return r.status_code
        except Exception:
            return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        codes = list(ex.map(reg, range(8)))

    assert codes.count(200) == 1, f"phải đúng 1 winner: {codes}"
    assert all(c in (200, 409) for c in codes), f"không được có 5xx: {codes}"
    db = SessionLocal()
    try:
        n = db.query(User).filter(User.username == uname).count()
        assert n == 1
    finally:
        db.close()


def test_epoch_race_change_password_leaves_exactly_one_valid_password():
    client = TestClient(app)
    stamp = str(int(time.time()))[-8:]
    uname = f"epochrace{stamp}"
    r = client.post("/api/auth/register", json={
        "username": uname, "email": f"{uname}@gmail.com",
        "password": "Old#2026abc", "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200, r.text
    old_tok = r.json()["token"]
    old_headers = {"Authorization": f"Bearer {old_tok}"}

    def chg(new_pwd):
        try:
            r = client.post("/api/auth/change-password", json={
                "old_password": "Old#2026abc", "new_password": new_pwd,
            }, headers=old_headers, timeout=30)
            return r.status_code, r.json().get("token", "")
        except Exception:
            return 0, ""

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        res = list(ex.map(chg, [f"RaceA#{stamp}", f"RaceB#{stamp}"]))

    assert all(c in (200, 401, 429) for c, _ in res), str(res)
    r = client.get("/api/auth/me", headers=old_headers, timeout=15)
    assert r.status_code == 401, "token cũ phải chết sau epoch-race"

    alive = 0
    valid_pwds = []
    for c, t in res:
        if t:
            rr = client.get("/api/auth/me", headers={"Authorization": f"Bearer {t}"}, timeout=15)
            if rr.status_code == 200:
                alive += 1
                valid_pwds.append(t)
    assert alive == 1, f"phải đúng 1 token mới sống qua epoch-race: {alive}"

    login_a = client.post("/api/auth/login", json={"username": uname, "password": f"RaceA#{stamp}"})
    login_b = client.post("/api/auth/login", json={"username": uname, "password": f"RaceB#{stamp}"})
    assert (login_a.status_code == 200) != (login_b.status_code == 200), \
        f"đúng 1 mật khẩu thắng: pwA={login_a.status_code} pwB={login_b.status_code}"
