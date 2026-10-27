"""HACKER 15 — Dò file tĩnh: .git, .env, backup, config qua SPA route."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, verdict  # noqa: E402

PROBES = [
    "/.env", "/.git/config", "/.git/HEAD", "/backup.zip", "/db.sqlite",
    "/hue_heritage.db", "/server/.env", "/storage/.env", "/config.json",
    "/package.json.bak", "/web/.env", "/.DS_Store", "/server.log",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=5)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)

    for rnd in range(args.rounds):
        for p in PROBES:
            r = c.get(p)
            attempts += 1
            if r.status_code == 200:
                body = r.text[:500].lower()
                # SPA trả index.html cho mọi path — chỉ là shell, KHÔNG rò
                if ("secret" in body or "database_url" in body or "begin rsa" in body
                        or r.headers.get("content-type", "").startswith("application/octet-stream")):
                    breaches.append((f"dò {p} RÒ NỘI DUNG", r.text[:80]))
                elif "<!doctype html" not in body[:50] and "di sản" not in body:
                    breaches.append((f"dò {p} trả nội dung lạ", r.text[:80]))

    verdict("STATIC-PROBE", attempts, breaches)


if __name__ == "__main__":
    main()
