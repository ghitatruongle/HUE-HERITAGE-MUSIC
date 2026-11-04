"""HACKER 19 — Task flood: tạo hàng loạt task sinh nhạc + hủy liên tục."""
import argparse
import httpx
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
            try:
                r = c.post("/api/music/sing-original", params={"heritage_id": f"flood{rnd}", "duration": 30})
            except httpx.ConnectError:
                attempts += 1
                continue
            attempts += 1
            if r.status_code >= 500 and r.status_code != 503:
                breaches.append((f"task flood 500 v{rnd} #{i}", r.text[:60]))
            if r.status_code == 200:
                tid = r.json().get("id", "")
                try:
                    rc = c.post(f"/api/music/task/{tid}/cancel")
                except httpx.ConnectError:
                    continue
                attempts += 1
                if rc.status_code >= 500 and rc.status_code != 503:
                    breaches.append((f"cancel flood 500 v{rnd}", ""))

    verdict("TASK-FLOOD", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai hoac crash tool: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
