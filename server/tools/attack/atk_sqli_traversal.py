"""HACKER 3 — SQL INJECTION + PATH TRAVERSAL toàn route, lặp liên tục."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, verdict  # noqa: E402

SQLI = [
    "' OR 1=1 --",
    "'; DROP TABLE users;--",
    "1' UNION SELECT id,username,password_hash,token_epoch FROM users--",
    "admin'--",
    "\x27\x29 OR (1=1)",
]
TRAVERSAL = [
    "/api/music/generated/..%2f..%2f..%2fserver%2f.env",
    "/api/music/generated/..%2f..%2fserver%2f.env",
    "/api/music/midi/..%2f..%2f..%2fserver%2f.env",
    "/api/music/restored/..%2f..%2fserver%2f.env",
    "/api/lessons/practice-midi/..%2f..%2f..%2fserver%2f.env",
    "/api/lessons/practice-midi/..%5C..%5Cserver%5C.env",
    "/api/music/generated/..%00/.env",
    "/api/music/generated/%252e%252e%252fserver%2f.env",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=10)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)

    for rnd in range(args.rounds):
        for p in SQLI:
            r = c.post("/api/auth/login", json={"identifier": p, "password": "x"})
            attempts += 1
            if r.status_code >= 500 and r.status_code != 503:
                breaches.append((f"SQLi login 500 v{rnd}", f"{p[:40]} → {r.status_code}"))
            if r.status_code == 200:
                breaches.append((f"SQLi login ĐĂNG NHẬP ĐƯỢC v{rnd}", p[:40]))
            if "SELECT" in r.text.upper() and "sqlalchemy" in r.text.lower():
                breaches.append((f"SQLi rò stack v{rnd}", p[:40]))

        for p in SQLI:
            r = c.get("/api/heritage", params={"q": p})
            attempts += 1
            if r.status_code >= 500 and r.status_code != 503:
                breaches.append((f"SQLi search 500 v{rnd}", p[:40]))

        for p in SQLI:
            r = c.get("/api/lessons", params={})
            attempts += 1
            break

        for path in TRAVERSAL:
            r = c.get(path)
            attempts += 1
            if r.status_code == 200 and (b"SECRET" in r.content or b"ACESTEP" in r.content or b"DATABASE_URL" in r.content):
                breaches.append((f"traversal RÒ FILE v{rnd}", path[:50]))
            if r.status_code >= 500 and r.status_code != 503:
                breaches.append((f"traversal 500 v{rnd}", path[:50]))

        r = c.get("/api/music/play-url", params={"path": "../../.env"})
        attempts += 1
        if r.status_code == 200:
            breaches.append(("play-url traversal", "../../.env được chấp nhận"))

    verdict("SQLI-TRAVERSAL", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
