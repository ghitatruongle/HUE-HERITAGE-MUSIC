import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server" / "tools"))

import httpx

from continuous_sweep import LOGDIR, PYTHON, Server, WORKDIR

VERIFY_DIR = LOGDIR / "verify_beta3"


def run_tool(script, args, env, timeout=1200):
    log = VERIFY_DIR / f"{script}.log"
    t0 = time.perf_counter()
    try:
        with open(log, "wb") as f:
            proc = subprocess.run(
                [str(PYTHON), "-I", str(ROOT / "server" / "tools" / script)] + args,
                cwd=WORKDIR, env=env, stdout=f, stderr=subprocess.STDOUT, timeout=timeout,
            )
        code = proc.returncode
    except subprocess.TimeoutExpired:
        code = 124
    dt = time.perf_counter() - t0
    tail = ""
    try:
        lines = log.read_text(errors="ignore").strip().splitlines()
        tail = " | ".join(lines[-6:])
    except Exception:
        pass
    return code, dt, tail, log


def rss_loop(pid, out):
    while not out.get("stop"):
        try:
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        out["rss_kb"] = max(out.get("rss_kb", 0), int(line.split()[1]))
                        break
            time.sleep(1)
        except Exception:
            try:
                cmd = ["ps", "-o", "rss=", "-p", str(pid)]
                v = subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
                if v.isdigit():
                    out["rss_kb"] = max(out.get("rss_kb", 0), int(v))
            except Exception:
                pass
            time.sleep(1)


def main():
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    global VERIFY_DIR
    VERIFY_DIR = LOGDIR / f"verify_beta3_{stamp}"
    VERIFY_DIR.mkdir(parents=True, exist_ok=True)
    print(f"VERIFY BETA3 {stamp} — smoke + DSP storm trên server cô lập")
    server = Server(VERIFY_DIR / "env")
    server.envdir.mkdir(parents=True, exist_ok=True)
    summary = []
    exit_code = 0
    try:
        server.start()
        c = httpx.Client(base_url=server.base, timeout=60)
        r = c.post("/api/auth/register", json={
            "username": "ghitatruongle", "email": "ghitatruongle@gmail.com",
            "password": "AdminCu#2026a", "invite_code": "CHAOS-CODE"})
        print(f"  register admin: {r.status_code}")
        r = c.post("/api/auth/register", json={
            "username": "userthuong1", "email": "userthuong1@gmail.com",
            "password": "secret123", "invite_code": "CHAOS-CODE"})
        print(f"  register user: {r.status_code}")
        c.close()
        server.restart()
        r = httpx.get(server.base + "/health", timeout=10)
        print(f"  health sau restart: {r.status_code} {r.json().get('version')}")

        code, dt, tail, _log = run_tool("smoke_e2e_official.py", ["--base", server.base], server.env())
        print(f"  [SMOKE] exit={code} {dt:.0f}s :: {tail}")
        summary.append(("SMOKE", code == 0))
        if code != 0:
            exit_code = 1

        rss = {"stop": False}
        if server.proc:
            th = threading.Thread(target=rss_loop, args=(server.proc.pid, rss), daemon=True)
            th.start()
        code, dt, tail, _log = run_tool(
            "load_dsp_storm_beta3.py",
            ["--base", server.base, "--users", "6", "--rounds", "2"],
            server.env(), timeout=1800)
        rss["stop"] = True
        time.sleep(1.5)
        rss_mb = rss.get("rss_kb", 0) / 1024
        print(f"  [DSP-STORM] exit={code} {dt:.0f}s server RSS peak≈{rss_mb:.0f}MB :: {tail}")
        summary.append(("DSP-STORM", code == 0))
        if code != 0:
            exit_code = 1

        code, dt, tail, _log = run_tool("stability_alpha2.py", ["--soak-seconds", "60"], server.env(), timeout=1800)
        print(f"  [STABILITY] exit={code} {dt:.0f}s :: {tail}")
        summary.append(("STABILITY", code == 0))
        if code != 0:
            exit_code = 1
    finally:
        try:
            server.stop()
        except Exception:
            pass
        if exit_code == 0:
            shutil.rmtree(VERIFY_DIR, ignore_errors=True)
        else:
            print(f"  log giữ lại để điều tra: {VERIFY_DIR}")

    print("\n== VERIFY BETA3 SUMMARY ==")
    for name, ok in summary:
        print(f"  {name}: {'XANH' if ok else 'DO'}")
    print(f"  VERDICT: {'TOAN XANH' if exit_code == 0 else 'CO DO'}")
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
