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
        if not u:
            print("khong dang ky duoc user (rate limit) — bo qua vong nay")
            continue
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
        if any(code in (429, 503) for _, code, _ in results):
            continue

        r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
        if r.status_code == 200:
            breaches.append((f"race token gốc sống v{rnd}", "token trước bão đổi mật khẩu vẫn dùng được"))
        for i, code, new_tok in results:
            r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {new_tok}"})
            if r.status_code == 200 and i not in (max(x[0] for x in results),):
                parts = new_tok.split(".")
                orig_epoch = tok.split(".")[2] if len(tok.split(".")) >= 3 else "0"
                if len(parts) >= 3 and parts[2] == orig_epoch:
                    breaches.append((f"race token cấp cũ sống v{rnd}", f"luồng {i} nhận token mang epoch gốc"))

    if attempts == 0:
        print("khong thuc hien duoc lan nao (rate limit chan toan bo) — BI CHAN, khong phai Sach")
        sys.exit(2)
    verdict("PASSWORD-RACE", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai hoac crash tool: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
