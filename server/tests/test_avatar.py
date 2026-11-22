import secrets
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import settings
from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture(autouse=True)
def _wipe_users():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    yield
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()


def _png_bytes(size=(600, 400), color=(180, 40, 90)):
    buf = BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return buf.getvalue()


def _jpg_bytes(size=(500, 700)):
    buf = BytesIO()
    Image.new("RGB", size, (30, 120, 200)).save(buf, format="JPEG")
    return buf.getvalue()


def _admin_ready():
    client = TestClient(create_app())
    r = client.post(
        "/api/auth/register",
        json={
            "username": settings.admin_truong_username,
            "email": f"{settings.admin_truong_username}@gmail.com",
            "password": "secret123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    client = TestClient(create_app())
    token = client.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]
    r = client.post("/api/auth/admin-unlock", json={"password": "secret123"}, headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, r.text
    return client, token


def _worker(client, admin_token, username):
    r = client.post(
        "/api/auth/users",
        json={"username": username, "password": "worker123a", "role": "worker"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 200, r.text
    logged = client.post("/api/auth/login", json={"identifier": username, "password": "worker123a"}).json()
    r = client.post(
        "/api/auth/change-password",
        json={"old_password": "worker123a", "new_password": "worker456b"},
        headers={"Authorization": f"Bearer {logged['token']}"},
    )
    assert r.status_code == 200, r.text
    return client.post("/api/auth/login", json={"identifier": username, "password": "worker456b"}).json()["token"]


def _plain(client, username):
    r = client.post(
        "/api/auth/register",
        json={"username": username, "email": f"{username}@gmail.com", "password": "secret123", "invite_code": "TESTINVITE"},
    )
    assert r.status_code == 200, r.text
    return r.json()["token"]


def test_admin_uploads_png_avatar_and_serves(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {admin_token}"}).json()
    r = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 200, r.text
    url = r.json()["avatar"]
    assert url.startswith("/api/avatars/")
    me2 = client.get("/api/auth/me", headers={"Authorization": f"Bearer {admin_token}"}).json()
    assert me2["avatar"] == url

    served = client.get(url, headers={"Authorization": f"Bearer {admin_token}"})
    assert served.status_code == 200
    assert served.headers["content-type"].startswith("image/png")
    img = Image.open(BytesIO(served.content))
    assert max(img.size) <= 256

    login = client.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()
    assert login["avatar"] == url


def test_worker_uploads_jpeg_avatar(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    wtoken = _worker(client, admin_token, "avworker1")
    r = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.jpg", _jpg_bytes(), "image/jpeg")},
        headers={"Authorization": f"Bearer {wtoken}"},
    )
    assert r.status_code == 200, r.text
    url = r.json()["avatar"]
    served = client.get(url, headers={"Authorization": f"Bearer {wtoken}"})
    assert served.status_code == 200
    assert served.headers["content-type"].startswith("image/jpeg")

    users = client.get("/api/auth/users", headers={"Authorization": f"Bearer {wtoken}"}).json()
    rows = {u["username"]: u for u in users["items"]}
    assert rows["avworker1"]["avatar"] == url


def test_plain_user_forbidden_avatar(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, _ = _admin_ready()
    utoken = _plain(client, "plainav1")
    r = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
        headers={"Authorization": f"Bearer {utoken}"},
    )
    assert r.status_code == 403


def test_avatar_rejects_bad_type_and_oversize(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    bad = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.txt", b"not an image", "text/plain")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert bad.status_code == 400
    fake = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", b"\x89PNG\r\n\x1a\n" + b"junk", "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert fake.status_code == 400
    big = b"\x89PNG\r\n\x1a\n" + b"0" * (2 * 1024 * 1024 + 1)
    over = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", big, "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert over.status_code == 413


def test_avatar_replace_removes_old_file(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {admin_token}"}).json()
    r1 = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r1.status_code == 200
    r2 = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.jpg", _jpg_bytes(), "image/jpeg")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r2.status_code == 200
    from pathlib import Path

    avatar_dir = Path(settings.storage_dir) / "avatars"
    mine = [p for p in avatar_dir.glob(f"{me['id']}.*")]
    assert len(mine) == 1
    assert mine[0].suffix == ".jpg"
    old_url = r1.json()["avatar"]
    new_url = r2.json()["avatar"]
    assert old_url == new_url
    served = client.get(new_url, headers={"Authorization": f"Bearer {admin_token}"})
    assert served.headers["content-type"].startswith("image/jpeg")


def test_avatar_requires_auth(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    r = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
    )
    assert r.status_code == 401
    url = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["avatar"]
    assert client.get(url).status_code == 401


def test_avatar_near_2mb_passes_body_limit(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    from io import BytesIO

    from PIL import Image

    small = BytesIO()
    Image.new("RGB", (64, 64), (10, 200, 30)).save(small, format="PNG")
    base = small.getvalue()

    def padded(total):
        return base + secrets.token_bytes(total - len(base))

    r = client.post(
        "/api/auth/me/avatar",
        files={"file": ("big.png", padded(2 * 1024 * 1024 - 100), "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 200, f"file 2MB-100B bị chặn sớm: {r.status_code} {r.text[:120]}"

    r2 = client.post(
        "/api/auth/me/avatar",
        files={"file": ("over.png", padded(2 * 1024 * 1024 + 4096), "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r2.status_code == 413


def test_avatar_disk_error_is_server_error_not_400(monkeypatch, tmp_path):
    from fastapi.testclient import TestClient as _TC

    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    readonly = tmp_path / "readonly_storage"
    readonly.mkdir()
    readonly.chmod(0o555)
    monkeypatch.setattr(settings, "storage_dir", readonly)

    client = _TC(create_app(), raise_server_exceptions=False)
    r = client.post(
        "/api/auth/register",
        json={
            "username": settings.admin_truong_username,
            "email": f"{settings.admin_truong_username}@gmail.com",
            "password": "secret123",
            "invite_code": "TESTINVITE",
        },
    )
    assert r.status_code == 200, r.text
    client2 = _TC(create_app(), raise_server_exceptions=False)
    token = client2.post(
        "/api/auth/login",
        json={"identifier": settings.admin_truong_username, "password": "secret123"},
    ).json()["token"]

    r2 = client2.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r2.status_code == 500, f"lỗi đĩa phải 500 thật, nhận {r2.status_code}"


def test_avatar_broken_png_stream_is_400(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    broken = bytes.fromhex(
        "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
        "0000000d4944415478da6364f8cfc00000030101006b1df91f0000000049454e44ae426082"
    )
    r = client.post(
        "/api/auth/me/avatar",
        files={"file": ("broken.png", broken, "image/png")},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 400, f"broken PNG stream phải 400, nhận {r.status_code}"


def test_avatar_upload_rate_limited_as_heavy_path(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    monkeypatch.setattr(settings, "heavy_rate_limit", 1, raising=False)
    client, admin_token = _admin_ready()
    codes = []
    for _ in range(4):
        r = client.post(
            "/api/auth/me/avatar",
            files={"file": ("a.png", _png_bytes(), "image/png")},
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        codes.append(r.status_code)
    assert 429 in codes, f"avatar phải nằm trong heavy rate limit, nhận {codes}"


def test_avatar_upload_blocked_before_password_change(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    monkeypatch.setattr(settings, "secret_key", secrets.token_hex(32), raising=False)
    client, admin_token = _admin_ready()
    r = client.post(
        "/api/auth/users",
        json={"username": "freshav1", "password": "Worker#2026a", "role": "worker"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 200, r.text
    logged = client.post("/api/auth/login", json={"identifier": "freshav1", "password": "Worker#2026a"})
    tok = logged.json()["token"]
    r2 = client.post(
        "/api/auth/me/avatar",
        files={"file": ("a.png", _png_bytes(), "image/png")},
        headers={"Authorization": f"Bearer {tok}"},
    )
    assert r2.status_code == 403, f"worker chưa đổi mật khẩu phải 403, nhận {r2.status_code}"
    assert "password change required" in str(r2.json())
