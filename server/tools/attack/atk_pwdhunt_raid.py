import secrets
import statistics
import sys
import threading
import time

import httpx

COMMON_PASSWORDS = [
    "password123", "Admin@123", "123456", "123456789", "qwerty123",
    "hue2026", "admin2026", "P@ssw0rd", "matkhau123", "iloveyou1",
    "abc123456", "password1", "1q2w3e4r", "zaq12wsx", "hueheritage",
]

USERNAME_TARGETS = [
    "admin", "administrator", "root", "ghitatruongle", "userthuong",
    "nguyenvana", "tranan", "leventb", "test", "guest",
    "hoang", "thanh", "hueuser", "music1", "singer1",
    "nghesi", "cahue", "dannguyet", "trongca", "admin01",
]


class Raid:
    def __init__(self):
        self.lock = threading.Lock()
        self.hits = []
        self.counts = {}
        self.statuses = {}

    def record(self, cls, status):
        with self.lock:
            self.counts[cls] = self.counts.get(cls, 0) + 1
            self.statuses[status] = self.statuses.get(status, 0) + 1

    def hit(self, cls, detail):
        with self.lock:
            self.hits.append((cls, detail[:200]))


def persona_spraying(raid, base, stop):
    client = httpx.Client(timeout=15)
    seen = set()
    i = 0
    while not stop.is_set():
        u = USERNAME_TARGETS[i % len(USERNAME_TARGETS)] + secrets.token_hex(2)
        if u in seen:
            continue
        seen.add(u)
        i += 1
        pw = COMMON_PASSWORDS[i % len(COMMON_PASSWORDS)]
        try:
            r = client.post(f"{base}/api/auth/login",
                            json={"identifier": u, "password": pw},
                            headers={"Origin": "https://evil.example"}, timeout=15)
        except Exception:
            raid.record("spraying-blind", 0)
            continue
        raid.record("spraying-blind", r.status_code)
        if r.status_code == 200:
            raid.hit("spraying-blind", f"DOAN TRUNG: {u} / {pw}")
        if r.status_code == 429:
            print("  [spraying-blind] server CHAN spray bang 429 — tot")
            break
        time.sleep(0.35)
    client.close()


def persona_stuffing_admin(raid, base, stop):
    client = httpx.Client(timeout=15)
    got429 = False
    for pw in COMMON_PASSWORDS * 3:
        if stop.is_set():
            break
        try:
            r = client.post(f"{base}/api/auth/login",
                            json={"identifier": "ghitatruongle", "password": pw}, timeout=15)
        except Exception:
            raid.record("stuffing-admin", 0)
            continue
        raid.record("stuffing-admin", r.status_code)
        if r.status_code == 200:
            raid.hit("stuffing-admin", f"ADMIN DOAN TRUNG voi mat khau pho thong: {pw}")
            break
        if r.status_code == 429:
            got429 = True
            break
    if not got429 and not stop.is_set():
        raid.hit("stuffing-admin", "30 mat khau pho thong khong bi 429 lan nao — khoa identifier khong hoat dong?")
    client.close()


def persona_xff_rotation(raid, base, stop):
    client = httpx.Client(timeout=15)
    blocked = False
    for i in range(150):
        if stop.is_set():
            break
        xff = f"10.{i // 250 % 250}.{i % 250}.{(i * 7) % 250}"
        try:
            r = client.post(f"{base}/api/auth/login",
                            json={"identifier": "ghitatruongle", "password": f"xffguess{i}"},
                            headers={"X-Forwarded-For": xff}, timeout=15)
        except Exception:
            raid.record("xff-rotation", 0)
            continue
        raid.record("xff-rotation", r.status_code)
        if r.status_code == 200:
            raid.hit("xff-rotation", "XFF ROTATION DOAN TRUNG — server tin XFF!")
            break
        if r.status_code == 429:
            blocked = True
            break
    if not blocked and not stop.is_set():
        raid.hit("xff-rotation", "150 attempt XFF xoay vong khong bi 429 (per-identifier van giu — kiem tra ky)")
    client.close()


def persona_timing_oracle(raid, base, stop):
    client = httpx.Client(timeout=15)
    real_times = []
    ghost_times = []
    for i in range(24):
        if stop.is_set():
            break
        try:
            t0 = time.time()
            client.post(f"{base}/api/auth/login",
                        json={"identifier": "userthuong", "password": f"wrong-{i}"}, timeout=15)
            real_times.append((time.time() - t0) * 1000)
            t0 = time.time()
            client.post(f"{base}/api/auth/login",
                        json={"identifier": f"ghost{i}xyz", "password": f"wrong-{i}"}, timeout=15)
            ghost_times.append((time.time() - t0) * 1000)
        except Exception:
            raid.record("timing-oracle", 0)
            continue
        raid.record("timing-oracle", 401)
        time.sleep(1.2)
    if real_times and ghost_times:
        rm = statistics.median(real_times)
        gm = statistics.median(ghost_times)
        diff = abs(rm - gm) / max(rm, gm) * 100
        print(f"  [timing-oracle] median ton-tai={rm:.0f}ms vs khong-ton-tai={gm:.0f}ms (lech {diff:.0f}%)")
        if diff > 40:
            raid.hit("timing-oracle", f"TIMING ORACLE: lech {diff:.0f}% — lộ user tồn tại")
    client.close()


def persona_normalization_split(raid, base, stop, invite):
    client = httpx.Client(timeout=15)
    u = "split" + secrets.token_hex(3)
    try:
        r = client.post(f"{base}/api/auth/register", json={
            "username": u, "email": f"{u}@gmail.com",
            "password": "secret123", "invite_code": invite,
        }, timeout=15)
        raid.record("normalization-split", r.status_code)
        if r.status_code != 200:
            client.close()
            return
    except Exception:
        raid.record("normalization-split", 0)
        return
    for i in range(5):
        if stop.is_set():
            return
        try:
            client.post(f"{base}/api/auth/login",
                        json={"identifier": u, "password": f"burn-{i}"}, timeout=15)
            raid.record("normalization-split", 401)
            time.sleep(0.3)
        except Exception:
            raid.record("normalization-split", 0)
    try:
        r = client.post(f"{base}/api/auth/login",
                        json={"identifier": f"{u}@gmail.com", "password": "split-probe"}, timeout=15)
        raid.record("normalization-split", r.status_code)
        if r.status_code == 401:
            raid.hit("normalization-split", "LOCKOUT SPLIT: dot 5 sai qua username — email cung tai khoan van 401 chua 429 (ngan sach do gap doi)")
        elif r.status_code == 429:
            print("  [normalization-split] email cung tai khoan da bi khoa chung — khong split")
    except Exception:
        raid.record("normalization-split", 0)
    client.close()


def persona_oracle_messages(raid, base, invite, stop):
    client = httpx.Client(timeout=15)
    u0 = "oracle" + secrets.token_hex(3)
    try:
        r0 = client.post(f"{base}/api/auth/register", json={
            "username": u0, "email": f"{u0}@gmail.com",
            "password": "secret123", "invite_code": invite,
        }, timeout=15)
        raid.record("oracle-messages", r0.status_code)
        probes = [
            {"username": u0, "email": f"moi{secrets.token_hex(2)}@gmail.com", "password": "secret123", "invite_code": invite},
            {"username": "moi" + secrets.token_hex(2), "email": f"{u0}@gmail.com", "password": "secret123", "invite_code": invite},
        ]
        msgs = []
        for body in probes:
            r = client.post(f"{base}/api/auth/register", json=body, timeout=15)
            raid.record("oracle-messages", r.status_code)
            msgs.append(r.text[:120])
        if len(msgs) == 2 and msgs[0] != msgs[1]:
            raid.hit("oracle-messages", f"MESSAGE ORACLE phan biet ton tai: {msgs[0][:60]} vs {msgs[1][:60]}")
    except Exception:
        raid.record("oracle-messages", 0)
    client.close()


def persona_policy_probe(raid, base, stop):
    client = httpx.Client(timeout=15)
    u = "policy" + secrets.token_hex(3)
    try:
        r = client.post(f"{base}/api/auth/register", json={
            "username": u, "email": f"{u}@gmail.com",
            "password": "secret123", "invite_code": raid.invite,
        }, timeout=15)
        raid.record("policy-probe", r.status_code)
        if r.status_code != 200:
            client.close()
            return
        tok = r.json()["token"]
        weak = ["123", "abc", "11111111", "matkhau"]
        for w in weak:
            r2 = client.post(f"{base}/api/auth/change-password", json={
                "old_password": "secret123", "new_password": w,
            }, headers={"Authorization": f"Bearer {tok}"}, timeout=15)
            raid.record("policy-probe", r2.status_code)
            if r2.status_code == 200:
                raid.hit("policy-probe", f"CHAP NHAN MAT KHAU YEU '{w}' — chinh sach that loi")
                break
    except Exception:
        raid.record("policy-probe", 0)
    client.close()


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--invite", default="CHAOS-CODE")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    raid = Raid()
    raid.invite = args.invite
    print(f"PWD-HUNT RAID 8 persona — do mat khau moi kieu trong {args.seconds}s — target {base}")
    assert httpx.get(base + "/health", timeout=10).status_code == 200, "server khong san sang"

    stop = threading.Event()
    personas = [
        ("spraying-blind", persona_spraying, ()),
        ("stuffing-admin", persona_stuffing_admin, ()),
        ("xff-rotation", persona_xff_rotation, ()),
        ("timing-oracle", persona_timing_oracle, ()),
        ("normalization-split", persona_normalization_split, (args.invite,)),
        ("oracle-messages", persona_oracle_messages, (args.invite,)),
        ("policy-probe", persona_policy_probe, ()),
    ]
    threads = []
    for name, fn, extra in personas:
        th = threading.Thread(target=fn, args=(raid, base, stop, *extra), daemon=True)
        threads.append(th)
    for th in threads:
        th.start()
    t0 = time.time()
    while time.time() - t0 < args.seconds:
        time.sleep(2)
    stop.set()
    for th in threads:
        th.join(timeout=5)

    print(f"\n== TONG KET {int(time.time() - t0)}s ==")
    total = 0
    for name, _, _ in personas:
        n = raid.counts.get(name, 0)
        total += n
        hits = sum(1 for cn, _ in raid.hits if cn == name)
        print(f"  {name:<20} requests={n:<7} hits={hits}")
    print(f"  phan bo status: {dict(sorted(raid.statuses.items()))}")
    print(f"  TONG requests={total} | HITS={len(raid.hits)}")
    for cn, d in raid.hits[:12]:
        print(f"  !!! [{cn}] {d}")

    ok = len(raid.hits) == 0
    print(f"\nVERDICT PWD-HUNT: {'CLEAN — KHONG CO LO HONG' if ok else 'CO PHAT HIEN'} | requests={total} | hits={len(raid.hits)}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
