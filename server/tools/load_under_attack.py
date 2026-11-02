import argparse
import asyncio
import random
import secrets
import sys
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from load_ramp import READ_ROUTES, TOKEN_ROUTES, percentile  # noqa: E402

ATTACK_CODE = "CHAOS-CODE"


async def legit_vu(client, token, deadline, results):
    while time.perf_counter() < deadline:
        pick = random.random()
        acc = 0.0
        path = "/health"
        for route, weight in READ_ROUTES:
            acc += weight
            if pick <= acc:
                path = route
                break
        headers = {"Authorization": f"Bearer {token}"} if (path in TOKEN_ROUTES and token) else {}
        t0 = time.perf_counter()
        status = 0
        try:
            r = await client.get(path, headers=headers)
            status = r.status_code
        except Exception:
            status = 0
        results.append((status, (time.perf_counter() - t0) * 1000))
        await asyncio.sleep(random.uniform(0.01, 0.05))


async def attacker_brute(client, deadline, counts):
    ident = "brutevictim" + secrets.token_hex(3)
    while time.perf_counter() < deadline:
        try:
            r = await client.post("/api/auth/login", json={"identifier": ident, "password": "x" + secrets.token_hex(2)})
            counts[r.status_code] = counts.get(r.status_code, 0) + 1
        except Exception:
            counts[0] = counts.get(0, 0) + 1
        await asyncio.sleep(0.005)


async def attacker_token_flood(client, deadline, counts):
    while time.perf_counter() < deadline:
        try:
            fake = f"{secrets.token_hex(8)}.{int(time.time()) + 999}.0.{secrets.token_hex(32)}"
            r1 = await client.get("/api/auth/me", headers={"Authorization": f"Bearer {fake}"})
            counts[r1.status_code] = counts.get(r1.status_code, 0) + 1
            r2 = await client.get("/api/admin/stats", headers={"Authorization": f"Bearer {fake}"})
            counts[r2.status_code] = counts.get(r2.status_code, 0) + 1
        except Exception:
            counts[0] = counts.get(0, 0) + 1
        await asyncio.sleep(0.005)


async def attacker_post_flood(client, deadline, counts):
    while time.perf_counter() < deadline:
        try:
            r = await client.post("/api/task", json={"kind": "transcribe", "params": {"x": "y"}})
            counts[r.status_code] = counts.get(r.status_code, 0) + 1
        except Exception:
            counts[0] = counts.get(0, 0) + 1
        await asyncio.sleep(0.005)


async def attacker_upload_flood(client, deadline, counts):
    junk = b"MZ" + secrets.token_bytes(400)
    while time.perf_counter() < deadline:
        try:
            r = await client.post(
                "/api/heritage/upload",
                files={"file": (f"evil{secrets.token_hex(2)}.wav", junk, "audio/wav")},
                data={"title": "evil"},
            )
            counts[r.status_code] = counts.get(r.status_code, 0) + 1
        except Exception:
            counts[0] = counts.get(0, 0) + 1
        await asyncio.sleep(0.01)


async def attacker_probe_flood(client, deadline, counts):
    probes = [
        "/api/admin/users?x=1' OR 1=1 --",
        "/api/admin/storage/../../etc/passwd",
        "/api/auth/users?limit=99999999",
        "/api/heritage?q=%27%3B%20DROP%20TABLE%20users%3B--",
        "/api/music/task/../../secrets",
    ]
    while time.perf_counter() < deadline:
        for p in probes:
            try:
                r = await client.get(p)
                counts[r.status_code] = counts.get(r.status_code, 0) + 1
            except Exception:
                counts[0] = counts.get(0, 0) + 1
        await asyncio.sleep(0.01)


async def health_watcher(base, deadline, probes):
    while time.perf_counter() < deadline:
        t0 = time.perf_counter()
        try:
            async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(10.0)) as ac:
                r = await ac.get("/health")
                probes.append((r.status_code, (time.perf_counter() - t0) * 1000))
        except Exception:
            probes.append((0, (time.perf_counter() - t0) * 1000))
        await asyncio.sleep(2.0)


def summarize_legit(label, results):
    lats = []
    statuses = {}
    hard = 0
    for status, ms in results:
        statuses[status] = statuses.get(status, 0) + 1
        if status == 200:
            lats.append(ms)
        if status == 0 or status >= 500:
            hard += 1
    rps = len(results) / max(1e-9, SPAN[label])
    print(f"  {label}: {len(results)} req, {rps:.0f} req/s | 200: p50={percentile(lats, 50):.0f}ms p95={percentile(lats, 95):.0f}ms p99={percentile(lats, 99):.0f}ms | lỗi thật={hard} | mã={statuses}")
    return {"rps": rps, "p50": percentile(lats, 50), "p95": percentile(lats, 95), "hard": hard}


async def run_phase(base, vu_count, duration, tokens, under_attack):
    legit_results = []
    attack_counts = {}
    probes = []
    deadline = time.perf_counter() + duration
    limits = httpx.Limits(max_connections=max(vu_count + 60, 120), max_keepalive_connections=max(vu_count + 60, 120))
    tasks = []
    attack_tasks = []
    legit_client = httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0), limits=limits)
    atk = httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(15.0))
    try:
        tasks = [
            asyncio.create_task(legit_vu(legit_client, tokens[i % len(tokens)] if tokens else None, deadline, legit_results))
            for i in range(vu_count)
        ]
        if under_attack:
            attack_tasks = [
                asyncio.create_task(attacker_brute(atk, deadline, attack_counts)),
                asyncio.create_task(attacker_token_flood(atk, deadline, attack_counts)),
                asyncio.create_task(attacker_post_flood(atk, deadline, attack_counts)),
                asyncio.create_task(attacker_upload_flood(atk, deadline, attack_counts)),
                asyncio.create_task(attacker_probe_flood(atk, deadline, attack_counts)),
            ]
        attack_tasks.append(asyncio.create_task(health_watcher(base, deadline, probes)))
        await asyncio.gather(*(tasks + attack_tasks))
    finally:
        await legit_client.aclose()
        await atk.aclose()
    return legit_results, attack_counts, probes


SPAN = {}


async def main():
    global SPAN
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8126")
    ap.add_argument("--users", type=int, default=100)
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--levels", default="25,100,400,1000")
    ap.add_argument("--baseline-duration", type=float, default=12.0)
    ap.add_argument("--phase-duration", type=float, default=10.0)
    args = ap.parse_args()
    base = args.base

    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
        r = await ac.get("/health")
        print(f"health: {r.status_code}")

    print(f"\n== Tạo {args.users} user thật ==")
    sem = asyncio.Semaphore(args.users)

    async def reg(i):
        async with sem:
            u = f"atkload{i:04d}"
            async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(90.0)) as ac:
                rr = await ac.post("/api/auth/register", json={
                    "username": u, "email": f"{u}@gmail.com", "password": "secret123", "invite_code": args.invite,
                })
                return rr.status_code

    rs = await asyncio.gather(*[reg(i) for i in range(args.users)])
    print(f"  đăng ký: {rs.count(200)}/{len(rs)} OK")

    tokens = []
    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
        for i in range(args.users):
            u = f"atkload{i:04d}"
            rr = await ac.post("/api/auth/login", json={"identifier": u, "password": "secret123"})
            if rr.status_code == 200:
                tokens.append(rr.json()["token"])
    print(f"  token: {len(tokens)}")

    print(f"\n== BASELINE: 100 người dùng thật, KHÔNG tấn công ({args.baseline_duration}s) ==")
    SPAN["baseline"] = args.baseline_duration
    t0 = time.perf_counter()
    legit, attacks, probes = await run_phase(base, 100, args.baseline_duration, tokens, under_attack=False)
    SPAN["baseline"] = time.perf_counter() - t0
    base_metrics = summarize_legit("baseline", legit)
    ok_health = sum(1 for s, _ in probes if s == 200)
    print(f"  health trong pha: {ok_health}/{len(probes)} OK")

    print(f"\n== UNDER ATTACK: người dùng thật + 5 luồng hacker ==")
    summary = {}
    for level in [int(x) for x in args.levels.split(",")]:
        label = f"VU{level}"
        SPAN[label] = args.phase_duration
        t0 = time.perf_counter()
        legit, attacks, probes = await run_phase(base, level, args.phase_duration, tokens, under_attack=True)
        SPAN[label] = time.perf_counter() - t0
        print(f"\n--- {level} người dùng thật + tấn công ---")
        summary[level] = summarize_legit(f"{label}", legit)
        blocked = sum(v for k, v in attacks.items() if k in (400, 401, 403, 404, 405, 413, 422, 429))
        passed = sum(v for k, v in attacks.items() if k == 200)
        errors = sum(v for k, v in attacks.items() if k == 0)
        print(f"  hacker: {blocked} lần bị chặn (4xx/429), {passed} lần into 200, {errors} lỗi mạng, chi tiết={attacks}")
        ok_health = sum(1 for s, _ in probes if s == 200)
        avg_health = sum(ms for s, ms in probes if s == 200) / max(1, ok_health)
        print(f"  health trong lúc bị tấn công: {ok_health}/{len(probes)} probe OK, trung bình {avg_health:.0f}ms")

    print("\n== SO SÁNH USER THẬT (baseline vs bị tấn công) ==")
    print(f"  baseline      : {base_metrics['rps']:.0f} req/s, p50={base_metrics['p50']:.0f}ms, p95={base_metrics['p95']:.0f}ms, lỗi thật={base_metrics['hard']}")
    for level, m in summary.items():
        print(f"  {level:>4} VU + attack: {m['rps']:.0f} req/s, p50={m['p50']:.0f}ms, p95={m['p95']:.0f}ms, lỗi thật={m['hard']}")

    breaches = [m for m in summary.values() if m["hard"] > 0 and m["p95"] > 15000]
    any_attack_success = False
    if not breaches:
        print("\nKẾT LUẬN: SERVER GIỮ VỮNG — user thật được phục vụ liên tục, tấn công bị chặn hoặc xả 503 lịch sự.")
    else:
        print("\nKẾT LUẬN: CÓ ẢNH HƯỞNG NGHIÊM TRỌNG ĐẾN USER THẬT — cần xem xét thêm.")
        any_attack_success = True
    sys.exit(1 if any_attack_success else 0)


if __name__ == "__main__":
    asyncio.run(main())
