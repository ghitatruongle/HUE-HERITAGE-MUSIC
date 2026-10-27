"""Đăng ký N user load-test từ file mã mời (mỗi user một bucket rate limit riêng)."""
import os
import secrets
import sys

import httpx


def main():
    base = os.environ.get("CHAOS_BASE", "http://127.0.0.1:8010")
    codes_file = sys.argv[1]
    out = sys.argv[2]
    codes = [l.strip() for l in open(codes_file) if l.strip()][-12:]
    c = httpx.Client(base_url=base, timeout=30)
    tokens = []
    for i, code in enumerate(codes):
        u = f"loaduser{i}_" + secrets.token_hex(2)
        r = c.post("/api/auth/register", json={"username": u, "email": u + "@gmail.com",
                                               "password": "secret123", "invite_code": code})
        if r.status_code == 200:
            tokens.append(r.json()["token"])
    c.close()
    open(out, "w").write("\n".join(tokens))
    print("load users:", len(tokens))


if __name__ == "__main__":
    main()
