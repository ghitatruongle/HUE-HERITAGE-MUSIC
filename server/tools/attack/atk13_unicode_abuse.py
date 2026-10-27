"""HACKER 13 — Unicode abuse: NFC/NFD, homoglyph, zero-width trong username."""
import argparse
import secrets
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

    weird_names = [
        "user\u0301",            # combining accent
        "u\u200bser",            # zero-width space
        "ａｄｍｉｎ",              # fullwidth admin
        "adm\u0131n",            # dotless i (homoglyph)
        "  spaces  ",
        "user\twith-tab",
    ]

    for rnd in range(args.rounds):
        for wn in weird_names:
            uname = (wn.replace("\\u0301", "\u0301").replace("\\u200b", "\u200b")
                      .replace("\\u0131", "\u0131").replace("\\t", "\t")
                      .encode().decode("unicode_escape") if "\\u" in wn else wn)
            r = c.post("/api/auth/register", json={
                "username": uname + secrets.token_hex(2),
                "email": f"u{secrets.token_hex(2)}@gmail.com",
                "password": "secret123", "invite_code": "CHAOS-CODE"})
            attempts += 1
            if r.status_code >= 500:
                breaches.append((f"unicode 500 v{rnd}", repr(wn)))

    verdict("UNICODE-ABUSE", attempts, breaches)


if __name__ == "__main__":
    main()
