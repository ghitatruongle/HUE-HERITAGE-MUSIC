import argparse
import asyncio
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from load_mega import ensure_tokens, health_ms, run_phase, print_row

LOGDIR = Path("/tmp/hue_storm_alpha2")
UVICORN = Path(sys.prefix) / "bin" / "uvicorn"


def server_rss(pid):
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return int(out) / 1024 if out else -1.0
    except Exception:
        return -1.0


def spawn_server(envdir, config):
    envdir.mkdir(parents=True, exist_ok=True)
    env = {
        **__import__("os").environ,
        "DATABASE_URL": f"sqlite:///{envdir}/sweep.db",
        "STORAGE_DIR": f"{envdir}/storage",
        "MODELS_DIR": f"{envdir}/models",
        "HUE_SECURITY_LOG": f"{envdir}/security.log",
        "AUTH_REQUIRED": "true",
        "SECRET_KEY": __import__("hashlib").sha256(b"hue-storm-alpha2-fixed-key").hexdigest(),
        "TOKEN_TTL_HOURS": "72",
        "INVITE_CODES": "CHAOS-CODE",
        "REGISTER_IP_RATE_LIMIT": "50000",
        "AUTH_FLOOD_IP_LIMIT": "50000",
        "REGISTER_FAILURE_IP_LIMIT": "50000",
        "HEAVY_RATE_LIMIT": "100000",
        "HUE_LOAD_MIX": "alpha2",
    }
    if config == "production":
        env["SHED_CONCURRENCY"] = "400"
        cmd = [str(UVICORN), "app.main:app", "--host", "127.0.0.1", "--port", "{PORT}",
               "--no-proxy-headers", "--limit-concurrency", "512"]
    else:
        env["SHED_CONCURRENCY"] = "2500"
        cmd = [str(UVICORN), "app.main:app", "--host", "127.0.0.1", "--port", "{PORT}"]
    import secrets as _s

    port = _s.SystemRandom().randint(21000, 29000)
    cmd = [c.replace("{PORT}", str(port)) for c in cmd]
    proc = subprocess.Popen(cmd, cwd=str(Path(__file__).resolve().parents[1]), env=env,
                            stdout=open(envdir / "uvicorn.log", "ab"), stderr=subprocess.STDOUT)
    base = f"http://127.0.0.1:{port}"
    for _ in range(60):
        import httpx as _hx

        try:
            r = _hx.get(base + "/health", timeout=3)
            if r.status_code == 200:
                return proc, base
        except Exception:
            pass
        time.sleep(0.5)
    proc.kill()
    raise RuntimeError(f"server {config} không lên")


async def health_patient(base, tries=6, gap=3.0):
    ms = 0.0
    for _ in range(tries):
        code, ms = await health_ms(base)
        if code == 200:
            return True, ms
        await asyncio.sleep(gap)
    return False, ms


async def run_config(config, tokens, stage_seconds, stagger, cooldown):
    print(f"\n{'#' * 8} CẤU HÌNH SERVER: {config} {'#' * 8}")
    if config == "production":
        envdir = LOGDIR / "prod"
    else:
        shutil.rmtree(LOGDIR / "bare", ignore_errors=True)
        envdir = LOGDIR / "bare"
    proc, base = spawn_server(envdir, config)
    pid = proc.pid
    code, ms = await health_ms(base)
    print(f"health trước: {code} ({ms:.0f}ms)")
    verdicts = []
    rss_peak = 0.0
    try:
        for stage in (10000, 15000, 20000):
            print(f"\n== {config} — GIAI ĐOẠN {stage} VU, {stage_seconds:.0f}s ==")
            row = run_phase(stage, base, stage_seconds, tokens, 16, 0.3, 1.5, stagger, pid)
            print_row(row, f"{stage} VU")
            rss_peak = max(rss_peak, server_rss(pid))
            print(f"  RSS server: {server_rss(pid):.0f}MB (đỉnh {rss_peak:.0f}MB)")
            shed_ratio = (row["s503"] + row["s429"]) / max(1, row["total"]) * 100
            conn_ratio = row["conn_err"] / max(1, row["total"]) * 100
            alive, hms = await health_patient(base)
            verdict = alive and row["other5xx"] == 0
            verdicts.append((f"{config} {stage} VU", verdict))
            print(f"  shed 503/429 = {shed_ratio:.1f}% (linh động hợp lí) | conn_err = {conn_ratio:.2f}% | 5xx khác = {row['other5xx']}")
            print(f"  health sau giai đoạn: {200 if alive else 0} ({hms:.0f}ms) — {'SERVER SỐNG' if verdict else 'VI PHẠM'}")
            if not alive:
                break
            await asyncio.sleep(cooldown)
        alive, ms = await health_patient(base, tries=6, gap=3.0)
        verdicts.append((f"{config} cuối phiên", alive))
        time.sleep(3)
        print(f"RSS cuối phiên: {server_rss(pid):.0f}MB | health cuối: {200 if alive else 0} ({ms:.0f}ms)")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    uvlog = envdir / "uvicorn.log"
    tb = uvlog.read_text(errors="ignore").count("Traceback") if uvlog.exists() else 0
    verdicts.append((f"{config} log 0 Traceback", tb == 0))
    print(f"Traceback trong log {config}: {tb}")
    return verdicts


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--users", type=int, default=10000)
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--stage-seconds", type=float, default=40.0)
    ap.add_argument("--stagger", type=float, default=10.0)
    ap.add_argument("--cooldown", type=float, default=8.0)
    ap.add_argument("--configs", default="production,bare")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    stamp = time.strftime("%Y-%m-%d %H:%M")
    print(f"MEGA LOAD ALPHA2 10k→20k VU — {stamp} — configs: {args.configs}")
    LOGDIR.mkdir(parents=True, exist_ok=True)

    setup_server = None
    os_env = __import__("os").environ
    prod_dir = LOGDIR / "prod"
    first = True
    if not prod_dir.exists() or not (prod_dir / "sweep.db").exists():
        shutil.rmtree(prod_dir, ignore_errors=True)
    proc, base = spawn_server(prod_dir, "production")
    tokens = await ensure_tokens(base, args.users, args.invite)
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
    if len(tokens) < 1000:
        print(f"quá ít token ({len(tokens)}) — dừng")
        sys.exit(1)
    print(f"chuẩn bị {len(tokens)} user thật cho {args.users}+ VU chia bù")

    all_verdicts = []
    for config in [c.strip() for c in args.configs.split(",") if c.strip()]:
        vs = await run_config(config, tokens, args.stage_seconds, args.stagger, args.cooldown)
        all_verdicts.extend(vs)

    print("\n" + "=" * 60)
    ok = all(v for _, v in all_verdicts)
    for name, v in all_verdicts:
        print(f"  {'SỐNG/SẠCH' if v else 'SỤP/LỖI'} — {name}")
    print("\nVERDICT: " + ("KHÔNG SỤP — phản hồi hợp lý linh động trên mọi cấu hình" if ok else "CÓ VI PHẠM — xem log"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    asyncio.run(main())


def run_mp(n_vu, base, duration, n_workers=16, stagger=6.0, mix="read", lesson=None):
    from load_mega import run_phase
    import json as _json
    tokens = _json.load(open("/tmp/hue_mega_tokens_10000.json"))["tokens"]
    row = run_phase(n_vu, base, duration, tokens, min(n_workers, 16), 0.3, 1.5, stagger, 0, mix=mix, lesson=lesson)
    total = max(1, row["total"])
    print(f"    {n_vu} VU: {row['total']} req | 200={row['ok200']} 503={row['s503']} 5xx-khac={row['other5xx']} conn_err={row['conn_err']/total*100:.1f}% rps={row['rps']:.0f}", flush=True)
    alive = row["other5xx"] == 0 and row["ok200"] > 0
    return {"alive": alive, "rows": [row]}
