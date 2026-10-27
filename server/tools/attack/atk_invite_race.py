"""HACKER 4 — ĐUA MÃ MỜI + SPAM ĐĂNG KÝ: 10 luồng dùng chung 1 mã one-time, spam tạo TK, chiếm tên admin."""
import argparse
import secrets
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import verdict  # noqa: E402


def register_once(base, code, username):
    c = httpx.Client(base_url=base, timeout=30.0)
    r = c.post("/api/auth/register", json={
        "username": username, "email": f"{username}@gmail.com",
        "password": "secret123", "invite_code": code,
    })
    c.close()
    return r.status_code


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--codes-file", default="")
    ap.add_argument("--code", default="CHAOS-CODE")
    ap.add_argument("--rounds", type=int, default=8)
    args = ap.parse_args()
    codes = []
    if args.codes_file:
        codes = [l.strip() for l in Path(args.codes_file).read_text().splitlines() if l.strip()]

    attempts = 0
    breaches = []
    c = httpx.Client(base_url=args.base, timeout=30.0)

    # 1. Chiếm tên nhạy cảm (rule 9 + giả mạo danh tính)
    for name in ("admin", "administrator", "root", "moderator", "system", "ghitatruongle", "ghitatruongle "):
        u = name.strip()
        r = c.post("/api/auth/register", json={
            "username": u, "email": f"{u.replace(' ', '')}{secrets.token_hex(2)}@gmail.com",
            "password": "secret123", "invite_code": args.code})
        attempts += 1
        if r.status_code == 200 and u.lower() in ("admin", "administrator", "root", "moderator", "system"):
            breaches.append((f"đăng ký tên nhạy cảm '{u}'", "tạo được TK mang tên quản trị dễ đoán"))

    # 2. Đua mã one-time: mỗi vòng tạo 1 mã mới qua admin? — script này chỉ dùng 1 code tĩnh,
    #    mã one-time thật do orchestrator cấp qua --code; 10 luồng đua cùng lúc:
    for rnd in range(args.rounds):
        race_code = codes[rnd] if rnd < len(codes) else args.code
        username_base = f"race{rnd}_{secrets.token_hex(2)}"
        with ThreadPoolExecutor(max_workers=10) as ex:
            rs = list(ex.map(
                lambda i: register_once(args.base, race_code, f"{username_base}u{i}"),
                range(10)))
        attempts += 10
        successes = sum(1 for s in rs if s == 200)
        if successes > 1:
            breaches.append((f"đua mã one-time v{rnd}", f"{successes}/10 luồng đăng ký thành công cùng 1 mã!"))

    # 3. Spam đăng ký vô mã (không code) — phải bị chặn hết
    blocked = 0
    for i in range(20):
        u = f"spam{secrets.token_hex(2)}"
        r = c.post("/api/auth/register", json={
            "username": u, "email": f"{u}@gmail.com", "password": "secret123", "invite_code": "NO-CODE"})
        attempts += 1
        if r.status_code == 200:
            breaches.append(("spam không mã đăng ký được", u))
        elif r.status_code == 400:
            blocked += 1
    if blocked == 0:
        breaches.append(("spam không mã", "không có lần nào bị chặn — cửa đăng ký mở rộng!"))

    verdict("INVITE-RACE-SPAM", attempts, breaches)


if __name__ == "__main__":
    main()
