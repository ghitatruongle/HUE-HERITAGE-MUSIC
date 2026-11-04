"""HACKER 1 — NÂNG QUYỀN: mass-assignment, IDOR, giả mạo token admin, khóa admin."""
import argparse
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=15)
    ap.add_argument("--code", default="CHAOS-CODE")
    args = ap.parse_args()

    attempts = 0
    breaches = []

    u = register_user(args.base, code=args.code)
    if not u:
        print("không đăng ký được user — kiểm tra mã mời")
        verdict("PRIVILEGE-ESCALATION", 0, [("no-user", "đăng ký thất bại")])
        return

    for rnd in range(args.rounds):
        attempts += 1
        c = client(args.base, u["token"])

        r = c.get("/api/auth/users")
        if r.status_code == 200:
            breaches.append((f"IDOR users v{rnd}", "user thường đọc được danh sách TK"))

        r = c.get("/api/auth/invites")
        if r.status_code == 200:
            breaches.append((f"IDOR invites v{rnd}", "user thường đọc được mã mời"))

        r = c.get("/api/auth/me")
        if r.status_code == 200 and r.json().get("role") == "admin":
            breaches.append((f"role escalate qua register v{rnd}", "đăng ký xong role=admin"))

        r = c.patch(f"/api/auth/users/{u['id']}/active", json={"active": True})
        if r.status_code == 200:
            breaches.append((f"self-active v{rnd}", "user tự PATCH active"))

        # cố khóa admin bằng token user
        me = c.get("/api/auth/me").json()
        r = c.post(f"/api/auth/users/{me['id']}/reset-password")
        if r.status_code == 200:
            breaches.append((f"self-reset v{rnd}", "user thường tự reset được (cần admin)"))

        c.close()

    verdict("PRIVILEGE-ESCALATION", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
