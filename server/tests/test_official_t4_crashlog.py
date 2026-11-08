import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.models import AudioFile, CrashReport, HeritageItem, User
from app.database.session import SessionLocal
from app.main import create_app


def _wipe():
    db = SessionLocal()
    try:
        db.query(CrashReport).delete()
        db.query(AudioFile).delete()
        db.query(HeritageItem).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


@pytest.fixture()
def crash_env(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    _wipe()
    yield
    _wipe()


def _register(client, username, password):
    r = client.post("/api/auth/register", json={
        "username": username, "email": f"{username}@x.com",
        "password": password, "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text


def _login(client, username, password):
    r = client.post("/api/auth/login", json={"identifier": username, "password": password})
    assert r.status_code == 200, r.text
    client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})


def test_crash_report_flow_admin_only_view(crash_env):
    anon = TestClient(create_app())
    r = anon.post("/api/crash-reports", json={"summary": "anon boom"})
    assert r.status_code == 401

    user_client = TestClient(create_app())
    _register(user_client, "crash_user1", "CrashPass#2026")
    _login(user_client, "crash_user1", "CrashPass#2026")
    r = user_client.post("/api/crash-reports", json={"summary": "boom", "detail": "Traceback..."})
    assert r.status_code == 200, r.text
    assert r.json()["received"] is True
    r = user_client.post("/api/crash-reports", json={"summary": "", "detail": ""})
    assert r.status_code == 400
    r = user_client.get("/api/admin/crash-reports")
    assert r.status_code == 403

    admin_client = TestClient(create_app())
    _register(admin_client, "ghitatruongle", "CrashAdmin#2026")
    TestClient(create_app())
    _login(admin_client, "ghitatruongle", "CrashAdmin#2026")
    r = admin_client.get("/api/admin/crash-reports")
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert len(items) >= 1
    assert any(i["summary"] == "boom" for i in items)
    assert all("user_id" in i for i in items)
    assert all("detail" not in i for i in items), "list không được trả detail (unbounded)"
    target = next(i for i in items if i["summary"] == "boom")
    r = admin_client.get(f"/api/admin/crash-reports/{target['id']}")
    assert r.status_code == 200, r.text
    assert r.json()["detail"] == "Traceback..."
    r = admin_client.post("/api/auth/admin-unlock", json={"password": "CrashAdmin#2026"})
    assert r.status_code == 200, r.text
    r = admin_client.delete("/api/admin/crash-reports")
    assert r.status_code == 200, r.text
    assert r.json()["deleted"] >= 1
    r = admin_client.get("/api/admin/crash-reports")
    assert r.json()["items"] == []


def test_crash_report_detail_cap(crash_env):
    client = TestClient(create_app())
    _register(client, "crash_user2", "CrashPass#2026")
    _login(client, "crash_user2", "CrashPass#2026")
    r = client.post("/api/crash-reports", json={"summary": "big", "detail": "x" * (256 * 1024 + 1)})
    assert r.status_code == 413


def test_crash_report_sqli_payload_stored_inert(crash_env):
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "crash_sqli_user", "email": "sqli@x.com",
        "password": "CrashPass#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client.post("/api/auth/login", json={"identifier": "crash_sqli_user", "password": "CrashPass#2026"})
    client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    payload = "'; DROP TABLE users; --' UNION SELECT password_hash FROM users --"
    r = client.post("/api/crash-reports", json={
        "app_version": payload[:64], "platform": payload[:64],
        "summary": payload[:500], "detail": payload * 3})
    assert r.status_code == 200, r.text
    admin_client = TestClient(create_app())
    admin_client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "sqliadmin@x.com",
        "password": "CrashAdmin#2026", "invite_code": "TESTINVITE"})
    TestClient(create_app())
    r = admin_client.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "CrashAdmin#2026"})
    admin_client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    r = admin_client.get("/api/admin/crash-reports")
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert any("DROP TABLE users" in i["summary"] for i in items)
    target = next(i for i in items if "DROP TABLE users" in i["summary"])
    r = admin_client.get(f"/api/admin/crash-reports/{target['id']}")
    assert r.status_code == 200, r.text
    assert "DROP TABLE users" in r.json()["detail"]
    from app.database.models import User
    db = SessionLocal()
    try:
        assert db.query(User).filter(User.role == "admin", User.username != "ghitatruongle").count() == 0
    finally:
        db.close()


def test_crash_payload_never_html(crash_env):
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "crash_xss_user", "email": "xss@x.com",
        "password": "CrashPass#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client.post("/api/auth/login", json={"identifier": "crash_xss_user", "password": "CrashPass#2026"})
    client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    payload = "<script>alert(document.cookie)</script><img src=x onerror=alert(1)>"
    r = client.post("/api/crash-reports", json={
        "app_version": payload[:64], "platform": payload[:64],
        "summary": payload[:500], "detail": payload * 3})
    assert r.status_code == 200, r.text
    r2 = client.get("/api/health")
    assert "text/html" not in r2.headers.get("content-type", "")
    for resp in (r, r2):
        assert resp.headers.get("content-security-policy")
        assert resp.headers.get("x-content-type-options") == "nosniff"


def test_crash_report_csrf_forged_blocked(crash_env):
    client = TestClient(create_app())
    r = client.post("/api/crash-reports", content="x=1",
                    headers={"Content-Type": "application/x-www-form-urlencoded",
                             "Origin": "https://evil.example"})
    assert r.status_code == 401
    assert r.headers.get("access-control-allow-origin") != "https://evil.example"
    assert "set-cookie" not in {k.lower() for k in r.headers.keys()}
    assert r.headers.get("content-security-policy")


def test_crash_detail_multibyte_cap(crash_env):
    client = TestClient(create_app())
    r = client.post("/api/auth/register", json={
        "username": "crash_utf_user", "email": "utf@x.com",
        "password": "CrashPass#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    r = client.post("/api/auth/login", json={"identifier": "crash_utf_user", "password": "CrashPass#2026"})
    client.headers.update({"Authorization": f"Bearer {r.json()['token']}"})
    viet_detail = "Tiếng Việt đầy đủ dấu: ơ ư ạ ế ộ " * 10000
    r = client.post("/api/crash-reports", json={"summary": "utf8", "detail": viet_detail})
    assert r.status_code == 413
    r = client.post("/api/crash-reports", json={"summary": "utf8 ok", "detail": viet_detail[:20000]})
    assert r.status_code == 200, r.text
