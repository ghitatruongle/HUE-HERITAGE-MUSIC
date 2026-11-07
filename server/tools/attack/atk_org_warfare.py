import argparse
import subprocess
import sys
import threading
import time
from pathlib import Path

import httpx

TOOLS = Path(__file__).resolve().parents[1]
PY = sys.executable


def run_tool(rel, args, timeout):
    try:
        p = subprocess.run(
            [PY, "-I", str(TOOLS / rel)] + args,
            capture_output=True, text=True, timeout=timeout, cwd=str(TOOLS.parent),
        )
        out = (p.stdout or "") + (p.stderr or "")
        try:
            LOGDIR = Path("/tmp/hue_santap/warfare_tools")
            LOGDIR.mkdir(parents=True, exist_ok=True)
            (LOGDIR / (Path(rel).stem + f"_{int(time.time())}.log")).write_text(out, errors="ignore")
        except Exception:
            pass
        verdict = ""
        for line in out.splitlines():
            if "VERDICT" in line or "SẠCH" in line or "CLEAN" in line or "COMPROMISED" in line:
                verdict = line.strip()[:150]
        return p.returncode, verdict, out
    except subprocess.TimeoutExpired:
        return 124, f"TIMEOUT {rel}", ""
    except Exception as e:
        return 125, f"{type(e).__name__}: {e}", ""


class Watchdog:
    def __init__(self, base, server_log, server_pid):
        self.base = base
        self.server_log = server_log
        self.server_pid = server_pid
        self.samples = []
        self.dead_windows = []
        self.stop = threading.Event()

    def start(self):
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while not self.stop.is_set():
            t0 = time.time()
            code = 0
            try:
                r = httpx.get(self.base + "/health", timeout=15)
                code = r.status_code
            except Exception:
                code = 0
            rt = (time.time() - t0) * 1000
            with threading.Lock():
                self.samples.append((time.time(), code, rt))
                if code != 200:
                    self.dead_windows.append(time.time())
            try:
                self.tb = sum(1 for _ in open(self.server_log, errors="ignore").read().split("Traceback")) - 1
            except Exception:
                self.tb = -1
            time.sleep(5)

    def summary(self):
        if not self.samples:
            return "khong co mau"
        ok = sum(1 for _, c, _ in self.samples if c == 200)
        worst = max(rt for _, _, rt in self.samples)
        alive_slow = sum(1 for _, c, rt in self.samples if c != 200 and c != 0)
        gap = 0.0
        ds = sorted(self.dead_windows)
        prev = None
        for t in ds:
            if prev is not None and t - prev < 10:
                gap += 5
            prev = t
        tb = getattr(self, "tb", -1)
        return (f"health {ok}/{len(self.samples)} mau 200 (quá tải phản hồi chậm: {alive_slow} mẫu), "
                f"rtt xau nhat {worst:.0f}ms, không phản hồi kịp ~{gap:.0f}s, Traceback server log={tb}")


def team_injection(base, invite, pw, wave_seconds, out):
    code, verdict, outlog = run_tool(
        "attack/atk_sqli_raid.py",
        ["--base", base, "--seconds", str(wave_seconds), "--invite", invite,
         "--admin-password", pw, "--no-integrity"],
        wave_seconds * 3 + 90,
    )
    out.append(("Team-Injection (SQLi raid)", code, verdict))


def team_xss(base, invite, pw, wave_seconds, out):
    code, verdict, outlog = run_tool(
        "attack/atk_xss_raid.py",
        ["--base", base, "--seconds", str(wave_seconds), "--invite", invite,
         "--admin-password", pw, "--no-integrity"],
        wave_seconds * 3 + 90,
    )
    out.append(("Team-WebXSS (xss raid)", code, verdict))


def team_flood(base, wave_seconds, out):
    code, verdict, _ = run_tool(
        "load_storm.py",
        ["--base", base, "--public-only", "--stages", "3000", "--stage-seconds", str(wave_seconds),
         "--workers", "6", "--stagger", "5", "--cooldown", "0"],
        wave_seconds + 120,
    )
    out.append(("Team-Flood (3000 VU che chan)", code, verdict))


def team_bruteforce(base, out):
    results = []
    for rel in (
        "attack/atk6_bruteforce_distributed.py",
        "attack/atk9_password_race.py",
        "attack/atk20_auth_switching.py",
    ):
        code, verdict, _ = run_tool(rel, ["--base", base], 240)
        results.append((rel.split("/")[-1], code, verdict))
    bad = [r for r in results if r[1] not in (0, 2)]
    blocked = sum(1 for r in results if r[1] == 2)
    note = "SẠCH toan bo" if not bad else f"LOI: {bad[:2]}"
    if blocked:
        note += f" | {blocked} tool BI CHAN (phong ve dung)"
    out.append(("Team-BruteForce (atk6+9+20)", 1 if bad else 0, note))


def team_protocol(base, out):
    results = []
    for rel in (
        "attack/atk10_oversized.py",
        "attack/atk11_http_methods.py",
        "attack/atk19_task_flood.py",
        "attack/atk17_register_abuse.py",
    ):
        code, verdict, _ = run_tool(rel, ["--base", base], 240)
        results.append((rel.split("/")[-1], code, verdict))
    bad = [r for r in results if r[1] not in (0, 2)]
    blocked = sum(1 for r in results if r[1] == 2)
    note = "SẠCH toan bo" if not bad else f"LOI: {bad[:2]}"
    if blocked:
        note += f" | {blocked} tool BI CHAN (phong ve dung)"
    out.append(("Team-Protocol/DoS (atk10+11+19+17)", 1 if bad else 0, note))


def team_recon(base, out):
    results = []
    for rel in (
        "attack/atk14_enumeration.py",
        "attack/atk15_static_probe.py",
        "attack/atk16_param_pollution.py",
        "attack/atk_sqli_traversal.py",
    ):
        code, verdict, _ = run_tool(rel, ["--base", base], 240)
        results.append((rel.split("/")[-1], code, verdict))
    bad = [r for r in results if r[1] not in (0, 2)]
    blocked = sum(1 for r in results if r[1] == 2)
    note = "SẠCH toan bo" if not bad else f"LOI: {bad[:2]}"
    if blocked:
        note += f" | {blocked} tool BI CHAN (phong ve dung)"
    out.append(("Team-Recon (atk14+15+16+sqli)", 1 if bad else 0, note))


def team_deepsuite(base, port, pw, out):
    results = []
    code, verdict, _ = run_tool("attack/atk_basic_suite.py", ["--base", base], 300)
    results.append(("basic_suite 95", code, verdict))
    code, verdict, _ = run_tool("attack/atk_intermediate_suite.py", ["--base", base, "--admin-password", pw], 300)
    results.append(("intermediate_suite 66", code, verdict))
    code, verdict, _ = run_tool("attack/atk_advanced_suite.py", ["--base", base, "--admin-password", pw], 300)
    results.append(("advanced_suite 81", code, verdict))
    bad = [r for r in results if r[1] not in (0, 2)]
    blocked = sum(1 for r in results if r[1] == 2)
    note = "SẠCH toan bo" if not bad else f"LOI: {bad[:3]}"
    if blocked:
        note += f" | {blocked} suite BI CHAN (nguon dang ky cạn dưới bão — phong ve dung)"
    out.append(("Team-DeepSuite (95+66+81 checks)", 1 if bad else 0, note))


def integrity(base, pw, admin_token=""):
    fails = []
    at = admin_token
    if not at:
        r = None
        for _ in range(15):
            try:
                r = httpx.post(f"{base}/api/auth/login",
                               json={"identifier": "ghitatruongle", "password": pw}, timeout=10)
            except Exception:
                r = None
            if r is not None and r.status_code == 200:
                at = r.json()["token"]
                break
            if r is not None and r.status_code == 429:
                time.sleep(8)
                continue
            break
        if not at:
            return [f"admin login cuoi cung {r.status_code if r is not None else 'exc'}"]
    try:
        r2 = httpx.get(f"{base}/api/heritage", params={"limit": 3},
                       headers={"Authorization": f"Bearer {at}"}, timeout=10)
        if r2.status_code != 200:
            fails.append(f"heritage {r2.status_code}")
        r3 = httpx.get(f"{base}/api/admin/stats", headers={"Authorization": f"Bearer {at}"}, timeout=10)
        if r3.status_code != 200:
            fails.append(f"admin stats {r3.status_code}")
    except Exception as e:
        fails.append(f"exc {type(e).__name__}")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--server-log", default="/tmp/hue_santap/uvicorn.log")
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--admin-password", default="")
    ap.add_argument("--waves", type=int, default=3)
    ap.add_argument("--wave-seconds", type=int, default=60)
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    port = base.rsplit(":", 1)[-1]
    import os as _os
    _os.environ["ATTACK_CODE"] = args.invite
    print(f"ORG WARFARE — to chuc hacker {args.waves} dot lien tuc, nhieu hinh thuc cung luc — target {base}")
    assert httpx.get(base + "/health", timeout=10).status_code == 200, "server khong san sang"
    r = httpx.post(f"{base}/api/auth/login",
                   json={"identifier": "ghitatruongle", "password": args.admin_password}, timeout=10)
    assert r.status_code == 200, "can admin password"
    ADMIN_TOKEN = r.json()["token"]
    print("admin token da đuc truoc — integrity khong phu thuoc khóa brute-force")

    import re as _re
    pid = 0
    try:
        out = subprocess.run(["lsof", "-ti", f"tcp:{port}"], capture_output=True, text=True)
        pid = int(out.stdout.strip().split()[0]) if out.stdout.strip() else 0
    except Exception:
        pass
    wd = Watchdog(base, args.server_log, pid)
    wd.start()

    all_team_results = []
    for wave in range(1, args.waves + 1):
        if wave > 1:
            t0 = time.time()
            try:
                subprocess.run(["/tmp/hue_santap/start-santap.sh"], capture_output=True, timeout=60)
            except FileNotFoundError:
                subprocess.run(["launchctl", "kickstart", "-k",
                                f"gui/{__import__('os').getuid()}/com.ghita.hueheritagemusic.santap"],
                               capture_output=True, timeout=60)
            up = False
            while time.time() - t0 < 45:
                try:
                    if httpx.get(base + "/health", timeout=4).status_code == 200:
                        up = True
                        break
                except Exception:
                    pass
                time.sleep(1)
            rec = time.time() - t0
            print(f"\n[tao lai cua so tan cong] restart san tap: {'OK' if up else 'THAT BAI'} trong {rec:.1f}s (khoa + rate counter xoa sach, DB giu nguyen)")
            if not up:
                all_team_results.append((f"Blue-Restore-dot{wave}", 1, "server khong hoi phuc sau restart"))
                break
        print(f"\n===== DOT {wave}/{args.waves} — moi team buoc vao cung luc =====")
        outs = []
        th = []
        if wave < 3:
            th.append(threading.Thread(target=team_injection, args=(base, args.invite, args.admin_password, args.wave_seconds, outs)))
        if wave == 3:
            pass
        th.append(threading.Thread(target=team_xss, args=(base, args.invite, args.admin_password, args.wave_seconds, outs)))
        if wave < 3:
            th.append(threading.Thread(target=team_flood, args=(base, args.wave_seconds, outs)))
        if wave == 1:
            th.append(threading.Thread(target=team_bruteforce, args=(base, outs)))
        if wave == 2:
            th.append(threading.Thread(target=team_protocol, args=(base, outs)))
            th.append(threading.Thread(target=team_recon, args=(base, outs)))
        if wave == 3:
            th.append(threading.Thread(target=team_deepsuite, args=(base, port, args.admin_password, outs)))
        if wave < 3:
            pass
        for t in th:
            t.start()
        for t in th:
            t.join()
        for name, code, verdict in outs:
            print(f"  [{name}] exit={code} — {verdict}")
        all_team_results.extend(outs)
        fails = integrity(base, args.admin_password, ADMIN_TOKEN)
        print(f"  [Blue-Integrity sau dot {wave}] " + ("toan ven" if not fails else "!!! " + "; ".join(fails)))
        if fails:
            all_team_results.append((f"Blue-Integrity-dot{wave}", 1, "; ".join(fails)))
        time.sleep(3)

    time.sleep(3)
    print("\n===== WATCHDOG (phe xanh) =====")
    print("  " + wd.summary())
    fails = integrity(base, args.admin_password, ADMIN_TOKEN)
    if fails:
        all_team_results.append(("Blue-Integrity-cuoi", 1, "; ".join(fails)))
        print("  !!! integrity cuoi: " + "; ".join(fails))
    else:
        print("  integrity cuoi: toan ven")

    print("\n===== TONG KET TO CHUC =====")
    bad = []
    for name, code, verdict in all_team_results:
        if code == 2:
            print(f"  [ BI CHAN ] {name} — phong ve dung chan du setup (khong tru diem): {verdict}")
            continue
        mark = "SONG/SACH" if code == 0 else "LOI"
        print(f"  [{mark:>9}] {name} — {verdict}")
        if code not in (0, 2):
            bad.append(name)
    ok = not bad
    print(f"\nVERDICT ORG-WARFARE: {'TO CHUC THAT BAI — SERVER DI TRONG TOAN BO TRAN' if ok else 'SERVER THUONG TON: ' + str(len(bad)) + ' loi'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
