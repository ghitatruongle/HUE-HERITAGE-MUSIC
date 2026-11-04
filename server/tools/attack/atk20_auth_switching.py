"""HACKER 20 — Chuyển tài khoản ma: đổi mật khẩu liên tục + login 2 nơi + epoch race."""
import argparse
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=6)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    u = register_user(args.base)
    if not u:
        print("FATAL: khong dang ky duoc user (rate limit) — setup that bai")
        sys.exit(2)
    current_password = "secret123"
    c1 = client(args.base, u["token"])
    c2 = client(args.base, u["token"])

    for rnd in range(args.rounds):
        # c1 đổi mật khẩu → c2 token phải chết
        r1 = c1.post("/api/auth/change-password",
                     json={"old_password": current_password, "new_password": f"switch{rnd}pass"},
                     headers={"Authorization": f"Bearer {u['token']}"})
        attempts += 1
        if r1.status_code != 200:
            breaches.append((f"đổi mk fail v{rnd}", r1.text[:60]))
            continue
        current_password = f"switch{rnd}pass"
        new_tok = r1.json()["token"]

        r2 = c2.get("/api/auth/me", headers={"Authorization": f"Bearer {u['token']}"})
        attempts += 1
        if r2.status_code == 200:
            breaches.append((f"token cũ sống sau đổi mk v{rnd}", "epoch không chặn"))

        # login lại bằng mk mới, epoch mới
        r3 = c2.post("/api/auth/login", json={"identifier": u["username"], "password": f"switch{rnd}pass"})
        attempts += 1
        if r3.status_code != 200:
            breaches.append((f"login mk mới fail v{rnd}", r3.text[:60]))
            break
        u["token"] = r3.json()["token"]
        c1 = client(args.base, u["token"])
        c2 = client(args.base, u["token"])

    if attempts == 0:
        print("khong thuc hien duoc lan nao (rate limit chan toan bo) — BI CHAN, khong phai Sach")
        sys.exit(2)
    verdict("AUTH-SWITCHING", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai hoac crash tool: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
