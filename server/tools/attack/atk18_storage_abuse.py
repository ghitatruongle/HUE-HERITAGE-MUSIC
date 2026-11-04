"""HACKER 18 — Storage abuse: upload 200 file nhỏ liên tục (lấp đầy đĩa)."""
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
        for i in range(20):
            r = c.post("/api/heritage/upload",
                       files={"file": (f"spam{rnd}_{i}.wav", b"RIFFxxxxWAVEfmt " + b"\x00" * 1000, "audio/wav")},
                       data={"title": f"spam {rnd} {i}"})
            attempts += 1
            if r.status_code >= 500:
                breaches.append((f"spam upload 500 v{rnd} #{i}", r.text[:60]))

    verdict("STORAGE-ABUSE", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
