import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app

ORIGINS = [
    "https://evil.example",
    "null",
    "http://127.0.0.1:8003.evil.example",
    "http://127.0.0.1:8003.",
]

MUTATING = [
    ("/api/auth/login", {"identifier": "victim", "password": "Forged#2026"}),
    ("/api/auth/admin-unlock", {"password": "Forged#2026"}),
    ("/api/auth/register", {"username": "forgedx", "email": "f@x.com", "password": "Forged#2026", "invite_code": "TESTINVITE"}),
    ("/api/crash-reports", {"summary": "forged"}),
]

OPEN_BY_DESIGN = {"login", "register"}


@pytest.fixture()
def cors_client(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "hue-csrf-lock-key-" + "0" * 40, raising=False)
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "x@x.com",
        "password": "CsrfLock#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    yield client
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def test_csrf_origin_matrix_never_echoes_or_authenticates(cors_client):
    client = cors_client
    for origin in ORIGINS:
        pre = client.options("/api/auth/login", headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type"})
        acao = pre.headers.get("access-control-allow-origin", "")
        assert acao != origin or origin == "null" and acao == "", (
            f"preflight echo evil origin {origin!r} -> ACAO={acao!r}")
        assert pre.headers.get("access-control-allow-credentials", "").lower() != "true"
        for route, body in MUTATING:
            r = client.post(route, json=body, headers={"Origin": origin})
            assert "set-cookie" not in r.headers, f"{route} origin={origin!r} gắn cookie"
            assert r.headers.get("access-control-allow-origin", "") != origin, (
                f"{route} echo evil origin {origin!r}")
            name = route.rsplit("/", 1)[-1]
            if name in OPEN_BY_DESIGN:
                assert r.status_code in (200, 400, 401, 409, 422, 429), f"{route} -> {r.status_code}"
                if r.status_code == 200:
                    assert name == "register", "login 200 với MK sai là bất thường"
            else:
                assert r.status_code in (400, 401, 403, 404, 422, 429), (
                    f"route đòi Bearer bị forged đi qua! {route} origin={origin!r} -> {r.status_code}")


def test_csrf_forged_bearer_and_shapes_stay_blocked(cors_client):
    client = cors_client
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "CsrfLock#2026"})
    assert r.status_code == 200 and "set-cookie" not in r.headers
    token = r.json()["token"]
    for route, body in MUTATING:
        for shape in ("form", "text-plain", "forged-bearer"):
            if shape == "form":
                r = client.post(route, data={"identifier": "victim", "password": "Forged#2026"},
                                headers={"Origin": "https://evil.example"})
            elif shape == "text-plain":
                r = client.post(route, content=str(body), headers={
                    "Content-Type": "text/plain", "Origin": "https://evil.example",
                    "Authorization": f"Bearer {token}"})
            else:
                r = client.post(route, json=body, headers={
                    "Origin": "https://evil.example", "Authorization": "Bearer forgedtoken0000"})
            name = route.rsplit("/", 1)[-1]
            if name in OPEN_BY_DESIGN and r.status_code == 200:
                assert "set-cookie" not in r.headers
                assert r.headers.get("access-control-allow-origin", "") != "https://evil.example"
                continue
            assert r.status_code in (400, 401, 403, 404, 422, 429), (
                f"forged đi qua route đòi Bearer! {route} [{shape}] -> {r.status_code} {r.text[:80]}")
            assert r.headers.get("access-control-allow-origin", "") != "https://evil.example"


def test_csrf_victim_token_never_flows_via_origin(cors_client):
    client = cors_client
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "CsrfLock#2026"})
    token = r.json()["token"]
    r = client.post("/api/auth/change-password", json={
        "old_password": "CsrfLock#2026", "new_password": "Hacked#2026x"},
        headers={"Origin": "https://evil.example"})
    assert r.status_code == 401, (
        f"request forged trình-duyệt (0 Bearer) từ evil phải 401, thật={r.status_code}")
    assert r.headers.get("access-control-allow-origin", "") != "https://evil.example"
    r = client.post("/api/auth/change-password", json={
        "old_password": "SaiHe#2026zz", "new_password": "Hacked#2026x"},
        headers={"Origin": "https://evil.example", "Authorization": f"Bearer {token}"})
    assert r.headers.get("access-control-allow-origin", "") != "https://evil.example"
    assert r.status_code in (400, 401), (
        f"stolen-token + old-MK sai vẫn không đổi được MK: {r.status_code}")
    r = client.post("/api/auth/change-password", json={
        "old_password": "CsrfLock#2026", "new_password": "CsrfLock#2026"},
        headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, (
        "Bearer thật + old-MK đúng (client hợp lệ) phải 200 — mọi hđộng đổi trạng thái đi qua Bearer header")
    r = client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "CsrfLock#2026"}, timeout=20)
    assert r.status_code == 200
