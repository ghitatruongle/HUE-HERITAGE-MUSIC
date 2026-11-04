"""HACKER 2 — ĐỘT NHẬP TÀI KHOẢN ADMIN: brute force, tự ký token, epoch giả, khóa admin."""
import argparse
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402

ADMIN = "ghitatruongle"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=3)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)

    # đăng ký user thường để có token gửi kèm các thử admin
    u = register_user(args.base)

    guesses = ["admin", "123456", "password", "AdminPass99!", "hueheritage", "ghita123",
               "admin123", "letmein", "QHH2026", "hueheritagemusic"]

    for rnd in range(args.rounds):
        # 1. Brute force mật khẩu admin (5 lần — trần rate limit mỗi vòng)
        breached_pw = False
        for g in guesses[:5]:
            r = c.post("/api/auth/login", json={"identifier": ADMIN, "password": g})
            attempts += 1
            if r.status_code == 200:
                breached_pw = True
                break
        if breached_pw:
            breaches.append((f"brute force admin v{rnd}", "đoán trúng mật khẩu admin!"))

        # 2. Sau khóa 429, thử né bằng XFF với IP giả khác nhau
        escaped = False
        for i in range(4):
            r = c.post("/api/auth/login", json={"identifier": ADMIN, "password": secrets.token_hex(6)},
                       headers={"X-Forwarded-For": f"10.{rnd}.{i}.9"})
            attempts += 1
            if r.status_code == 200:
                escaped = True
                break
            if r.status_code != 429:
                escaped = False
        if escaped:
            breaches.append((f"XFF escape v{rnd}", "né 429 bằng X-Forwarded-For"))

        # 3. Giả mạo token admin: token user + user_id admin, token tự ký key đoán
        utok = u["token"] if u else ""
        parts = utok.split(".")
        if len(parts) == 4:
            forged_userid = f"{parts[0]}.{parts[1]}.{parts[2]}.{parts[3]}"
            r = c.get("/api/auth/users", headers={"Authorization": f"Bearer {forged_userid}"})
            attempts += 1
            if r.status_code == 200:
                breaches.append(("forge swap", "swap token không bị chữ ký chặn"))

        fake = "x." + str(9999999999) + ".0." + "a" * 64
        r = c.get("/api/auth/users", headers={"Authorization": f"Bearer {fake}"})
        attempts += 1
        if r.status_code == 200:
            breaches.append(("fake token", "token tự chế được chấp nhận"))

        # 4. Đăng nhập tài khoản admin bằng SQLi
        for payload in ("ghitatruongle' --", "ghitatruongle' OR '1'='1"):
            r = c.post("/api/auth/login", json={"identifier": payload, "password": "x"})
            attempts += 1
            if r.status_code == 200:
                breaches.append((f"SQLi login admin v{rnd}", "SQLi đăng nhập được admin!"))

        # 5. Reset mật khẩu admin qua user token
        if u:
            me = client(args.base, u["token"]).get("/api/auth/me").json()
            r = c.post(f"/api/auth/users/{me['id']}/reset-password", headers={"Authorization": f"Bearer {u['token']}"})
            attempts += 1
            if r.status_code == 200:
                breaches.append(("self-reset admin?", "reset nhầm user khác thành admin?"))

    verdict("ADMIN-TAKEOVER", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
