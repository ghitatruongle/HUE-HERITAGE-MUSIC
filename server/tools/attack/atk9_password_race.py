"""HACKER 9 — Race: đổi mật khẩu song song + token cũ/mới dùng chéo."""
import argparse
import sys
import threading
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

    for rnd in range(args.rounds):
        u = register_user(args.base)
        tok = u["token"]
        c = client(args.base, tok)

        # 5 luồng đổi mật khẩu KHÁC NHAU cùng lúc
        results = []
        lock = threading.Lock()

        def do_change(i):
            cc = client(args.base, tok)
            r = cc.post("/api/auth/change-password",
                        json={"old_password": "secret123", "new_password": f"racepass{i}xx"},
                        headers={"Authorization": f"Bearer {tok}"})
            with lock:
                results.append((i, r.status_code, r.json().get("token", "")))
            cc.close()

        threads = [threading.Thread(target=do_change, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        attempts += 5

        # TẤT CẢ token trừ cái đổi cuối cùng phải chết (epoch)
        for i, code, new_tok in results:
            r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {new_tok}"})
            if r.status_code == 200 and i != max(x[0] for x in results):
                breaches.append((f"race token cũ sống v{rnd}", f"token của luồng {i} còn dùng được sau epoch mới"))

    verdict("PASSWORD-RACE", attempts, breaches)


if __name__ == "__main__":
    main()
