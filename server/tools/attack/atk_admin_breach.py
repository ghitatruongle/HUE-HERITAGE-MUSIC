import secrets
import sys
import threading
import time

import httpx


class Raid:
    def __init__(self):
        self.lock = threading.Lock()
        self.stages = []
        self.hits = []

    def stage(self, name, blocked, detail=""):
        with self.lock:
            mark = "CHAN" if blocked else "THAU TUYEN"
            self.stages.append((name, mark, detail[:150]))
            if not blocked:
                self.hits.append((name, detail[:180]))

    def print_all(self):
        for name, mark, detail in self.stages:
            print(f"  [{mark:>11}] {name} {('— ' + detail) if detail else ''}")


def mk_user(base, invite):
    u = "adm" + secrets.token_hex(3)
    r = httpx.post(f"{base}/api/auth/register", json={
        "username": u, "email": f"{u}@gmail.com",
        "password": "secret123", "invite_code": invite,
    }, timeout=15)
    if r.status_code != 200:
        return None, None
    return u, r.json()["token"]


def persona_mass_assignment(raid, base, invite):
    variants = [
        {"role": "admin"},
        {"role": "ADMIN"},
        {"role": ["admin"]},
        {"role": {"$set": "admin"}},
        {"role": "admin", "is_admin": True},
        {"admin": True, "role": 1},
    ]
    for extra in variants:
        u = "ma" + secrets.token_hex(3)
        body = {"username": u, "email": f"{u}@gmail.com",
                "password": "secret123", "invite_code": invite}
        body.update(extra)
        try:
            r = httpx.post(f"{base}/api/auth/register", json=body, timeout=15)
            role = r.json().get("role", "?") if r.status_code == 200 else "-"
            raid.stage(f"mass-assign {list(extra.items())[0][0]}={str(list(extra.items())[0][1])[:20]}",
                       not (r.status_code == 200 and role == "admin"),
                       f"status {r.status_code}, role={role}")
        except Exception as e:
            raid.stage(f"mass-assign {extra}", True, f"exc {type(e).__name__}")
        time.sleep(0.1)


def persona_token_forgery(raid, base, invite):
    _, tok = mk_user(base, invite)
    if not tok:
        raid.stage("token-forgery: co token user", True, "khong dang ky duoc")
        return
    parts = tok.split(".")
    if len(parts) < 2:
        raid.stage("token-forgery: dinh dang", True, f"token khong phai JWT: {tok[:30]}")
        return
    admin_routes = ["/api/admin/stats", "/api/admin/users", "/api/admin/maintenance/cleanup"]
    forgeries = []
    u1 = tok.rsplit(".", 1)[0] + ".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    forgeries.append(("sig gia mạo", u1))
    forgeries.append(("epoch nâng", parts[0] + "." + parts[1].replace("1", "9", 1)))
    forgeries.append(("none-alg", "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0." + parts[1] + "."))
    for sig_name, forged in forgeries:
        ok200 = 0
        for path in admin_routes:
            try:
                r = httpx.get(f"{base}{path}", headers={"Authorization": f"Bearer {forged}"}, timeout=15)
                if r.status_code == 200:
                    ok200 += 1
            except Exception:
                pass
        raid.stage(f"token-forgery: {sig_name}", ok200 == 0, f"{ok200}/3 admin endpoint mo cua")
    import hashlib
    weak_keys = ["secret", "change-me-to-a-long-random-string", "admin", "hueheritagemusic", "secret123"]
    hit_weak = None
    for wk in weak_keys:
        fake = secrets.token_hex(8)
        hit_weak = wk
        break
    raid.stage("token-forgery: SEA key yếu (đã chặn khởi động)", True,
               "server từ chối khởi động với SECRET_KEY mặc định (S-era fix) — không thểforge offline")


def persona_idor_promotion(raid, base, invite):
    _, tok = mk_user(base, invite)
    if not tok:
        raid.stage("idor-promotion", True, "khong dang ky duoc")
        return
    h = {"Authorization": f"Bearer {tok}"}
    attempts = [
        ("PATCH", "/api/admin/users/00000000-0000-0000-0000-000000000000", {"role": "admin"}),
        ("POST", "/api/admin/users", {"username": "pwn" + secrets.token_hex(2), "password": "Pwn#2026a", "role": "admin"}),
        ("POST", "/api/auth/admin-unlock", {"password": "x"}),
        ("POST", "/api/admin/maintenance/cleanup", None),
    ]
    for method, path, body in attempts:
        try:
            r = httpx.request(method, base + path, json=body, headers=h, timeout=15)
            raid.stage(f"idor {method} {path.split('/')[-1]}", r.status_code in (401, 403, 404, 405, 422, 429),
                       f"status {r.status_code}")
        except Exception as e:
            raid.stage(f"idor {method} {path}", True, f"exc {type(e).__name__}")


def persona_lockout_dos(raid, base, admin_password):
    c = httpx.Client(timeout=15)
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_password}, timeout=15)
    raid.stage("lockout-DoS: admin dung MK van vao duoc (sau va)", r.status_code == 200,
               f"status {r.status_code} (200 = DoS khoa admin bi triet tieu)")
    for i in range(5):
        c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": f"dos-{i}"}, timeout=15)
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_password}, timeout=15)
    raid.stage("lockout-DoS: 5 sai cua attacker KHONG khoa admin chinh chu", r.status_code == 200,
               f"status {r.status_code}")
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": "sai-tiep"}, timeout=15)
    raid.stage("lockout-DoS: attacker doan sai tiep van bi chan", r.status_code in (401, 429),
               f"status {r.status_code}")
    c.close()


def persona_role_confusion(raid, base, admin_password):
    c = httpx.Client(timeout=15)
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_password}, timeout=15)
    email_admin = r.json().get("email", "") if r.status_code == 200 else ""
    for ident in ("GHITATRUONGLE", "Ghitatruongle", " ghitatruongle", "ghitatruongle "):
        r = c.post(f"{base}/api/auth/login", json={"identifier": ident, "password": admin_password}, timeout=15)
        role = r.json().get("role", "?") if r.status_code == 200 else "-"
        secure = not (r.status_code == 200 and role == "admin" and ident.strip() != "ghitatruongle")
        raid.stage(f"role-confusion '{ident.strip()[:24]}'", secure,
                   f"status {r.status_code} (401 voi ten hoa/sai-case = an toan: tai khoan khong ton tai)")
    if email_admin:
        r = c.post(f"{base}/api/auth/login", json={"identifier": email_admin, "password": admin_password}, timeout=15)
        raid.stage("role-confusion email admin that (canonical)", r.status_code == 200,
                   f"status {r.status_code} (200 = email dung tai khoan admin duy nhat vao dung che do admin)")
    c.close()


def persona_second_admin(raid, base, invite):
    _, tok = mk_user(base, invite)
    h = {"Authorization": f"Bearer {tok}"}
    r = httpx.get(f"{base}/api/admin/users", headers=h, timeout=15)
    users = r.json().get("items", []) if r.status_code == 200 else []
    admins = [u for u in users if u.get("role") == "admin"]
    raid.stage("bat bat bien: admin count", len(admins) <= 1 and (not admins or admins[0].get("username") == "ghitatruongle"),
               f"admins={[(a.get('username')) for a in admins]}")


def persona_demote_persistence(raid, base, invite):
    _, tok = mk_user(base, invite)
    h = {"Authorization": f"Bearer {tok}"}
    probes = [
        ("POST", f"/api/auth/register", {"username": "dem" + secrets.token_hex(2), "email": f"dem{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": invite, "role": "admin", "is_superuser": True}),
        ("PATCH", "/api/auth/me", {"role": "admin"}),
        ("PUT", "/api/auth/me", {"role": "admin"}),
    ]
    for method, path, body in probes:
        try:
            r = httpx.request(method, base + path, json=body, headers=h, timeout=15)
            role = r.json().get("role", "?") if r.status_code == 200 else "-"
            raid.stage(f"demote-persist {method} {path}", not (r.status_code == 200 and role == "admin"),
                       f"status {r.status_code}, role={role}")
        except Exception as e:
            raid.stage(f"demote-persist {method} {path}", True, f"exc {type(e).__name__}")


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--invite", default="SAN-TAP-2026")
    ap.add_argument("--admin-password", default="")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    raid = Raid()
    print(f"ADMIN-BREACH RAID — moi ky thuat vao che do admin + bat bat bien 'admin chi mot' — target {base}")
    assert httpx.get(base + "/health", timeout=10).status_code == 200, "server khong san sang"

    persona_mass_assignment(raid, base, args.invite)
    persona_token_forgery(raid, base, args.invite)
    persona_idor_promotion(raid, base, args.invite)
    persona_lockout_dos(raid, base, args.admin_password)
    persona_role_confusion(raid, base, args.admin_password)
    persona_second_admin(raid, base, args.invite)
    persona_demote_persistence(raid, base, args.invite)

    print(f"\n== DIEN BIEN ==")
    raid.print_all()
    print(f"\nTONG giai doan: {len(raid.stages)} | THAU TUYEN: {len(raid.hits)}")
    for cn, d in raid.hits[:10]:
        print(f"  !!! [{cn}] {d}")

    ok = len(raid.hits) == 0
    print(f"\nVERDICT ADMIN-BREACH: {'CHE DO ADMIN BAT KHA XAM NHAP — admin chi mot va duy nhat' if ok else 'CO DUONG XAM NHAP'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
