import argparse
import asyncio
import json
import random
import secrets
import subprocess
import time
from multiprocessing import Process, Queue

import httpx

READ_ROUTES = [
    ("/health", 0.08),
    ("/api/heritage", 0.28),
    ("/api/heritage?q=Hu%E1%BA%BF", 0.06),
    ("/api/lessons", 0.20),
    ("/api/music/models", 0.10),
    ("/api/task", 0.10),
    ("/api/auth/me", 0.10),
    ("/api/music/heritage-tunes", 0.08),
]
TOKEN_ROUTES = {"/api/auth/me", "/api/task"}
WEIGHT_TOTAL = sum(w for _, w in READ_ROUTES)
TOKEN_FILE_TEMPLATE = "/tmp/hue_mega_tokens_{n}.json"


def weighted_pick():
    pick = random.uniform(0, WEIGHT_TOTAL)
    acc = 0.0
    for path, weight in READ_ROUTES:
        acc += weight
        if pick <= acc:
            return path
    return READ_ROUTES[-1][0]


def percentile(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    idx = min(len(s) - 1, max(0, int(round(p / 100 * (len(s) - 1)))))
    return s[idx]


def worker_main(worker_id, base, n_vu, duration, tokens, think_lo, think_hi, stagger, out_q):
    async def run():
        results = []
        limits = httpx.Limits(max_connections=max(n_vu, 50), max_keepalive_connections=max(n_vu, 50))
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(20.0), limits=limits) as ac:

            async def vu(index):
                token = tokens[index % len(tokens)] if tokens else None
                if stagger > 0:
                    await asyncio.sleep(random.uniform(0, stagger))
                deadline = time.perf_counter() + duration
                while time.perf_counter() < deadline:
                    path = weighted_pick()
                    headers = {"Authorization": f"Bearer {token}"} if (path in TOKEN_ROUTES and token) else {}
                    t0 = time.perf_counter()
                    status = 0
                    err = ""
                    try:
                        r = await ac.get(path, headers=headers)
                        status = r.status_code
                    except Exception as e:
                        status = 0
                        err = type(e).__name__
                    results.append((status, (time.perf_counter() - t0) * 1000, err))
                    await asyncio.sleep(random.uniform(think_lo, think_hi))

            await asyncio.gather(*[asyncio.create_task(vu(i)) for i in range(n_vu)])
        out_q.put((worker_id, results))

    asyncio.run(run())


def run_phase(n_vu, base, duration, tokens, workers, think_lo, think_hi, stagger, server_pid):
    per_worker = n_vu // workers
    counts = [per_worker] * workers
    for i in range(n_vu - per_worker * workers):
        counts[i] += 1
    out_q = Queue()
    t0 = time.perf_counter()
    procs = []
    for w in range(workers):
        if counts[w] <= 0:
            continue
        p = Process(target=worker_main, args=(w, base, counts[w], duration, tokens, think_lo, think_hi, stagger, out_q))
        p.start()
        procs.append(p)
    all_results = []
    for _ in procs:
        _wid, res = out_q.get()
        all_results.extend(res)
    for p in procs:
        p.join()
    wall = time.perf_counter() - t0
    statuses = {}
    lats = []
    err_types = {}
    for status, ms, err in all_results:
        statuses[status] = statuses.get(status, 0) + 1
        if status == 0 and err:
            err_types[err] = err_types.get(err, 0) + 1
        if status == 200:
            lats.append(ms)
    rss_mb = -1.0
    if server_pid:
        try:
            out = subprocess.run(
                ["ps", "-o", "rss=", "-p", str(server_pid)],
                capture_output=True, text=True, timeout=5,
            ).stdout.strip()
            rss_mb = int(out) / 1024 if out else -1.0
        except Exception:
            pass
    return {
        "n_vu": n_vu,
        "total": len(all_results),
        "ok200": statuses.get(200, 0),
        "s503": statuses.get(503, 0),
        "s429": statuses.get(429, 0),
        "other5xx": sum(v for k, v in statuses.items() if k >= 500 and k != 503),
        "conn_err": statuses.get(0, 0),
        "other": sum(v for k, v in statuses.items() if k not in (0, 200, 429, 503) and k < 500),
        "statuses": statuses,
        "p50": percentile(lats, 50),
        "p95": percentile(lats, 95),
        "p99": percentile(lats, 99),
        "max": max(lats) if lats else 0.0,
        "rps": len(all_results) / wall if wall > 0 else 0.0,
        "server_rss_mb": rss_mb,
        "err_types": err_types,
    }


async def health_ms(base):
    t0 = time.perf_counter()
    try:
        async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(15.0)) as ac:
            r = await ac.get("/health")
        return r.status_code, (time.perf_counter() - t0) * 1000
    except Exception:
        return 0, (time.perf_counter() - t0) * 1000


async def ensure_tokens(base, n, invite):
    path = TOKEN_FILE_TEMPLATE.format(n=n)
    try:
        with open(path) as fh:
            data = json.load(fh)
        if len(data.get("tokens", [])) >= n:
            print(f"  token cache còn dùng: {len(data['tokens'])} token từ {path}")
            return data["tokens"]
    except Exception:
        pass
    print(f"  đăng ký {n} user thật (song song 200, PBKDF2 600k)...")
    tokens = []
    sem = asyncio.Semaphore(200)

    async def one(i):
        async with sem:
            u = f"mega{i:05d}"
            async with httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(90.0)) as ac:
                try:
                    r = await ac.post("/api/auth/register", json={
                        "username": u, "email": f"{u}@gmail.com",
                        "password": "secret123", "invite_code": invite,
                    })
                    if r.status_code == 200:
                        return r.json().get("token")
                except Exception:
                    return None
        return None

    t0 = time.perf_counter()
    got = await asyncio.gather(*[asyncio.create_task(one(i)) for i in range(n)])
    tokens = [t for t in got if t]
    print(f"  thu được {len(tokens)}/{n} token trong {time.perf_counter() - t0:.0f}s")
    with open(path, "w") as fh:
        json.dump({"tokens": tokens}, fh)
    return tokens


def print_row(row, label):
    print(
        f"{label:>14} | {row['total']:>8} | {row['rps']:>7.0f} | {row['p50']:>7.0f} | {row['p95']:>7.0f} | "
        f"{row['p99']:>7.0f} | {row['max']:>7.0f} | 200:{row['ok200']:>6} 503:{row['s503']:>6} "
        f"429:{row['s429']:>4} 5xx-khác:{row['other5xx']:>3} chết:{row['conn_err']:>5} | RSS {row['server_rss_mb']:.0f}MB"
    )
    if row.get("err_types"):
        print(f"{'':>14}   lỗi client: {row['err_types']}")


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8126")
    ap.add_argument("--users", type=int, default=10000)
    ap.add_argument("--token-file", default="")
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--server-pid", type=int, default=0)
    ap.add_argument("--setup-only", action="store_true")
    ap.add_argument("--burst-vu", type=int, default=10000)
    ap.add_argument("--burst-duration", type=float, default=8.0)
    ap.add_argument("--browse-vus", default="2000,5000,10000")
    ap.add_argument("--browse-duration", type=float, default=8.0)
    args = ap.parse_args()
    base = args.base

    code, ms = await health_ms(base)
    print(f"health trước: {code} ({ms:.0f}ms)")

    if args.token_file:
        with open(args.token_file) as fh:
            tokens = json.load(fh)["tokens"]
        print(f"  nạp {len(tokens)} token từ {args.token_file}")
    else:
        tokens = await ensure_tokens(base, args.users, args.invite)
    if args.setup_only or not tokens:
        return

    print("\n== HÌNH THÁI A: BÚT PHÁ ĐỒNG LOẠT (mọi VU nhấn cùng lúc, không stagger) ==")
    print(f"{'VU':>14} | {'req':>8} | {'req/s':>7} | {'p50':>7} | {'p95':>7} | {'p99':>7} | {'max':>7} | phân bố mã | RSS server")
    row = run_phase(args.burst_vu, base, args.burst_duration, tokens, args.workers, 0.01, 0.05, 0, args.server_pid)
    print_row(row, f"A:{args.burst_vu}")
    code, ms = await health_ms(base)
    print(f"  health sau burst: {code} ({ms:.0f}ms)")

    print("\n== HÌNH THÁI B: NGƯỜI DÙNG THẬT LƯỚT (stagger vào 6s, nghĩ 0.5-2s) ==")
    print(f"{'VU':>14} | {'req':>8} | {'req/s':>7} | {'p50':>7} | {'p95':>7} | {'p99':>7} | {'max':>7} | phân bố mã | RSS server")
    for n in [int(x) for x in args.browse_vus.split(",")]:
        row = run_phase(n, base, args.browse_duration, tokens, args.workers, 0.5, 2.0, 6.0, args.server_pid)
        print_row(row, f"B:{n}")
        code, ms = await health_ms(base)
        print(f"  health sau phase {n}: {code} ({ms:.0f}ms)")

    code, ms = await health_ms(base)
    print(f"\nhealth kết thúc: {code} ({ms:.0f}ms)")


if __name__ == "__main__":
    asyncio.run(main())
