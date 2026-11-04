import argparse
import subprocess
import sys
import threading
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from atk_org_warfare import (  # noqa: E402
    Watchdog,
    integrity,
    team_bruteforce,
    team_deepsuite,
    team_injection,
    team_protocol,
    team_recon,
    team_xss,
)
from load_mega import health_ms  # noqa: E402


def team_users(base, stages, burst_seconds, out):
    results = []
    for vu in stages:
        code, verdict, _ = run_tool_quiet(
            "load_storm.py",
            ["--base", base, "--public-only", "--stages", str(vu), "--stage-seconds", str(burst_seconds),
             "--workers", "10", "--stagger", "4", "--cooldown", "0"],
            burst_seconds + 150,
        )
        results.append((vu, code))
    bad = [r for r in results if r[1] not in (0, 2)]
    flows = "->".join(str(r[0]) for r in results)
    out.append(("Team-Users (VU thay doi lien tuc)", 1 if bad else 0,
                f"song dien {flows}" + ("" if not bad else f" | LOI: {bad}")))


def run_tool_quiet(rel, args, timeout):
    import subprocess as sp
    try:
        p = sp.run(
            [sys.executable, "-I", str(TOOLS / rel)] + args,
            capture_output=True, text=True, timeout=timeout, cwd=str(TOOLS.parent),
        )
        return p.returncode, "", (p.stdout or "") + (p.stderr or "")
    except sp.TimeoutExpired:
        return 124, "TIMEOUT", ""
    except Exception as e:
        return 125, f"{type(e).__name__}", ""


TOOLS = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--server-log", default="/tmp/hue_santap/uvicorn.log")
    ap.add_argument("--invite", default="SAN-TAP-2026")
    ap.add_argument("--admin-password", default="")
    ap.add_argument("--waves", type=int, default=3)
    ap.add_argument("--wave-seconds", type=int, default=90)
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    port = base.rsplit(":", 1)[-1]
    print(f"FINAL ASSAULT — doi hacker hang dau, 5 hinh thuc cung luc, nen 10k-15k nguoi dung thay doi lien tuc")
    print(f"target {base} — {args.waves} dot x {args.wave_seconds}s")

    r = httpx.post(f"{base}/api/auth/login",
                   json={"identifier": "ghitatruongle", "password": args.admin_password}, timeout=10)
    assert r.status_code == 200, "can admin password dung"
    ADMIN_TOKEN = r.json()["token"]
    print("admin token đúc sẵn cho phe xanh")

    all_results = []
    pid = 0
    try:
        import subprocess as sp
        out = sp.run(["lsof", "-ti", f"tcp:{port}"], capture_output=True, text=True)
        pid = int(out.stdout.strip().split()[0]) if out.stdout.strip() else 0
    except Exception:
        pass
    wd = Watchdog(base, args.server_log, pid)
    wd.start()

    for wave in range(1, args.waves + 1):
        if wave > 1:
            t0 = time.time()
            subprocess.run(["/tmp/hue_santap/start-santap.sh"], capture_output=True, timeout=90)
            up = False
            while time.time() - t0 < 60:
                try:
                    if httpx.get(base + "/health", timeout=5).status_code == 200:
                        up = True
                        break
                except Exception:
                    pass
                time.sleep(1)
            print(f"\n[tao lai san tap] hoi phuc {time.time() - t0:.1f}s (khoa + counter xoa, DB giu)")
            if not up:
                all_results.append((f"Blue-Restore-dot{wave}", 1, "khong hoi phuc"))
                break

        print(f"\n===== DOT {wave}/{args.waves} — 5 hinh thuc + nen 10k-15k VU dong thoi =====")
        outs = []
        th = []
        th.append(threading.Thread(target=team_injection, args=(base, args.invite, args.admin_password, args.wave_seconds - 20, outs)))
        th.append(threading.Thread(target=team_xss, args=(base, args.invite, args.admin_password, args.wave_seconds - 20, outs)))
        th.append(threading.Thread(target=team_bruteforce, args=(base, outs)))
        th.append(threading.Thread(target=team_protocol, args=(base, outs)))
        if wave == 2:
            th.append(threading.Thread(target=team_recon, args=(base, outs)))
        if wave == 3:
            th.append(threading.Thread(target=team_deepsuite, args=(base, port, args.admin_password, outs)))
        user_stages = [
            [10000, 12000, 15000, 11000, 14000, 12500],
            [15000, 11000, 13000, 10000, 14500, 12000],
            [12500, 10000, 14000, 11500, 15000, 13500],
        ][wave - 1]
        th.append(threading.Thread(target=team_users, args=(base, user_stages, max(12, args.wave_seconds // 6), outs)))
        for t in th:
            t.start()
        for t in th:
            t.join()
        for name, code, verdict in outs:
            print(f"  [{name}] exit={code} — {verdict}")
        all_results.extend(outs)

        fails = integrity(base, args.admin_password, ADMIN_TOKEN)
        print(f"  [Blue-Integrity sau dot {wave}] " + ("toan ven" if not fails else "!!! " + "; ".join(fails)))
        if fails:
            all_results.append((f"Blue-Integrity-dot{wave}", 1, "; ".join(fails)))
        time.sleep(3)

    time.sleep(3)
    print("\n===== WATCHDOG (phe xanh) =====")
    print("  " + wd.summary())
    fails = integrity(base, args.admin_password, ADMIN_TOKEN)
    if fails:
        all_results.append(("Blue-Integrity-cuoi", 1, "; ".join(fails)))
        print("  !!! " + "; ".join(fails))
    else:
        print("  integrity cuoi: toan ven")

    print("\n===== TONG KET TO CHUC HANG DAU =====")
    bad = []
    for name, code, verdict in all_results:
        if code == 2:
            print(f"  [ BI CHAN ] {name} — phong ve dung (khong tru diem)")
            continue
        mark = "SONG/SACH" if code == 0 else "LOI"
        print(f"  [{mark:>9}] {name} — {verdict}")
        if code not in (0, 2):
            bad.append(name)
    ok = not bad
    print(f"\nVERDICT FINAL-ASSAULT: " + (
        "TO CHUC HACKER HANG DAU THAT BAI — SERVER DỰ TRONG TOAN BO TRAN (nen 10k-15k VU dong thoi)"
        if ok else f"SERVER THUONG TON: {len(bad)} loi"
    ))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
