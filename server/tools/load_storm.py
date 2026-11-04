import argparse
import asyncio
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from load_mega import ensure_tokens, health_ms, print_row, run_phase

LOGDIR = Path("/tmp/hue_storm")


def server_rss(pid):
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return int(out) / 1024 if out else -1.0
    except Exception:
        return -1.0


async def health_patient(base, tries=5, gap=3.0):
    ms = 0.0
    for _ in range(tries):
        code, ms = await health_ms(base)
        if code == 200:
            return True, ms
        await asyncio.sleep(gap)
    return False, ms


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8126")
    ap.add_argument("--spawn", action="store_true", help="tu dung server co lap moi (code giong het LAN)")
    ap.add_argument("--users", type=int, default=10000, help="so token/user that cap cho VU chia bu")
    ap.add_argument("--token-file", default="")
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--stages", default="10000,14000,17000,20000")
    ap.add_argument("--stage-seconds", type=float, default=45.0)
    ap.add_argument("--stagger", type=float, default=10.0)
    ap.add_argument("--cooldown", type=float, default=8.0)
    ap.add_argument("--server-pid", type=int, default=0)
    ap.add_argument("--public-only", action="store_true", help="khong can token — chi route cong khai, chay duoc tren moi loai server")
    ap.add_argument("--setup-only", action="store_true")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    server = None
    if args.spawn:
        shutil.rmtree(LOGDIR, ignore_errors=True)
        LOGDIR.mkdir(parents=True, exist_ok=True)
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from continuous_sweep import Server

        server = Server(LOGDIR / "env")
        server.envdir.mkdir(parents=True, exist_ok=True)
        server._env.update({
            "REGISTER_IP_RATE_LIMIT": "50000",
            "AUTH_FLOOD_IP_LIMIT": "50000",
            "REGISTER_FAILURE_IP_LIMIT": "50000",
            "HEAVY_RATE_LIMIT": "100000",
        })
        server.start()
        args.base = server.base
        args.server_pid = server.proc.pid

    base = args.base
    stamp = time.strftime("%Y-%m-%d %H:%M")
    print(f"LOAD STORM RAMP {args.stages} VU — {stamp} — target {base}")
    code, ms = await health_ms(base)
    print(f"health truoc: {code} ({ms:.0f}ms)")
    if code != 200:
        print("server khong san sang")
        if server:
            server.stop()
        sys.exit(1)

    tokens = []
    if not args.public_only:
        if args.token_file:
            with open(args.token_file) as fh:
                tokens = json.load(fh)["tokens"]
            print(f"nap {len(tokens)} token tu {args.token_file}")
        else:
            tokens = await ensure_tokens(base, args.users, args.invite)
        if args.setup_only:
            if server:
                server.stop()
            return
        if len(tokens) < 100:
            print(f"qua it token ({len(tokens)}) — dung --public-only hoac --token-file")
            if server:
                server.stop()
            sys.exit(1)
        print(f"chi dinh danh: {len(tokens)} user that chia bu cho {args.stages} VU")

    rss_peak = 0.0
    verdicts = []
    for stage in [int(x) for x in args.stages.split(",")]:
        print(f"\n== GIAI DOAN {stage} VU — {args.stage_seconds:.0f}s, {args.workers} tien trinh, luot vao {args.stagger:.0f}s ==")
        row = run_phase(stage, base, args.stage_seconds, tokens, args.workers, 0.3, 1.5, args.stagger, args.server_pid)
        print_row(row, f"{stage} VU")
        if args.server_pid:
            rss_peak = max(rss_peak, server_rss(args.server_pid))
            print(f"  RSS server: {rss_peak:.0f}MB")
        no_bad_5xx = row["other5xx"] == 0
        alive, hms = await health_patient(base)
        verdict = alive and no_bad_5xx
        verdicts.append((stage, verdict))
        print(f"  health sau giai doan: {200 if alive else 0} ({hms:.0f}ms) — {'SERVER SONG, khong sup' if verdict else 'VI PHAM (5xx truot hoac health chet)'}")
        if not alive:
            break
        await asyncio.sleep(args.cooldown)

    alive, ms = await health_patient(base, tries=6, gap=3.0)
    verdicts.append(("cuoi-phien", alive))
    if server and args.server_pid:
        time.sleep(3)
        rss_final = server_rss(args.server_pid)
        print(f"RSS cuoi phien: {rss_final:.0f}MB")
    if server:
        server.stop()
    print(f"\nhealth ket thuc: {200 if alive else 0} ({ms:.0f}ms) | RSS dinh: {rss_peak:.0f}MB")
    ok = all(v for _, v in verdicts)
    print(" | ".join(f"{n}: {'SONG' if v else 'SUP/LOI'}" for n, v in verdicts))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    asyncio.run(main())
