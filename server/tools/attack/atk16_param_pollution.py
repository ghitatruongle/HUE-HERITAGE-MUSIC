"""HACKER 16 — HTTP Parameter Pollution: params trùng, kiểu lẫn lộn."""
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
        # limit trùng
        r = c.get("/api/heritage?limit=5&limit=99999")
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"limit pollution 500 v{rnd}", ""))

        # kiểu lẫn lộn
        r = c.get("/api/heritage", params={"limit": "abc"})
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"limit=abc 500 v{rnd}", ""))

        r = c.get("/api/heritage", params={"limit": "-1"})
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"limit=-1 500 v{rnd}", ""))

        r = c.get("/api/heritage", params={"limit": "1e10"})
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"limit=1e10 500 v{rnd}", ""))

        # duration âm / float
        r = c.post("/api/music/sing-original", params={"heritage_id": "x", "duration": "-50"})
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"duration âm 500 v{rnd}", ""))

    verdict("PARAM-POLLUTION", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
