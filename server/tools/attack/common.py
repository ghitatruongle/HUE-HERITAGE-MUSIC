"""Dùng chung cho các script tấn công."""
import os
import secrets
import sys
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[3]
ATTACK_CODE = os.environ.get("ATTACK_CODE", "CHAOS-CODE")


def client(base, token=None, timeout=30.0):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return httpx.Client(base_url=base, timeout=timeout, headers=headers)


def register_user(base, code=None, username=None, password="secret123", extra=None):
    code = code or ATTACK_CODE
    u = username or ("atk" + secrets.token_hex(3))
    body = {"username": u, "email": f"{u}@gmail.com", "password": password, "invite_code": code}
    if extra:
        body.update(extra)
    d = None
    for _ in range(6):
        c = httpx.Client(base_url=base, timeout=30.0)
        r = c.post("/api/auth/register", json=body)
        c.close()
        if r.status_code == 200:
            d = r.json()
            break
        if r.status_code in (429, 503):
            import time as _t

            _t.sleep(2.5)
            continue
        return None
    if d is None:
        return None
    return {"username": u, "token": d["token"], "id": d["id"], "role": d.get("role", "user"), "email": d.get("email", "")}


def admin_token(base):
    c = httpx.Client(base_url=base, timeout=30.0)
    r = c.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminPass99!"})
    c.close()
    if r.status_code != 200:
        return None
    return r.json()["token"]


def verdict(name, attempts, compromised):
    """In kết quả và thoát với mã phù hợp cho orchestrator tổng hợp."""
    ok = len(compromised) == 0
    print(f"VERDICT {name}: {'CLEAN' if ok else 'COMPROMISED'} | attempts={attempts} | breaches={len(compromised)}")
    for n, note in compromised:
        print(f"  !!! {n}: {note}")
    sys.exit(0 if ok else 1)


def forge_token(base, user_id, epoch=0, key=b"attacker-guess"):
    import hashlib
    import hmac
    import time

    from app.config import settings  # chỉ đọc TTL, không lộ key

    try:
        expires = int(time.time()) + settings.token_ttl_hours * 3600
    except Exception:
        expires = int(time.time()) + 86400
    payload = f"{user_id}.{expires}.{epoch}"
    sig = hmac.new(key, payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"
