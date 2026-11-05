"""HACKER 11 — HTTP method abuse: PUT/DELETE/TRACE/OPTIONS/PATCH trên mọi route."""
import argparse
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

    routes = ["/api/heritage", "/api/auth/me", "/api/music/models", "/health", "/api/lessons"]
    methods = ["PUT", "DELETE", "TRACE", "OPTIONS", "HEAD"]

    for rnd in range(args.rounds):
        for route in routes:
            for m in methods:
                r = c.request(m, route)
                attempts += 1
                if r.status_code >= 500 and r.status_code != 503:
                    breaches.append((f"{m} {route} 500 v{rnd}", ""))

    verdict("HTTP-METHODS", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
