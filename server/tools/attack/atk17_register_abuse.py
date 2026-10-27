"""HACKER 17 — Register abuse: username dài 500 ký tự, email dài, null bytes, mảng JSON."""
import argparse
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=5)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)

    bodies = [
        {"username": "A" * 500, "email": f"a{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": "CHAOS-CODE"},
        {"username": "ok" + secrets.token_hex(2), "email": "A" * 400 + "@gmail.com", "password": "secret123", "invite_code": "CHAOS-CODE"},
        {"username": "null\u0000user", "email": f"n{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": "CHAOS-CODE"},
        {"username": ["array"], "email": f"a{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": "CHAOS-CODE"},
        {"username": {"obj": 1}, "email": f"o{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": "CHAOS-CODE"},
    ]

    for rnd in range(args.rounds):
        for i, b in enumerate(bodies):
            r = c.post("/api/auth/register", json=b)
            attempts += 1
            if r.status_code >= 500:
                breaches.append((f"register abuse #{i} 500 v{rnd}", r.text[:80]))

    verdict("REGISTER-ABUSE", attempts, breaches)


if __name__ == "__main__":
    main()
