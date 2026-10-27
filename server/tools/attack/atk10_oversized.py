"""HACKER 10 — Payload khổng lồ: JSON lớn, mảng lồng, nhiều params."""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=5)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)
    u = register_user(args.base)
    hdr = {"Authorization": f"Bearer {u['token']}"} if u else {}

    for rnd in range(args.rounds):
        # JSON body 5MB
        big = {"a": "A" * (5 * 1024 * 1024)}
        r = c.post("/api/auth/login", content=json.dumps({"identifier": "x", "password": "y", "pad": big["a"]}),
                   headers={"Content-Type": "application/json", **hdr})
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"json 5MB 500 v{rnd}", ""))

        # mảng lồng sâu 1000 tầng
        deep = {"data": None}
        ref = deep
        for _ in range(1000):
            ref["data"] = {}
            ref = ref["data"]
        r = c.post("/api/auth/login", content=json.dumps({"identifier": "x", "password": "y", **deep}),
                   headers={"Content-Type": "application/json", **hdr})
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"deep nesting 500 v{rnd}", ""))

        # 500 query params
        qs = "&".join(f"p{i}=v" for i in range(500))
        r = c.get(f"/api/heritage?limit=1&{qs}")
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"500 params 500 v{rnd}", ""))

    verdict("OVERSIZED-PAYLOAD", attempts, breaches)


if __name__ == "__main__":
    main()
