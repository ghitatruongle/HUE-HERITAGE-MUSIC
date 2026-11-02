import argparse
import asyncio
import random
import secrets
import time

import httpx

PHASES = [1, 5, 10, 25, 50, 100, 200, 400, 700, 1000]
READ_ROUTES = [
    ("/health", 0.10),
    ("/api/heritage", 0.25),
    ("/api/lessons", 0.20),
    ("/api/music/models", 0.15),
    ("/api/task", 0.15),
    ("/api/auth/me", 0.15),
]
TOKEN_ROUTES = {"/api/auth/me", "/api/task"}


def percentile(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    idx = min(len(s) - 1, max(0, int(round(p / 100 * (len(s) - 1)))))
    return s[idx]


async def vu(client, token, deadline, results):
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


async def run_phase(n, base, duration, tokens):
    results = []
    limits = httpx.Limits(max_connections=max(n + 20, 50), max_keepalive_connections=max(n + 20, 50))
    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0), limits=limits) as ac:
        deadline = time.perf_counter() + duration
        tasks = [
            asyncio.create_task(vu(ac, tokens[i % len(tokens)] if tokens else None, deadline, results))
            for i in range(n)
        ]
        await asyncio.gather(*tasks)
    statuses = {}
    lats = []
    hard_errors = 0
    for status, ms in results:
        statuses[status] = statuses.get(status, 0) + 1
        if status == 200:
            lats.append(ms)
        if status == 0 or status >= 500:
            hard_errors += 1
    total = len(results)
    ok = len(lats)
    t0 = time.perf_counter()
    health_ms = -1.0
    try:
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0)) as ac:
            await ac.get("/health")
        health_ms = (time.perf_counter() - t0) * 1000
    except Exception:
        health_ms = -1.0
    return {
        "n": n,
        "total": total,
        "ok": ok,
        "statuses": statuses,
        "p50": percentile(lats, 50),
        "p95": percentile(lats, 95),
        "p99": percentile(lats, 99),
        "max": max(lats) if lats else 0.0,
        "rps": total / duration if duration else 0.0,
        "health_after_ms": health_ms,
        "hard_errors": hard_errors,
    }


async def burst_register(base, m, code):
    sem = asyncio.Semaphore(m)

    async def one(i):
        async with sem:
            u = f"ramp{i:04d}"
            async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
                t0 = time.perf_counter()
                try:
                    r = await ac.post("/api/auth/register", json={
                        "username": u,
                        "email": f"{u}@gmail.com",
                        "password": "secret123",
                        "invite_code": code,
                    })
                    return r.status_code, (time.perf_counter() - t0) * 1000
                except Exception:
                    return 0, (time.perf_counter() - t0) * 1000

    tasks = [asyncio.create_task(one(i)) for i in range(m)]
    out = await asyncio.gather(*tasks)
    return out


async def burst_login(base, creds, m):
    sem = asyncio.Semaphore(m)

    async def one(i):
        ident, pw = creds[i % len(creds)]
        async with sem:
            async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
                t0 = time.perf_counter()
                try:
                    r = await ac.post("/api/auth/login", json={"identifier": ident, "password": pw})
                    return r.status_code, (time.perf_counter() - t0) * 1000
                except Exception:
                    return 0, (time.perf_counter() - t0) * 1000

    tasks = [asyncio.create_task(one(i)) for i in range(m)]
    out = await asyncio.gather(*tasks)
    return out


def summarize_burst(label, out):
    codes = {}
    lats = []
    for status, ms in out:
        codes[status] = codes.get(status, 0) + 1
        if status == 200:
            lats.append(ms)
    print(f"  {label}: mã={codes}")
    print(f"    200: p50={percentile(lats, 50):.0f}ms p95={percentile(lats, 95):.0f}ms p99={percentile(lats, 99):.0f}ms max={max(lats) if lats else 0:.0f}ms")
    return codes


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8125")
    ap.add_argument("--duration", type=float, default=6.0)
    ap.add_argument("--users", type=int, default=100)
    ap.add_argument("--invite", default="CHAOS-CODE")
    args = ap.parse_args()
    base = args.base

    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
        r = await ac.get("/health")
        print(f"health trước ramp: {r.status_code} {r.text[:80]}")

    print(f"\n== Tạo {args.users} user thật để có token (song song 20) ==")
    reg = await burst_register(base, args.users, args.invite)
    codes = summarize_burst(f"đăng ký {args.users} user", reg)

    print("\n== Thu token + mật khẩu cho phiên test ==")
    tokens = []
    creds = []
    async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(60.0)) as ac:
        for i in range(min(args.users, 100)):
            u = f"ramp{i:04d}"
            r = await ac.post("/api/auth/login", json={"identifier": u, "password": "secret123"})
            if r.status_code == 200:
                tokens.append(r.json()["token"])
                creds.append((u, "secret123"))
    print(f"  thu được {len(tokens)} token")

    print("\n== BÚT PHÁ ĐĂNG NHẬP: 100 đăng nhập song song (PBKDF2 600k) ==")
    if creds:
        out = await burst_login(base, creds, 100)
        summarize_burst("100 đăng nhập song song", out)
    else:
        print("  (không có creds — bỏ qua bút pháp đăng nhập)")

    print("\n== BÚT PHÁ ĐĂNG KÝ: 200 đăng ký song song ==")
    out = await burst_register(base, 200, args.invite)
    summarize_burst("200 đăng ký song song (tên mới)", out)

    print("\n== RAMP 1 → 1000 NGƯỜI DÙNG CÙNG LÚC (đọc/xem, nghĩ 10-50ms) ==")
    print(f"{'VU':>5} | {'req':>7} | {'req/s':>6} | {'p50(ms)':>8} | {'p95(ms)':>8} | {'p99(ms)':>8} | {'max':>7} | lỗi | health-sau")
    for n in PHASES:
        row = await run_phase(n, base, args.duration, tokens)
        others = {k: v for k, v in row["statuses"].items() if k not in (200, 401)}
        print(
            f"{row['n']:>5} | {row['total']:>7} | {row['rps']:>6.0f} | {row['p50']:>8.0f} | {row['p95']:>8.0f} | {row['p99']:>8.0f} | {row['max']:>7.0f} | {row['hard_errors']:>3} | {row['health_after_ms']:.0f}ms  khác={others}"
        )

    try:
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(30.0)) as ac:
            r = await ac.get("/health")
            print(f"\nhealth sau ramp: {r.status_code} {r.text[:80]}")
    except Exception as e:
        print(f"\nhealth sau ramp: LỖI {e}")


if __name__ == "__main__":
    asyncio.run(main())
