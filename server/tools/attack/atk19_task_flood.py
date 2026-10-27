"""HACKER 19 — Task flood: tạo hàng loạt task sinh nhạc + hủy liên tục."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=3)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    u = register_user(args.base)
    c = client(args.base, u["token"] if u else None)

    for rnd in range(args.rounds):
        for i in range(15):
            r = c.post("/api/music/sing-original", params={"heritage_id": f"flood{rnd}", "duration": 30})
            attempts += 1
            if r.status_code >= 500:
                breaches.append((f"task flood 500 v{rnd} #{i}", r.text[:60]))
            if r.status_code == 200:
                tid = r.json().get("id", "")
                rc = c.post(f"/api/music/task/{tid}/cancel")
                attempts += 1
                if rc.status_code >= 500:
                    breaches.append((f"cancel flood 500 v{rnd}", ""))

    verdict("TASK-FLOOD", attempts, breaches)


if __name__ == "__main__":
    main()
