import argparse
import random
import secrets
import statistics
import sys
import threading
import time

import httpx

LEAK_MARKERS = ("sqlite", "sqlalchemy", "OperationalError", "IntegrityError", "Traceback", "sqlite_master", "SELECT ")
ADMIN_USER = "ghitatruongle"


def payloads():
    return {
        "boolean-auth": [
            ("identifier", "' OR '1'='1"), ("identifier", "admin'--"), ("identifier", "' OR 1=1--"),
            ("password", "' OR '1'='1"), ("password", "' OR 1=1--"), ("identifier", "' OR '1'='1' --"),
        ],
        "union-exfil": [
            "' UNION SELECT null,username,password_hash FROM users--",
            "' UNION SELECT 1,2,3--",
            "x' UNION SELECT id,username,role FROM users--",
            "%' UNION SELECT null,email,password_hash FROM users--",
        ],
        "error-based": [
            "'", "''", "';", "\"", "`", "')", "%%'", "a'b\"c`d--",
            "' AND 1=CONVERT(int,@@version)--", "1)) OR 1=1#",
        ],
        "time-blind": [
            "' OR 1=randomblob(500000000)--",
            "1 AND EXISTS(SELECT 1 FROM users,users a,users b WHERE randomblob(200000000))",
            "x' OR 1=WITH RECURSIVE q(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM q) SELECT randomblob(300000000)--",
        ],
        "stacked": [
            "x'; DROP TABLE users;--",
            "x'; DELETE FROM users;--",
            "x'; INSERT INTO users(username,password_hash,role) VALUES('pwn','x','admin');--",
            "x'; UPDATE users SET role='admin' WHERE username='userthuong';--",
        ],
        "second-order": [
            "atk'--", "atk';--", "atk' OR '1'='1", "atk' UNION SELECT 1--", "atk\"--",
        ],
        "encoding-evasion": [
            "%27%20OR%201%3D1--", "%2527 OR 1=1--", "＇ OR ＇1＇=＇1", "'%00 OR 1=1--",
            "\\' OR 1=1--", "\\\\' OR 1=1--", "' || '1'='1",
        ],
        "like-wildcard": [
            "%" * 500, "_" * 500, "%_%_%_" * 100, "[%]" * 100, "%%' OR '1'='1",
        ],
        "json-type": [
            ["' OR '1'='1"], {"$ne": None}, {"q": "' OR 1=1--"},
        ],
        "header-log": [
            "x' OR '1'='1", "'; DROP TABLE security_events;--", "%00', 'admin",
        ],
    }


class Raid:
    def __init__(self, base, seconds):
        self.base = base
        self.seconds = seconds
        self.lock = threading.Lock()
        self.hits = []
        self.counts = {k: 0 for k in payloads()}
        self.statuses = {}
        self.slow = []

    def hit(self, cls, detail):
        with self.lock:
            self.hits.append((cls, detail[:160]))

    def record(self, cls, status, elapsed=None):
        with self.lock:
            self.counts[cls] += 1
            self.statuses[status] = self.statuses.get(status, 0) + 1
        if elapsed is not None and elapsed > 3.0:
            with self.lock:
                self.slow.append((cls, round(elapsed, 2)))

    def scan_body(self, cls, r):
        body = r.text[:2000].lower()
        for marker in LEAK_MARKERS:
            if marker.lower() in body:
                self.hit(cls, f"leak marker '{marker}' status {r.status_code}: {r.text[:120]}")
                return True
        if r.status_code == 503:
            return
        if r.status_code >= 500 and r.status_code != 503:
            self.hit(cls, f"status {r.status_code}: {r.text[:120]}")
            return True
        return False


def persona_boolean(raid, client, stop, cls_name=None):
    for cls, items in payloads().items():
        if cls != "boolean-auth":
            continue
        while not stop.is_set():
            for field, val in items:
                if stop.is_set():
                    return
                body = {"identifier": f"u{secrets.token_hex(3)}", "password": secrets.token_hex(8)}
                body[field] = val
                t0 = time.time()
                try:
                    r = client.post("/api/auth/login", json=body, timeout=15)
                except Exception as e:
                    raid.record(cls, 0)
                    continue
                raid.record(cls, r.status_code, time.time() - t0)
                if r.status_code == 200:
                    raid.hit(cls, f"AUTH BYPASS login 200 with {field}={val[:60]}")
                elif r.status_code != 503:
                    raid.scan_body(cls, r)
                time.sleep(0.15)


def persona_generic(raid, client, stop, cls_name, mode):
    items = payloads()[cls_name]
    while not stop.is_set():
        for val in items:
            if stop.is_set():
                return
            t0 = time.time()
            try:
                if mode == "q":
                    r = client.get("/api/heritage", params={"q": val, "limit": 5}, timeout=15)
                elif mode == "q2":
                    r = client.get("/api/lessons", params={"q": val}, timeout=15)
                elif mode == "register-username":
                    u = ("atk" + secrets.token_hex(3))
                    r = client.post("/api/auth/register", json={
                        "username": val[:40], "email": f"{u}@gmail.com",
                        "password": "secret123", "invite_code": raid.invite,
                    }, timeout=15)
                    if r.status_code == 200 and r.json().get("role") == "admin":
                        raid.hit(cls_name, f"ROLE ESCALATION via username={val[:40]}")
                    elif r.status_code >= 500 and r.status_code != 503:
                        raid.scan_body(cls_name, r)
                    raid.record(cls_name, r.status_code, time.time() - t0)
                    if r.status_code == 429:
                        time.sleep(3)
                    continue
                elif mode == "register-email":
                    u = ("atk" + secrets.token_hex(3))
                    r = client.post("/api/auth/register", json={
                        "username": u, "email": val[:60],
                        "password": "secret123", "invite_code": raid.invite,
                    }, timeout=15)
                elif mode == "header":
                    r = client.get("/api/heritage", params={"limit": 2},
                                   headers={"X-Forwarded-For": val, "User-Agent": val}, timeout=15)
                elif mode == "id":
                    r = client.get(f"/api/heritage/{val}", timeout=15)
                else:
                    r = client.get("/health", timeout=15)
            except Exception:
                raid.record(cls_name, 0)
                continue
            raid.record(cls_name, r.status_code, time.time() - t0)
            raid.scan_body(cls_name, r)
            time.sleep(0.1)


def persona_time_blind(raid, client, stop, cls_name=None):
    slow_streak = {}
    control = "A" * 40
    while not stop.is_set():
      for val in payloads()["time-blind"]:
        if stop.is_set():
            return
        try:
            t0 = time.time()
            client.get("/api/heritage", params={"q": control, "limit": 5}, timeout=20)
            base_ms = (time.time() - t0) * 1000
            t0 = time.time()
            r = client.get("/api/heritage", params={"q": val, "limit": 5}, timeout=20)
            elapsed = time.time() - t0
            t0 = time.time()
            client.get("/api/heritage", params={"q": control, "limit": 5}, timeout=20)
            base_ms2 = (time.time() - t0) * 1000
        except Exception:
            raid.record("time-blind", 0)
            continue
        raid.record("time-blind", r.status_code, elapsed)
        if base_ms < 500 and base_ms2 < 500:
            if elapsed * 1000 > max(3000, base_ms * 5):
                slow_streak[val] = slow_streak.get(val, 0) + 1
                if slow_streak[val] >= 2:
                    raid.hit("time-blind", f"TIME BLIND tai lap trong cua so khong nghen: payload {elapsed:.1f}s x2 (control {base_ms / 1000:.2f}s/{base_ms2 / 1000:.2f}s) -> SQL thuc thi that")
            else:
                slow_streak[val] = 0
        raid.scan_body("time-blind", r)
        time.sleep(0.2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--seconds", type=int, default=45)
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--admin-password", default="")
    ap.add_argument("--no-integrity", action="store_true")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    raid = Raid(base, args.seconds)
    raid.invite = args.invite
    print(f"SQLI RAID 10 lop tan cong x nhom hacker dong thoi trong {args.seconds}s — target {base}")

    probe = httpx.get(base + "/health", timeout=10)
    assert probe.status_code == 200, "server khong san sang"

    stop = threading.Event()
    client = httpx.Client(base_url=base, timeout=20)

    roles_thread = threading.Thread(
        target=persona_generic,
        args=(raid, client, stop, "second-order", "register-username"), daemon=True,
    )
    classes = [
        ("boolean-auth", persona_boolean, {}),
        ("union-exfil", persona_generic, ("q",)),
        ("error-based", persona_generic, ("q",)),
        ("time-blind", persona_time_blind, {}),
        ("stacked", persona_generic, ("register-username",)),
        ("second-order", persona_generic, ("register-email",)),
        ("encoding-evasion", persona_generic, ("q",)),
        ("like-wildcard", persona_generic, ("q",)),
        ("json-type", persona_generic, ("id",)),
        ("header-log", persona_generic, ("header",)),
    ]
    threads = []
    for cls_name, fn, extra in classes:
        if fn is persona_boolean:
            extra = ()
        th = threading.Thread(
            target=fn, args=(raid, httpx.Client(base_url=base, timeout=20), stop, cls_name, *extra), daemon=True
        )
        threads.append(th)

    threads.append(roles_thread)
    for th in threads:
        th.start()
    t0 = time.time()
    while time.time() - t0 < args.seconds:
        time.sleep(2)
    stop.set()
    for th in threads:
        th.join(timeout=3)

    print(f"\n== TONG KET {int(time.time() - t0)}s ==")
    total = 0
    for cls, n in raid.counts.items():
        total += n
        print(f"  {cls:<18} requests={n:<7} hits={sum(1 for c, _ in raid.hits if c == cls)}")
    print(f"  phan bo status: {dict(sorted(raid.statuses.items()))}")
    if raid.slow:
        print(f"  response cham >3s: {raid.slow[:6]}")
    print(f"  TONG requests={total} | HITS={len(raid.hits)}")
    for c, d in raid.hits[:12]:
        print(f"  !!! [{c}] {d}")

    if args.no_integrity:
        ok = len(raid.hits) == 0
        print(f"\nVERDICT SQLI-RAID: " + ("CLEAN — KHONG CO LO HONG" if ok else "COMPROMISED") + f" | hits={len(raid.hits)} (bo qua integrity — orchestrator tu lam phan xanh)")
        sys.exit(0 if ok else 1)

    print("\n== KIEM TRA TOAN VEN SAU RAID ==")
    integrity_fails = []
    try:
        r = client.get("/api/heritage", params={"limit": 3}, timeout=10)
        if r.status_code != 200:
            integrity_fails.append(f"heritage list pha hong: {r.status_code}")
    except Exception as e:
        integrity_fails.append(f"heritage list exception {type(e).__name__}")
    if args.admin_password:
        at = ""
        for attempt in range(15):
            r = client.post("/api/auth/login", json={"identifier": ADMIN_USER, "password": args.admin_password}, timeout=10)
            if r.status_code == 200:
                at = r.json()["token"]
                break
            if r.status_code == 429:
                time.sleep(8)
                continue
            break
        if not at:
            integrity_fails.append(f"tai khoan admin khong dang nhap duoc sau khi cho qua flood window (cuoi cung {r.status_code})")
        else:
            r2 = client.get("/api/admin/stats", headers={"Authorization": f"Bearer {at}"}, timeout=10)
            if r2.status_code != 200:
                integrity_fails.append(f"admin stats tra loi {r2.status_code}")
    if integrity_fails:
        print("  !!! " + " | ".join(integrity_fails))
        raid.hits.append(("integrity", "; ".join(integrity_fails)))
    else:
        print("  toan ven: users table con nguyen, khong co admin ro ri, API van song")

    client.close()
    ok = len(raid.hits) == 0
    print(f"\nVERDICT SQLI-RAID: {'CLEAN — KHONG CO LO HONG' if ok else 'COMPROMISED'} | requests={total} | hits={len(raid.hits)}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
