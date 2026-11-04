import argparse
import hashlib
import io
import secrets
import shutil
import subprocess
import sys
import threading
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

TOOLS_DIR = Path(__file__).resolve().parent
LOGDIR = Path("/tmp/hue_soak")

SIZES = [("64k", 64 * 1024, 40), ("1m", 1024 * 1024, 20), ("8m", 8 * 1024 * 1024, 10), ("30m", 30 * 1024 * 1024, 2)]
ROUNDS = {"64k": 3, "1m": 2, "8m": 2, "30m": 1}
USERS = {"64k": 12, "1m": 12, "8m": 6, "30m": 3}


def make_wav(size, seed):
    import numpy as np

    sr = 8000
    n = max(1600, (size - 44) // 2)
    t = (np.arange(n, dtype=np.float64) + seed * 997) / sr
    f0 = 220 + (seed % 9) * 30
    sig = (12000 * np.sin(2 * np.pi * f0 * t)).astype("<i2")
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(sig.tobytes())
    return out.getvalue()


class Metrics:
    def __init__(self, name):
        self.name = name
        self.ok = 0
        self.err4 = 0
        self.err5 = 0
        self.excepted = 0
        self.lat = []

    def add(self, status, elapsed):
        if 200 <= status < 300:
            self.ok += 1
        elif 400 <= status < 500:
            self.err4 += 1
        else:
            self.err5 += 1
        self.lat.append(elapsed)

    def line(self):
        p95 = ""
        if self.lat:
            s = sorted(self.lat)
            p95 = f" p50={s[len(s) // 2] * 1000:.0f}ms p95={s[min(len(s) - 1, int(len(s) * 0.95))] * 1000:.0f}ms"
        return (f"  {self.name}: OK={self.ok} 4xx={self.err4} 5xx={self.err5} ex={self.excepted}{p95}")

    def clean(self):
        return self.err5 == 0 and self.excepted == 0


def register_login(base, username, password="Soak#2026a"):
    c = httpx.Client(base_url=base, timeout=60)
    try:
        r = c.post("/api/auth/register", json={
            "username": username, "email": f"{username}@gmail.com",
            "password": password, "invite_code": "CHAOS-CODE",
        })
        if r.status_code == 409:
            pass
        elif r.status_code >= 300:
            return None
        r = c.post("/api/auth/login", json={"identifier": username, "password": password})
        if r.status_code != 200:
            return None
        return r.json().get("token", "")
    finally:
        c.close()


def worker_client(base):
    return httpx.Client(base_url=base, timeout=180)


def upload_one(client, token, data, name, seed):
    t0 = time.time()
    r = client.post(
        "/api/heritage/upload",
        files={"file": (name, data, "audio/wav")},
        data={"title": f"soak-{seed}", "type": "hue", "artist": "soak"},
        headers={"Authorization": f"Bearer {token}"},
    )
    elapsed = time.time() - t0
    return r, elapsed


def phase_upload_matrix(base, tokens):
    print("== P1 UPLOAD MATRIX (4 kich thuoc x nhan viec dung/sai x song song) ==")
    m = Metrics("upload")
    fails = []
    item_ids = {}
    seq = 0
    for label, size, vu in SIZES:
        rounds = ROUNDS[label]
        n_users = USERS[label]
        for rnd in range(rounds):
            jobs = []
            for i in range(n_users):
                seq += 1
                seed = (rnd * 100000) + seq
                data = make_wav(size, seed)
                jobs.append((tokens[i % len(tokens)], data, f"soak_{label}_{seed}.wav", seed))
            with ThreadPoolExecutor(max_workers=vu) as ex:
                futs = {ex.submit(upload_one, worker_client(base), tok, dat, nm, sd): (sd, len(dat),
                        hashlib.sha256(dat).hexdigest()) for tok, dat, nm, sd in jobs}
                for fut, (seed, nbytes, sha) in futs.items():
                    try:
                        r, elapsed = fut.result()
                        m.add(r.status_code, elapsed)
                        if r.status_code != 200:
                            fails.append(f"upload {label} seed {seed} -> {r.status_code}")
                        else:
                            j = r.json()
                            if not j.get("created"):
                                fails.append(f"upload {label} seed {seed} van duy khong created")
                            item_ids[seed] = {"id": j["id"], "sha": sha, "size": nbytes}
                    except Exception as e:
                        m.excepted += 1
                        fails.append(f"upload {label} seed {seed} exception {type(e).__name__}")
        dedup_seed = seq + 700000
        data = make_wav(size, dedup_seed)
        tok = tokens[0]
        try:
            r1, _ = upload_one(worker_client(base), tok, data, f"dedup_{label}.wav", dedup_seed)
            m.add(r1.status_code, 0)
            r2, _ = upload_one(worker_client(base), tok, data, f"dedup_{label}.wav", dedup_seed)
            m.add(r2.status_code, 0)
            if r1.status_code == 200 and r2.status_code == 200:
                if r2.json().get("created") or r2.json()["id"] != r1.json()["id"]:
                    fails.append(f"dedup {label} gat: lan 2 khong tro ve cung item")
                else:
                    item_ids[dedup_seed] = {"id": r1.json()["id"], "sha": hashlib.sha256(data).hexdigest(),
                                            "size": len(data)}
            elif r1.status_code != 200 or r2.status_code != 200:
                fails.append(f"dedup {label} status {r1.status_code}/{r2.status_code}")
        except Exception as e:
            m.excepted += 1
            fails.append(f"dedup {label} exception {type(e).__name__}")
        print(m.line())

    probes = []
    probes.append(("rong", b"", "empty.wav", 400))
    probes.append(("magic-sai", b"DAY LA TEXT KHONG PHAI AUDIO........", "fake.wav", 400))
    probes.append(("ext-le", b"RIIDdata", "music.txt", 400))
    big = make_wav(30 * 1024 * 1024, 990001) + b"\x00" * (55 * 1024 * 1024 - 30 * 1024 * 1024)
    probes.append(("vuot-tran-55M", big, "big.wav", 413))
    for label, data, name, expect in probes:
        try:
            c = worker_client(base)
            t0 = time.time()
            r = c.post("/api/heritage/upload",
                       files={"file": (name, data, "audio/wav")},
                       data={"title": f"probe-{label}"},
                       headers={"Authorization": f"Bearer {tokens[0]}"})
            c.close()
            m.add(r.status_code, time.time() - t0)
            if r.status_code != expect:
                fails.append(f"probe {label} -> {r.status_code}, ky vong {expect}")
        except Exception as e:
            m.excepted += 1
            fails.append(f"probe {label} exception {type(e).__name__}")
    print(m.line())
    try:
        c = worker_client(base)
        r = c.post("/api/heritage/upload",
                   files={"file": ("badbpm.wav", make_wav(64 * 1024, 990002), "audio/wav")},
                   data={"title": "badbpm", "bpm": "999"},
                   headers={"Authorization": f"Bearer {tokens[0]}"})
        c.close()
        m.add(r.status_code, 0)
        if r.status_code != 400:
            fails.append(f"probe bpm 999 -> {r.status_code}, ky vong 400")
    except Exception as e:
        m.excepted += 1
        fails.append(f"probe bpm exception {type(e).__name__}")
    print(m.line())
    return m, fails, item_ids


def phase_link_storm(base, tokens, item_ids):
    print("== P2 LINK STORM (audio-url -> URL ky -> tai xuong sha256 trung khop) ==")
    m = Metrics("link")
    fails = []
    sample = list(item_ids.items())[:60]
    if not sample:
        return m, ["khong co item de thu link"]

    def one(args):
        seed, info = args
        try:
            c = worker_client(base)
            t0 = time.time()
            r = c.get(f"/api/heritage/{info['id']}/audio-url",
                      headers={"Authorization": f"Bearer {tokens[seed % len(tokens)]}"})
            if r.status_code != 200:
                c.close()
                return r.status_code, time.time() - t0, f"url {seed} -> {r.status_code}"
            u = r.json().get("url", "")
            r2 = c.get(u)
            elapsed = time.time() - t0
            c.close()
            if r2.status_code != 200:
                return r2.status_code, elapsed, f"download {seed} -> {r2.status_code}"
            if len(r2.content) != info["size"]:
                return 200, elapsed, f"download {seed} sai kich thuoc {len(r2.content)} != {info['size']}"
            if info["sha"] and hashlib.sha256(r2.content).hexdigest() != info["sha"]:
                return 200, elapsed, f"download {seed} sai sha256"
            return 200, elapsed, None
        except Exception as e:
            return 0, 0, f"exception {type(e).__name__}"

    with ThreadPoolExecutor(max_workers=20) as ex:
        for status, elapsed, err in ex.map(one, sample * 2):
            m.add(status, elapsed)
            if err:
                fails.append(err)
    print(m.line())
    return m, fails


def phase_mixed_soak(base, tokens, stop_at, server_pid=None):
    print(f"== P3 MIXED SOAK {stop_at}s (20 VU tron upload+tai+list, health 5s, RSS 10s) ==")
    m = Metrics("soak")
    fails = []
    health_rtts = []
    rss = []
    deadline = time.time() + stop_at
    stop = threading.Event()

    def op(idx):
        seed = secrets.randbelow(10 ** 9)
        try:
            c = worker_client(base)
            kind = seed % 4
            if kind == 0:
                tok = tokens[idx % len(tokens)]
                data = make_wav(64 * 1024, seed)
                r, elapsed = upload_one(c, tok, data, f"soak_{seed}.wav", seed)
                m.add(r.status_code, elapsed)
                if r.status_code not in (200, 429):
                    fails.append(f"soak upload -> {r.status_code}")
            elif kind == 1:
                t0 = time.time()
                r = c.get("/api/heritage", params={"limit": 50, "offset": (seed % 3) * 50})
                elapsed = time.time() - t0
                m.add(r.status_code, elapsed)
                if r.status_code != 200:
                    fails.append(f"soak list -> {r.status_code}")
                else:
                    items = r.json().get("items", [])
                    if items:
                        iid = items[seed % len(items)]["id"]
                        r2 = c.get(f"/api/heritage/{iid}/audio-url",
                                   headers={"Authorization": f"Bearer {tokens[idx % len(tokens)]}"})
                        if r2.status_code == 200:
                            r3 = c.get(r2.json().get("url", ""))
                            m.add(r3.status_code, time.time() - t0)
                            if r3.status_code != 200:
                                fails.append(f"soak signed download -> {r3.status_code}")
                        else:
                            m.add(r2.status_code, 0)
                            fails.append(f"soak audio-url -> {r2.status_code}")
            elif kind == 2:
                t0 = time.time()
                r = c.get("/api/heritage", params={"q": "soak", "limit": 10})
                m.add(r.status_code, time.time() - t0)
                if r.status_code != 200:
                    fails.append(f"soak search -> {r.status_code}")
            else:
                t0 = time.time()
                r = c.get("/health")
                m.add(r.status_code, time.time() - t0)
                if r.status_code != 200:
                    fails.append(f"soak health -> {r.status_code}")
            c.close()
        except Exception as e:
            m.excepted += 1
            fails.append(f"soak exception {type(e).__name__}")

    def watchdog():
        while not stop.is_set():
            t0 = time.time()
            try:
                r = httpx.get(base + "/health", timeout=10)
                health_rtts.append((time.time() - t0, r.status_code))
            except Exception:
                health_rtts.append((time.time() - t0, 0))
            if server_pid:
                try:
                    out = subprocess.run(["ps", "-o", "rss=", "-p", str(server_pid)],
                                         capture_output=True, text=True)
                    if out.stdout.strip():
                        rss.append(int(out.stdout.strip()))
                except Exception:
                    pass
            time.sleep(5)

    wd = threading.Thread(target=watchdog, daemon=True)
    wd.start()
    with ThreadPoolExecutor(max_workers=20) as ex:
        idx = 0
        while time.time() < deadline:
            futs = [ex.submit(op, idx + k) for k in range(20)]
            for f in futs:
                f.result()
            idx += 20
    stop.set()
    time.sleep(1)
    print(m.line())
    bad_health = [h for h in health_rtts if h[1] != 200 or h[0] > 5]
    if bad_health:
        fails.append(f"watchdog health xau {len(bad_health)} mau: {bad_health[:3]}")
    if rss:
        print(f"  RSS server: min={min(rss) / 1024:.0f}MB max={max(rss) / 1024:.0f}MB cuoi={rss[-1] / 1024:.0f}MB ({len(rss)} mau)")
    print(f"  health rtt: max={max(h[0] for h in health_rtts) * 1000:.0f}ms mau loai={len(bad_health)}/{len(health_rtts)}")
    return m, fails


def phase_restart_resilience(base, tokens):
    print("== P4 RESTART RESILIENCE (kill -9 giua luc upload -> do thoi gian hoi phuc -> ton ton du lieu) ==")
    fails = []

    sys.path.insert(0, str(TOOLS_DIR))
    from continuous_sweep import Server

    server = Server(LOGDIR / "restart_server")
    server.envdir.mkdir(parents=True, exist_ok=True)
    server.start()
    base2 = server.base
    tokens2 = []
    for i in range(4):
        tok = register_login(base2, f"rs_user{i}", "Soak#2026a")
        if tok:
            tokens2.append(tok)
    if not tokens2:
        return None, ["restart phase: khong tao duoc user tren server moi"], None

    uploaded = []

    def burst(idx):
        try:
            cc = worker_client(base2)
            data = make_wav(128 * 1024, 500000 + idx)
            r = cc.post("/api/heritage/upload",
                        files={"file": (f"rs_{idx}.wav", data, "audio/wav")},
                        data={"title": f"rs-{idx}"},
                        headers={"Authorization": f"Bearer {tokens2[idx % len(tokens2)]}"})
            cc.close()
            if r.status_code == 200:
                uploaded.append({"id": r.json()["id"], "size": len(data), "sha": r.json().get("sha256", "")})
        except Exception:
            pass

    stop_flag = threading.Event()

    def keep_uploading():
        idx = 0
        while not stop_flag.is_set():
            burst(idx)
            idx += 1
            time.sleep(0.2)

    th = threading.Thread(target=keep_uploading, daemon=True)
    th.start()
    time.sleep(3)
    server.proc.kill()
    stop_flag.set()
    time.sleep(1)
    t0 = time.time()
    server.start()
    recover_s = time.time() - t0
    print(f"  hoi phuc sau kill -9 (respawn + health OK): {recover_s:.1f}s")

    tok = register_login(server.base, "rs_user0", "Soak#2026a")
    if not tok:
        fails.append("re-login sau restart that bai")
        server.stop()
        return server.base, fails, None
    cc = httpx.Client(base_url=server.base, timeout=60)
    r = cc.get("/api/heritage", params={"limit": 200})
    after_total = r.json().get("total", 0)
    ok_dl = 0
    for u in uploaded[:10]:
        r2 = cc.get(f"/api/heritage/{u['id']}/audio-url", headers={"Authorization": f"Bearer {tok}"})
        if r2.status_code == 200:
            r3 = cc.get(r2.json().get("url", ""))
            if r3.status_code == 200 and len(r3.content) == u["size"]:
                ok_dl += 1
            else:
                fails.append(f"sau restart tai file {u['id']} loi {r3.status_code}")
        else:
            fails.append(f"sau restart audio-url {u['id']} loi {r2.status_code}")
    cc.close()
    print(f"  ton ton: server moi co {after_total} item, {ok_dl}/{len(uploaded[:10])} file tai lai nguyen ven sau restart")
    if uploaded and ok_dl == 0:
        fails.append("khong tai lai duoc file nao sau restart")
    server.stop()
    return server.base, fails, None


def phase_read_only(base):
    print(f"== P5 READ-ONLY STORM tren server that {base} (30 VU, khong ghi gi) ==")
    m = Metrics("readonly")
    fails = []
    c0 = httpx.Client(base_url=base, timeout=30)
    r = c0.get("/api/heritage", params={"limit": 100})
    if r.status_code != 200:
        c0.close()
        return m, [f"lan dau list -> {r.status_code}"]
    items = r.json().get("items", [])
    ids = [i["id"] for i in items][:50]
    c0.close()

    def op(idx):
        try:
            c = httpx.Client(base_url=base, timeout=30)
            t0 = time.time()
            kind = idx % 4
            if kind == 0:
                r = c.get("/health")
            elif kind == 1:
                r = c.get("/api/heritage", params={"limit": 50, "offset": (idx * 7) % 200})
            elif kind == 2 and ids:
                r = c.get(f"/api/heritage/{ids[idx % len(ids)]}")
            else:
                r = c.get("/")
            m.add(r.status_code, time.time() - t0)
            c.close()
            if r.status_code >= 500:
                fails.append(f"read-only op {idx} -> {r.status_code}")
        except Exception as e:
            m.excepted += 1
            fails.append(f"read-only exception {type(e).__name__}")

    with ThreadPoolExecutor(max_workers=30) as ex:
        list(ex.map(op, range(600)))
    print(m.line())
    return m, fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="", help="server muc tieu cho che do read-only")
    ap.add_argument("--read-only", action="store_true", help="chi GET, khong ghi gi (danh cho server LAN that)")
    ap.add_argument("--soak-seconds", type=int, default=120)
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    stamp = time.strftime("%Y-%m-%d %H:%M")
    print(f"SOAK ON DINH SERVER {stamp}")
    results = []

    if args.read_only:
        if not args.base:
            print("--read-only can --base")
            sys.exit(2)
        m, fails = phase_read_only(args.base)
        results.append(("read-only", m.clean() and not fails))
        print(f"KET QUA read-only: {'SACH' if results[-1][1] else 'LOI'} | {m.line()}")
        for f in fails[:10]:
            print(f"  !!! {f}")
        sys.exit(0 if results[-1][1] else 1)

    LOGDIR.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(LOGDIR / "env", ignore_errors=True)
    shutil.rmtree(LOGDIR / "restart_server", ignore_errors=True)
    sys.path.insert(0, str(TOOLS_DIR))
    from continuous_sweep import Server

    server = Server(LOGDIR / "env")
    server.envdir.mkdir(parents=True, exist_ok=True)
    server._env.update({"HEAVY_RATE_LIMIT": "100000"})
    server.start()
    print(f"server co lap: {server.base}")

    tokens = []
    for i in range(12):
        tok = register_login(server.base, f"soak_user{i}")
        if tok:
            tokens.append(tok)
    if len(tokens) < 4:
        print(f"KHONG tao du user ({len(tokens)}/12)")
        server.stop()
        sys.exit(1)

    m1, fails1, item_ids = phase_upload_matrix(server.base, tokens)
    results.append(("P1 upload-matrix", m1.clean() and not fails1))
    print(f"KET QUA P1: {'SACH' if results[-1][1] else 'LOI'} | {m1.line()}")
    for f in fails1[:10]:
        print(f"  !!! {f}")

    m2, fails2 = phase_link_storm(server.base, tokens, item_ids)
    results.append(("P2 link-storm", m2.clean() and not fails2))
    print(f"KET QUA P2: {'SACH' if results[-1][1] else 'LOI'} | {m2.line()}")
    for f in fails2[:10]:
        print(f"  !!! {f}")

    m3, fails3 = phase_mixed_soak(server.base, tokens, args.soak_seconds, server_pid=server.proc.pid)
    results.append(("P3 mixed-soak", m3.clean() and not fails3))
    print(f"KET QUA P3: {'SACH' if results[-1][1] else 'LOI'} | {m3.line()}")
    for f in fails3[:10]:
        print(f"  !!! {f}")

    _, fails4, _ = phase_restart_resilience(server.base, tokens)
    results.append(("P4 restart-resilience", not fails4))
    print(f"KET QUA P4: {'SACH' if results[-1][1] else 'LOI'}")
    for f in fails4[:10]:
        print(f"  !!! {f}")

    server.stop()

    tb = 0
    uvlog = LOGDIR / "env" / "uvicorn.log"
    if uvlog.exists():
        tb = uvlog.read_text(errors="ignore").count("Traceback")
    results.append(("server-log-traceback", tb == 0))
    print(f"KET QUA log server: {'SACH' if tb == 0 else f'{tb} Traceback'}")

    ok = all(v for _, v in results)
    print("\n" + " | ".join(f"{n}: {'SACH' if v else 'LOI'}" for n, v in results))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
