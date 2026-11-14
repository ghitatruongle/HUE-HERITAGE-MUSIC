import concurrent.futures
import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app
from app.rate_limit import RATE_LIMIT_DETAIL, hit_and_allow, reset


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
        "password": "RlLock#2026", "invite_code": "TESTINVITE"})
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
        reset()


def test_429_bodies_uniform_across_sources(client):
    bodies = []
    for i in range(130):
        r = client.post("/api/auth/login", json={"identifier": f"unirot{i}", "password": "WrongUni#x1"})
        if r.status_code == 429:
            bodies.append(r.text)

    ra = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "RlLock#2026"})
    ah = {"Authorization": f"Bearer {ra.json()['token']}"}
    for i in range(8):
        r = client.post("/api/auth/admin-unlock", json={"password": f"WrongUnlock{i}#x"}, headers=ah)
        if r.status_code == 429:
            bodies.append(r.text)

    r = client.post("/api/auth/register", json={
        "username": "slideuni", "email": "slideuni@x.com", "password": "Slide#2026x", "invite_code": "TESTINVITE"})
    tok = r.json()["token"]
    for i in range(8):
        r = client.post("/api/auth/change-password", json={
            "old_password": f"WrongOld{i}#x", "new_password": "Whatever#2026"},
            headers={"Authorization": f"Bearer {tok}"})
        if r.status_code == 429:
            bodies.append(r.text)

    assert bodies, f"phải thu được ít nhất một 429 thật, got {len(bodies)}"
    unique = set(bodies)
    assert len(unique) == 1, f"body 429 phải đồng nhất, thấy {len(unique)} biến thể: {sorted(unique)[:3]}"
    assert RATE_LIMIT_DETAIL in unique.pop()


def test_all_429_raise_sites_use_uniform_constant():
    app_dir = Path(__file__).resolve().parents[1] / "app"
    offenders = []
    for py in list(app_dir.rglob("*.py")):
        if "test" in py.name:
            continue
        src_lines = py.read_text().splitlines()
        for i, line in enumerate(src_lines, start=1):
            if "status_code=429" in line and "RATE_LIMIT_DETAIL" not in line and "JSONResponse" not in line:
                window = "\n".join(src_lines[max(0, i - 3):i + 3])
                if "RATE_LIMIT_DETAIL" in window:
                    continue
                offenders.append(f"{py.name}:{i}: {line.strip()[:90]}")
    assert not offenders, f"các điểm raise 429 phải dùng RATE_LIMIT_DETAIL: {offenders[:5]}"


def test_hit_and_allow_concurrent_burst_never_exceeds_limit():
    reset()
    allowed = {"n": 0}
    lock = __import__("threading").Lock()

    def hit(_i):
        ok = hit_and_allow("race-key-005", 20)
        with lock:
            if ok:
                allowed["n"] += 1

    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as ex:
        list(ex.map(hit, range(200)))
    assert allowed["n"] == 20, f"200 hit đồng thời limit 20 phải cho đúng 20 lượt qua, got {allowed['n']}"
    reset()
