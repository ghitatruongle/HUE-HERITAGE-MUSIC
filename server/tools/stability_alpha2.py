import argparse
import hashlib
import io
import math
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
LOGDIR = Path("/tmp/hue_stability_alpha2")

PASS = []
FAIL = []


def check(name, cond, note=""):
    (PASS if cond else FAIL).append(name)
    print(f"  {'OK' if cond else '!!'} {name}" + (f" — {note}" if note else ""))


def tone_wav(freqs, sr=16000, tone_len=2.0, gap=1.2, pad_to=0):
    out = bytearray()
    for f in freqs:
        n = int(sr * tone_len)
        phase = 0.0
        for i in range(n):
            env = min(1.0, i / (sr * 0.05), (n - i) / (sr * 0.05))
            phase += 2 * math.pi * f / sr
            out += struct_pack(int(8000 * env * math.sin(phase)))
        out += b"\x00\x00" * (int(sr * gap) )
    data = bytes(out)
    if pad_to and len(data) < pad_to:
        data = data + b"\x00" * (pad_to - len(data))
    hdr = b"RIFF" + _u32(36 + len(data)) + b"WAVEfmt " + _u32(16) + _u16(1) + _u16(1) + _u32(sr) + _u32(sr * 2) + _u16(2) + _u16(16) + b"data" + _u32(len(data))
    return hdr + data


def struct_pack(v):
    import struct

    return struct.pack("<h", max(-32767, min(32767, v)))


def _u32(v):
    import struct

    return struct.pack("<I", v)


def _u16(v):
    import struct

    return struct.pack("<H", v)


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
            p95 = f" p50={s[len(s) // 2] * 1000:.0f}ms p95={s[min(len(s) - 1, int(len(s) * 0.95))] * 1000:.0f}ms max={s[-1] * 1000:.0f}ms"
        return f"  [{self.name}] OK={self.ok} 4xx={self.err4} 5xx={self.err5} ex={self.excepted}{p95}"

    def clean(self):
        return self.err5 == 0 and self.excepted == 0


def worker_client(base):
    return httpx.Client(base_url=base, timeout=180)


def register_login(base, username, password="Stab#2026a"):
    c = httpx.Client(base_url=base, timeout=60)
    try:
        r = c.post("/api/auth/register", json={
            "username": username, "email": f"{username}@gmail.com",
            "password": password, "invite_code": "CHAOS-CODE",
        })
        if r.status_code not in (200, 409):
            return None
        r = c.post("/api/auth/login", json={"identifier": username, "password": password})
        if r.status_code != 200:
            return None
        return r.json().get("token", "")
    finally:
        c.close()


def phase_setup(base, server, admin_pass):
    print("== P0 SETUP: admin + user + bài học + mẫu nghệ nhân ==")
    admin_tok = register_login(base, "ghitatruongle", admin_pass)
    check("đăng ký/login admin", bool(admin_tok))
    user_tok = register_login(base, "stab_user1")
    check("đăng ký/login user thường", bool(user_tok))
    server.restart()
    admin_tok = register_login(base, "ghitatruongle", admin_pass)
    check("admin được thăng chức sau restart", bool(admin_tok))
    c = worker_client(base)
    ah = {"Authorization": f"Bearer {admin_tok}"}
    r = c.post("/api/auth/admin-unlock", json={"password": admin_pass}, headers=ah)
    check("admin unlock", r.status_code == 200, f"status={r.status_code}")

    lesson_wav = tone_wav([220.0, 330.0, 262.0], tone_len=2.0, gap=1.2)
    r = c.post("/api/heritage/upload", files={"file": ("stab_baihoc.wav", lesson_wav, "audio/wav")},
               data={"title": "Stab Bai Hoc A2", "type": "Ca Hue", "lyrics_with_ornaments": "Câu một\nCâu hai\nCâu ba",
                     "featured_in_creation": "true"}, headers=ah)
    check("upload bài học", r.status_code == 200, f"status={r.status_code}")
    lid = r.json()["id"]
    detail = c.get(f"/api/lessons/{lid}", headers=ah).json()
    sections = detail.get("sections", [])
    check("lesson có sections", len(sections) >= 2, f"{len(sections)} sections")
    sec = sections[0]["index"]

    sample_wav = tone_wav([220.0], tone_len=2.0, gap=0.0)
    r = c.post(f"/api/lessons/{lid}/sections/{sec}/sample.wav", files={"file": ("s.wav", sample_wav, "audio/wav")}, headers=ah)
    check("upload mẫu nghệ nhân", r.status_code == 200, f"status={r.status_code}")
    c.close()
    return admin_tok, user_tok, lid, sec, sample_wav


def phase_upload_matrix(base, admin_tok, user_tok, lid, sec):
    print("== P1 UPLOAD MATRIX học hát (5 kích thước x nhiều VU + probe trần body theo route) ==")
    m = Metrics("a2-upload")
    fails = []
    sizes = [("64k", 64 * 1024, 8), ("256k", 256 * 1024, 6), ("800k", 800 * 1024, 4),
             ("2m5", int(2.5 * 1024 * 1024), 4), ("5m", 5 * 1024 * 1024, 2)]
    for label, size, vu in sizes:
        data = tone_wav([220.0], tone_len=2.0, gap=0.0, pad_to=size)
        jobs = []
        use_admin_only = True

        def one(args):
            idx, tok = args
            try:
                c = worker_client(base)
                t0 = time.time()
                r = c.post(f"/api/lessons/{lid}/practice?section={sec}",
                           files={"file": (f"stab_{label}_{idx}.wav", data, "audio/wav")},
                           headers={"Authorization": f"Bearer {tok}"})
                el = time.time() - t0
                c.close()
                return r, el
            except Exception as e:
                return None, f"{type(e).__name__}"

        for i in range(vu):
            jobs.append((i, admin_tok))
        with ThreadPoolExecutor(max_workers=vu) as ex:
            for r, el in ex.map(one, jobs):
                if isinstance(el, str):
                    m.excepted += 1
                    fails.append(f"practice {label} exception {el}")
                    continue
                m.add(r.status_code if r is not None else 0, el)
                if r is None or r.status_code != 200:
                    fails.append(f"practice {label} -> {getattr(r, 'status_code', '?')}")
                else:
                    j = r.json()
                    notes = j.get("notes") or []
                    if notes and "verdict_code" not in notes[0]:
                        fails.append(f"practice {label} thiếu verdict_code")

    final_sample = None
    for label, size in [("s100k", 100 * 1024), ("s1m", 1024 * 1024), ("s3m", 3 * 1024 * 1024)]:
        data = tone_wav([262.0], tone_len=2.0, gap=0.0, pad_to=size)
        c = worker_client(base)
        t0 = time.time()
        r = c.post(f"/api/lessons/{lid}/sections/{sec}/sample.wav",
                   files={"file": (f"stab_{label}.wav", data, "audio/wav")},
                   headers={"Authorization": f"Bearer {admin_tok}"})
        m.add(r.status_code, time.time() - t0)
        c.close()
        if r.status_code != 200:
            fails.append(f"sample upload {label} -> {r.status_code}")
        else:
            final_sample = (data, hashlib.sha256(data).hexdigest(), len(data))
    print(m.line())

    c = worker_client(base)
    probes = []
    probes.append(("practice 16MB -> 413", f"/api/lessons/{lid}/practice?section={sec}", tone_wav([220.0], tone_len=2.0, gap=0.0, pad_to=16 * 1024 * 1024 + 1024), 413))
    probes.append(("unlock 2m5 -> 413 (trần mặc định 2MB)", "/api/auth/admin-unlock", b"x" * (int(2.5 * 1024 * 1024)), 413))
    probes.append(("practice rỗng -> 400", f"/api/lessons/{lid}/practice?section={sec}", b"", 400))
    for label, path, data, expect in probes:
        t0 = time.time()
        if path.endswith("admin-unlock"):
            r = c.post(path, json={"password": "x" * 100}, headers={"Authorization": f"Bearer {admin_tok}", "content-type": "application/json"}) if False else c.post(path, content=data, headers={"Authorization": f"Bearer {admin_tok}", "content-type": "application/json"})
        else:
            r = c.post(path, files={"file": ("p.bin", data, "audio/wav")}, headers={"Authorization": f"Bearer {admin_tok}"})
        m.add(r.status_code, time.time() - t0)
        check(label, r.status_code == expect, f"thực tế {r.status_code}")
    c.close()
    return m, fails, final_sample


def phase_link_storm(base, admin_tok, user_tok, lid, sec, sample_wav):
    print("== P2 LINK STORM (play-url audio + sample -> tải sha256 khớp; điều kiện bearer/ẩn danh/không ký) ==")
    m = Metrics("a2-link")
    fails = []
    sha_sample = hashlib.sha256(sample_wav).hexdigest()
    sample_path = f"/api/lessons/{lid}/sections/{sec}/sample.wav"
    audio_path = f"/api/heritage/{lid}/audio"
    c0 = worker_client(base)
    r = c0.get("/api/music/play-url", params={"path": audio_path}, headers={"Authorization": f"Bearer {admin_tok}"})
    check("play-url audio (admin)", r.status_code == 200, f"status={r.status_code}")
    signed_audio = r.json().get("url", "")
    r = c0.get("/api/music/play-url", params={"path": sample_path}, headers={"Authorization": f"Bearer {admin_tok}"})
    check("play-url sample", r.status_code == 200, f"status={r.status_code}")
    signed_sample = r.json().get("url", "")

    r = c0.get(sample_path)
    check("GET sample không ký không bearer -> 401", r.status_code == 401, f"thực tế {r.status_code}")
    r = c0.get(signed_sample)
    ok_bytes = r.status_code == 200 and hashlib.sha256(r.content).hexdigest() == sha_sample and len(r.content) == len(sample_wav)
    check("GET sample bằng URL ký -> nguyên vẹn sha256", ok_bytes, f"status={r.status_code} bytes={len(r.content)}")
    r = c0.get(audio_path)
    check("GET audio không ký -> 401", r.status_code == 401, f"thực tế {r.status_code}")
    r = c0.get(signed_audio)
    check("GET audio URL ký -> 200", r.status_code == 200, f"thực tế {r.status_code}")
    c0.close()

    ops = []
    for i in range(40):
        ops.append("sample-sign")
        ops.append("audio-sign")

    def one(kind):
        try:
            c = worker_client(base)
            t0 = time.time()
            path = sample_path if kind == "sample-sign" else audio_path
            r1 = c.get("/api/music/play-url", params={"path": path}, headers={"Authorization": f"Bearer {admin_tok}"})
            if r1.status_code != 200:
                c.close()
                return r1.status_code, time.time() - t0, f"play-url {kind} -> {r1.status_code}"
            u = r1.json().get("url", "")
            r2 = c.get(u)
            el = time.time() - t0
            c.close()
            if r2.status_code != 200:
                return r2.status_code, el, f"download {kind} -> {r2.status_code}"
            if kind == "sample-sign" and hashlib.sha256(r2.content).hexdigest() != sha_sample:
                return 200, el, "sample tải về sai sha256"
            return 200, el, None
        except Exception as e:
            return 0, 0, f"exception {type(e).__name__}"

    with ThreadPoolExecutor(max_workers=20) as ex:
        for status, el, err in ex.map(one, ops):
            m.add(status, el)
            if err:
                fails.append(err)
    print(m.line())
    return m, fails


def phase_audio_pipeline(base, admin_tok, user_tok, lid, sec, sample_wav):
    print("== P3 AUDIO PIPELINE STORM (analyze-pitch + compare + luyện thang transpose + practice, 10 VU) ==")
    m = Metrics("a2-audio")
    fails = []
    user_wav = tone_wav([220.0], tone_len=2.0, gap=0.0)
    ref_wav = tone_wav([220.0, 330.0], tone_len=1.2, gap=0.3)
    scale_wav = tone_wav([261.63, 293.66, 349.23, 392.0, 440.0, 523.25], tone_len=0.9, gap=0.15)

    def op(idx):
        kind = idx % 4
        try:
            c = worker_client(base)
            tok = admin_tok if kind == 3 else user_tok
            h = {"Authorization": f"Bearer {tok}"}
            t0 = time.time()
            if kind == 0:
                r = c.post("/api/music/analyze-pitch", files={"file": ("a.wav", user_wav, "audio/wav")}, headers=h)
                ok = r.status_code == 200 and r.json().get("frames", 0) >= 0
            elif kind == 1:
                r = c.post("/api/music/compare", files={"sample": ("s.wav", ref_wav, "audio/wav"), "user": ("u.wav", user_wav, "audio/wav")}, headers=h)
                ok = r.status_code == 200 and "metrics" in r.json() and "reference_quality" in r.json()["metrics"]
            elif kind == 2:
                tr = [-2, 0, 3][idx % 3]
                r = c.post(f"/api/lessons/scales/bac/practice?transpose={tr}", files={"file": ("sc.wav", scale_wav, "audio/wav")}, headers=h)
                ok = r.status_code == 200 and r.json().get("transpose") == tr
            else:
                r = c.post(f"/api/lessons/{lid}/practice?section={sec}", files={"file": ("u.wav", user_wav, "audio/wav")}, headers=h)
                ok = r.status_code == 200 and r.json().get("reference") in ("sample", "original")
            el = time.time() - t0
            c.close()
            return (200 if ok else (r.status_code or 599)), el, (None if ok else f"audio {kind} -> {r.status_code}")
        except Exception as e:
            return 0, 0, f"audio exception {type(e).__name__}"

    rounds = 6
    with ThreadPoolExecutor(max_workers=10) as ex:
        for status, el, err in ex.map(op, range(rounds * 10)):
            m.add(status, el)
            if err:
                fails.append(err)
    print(m.line())
    return m, fails


def phase_mixed_soak(base, admin_tok, user_tok, lid, sec, seconds=120):
    print(f"== P4 MIXED SOAK {seconds}s (18 VU đọc 65% / ghi 35%, health 5s, RSS 10s) ==")
    m = Metrics("a2-soak")
    fails = []
    health_rtts = []
    rss = []
    deadline = time.time() + seconds
    stop = threading.Event()
    sample_wav_small = tone_wav([220.0], tone_len=1.0, gap=0.0)
    scale_wav = tone_wav([261.63, 293.66, 349.23, 392.0, 440.0, 523.25], tone_len=0.9, gap=0.15)

    def op(idx):
        seed = secrets.randbelow(10 ** 9)
        kind_token = seed % 20 in (6, 7, 8, 9, 15, 16)
        try:
            c = worker_client(base)
            tok = admin_tok if kind_token else user_tok
            h = {"Authorization": f"Bearer {tok}"}
            kind = seed % 20
            t0 = time.time()
            if kind < 6:
                r = c.get("/api/lessons")
                ok = r.status_code == 200
            elif kind < 10:
                r = c.get(f"/api/lessons/{lid}", headers=h)
                ok = r.status_code == 200
            elif kind < 12:
                r = c.get("/api/lessons/my-progress", headers=h)
                ok = r.status_code == 200
            elif kind < 14:
                r = c.get("/api/lessons/scales/bac/reference.wav", headers=h)
                ok = r.status_code == 200
            elif kind < 15:
                r = c.post("/api/music/analyze-pitch", files={"file": ("a.wav", sample_wav_small, "audio/wav")}, headers=h)
                ok = r.status_code == 200
            elif kind < 17:
                r = c.post(f"/api/lessons/{lid}/practice?section={sec}", files={"file": ("u.wav", sample_wav_small, "audio/wav")}, headers=h)
                ok = r.status_code == 200
            else:
                r = c.post("/api/lessons/scales/bac/practice", files={"file": ("sc.wav", scale_wav, "audio/wav")}, headers=h)
                ok = r.status_code == 200
            el = time.time() - t0
            m.add(r.status_code, el)
            c.close()
            if not ok:
                fails.append(f"soak kind {kind} -> {r.status_code}")
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
            try:
                out = subprocess.run(["ps", "-o", "rss=", "-p", str(SERVER_PID)], capture_output=True, text=True)
                if out.stdout.strip():
                    rss.append(int(out.stdout.strip()))
            except Exception:
                pass
            time.sleep(5)

    wd = threading.Thread(target=watchdog, daemon=True)
    wd.start()
    with ThreadPoolExecutor(max_workers=18) as ex:
        idx = 0
        while time.time() < deadline:
            futs = [ex.submit(op, idx + k) for k in range(18)]
            for f in futs:
                f.result()
            idx += 18
    stop.set()
    time.sleep(1)
    print(m.line())
    bad = [h for h in health_rtts if h[1] != 200 or h[0] > 5]
    if bad:
        fails.append(f"watchdog health xau {len(bad)} mẫu: {bad[:3]}")
    if rss:
        print(f"  RSS server: min={min(rss) / 1024:.0f}MB max={max(rss) / 1024:.0f}MB cuối={rss[-1] / 1024:.0f}MB ({len(rss)} mẫu)")
    print(f"  health rtt max={max(h[0] for h in health_rtts) * 1000:.0f}ms mẫu xấu={len(bad)}/{len(health_rtts)}")
    return m, fails


def phase_burst_sawtooth(base, admin_tok, user_tok, lid, sec):
    print("== P5 BURST + SAWTOOTH (burst 60 VU 10s; 5 sóng 5->50->5 VU) ==")
    m = Metrics("a2-burst")
    fails = []
    small = tone_wav([220.0], tone_len=1.0, gap=0.0)

    def op_read(idx):
        try:
            c = worker_client(base)
            r = c.get("/api/lessons")
            c.close()
            return r.status_code, 0
        except Exception:
            return 0, 0

    def op_write(idx):
        try:
            c = worker_client(base)
            h = {"Authorization": f"Bearer {admin_tok}"}
            r = c.post(f"/api/lessons/{lid}/practice?section={sec}", files={"file": ("u.wav", small, "audio/wav")}, headers=h)
            c.close()
            return r.status_code, 0
        except Exception:
            return 0, 0

    with ThreadPoolExecutor(max_workers=60) as ex:
        futs = [ex.submit(op_read if i % 5 else op_write, i) for i in range(300)]
        for f in futs:
            st, _ = f.result()
            m.add(st, 0)
    print(m.line())

    m2 = Metrics("a2-sawtooth")
    wave_fail = 0
    for wv in range(5):
        for vu in [5, 15, 30, 50, 30, 15, 5]:
            with ThreadPoolExecutor(max_workers=vu) as ex:
                futs = [ex.submit(op_read, i) for i in range(vu)]
                for f in futs:
                    st, _ = f.result()
                    m2.add(st, 0)
                    if st >= 500 or st == 0:
                        wave_fail += 1
    print(m2.line())
    if wave_fail:
        fails.append(f"sawtooth có {wave_fail} request lỗi 5xx/mất kết nối")
    return m, m2, fails


def phase_restart_resilience(base, server, admin_tok, lid, sec, sample_wav, admin_pass=""):
    print("== P6 RESTART GIỮA BÃO (đang nộp bài liên tục -> kill -9 -> hồi phục -> dữ liệu còn nguyên) ==")
    fails = []
    before_prog = 0
    c0 = worker_client(base)
    h = {"Authorization": f"Bearer {admin_tok}"}
    r = c0.get("/api/lessons/my-progress", headers=h)
    before_prog = len(r.json().get("items", []))
    c0.close()
    sha_sample = hashlib.sha256(sample_wav).hexdigest()
    small = tone_wav([220.0], tone_len=1.0, gap=0.0)
    stop = threading.Event()
    submitted = []

    def keep_submitting():
        idx = 0
        while not stop.is_set():
            try:
                c = worker_client(base)
                r = c.post(f"/api/lessons/{lid}/practice?section={sec}", files={"file": (f"rs{idx}.wav", small, "audio/wav")},
                           headers={"Authorization": f"Bearer {admin_tok}"})
                c.close()
                if r.status_code == 200:
                    submitted.append(idx)
            except Exception:
                pass
            idx += 1
            time.sleep(0.15)

    th = threading.Thread(target=keep_submitting, daemon=True)
    th.start()
    time.sleep(4)
    server.proc.kill()
    stop.set()
    time.sleep(1)
    t0 = time.time()
    server.start()
    recover_s = time.time() - t0
    print(f"  hồi phục sau kill -9: {recover_s:.1f}s")
    check("hồi phục < 20s", recover_s < 20, f"{recover_s:.1f}s")

    tok = register_login(server.base, "ghitatruongle", admin_pass)
    check("re-login sau restart", bool(tok))
    c = worker_client(server.base)
    h2 = {"Authorization": f"Bearer {tok}"}
    r = c.get("/api/lessons/my-progress", headers=h2)
    after_prog = len(r.json().get("items", []))
    check("practice_sessions còn nguyên sau restart", after_prog >= before_prog, f"trước={before_prog} sau={after_prog}")
    r = c.get(f"/api/lessons/{lid}/sections/{sec}/sample.wav", headers=h2)
    ok = r.status_code == 200 and hashlib.sha256(r.content).hexdigest() == sha_sample
    check("mẫu nghệ nhân nguyên vẹn sau restart", ok, f"status={r.status_code}")
    r = c.get("/api/lessons", headers=h2)
    check("danh sách bài học còn sau restart", r.status_code == 200 and any(x["id"] == lid for x in r.json()))
    c.close()
    return fails


SERVER_PID = 0


def main():
    global SERVER_PID
    ap = argparse.ArgumentParser()
    ap.add_argument("--soak-seconds", type=int, default=120)
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    stamp = time.strftime("%Y-%m-%d %H:%M")
    print(f"STABILITY ALPHA2 {stamp} — upload + liên kết + audio, nhiều điều kiện")
    LOGDIR.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(LOGDIR / "env", ignore_errors=True)
    sys.path.insert(0, str(TOOLS_DIR))
    from continuous_sweep import Server

    server = Server(LOGDIR / "env")
    server.envdir.mkdir(parents=True, exist_ok=True)
    server._env.update({
        "HEAVY_RATE_LIMIT": "100000",
        "ADMIN_TOKEN_TTL_HOURS": "8",
        "SHED_CONCURRENCY": "400",
    })
    server.start()
    SERVER_PID = server.proc.pid
    print(f"server cô lập: {server.base} (pid {SERVER_PID})")

    ADMIN_PASS = secrets.token_hex(12)
    admin_tok, user_tok, lid, sec, sample_wav = phase_setup(server.base, server, ADMIN_PASS)

    m1, f1, final_sample = phase_upload_matrix(server.base, admin_tok, user_tok, lid, sec)
    check("P1 upload matrix + trần body", m1.clean() and not f1, m1.line() + (f" fails={f1[:3]}" if f1 else ""))
    if final_sample:
        sample_wav = final_sample[0]

    m2, f2 = phase_link_storm(server.base, admin_tok, user_tok, lid, sec, sample_wav)
    check("P2 link storm + integrity", m2.clean() and not f2, m2.line() + (f" fails={f2[:3]}" if f2 else ""))

    m3, f3 = phase_audio_pipeline(server.base, admin_tok, user_tok, lid, sec, sample_wav)
    check("P3 audio pipeline storm", m3.clean() and not f3, m3.line() + (f" fails={f3[:3]}" if f3 else ""))

    m4, f4 = phase_mixed_soak(server.base, admin_tok, user_tok, lid, sec, args.soak_seconds)
    check("P4 mixed soak", m4.clean() and not f4, m4.line() + (f" fails={f4[:3]}" if f4 else ""))

    m5, m5b, f5 = phase_burst_sawtooth(server.base, admin_tok, user_tok, lid, sec)
    check("P5 burst + sawtooth", m5.clean() and m5b.clean() and not f5, m5.line() + (f" fails={f5[:3]}" if f5 else ""))

    f6 = phase_restart_resilience(server.base, server, admin_tok, lid, sec, sample_wav, ADMIN_PASS)
    check("P6 restart giữa bão", not f6, f"fails={f6[:3]}" if f6 else "")

    server.stop()
    uvlog = LOGDIR / "env" / "uvicorn.log"
    tb = uvlog.read_text(errors="ignore").count("Traceback") if uvlog.exists() else 0
    check("log server 0 Traceback", tb == 0, f"{tb} Traceback")

    print("\n" + "=" * 60)
    print("TỔNG KẾT STABILITY ALPHA2:")
    for name in PASS:
        print(f"  SẠCH — {name}")
    for name in FAIL:
        print(f"  LỖI  — {name}")
    sys.exit(0 if not FAIL else 1)


if __name__ == "__main__":
    main()
