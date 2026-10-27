"""HACKER 6 — Brute force MỘT tài khoản từ NHIỀU "IP" (per-identifier cap phải chặn)."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--target", default="ghitatruongle")
    ap.add_argument("--rounds", type=int, default=30)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)
    for rnd in range(args.rounds):
        # mỗi lần một IP giả khác — sau vá phải vẫn 429 nhờ per-identifier cap
        r = c.post("/api/auth/login", json={"identifier": args.target, "password": f"guess{rnd}"},
                   headers={"X-Forwarded-For": f"10.{rnd // 250}.{rnd % 250}.{(rnd * 7) % 250}"})
        attempts += 1
        if r.status_code == 200:
            breaches.append((f"brute force thành công v{rnd}", "đăng nhập được!"))
        # 25 attempt đầu 401 là bình thường; từ 20 sai (per-identifier) phải 429
    verdict("BRUTEFORCE-DISTRIBUTED", attempts, breaches)


if __name__ == "__main__":
    main()
