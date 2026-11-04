"""HACKER 8 — Header injection: CRLF trong params, XFF nhiều tầng, header Oversized."""
import argparse
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, verdict  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--rounds", type=int, default=10)
    args = ap.parse_args()

    attempts = 0
    breaches = []
    c = client(args.base)

    for rnd in range(args.rounds):
        # CRLF trong query params (không được phép phản chiếu header mới)
        r = c.get("/api/heritage", params={"q": f"x{secrets.token_hex(2)}"})
        attempts += 1
        if "\r\n" in r.text[:200]:
            breaches.append((f"CRLF reflect v{rnd}", "header phản chiếu"))

        # XFF chuỗi nhiều tầng
        r = c.get("/health", headers={"X-Forwarded-For": "1.2.3.4, 5.6.7.8, 9.10.11.12",
                                       "X-Real-IP": "1.2.3.4", "Forwarded": "for=1.2.3.4"})
        attempts += 1
        if r.status_code >= 500:
            breaches.append((f"XFF nhiều tầng 500 v{rnd}", ""))

        # Header oversized
        try:
            r = c.get("/health", headers={"X-Junk": "A" * 30000})
            attempts += 1
            if r.status_code >= 500:
                breaches.append((f"header oversized 500 v{rnd}", ""))
        except Exception:
            pass

    verdict("HEADER-INJECTION", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
