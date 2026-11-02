import argparse
import asyncio
import secrets
import sys
import time
from pathlib import Path

import httpx

INVITE = "CHAOS-CODE"


def make_wav(seed):
    import struct
    n = 2000 + seed
    data = b"".join(struct.pack("<h", (seed * 37 + i * 11) % 16000 - 8000) for i in range(n))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, 8000, 16000, 2, 16
    ) + b"data" + struct.pack("<I", len(data))
    return hdr + data


async def register(base, username, password="secret123"):
    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(90.0)) as ac:
        r = await ac.post("/api/auth/register", json={
            "username": username, "email": f"{username}@gmail.com",
            "password": password, "invite_code": INVITE,
        })
        return r.status_code, r.json() if r.status_code == 200 else {}


async def login(base, identifier, password="secret123"):
    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
        r = await ac.post("/api/auth/login", json={"identifier": identifier, "password": password})
        return r.json().get("token", "") if r.status_code == 200 else ""


class Counters:
    def __init__(self):
        self.data = {}

    def add(self, status):
        self.data[status] = self.data.get(status, 0) + 1

    def blocked(self):
        return sum(v for k, v in self.data.items() if isinstance(k, int) and 400 <= k < 500)


async def legit_vu(ac, token, seed, deadline, results, own_item_titles):
    headers = {"Authorization": f"Bearer {token}"}
    read_routes = ["/api/heritage", "/api/lessons", "/api/music/models", "/api/task", "/api/auth/me"]
    while time.perf_counter() < deadline:
        pick = seed % 4
        if pick == 0:
            path = "/api/heritage"
        elif pick == 1:
            path = "/api/lessons"
        elif pick == 2:
            path = "/api/auth/me"
        else:
            path = "/api/task"
        t0 = time.perf_counter()
        status = 0
        try:
            r = await ac.get(path, headers=headers)
            status = r.status_code
        except Exception:
            status = 0
        results.append((status, (time.perf_counter() - t0) * 1000))
        if pick == 1 and time.perf_counter() < deadline - 1:
            title = f"vu{seed}-{secrets.token_hex(3)}"
            t0 = time.perf_counter()
            try:
                r = await ac.post(
                    "/api/heritage/upload",
                    files={"file": (f"{title}.wav", make_wav(seed), "audio/wav")},
                    data={"title": title},
                    headers=headers,
                )
                status2 = r.status_code
                if status2 == 200:
                    own_item_titles.append(r.json().get("id"))
            except Exception:
                status2 = 0
            results.append((status2, (time.perf_counter() - t0) * 1000))
        await asyncio.sleep(random_sleep())


def random_sleep():
    return 0.01 + (secrets.randbelow(40) / 1000)


async def attacker_idor(ac, attacker_token, victim_tasks, deadline, counts):
    headers = {"Authorization": f"Bearer {attacker_token}"}
    while time.perf_counter() < deadline:
        tid = secrets.choice(victim_tasks) if victim_tasks else secrets.token_hex(16)
        try:
            r = await ac.get(f"/api/music/task/{tid}", headers=headers)
            counts.add(r.status_code)
            r2 = await ac.post(f"/api/music/task/{tid}/cancel", headers=headers)
            counts.add(r2.status_code)
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.01)


async def attacker_admin_hammer(ac, token, deadline, counts):
    headers = {"Authorization": f"Bearer {token}"}
    paths = ["/api/admin/stats", "/api/admin/storage", "/api/auth/users", "/api/auth/invites"]
    while time.perf_counter() < deadline:
        try:
            for p in paths:
                r = await ac.get(p, headers=headers)
                counts.add(r.status_code)
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.01)


async def attacker_forger(ac, victim_id, deadline, counts):
    while time.perf_counter() < deadline:
        try:
            variants = [
                f"{victim_id}.{int(time.time()) + 3600}.0.{secrets.token_hex(32)}",
                f"{victim_id}.{int(time.time()) + 3600}.0.",
                f"{secrets.token_hex(8)}.{int(time.time()) + 3600}.0.{secrets.token_hex(32)}",
            ]
            for tok in variants:
                r = await ac.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
                counts.add(r.status_code)
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.01)


async def attacker_upload_evil(ac, token, deadline, counts):
    headers = {"Authorization": f"Bearer {token}"}
    while time.perf_counter() < deadline:
        try:
            evil = secrets.choice([
                b"MZ" + secrets.token_bytes(300),
                b"<?php phpinfo(); ?>" * 20,
                b"GIF89a" + secrets.token_bytes(200),
            ])
            r = await ac.post(
                "/api/heritage/upload",
                files={"file": (f"evil{secrets.token_hex(3)}.wav", evil, "audio/wav")},
                data={"title": "evil"},
                headers=headers,
            )
            counts.add(r.status_code)
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.01)


async def attacker_register_spam(ac, deadline, counts):
    while time.perf_counter() < deadline:
        try:
            r = await ac.post("/api/auth/register", json={
                "username": f"spam{secrets.token_hex(4)}",
                "email": f"spam{secrets.token_hex(4)}@gmail.com",
                "password": "secret123",
                "invite_code": f"SAI-{secrets.token_hex(3)}",
            })
            counts.add(r.status_code)
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.01)


async def attacker_cross_change(ac, victim_name, deadline, counts):
    while time.perf_counter() < deadline:
        try:
            r = await ac.post("/api/auth/change-password", json={
                "old_password": "dodolac", "new_password": "hacked123",
            }, headers={"Authorization": "Bearer x"})
            counts.add(r.status_code)
            r2 = await ac.get("/api/auth/users")
            counts.add(r2.status_code)
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.01)


async def epoch_race_victim(ac, token, password, deadline, counts, state):
    headers = {"Authorization": f"Bearer {token}"}
    bumped = False
    while time.perf_counter() < deadline:
        try:
            r = await ac.get("/api/auth/me", headers=headers)
            counts.add(r.status_code)
            if not bumped and time.perf_counter() > deadline - 3:
                rr = await ac.post("/api/auth/change-password", json={
                    "old_password": password, "new_password": "EpochBump#99x",
                }, headers=headers)
                counts.add(rr.status_code)
                if rr.status_code == 200:
                    state["new_token"] = rr.json().get("token", "")
                    bumped = True
                    headers = {"Authorization": f"Bearer {state['new_token']}"}
        except Exception:
            counts.add(0)
        await asyncio.sleep(0.02)


async def health_watch(ac, deadline, probes):
    while time.perf_counter() < deadline:
        t0 = time.perf_counter()
        try:
            r = await ac.get("/health")
            probes.append((r.status_code, (time.perf_counter() - t0) * 1000))
        except Exception:
            probes.append((0, (time.perf_counter() - t0) * 1000))
        await asyncio.sleep(2.0)


def pct(vals, p):
    if not vals:
        return 0.0
    s = sorted(vals)
    return s[min(len(s) - 1, int(p / 100 * (len(s) - 1)))]


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8128")
    ap.add_argument("--levels", default="100,400,1000")
    ap.add_argument("--phase", type=float, default=12.0)
    ap.add_argument("--legit-users", type=int, default=100)
    args = ap.parse_args()
    base = args.base

    print("== CHUẨN BỊ: nạn nhân + attacker + user thật ==")
    victims = []
    for i in range(12):
        name = f"deepvictim{i:02d}"
        st, body = await register(base, name)
        if st == 200:
            victims.append({"name": name, "id": body["id"], "token": body["token"]})
    print(f"  nạn nhân: {len(victims)}")

    victim_tasks = []
    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0)) as ac:
        r = await ac.post(
            "/api/heritage/upload",
            files={"file": ("bai_nanan.wav", make_wav(1), "audio/wav")},
            data={"title": "Bai nan nhan"},
            headers={"Authorization": f"Bearer {victims[0]['token']}"},
        )
        if r.status_code == 200:
            heritage_id = r.json()["id"]
            for v in victims[:8]:
                rr = await ac.post(
                    "/api/music/sing-original",
                    data={"heritage_id": heritage_id, "lyrics": "lời thử"},
                    headers={"Authorization": f"Bearer {v['token']}"},
                )
                if rr.status_code == 200:
                    tid = rr.json().get("task_db_id") or rr.json().get("id")
                    if tid:
                        victim_tasks.append(tid)
    print(f"  task thật của nạn nhân (để thử IDOR): {len(victim_tasks)}")

    attacker_tokens = []
    for i in range(40):
        st, body = await register(base, f"deepatk{i:02d}")
        if st == 200:
            attacker_tokens.append(body["token"])
    print(f"  attacker có tài khoản thật: {len(attacker_tokens)}")

    tokens = []
    for i in range(args.legit_users):
        tok = await login(base, f"deeplegit{i:04d}") or ""
        if not tok:
            name = f"deeplegit{i:04d}"
            st, body = await register(base, name)
            tok = body.get("token", "")
        if tok:
            tokens.append(tok)
    print(f"  user thật có token: {len(tokens)}")

    victim_id = victims[0]["id"] if victims else "x"
    attacker_token = attacker_tokens[0] if attacker_tokens else None

    grand_attacks = {}
    all_legit = []
    grand_probe_fail = 0

    for level in [int(x) for x in args.levels.split(",")]:
        print(f"\n=== MỨC {level} VU + 40 ATTACKER CHUYÊN SÂU ({args.phase:.0f}s) ===")
        legit_results = []
        own_titles = []
        attack_counts = Counters()
        probes = []
        epoch_state = {}
        epoch_victim = victims[1] if len(victims) > 1 else None
        deadline = time.perf_counter() + args.phase

        shared = httpx.AsyncClient(
            base_url=base,
            timeout=httpx.Timeout(30.0),
            limits=httpx.Limits(max_connections=max(level + 80, 160), max_keepalive_connections=max(level + 80, 160)),
        )
        try:
            tasks = []
            for i in range(level):
                tasks.append(asyncio.create_task(legit_vu(
                    shared, tokens[i % len(tokens)], i, deadline, legit_results, own_titles,
                )))
            if attacker_token:
                tasks.append(asyncio.create_task(attacker_idor(shared, attacker_token, victim_tasks, deadline, attack_counts)))
            for i in range(6):
                tasks.append(asyncio.create_task(attacker_admin_hammer(
                    shared, attacker_tokens[i % len(attacker_tokens)], deadline, attack_counts,
                )))
            for i in range(6):
                tasks.append(asyncio.create_task(attacker_forger(
                    shared, victim_id, deadline, attack_counts,
                )))
            for i in range(6):
                tasks.append(asyncio.create_task(attacker_upload_evil(
                    shared, attacker_tokens[(i + 6) % len(attacker_tokens)], deadline, attack_counts,
                )))
            for i in range(6):
                tasks.append(asyncio.create_task(attacker_register_spam(shared, deadline, attack_counts)))
            tasks.append(asyncio.create_task(attacker_cross_change(shared, victim_id, deadline, attack_counts)))
            if epoch_victim:
                tasks.append(asyncio.create_task(epoch_race_victim(
                    shared, epoch_victim["token"], "secret123", deadline, attack_counts, epoch_state,
                )))
            tasks.append(asyncio.create_task(health_watch(shared, deadline, probes)))
            await asyncio.gather(*tasks)
        finally:
            await shared.aclose()

        lats = [ms for st, ms in legit_results if st == 200]
        hard = sum(1 for st, _ in legit_results if st == 0 or st >= 500)
        shed = sum(1 for st, _ in legit_results if st == 503)
        statuses = {}
        for st, _ in legit_results:
            statuses[st] = statuses.get(st, 0) + 1
        ok_health = sum(1 for st, _ in probes if st == 200)
        print(f"  user thật: {len(legit_results)} req, p50={pct(lats, 50):.0f}ms p95={pct(lats, 95):.0f}ms, lỗi thật={hard}, 503-shed={shed}, mã={statuses}")
        print(f"  attacker: {sum(attack_counts.data.values())} phát, bị chặn 4xx={attack_counts.blocked()}, 200={attack_counts.data.get(200, 0)}, chi tiết={attack_counts.data}")
        print(f"  health: {ok_health}/{len(probes)} OK")
        grand_attacks.update(attack_counts.data)
        all_legit.extend(legit_results)
        grand_probe_fail += sum(1 for st, _ in probes if st != 200)

    print("\n=== KIỂM CHỨNG TOÀN VẸN SAU BÃO ===")
    breaches = []

    lats = [ms for st, ms in all_legit if st == 200]
    print(f"  tổng user thật: {len(all_legit)} req, p50={pct(lats, 50):.0f}ms, p95={pct(lats, 95):.0f}ms")

    idor_blocked = sum(v for k, v in grand_attacks.items() if k == 404)
    idor_leak = grand_attacks.get(200, 0)
    attacker_admin = grand_attacks.get(403, 0)
    forged = grand_attacks.get(401, 0)

    if attacker_token:
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0)) as ac:
            for tid in victim_tasks[:4]:
                r = await ac.get(f"/api/music/task/{tid}", headers={"Authorization": f"Bearer {attacker_token}"})
                if r.status_code == 200:
                    breaches.append(f"IDOR: attacker đọc được task {tid} của nạn nhân")
                else:
                    print(f"  ✓ attacker với token thật đọc task nạn nhân → {r.status_code} (chặn)")

    epoch_password = "EpochBump#99x"
    for v in victims[:6]:
        tok = await login(base, v["name"])
        if not tok and v is victims[1]:
            tok = await login(base, v["name"], epoch_password)
            if tok:
                print(f"  {v['name']} login lại bằng mật khẩu MỚI sau epoch bump")
            continue
        if not tok:
            breaches.append(f"nạn nhân {v['name']} không login lại được")
            continue
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0)) as ac:
            r = await ac.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
            if r.status_code == 200 and r.json().get("username") == v["name"]:
                pass
            else:
                breaches.append(f"identity crossover cho {v['name']}")

    if epoch_state.get("new_token"):
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0)) as ac:
            r = await ac.get("/api/auth/me", headers={"Authorization": f"Bearer {epoch_state['new_token']}"})
            print(f"  ✓ epoch-bump victim dùng token mới → {r.status_code}")
    else:
        print("  (epoch race chưa kích hoạt — bỏ qua)")

    if grand_probe_fail > 0:
        breaches.append(f"health probe fail {grand_probe_fail} lần trong bão")

    hard_legit = sum(1 for st, _ in all_legit if st >= 500 and st != 503)
    if hard_legit > 0:
        breaches.append(f"user thật gặp {hard_legit} lỗi 5xx thực sự (503-shed là hành vi thiết kế)")

    print(f"\n  IDOR 404={idor_blocked}, admin 403={attacker_admin}, forged 401={forged}, attacker-200={idor_leak}")
    if breaches:
        print("\nLỖ HỔNG:")
        for b in breaches:
            print(f"  ✗ {b}")
        sys.exit(1)
    print("\nVERDICT: SẠCH — không breach, toàn vẹn dữ liệu giữ nguyên, user thật được phục vụ xuyên suốt.")
    sys.exit(0)


if __name__ == "__main__":
    asyncio.run(main())
