"""HACKER 12 — Content-Type confusion: form-as-json, json-as-form, charset tricks."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=6)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)

    for rnd in range(args.rounds):
        # JSON body nhưng khai báo form
        r = c.post("/api/auth/login", content='{"identifier":"x","password":"y"}',
                   headers={"Content-Type": "application/x-www-form-urlencoded"})
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"form-as-json 500 v{rnd}", ""))

        # form data nhưng khai báo JSON
        r = c.post("/api/auth/login", content="identifier=x&password=y",
                   headers={"Content-Type": "application/json"})
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"json-as-form 500 v{rnd}", ""))

        # charset lạ
        r = c.post("/api/auth/login", content='{"identifier":"x","password":"y"}'.encode("utf-16"),
                   headers={"Content-Type": "application/json; charset=utf-16"})
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"utf-16 500 v{rnd}", ""))

    verdict("CONTENT-TYPE", attempts, breaches)


if __name__ == "__main__":
    main()
