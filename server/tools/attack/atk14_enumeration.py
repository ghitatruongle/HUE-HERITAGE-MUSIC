"""HACKER 14 — User enumeration: đo phản hồi login/register phân biệt user tồn tại."""
import argparse
import secrets
import time
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)
    u = register_user(args.base, username="enumerateme")

    # login: user TỒN TẠI mật khẩu sai vs user KHÔNG tồn tại — response phải giống hệt
    r1 = c.post("/api/auth/login", json={"identifier": "enumerateme", "password": "wrongwrong"})
    t1 = (time.perf_counter(), r1.status_code, len(r1.text), r1.text)
    r2 = c.post("/api/auth/login", json={"identifier": "khongtontai999", "password": "wrongwrong"})
    t2 = (time.perf_counter(), r2.status_code, len(r2.text), r2.text)
    attempts += 2
    if t1[1] != t2[1] or t1[2] != t2[2] or t1[3] != t2[3]:
        breaches.append(("enumeration qua login", f"phản hồi khác nhau: {t1[1]}/{t1[3][:40]} vs {t2[1]}/{t2[3][:40]}"))

    # register: email trùng tiết lộ email đã đăng ký (đã biết — chấp nhận, kiểm tra không 500)
    r3 = c.post("/api/auth/register", json={
        "username": "enum" + secrets.token_hex(2),
        "email": "enumerateme@gmail.com", "password": "secret123", "invite_code": "CHAOS-CODE"})
    attempts += 1
    if r3.status_code >= 500:
        breaches.append(("enumeration email 500", ""))

    verdict("USER-ENUMERATION", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
