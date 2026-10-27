"""Đếm admin/users — kiểm tra không có tài khoản admin nào được tạo trái phép."""
import os
import sys

import httpx


def main():
    base = os.environ.get("CHAOS_BASE", "http://127.0.0.1:8010")
    token = sys.argv[1]
    c = httpx.Client(base_url=base, timeout=15)
    r = c.get("/api/auth/users", headers={"Authorization": f"Bearer {token}"})
    if r.status_code != 200:
        print(f"HTTP {r.status_code} — không xác minh được")
        sys.exit(1)
    users = r.json()
    admins = [u for u in users if u.get("role") == "admin" and u.get("active")]
    status = "AN TOÀN" if len(admins) == 1 and admins[0]["username"] == "ghitatruongle" else "!!! BỊ XÂM NHẬP"
    print(f"{len(admins)} admin active / {len(users)} users — {status}")
    sys.exit(0 if len(admins) == 1 and admins[0]["username"] == "ghitatruongle" else 1)


if __name__ == "__main__":
    main()
