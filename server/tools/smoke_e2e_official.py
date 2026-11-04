import argparse
import secrets
import struct
import sys
import time

import httpx

PASS = []
FAIL = []


def check(name, cond, note=""):
    (PASS if cond else FAIL).append(name)
    print(f"  {'✓' if cond else '✗'} {name}" + (f" — {note}" if note else ""))


def token_exp(token):
    return int(token.split(".")[1])


def make_wav():
    sr = 8000
    n = sr
    data = b"".join(struct.pack("<h", int(12000 * (i % 256) / 256 - 128)) for i in range(n))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16
    ) + b"data" + struct.pack("<I", len(data))
    return hdr + data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8127")
    args = ap.parse_args()
    base = args.base
    c = httpx.Client(base_url=base, timeout=60)

    print("\n== 1. Đăng ký admin + user thường, khởi động lại để thăng chức ==")
    r = c.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "ghitatruongle@gmail.com",
        "password": "AdminCu#2026a", "invite_code": "CHAOS-CODE",
    })
    check("đăng ký admin (hoặc đã có)", r.status_code in (200, 409), f"status={r.status_code}")
    r = c.post("/api/auth/register", json={
        "username": "userthuong1", "email": "userthuong1@gmail.com",
        "password": "secret123", "invite_code": "CHAOS-CODE",
    })
    check("đăng ký user thường (hoặc đã có)", r.status_code in (200, 409))
    c.close()
    return base


def phase2(base):
    c = httpx.Client(base_url=base, timeout=60)
    print("\n== 2. TTL token theo vai trò ==")
    admin_token = c.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminCu#2026a"}).json()["token"]
    user_token = c.post("/api/auth/login", json={"identifier": "userthuong1", "password": "secret123"}).json()["token"]
    admin_h = {"Authorization": f"Bearer {admin_token}"}
    user_h = {"Authorization": f"Bearer {user_token}"}
    now = time.time()
    admin_ttl_h = (token_exp(admin_token) - now) / 3600
    user_ttl_h = (token_exp(user_token) - now) / 3600
    check("token admin ≈ 8h", 7.5 <= admin_ttl_h <= 8.1, f"{admin_ttl_h:.2f}h")
    check("token user = 72h", 71.5 <= user_ttl_h <= 72.1, f"{user_ttl_h:.2f}h")

    print("\n== 3. Sliding session qua /auth/me ==")
    r = c.get("/api/auth/me", headers=user_h)
    check("/auth/me trả token mới", r.status_code == 200 and r.json().get("token"))
    new_token = r.json()["token"]
    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {new_token}"})
    check("token mới dùng được ngay", r.status_code == 200)
    r = c.get("/api/auth/me", headers=user_h)
    check("token cũ vẫn hợp lệ (chưa hết hạn)", r.status_code == 200)

    print("\n== 4. Step-up unlock admin ==")
    r = c.post("/api/auth/users", json={"username": "usermoi1"}, headers=admin_h)
    check("tạo user khi CHƯA unlock → 403", r.status_code == 403 and r.json()["detail"] == "admin reauth required", f"status={r.status_code}")
    r = c.post("/api/auth/admin-unlock", json={"password": "sai-va-tai"}, headers=admin_h)
    check("unlock sai mật khẩu → 401", r.status_code == 401)
    r = c.post("/api/auth/admin-unlock", json={"password": "AdminCu#2026a"}, headers=admin_h)
    check("unlock đúng mật khẩu → 200", r.status_code == 200)

    print("\n== 5. Admin tạo user + force-change + chặn ghi ==")
    r = c.post("/api/auth/users", json={"username": "usermoi1", "email": "usermoi1@gmail.com"}, headers=admin_h)
    check("tạo user sau unlock → 200, mật khẩu tự sinh", r.status_code == 200 and r.json()["generated"], f"status={r.status_code}")
    temp = r.json()["temp_password"]
    u2 = c.post("/api/auth/login", json={"identifier": "usermoi1", "password": temp}).json()
    check("login user mới → cờ force-change đúng", u2.get("must_change_password") is True)
    u2_h = {"Authorization": f"Bearer {u2['token']}"}
    r = c.post("/api/heritage/upload", files={"file": ("a.wav", make_wav(), "audio/wav")}, data={"title": "Bai cua user2"}, headers=u2_h)
    check("user force-change upload → 403 password change required", r.status_code == 403 and r.json()["detail"] == "password change required", f"status={r.status_code}")
    r = c.get("/api/heritage", headers=u2_h)
    check("user force-change vẫn đọc được → 200", r.status_code == 200)
    r = c.post("/api/auth/change-password", json={"old_password": temp, "new_password": "MatkhauMoi#77"}, headers=u2_h)
    check("đổi mật khẩu được phép → 200", r.status_code == 200)
    u2_token_new = r.json()["token"]
    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {u2_token_new}"})
    check("sau đổi mật khẩu cờ tắt", r.status_code == 200 and r.json()["must_change_password"] is False)

    print("\n== 6. Upload thật + cascade delete ==")
    r = c.post("/api/heritage/upload", files={"file": ("bai1.wav", make_wav(), "audio/wav")}, data={"title": "Bai test cascade"}, headers=user_h)
    check("upload bản thu hợp lệ → 200", r.status_code == 200, f"status={r.status_code}")
    item_id = r.json()["id"]
    r = c.get("/api/admin/storage", params={"q": "cascade"}, headers=admin_h)
    found = any(x["id"] == item_id for x in r.json()["items"])
    check("admin thấy bản ghi trong kho", found)
    r = c.delete(f"/api/admin/storage/{item_id}", headers=admin_h)
    check("admin xóa bản ghi (sau unlock) → 200", r.status_code == 200, f"status={r.status_code}")
    r = c.get(f"/api/heritage/{item_id}")
    check("bản ghi biến mất khỏi catalog → 404", r.status_code == 404)

    print("\n== 7. Chính sách mật khẩu admin ==")
    r = c.post("/api/auth/change-password", json={"old_password": "AdminCu#2026a", "new_password": "yeuqua11"}, headers=admin_h)
    check("mật khẩu admin yếu → 400", r.status_code == 400)
    r = c.post("/api/auth/change-password", json={"old_password": "AdminCu#2026a", "new_password": "AdminMoi#2026b"}, headers=admin_h)
    check("mật khẩu admin mạnh → 200", r.status_code == 200)

    r = c.get("/health")
    check("health cuối giờ vẫn OK", r.status_code == 200 and r.json()["version"] == "0.0.2-alpha1")
    c.close()


if __name__ == "__main__":
    base = main()
    phase2(base)
    print(f"\nKẾT QUẢ SMOKE E2E: {len(PASS)} pass / {len(FAIL)} fail")
    if FAIL:
        print("FAIL:", "; ".join(FAIL))
    sys.exit(0 if not FAIL else 1)
