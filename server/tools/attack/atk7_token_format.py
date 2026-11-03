"""HACKER 7 — Token format abuse: phần thừa, thiếu, khoảng trắng, unicode, alg-none kiểu."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=6)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    u = register_user(args.base)
    if not u:
        verdict("TOKEN-FORMAT", 0, [])
        return
    tok = u["token"]
    parts = tok.split(".")

    weird = [
        tok + "." + "x",                      # thêm phần thừa
        " " + tok,                            # khoảng trắng đầu
        tok.replace(".", "." * 1),            # giữ nguyên (control)
        ".." + tok,                           # tiền tố chấm
        tok.upper(),                          # hoa hóa hex sig
        "none." + parts[1] + "." + parts[2] + "." + parts[3] if len(parts) >= 4 else tok,
        parts[0] + "." + "99999999999" + "." + parts[2] + "." + parts[3] if len(parts) >= 4 else tok,
        "admin." + parts[1] + "." + parts[2] + "." + parts[3] if len(parts) >= 4 else tok,
        tok.replace(parts[0], "ghitatruongle") if u["username"] != "ghitatruongle" else tok,
    ]
    c = client(args.base)
    for rnd in range(args.rounds):
        for i, t in enumerate(weird):
            r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {t}"})
            attempts += 1
            if r.status_code == 200 and i not in (1, 2):
                breaches.append((f"token weird #{i} được chấp nhận v{rnd}", f"{t[:40]}"))

    verdict("TOKEN-FORMAT", attempts, breaches)


if __name__ == "__main__":
    main()
