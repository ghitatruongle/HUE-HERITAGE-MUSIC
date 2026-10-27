"""Mô phỏng người dùng thật: đăng ký → dùng nhiệt tình mọi tính năng → chuyển tài khoản.

Chạy độc lập: tự tạo DB/storage tạm, tự khởi uvicorn :8010 (AUTH ON), tự dọn.
Phát hiện: lỗi HTTP bất thường, chậm (mỗi bước >2s), hành vi sai.
"""
import io
import json
import math
import secrets
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[2]
VENV_PY = ROOT / ".venv-mac312" / "bin" / "python"
BASE = "http://127.0.0.1:8010"
LAG_MS = 2000.0

results = []
timings = {}


def record(user, step, ok, ms, note=""):
    results.append((user, step, ok, ms, note))
    flag = "⚡LAG" if ms > LAG_MS else ("ok" if ok else "ERR")
    print(f"  [{flag}] {step:38s} {ms:7.0f}ms  {note}", flush=True)


def tone_wav(freqs, sr=16000, seg=2.5, gap=0.4):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for f in freqs:
            n = int(sr * seg)
            for i in range(n):
                env = min(1.0, i / (sr * 0.03), (n - i) / (sr * 0.03))
                v = int(7000 * env * math.sin(2 * math.pi * f * i / sr))
                w.writeframes(v.to_bytes(2, "little", signed=True))
            for _ in range(int(sr * gap)):
                w.writeframes((0).to_bytes(2, "little", signed=True))
    return buf.getvalue()


def post(c, user, step, url, *, expect=(200,), retry_429=True, **kw):
    t0 = time.perf_counter()
    tries = 0
    while True:
        r = c.post(url, **kw)
        ms = (time.perf_counter() - t0) * 1000
        if r.status_code == 429 and retry_429 and tries < 6:
            tries += 1
            time.sleep(6)
            continue
        break
    ok = r.status_code in expect
    note = "" if ok else f"HTTP {r.status_code}: {r.text[:100]}"
    if not ok and "Rate limit" in r.text or "too many" in r.text.lower():
        note = f"HTTP 429 (vẫn bị sau retry)"
    record(user, step, ok, ms, note)
    return r, ms


def patch(c, user, step, url, *, expect=(200,), **kw):
    t0 = time.perf_counter()
    r = c.patch(url, **kw)
    ms = (time.perf_counter() - t0) * 1000
    ok = r.status_code in expect
    note = "" if ok else f"HTTP {r.status_code}: {r.text[:100]}"
    record(user, step, ok, ms, note)
    return r, ms


def get(c, user, step, url, *, expect=(200,), params=None, headers=None):
    t0 = time.perf_counter()
    r = c.get(url, params=params, headers=headers)
    ms = (time.perf_counter() - t0) * 1000
    ok = r.status_code in expect
    note = "" if ok else f"HTTP {r.status_code}: {r.text[:100]}"
    record(user, step, ok, ms, note)
    return r, ms


def journey(c, user, admin_mode=False, round_no=1):
    print(f"\n─── USER {user} — VÒNG {round_no} ───", flush=True)

    r, _ = get(c, user, "trang chủ /", "/")
    r, _ = get(c, user, "danh sách di sản", "/api/heritage", params={"limit": 50})
    items = r.json() if r.status_code == 200 else []

    r, ms = get(c, user, "mở Creation (models)", "/api/music/models")

    print(f"  -- upload 2 bài di sản (audio thật 30s) --", flush=True)
    lesson_ids = []
    for k, (f1, f2, title) in enumerate(
        [([220.0, 247.0], [262.0, 294.0], f"Bai hoc {user} v{round_no}A"), ([330.0, 392.0], [440.0, 494.0], f"Bai hoc {user} v{round_no}B")]
    ):
        wav = tone_wav(f1 + f2, seg=3.0)
        r, _ = post(c, user, f"upload di sản {k+1}", "/api/heritage/upload",
                    files={"file": (f"{title}.wav", wav, "audio/wav")},
                    data={"title": title, "type": "Ca Hue",
                          "lyrics_with_ornaments": "Câu một tình tang\nCâu hai a í a\nCâu ba hò kia",
                          "mode_system": "Nam", "featured_in_creation": "true"})
        if r.status_code == 200:
            lesson_ids.append(r.json()["id"])

    for lid in lesson_ids:
        r, ms = get(c, user, f"MỞ bài học lần đầu (build cache)", f"/api/lessons/{lid}")
        r, _ = get(c, user, "mở lại (đã cache)", f"/api/lessons/{lid}")

    for lid in lesson_ids:
        r, _ = get(c, user, "chi tiết bài học", f"/api/lessons/{lid}")
        sections = r.json().get("sections", []) if r.status_code == 200 else []
        for s in sections[:2]:
            wav = tone_wav([220.0 + s["index"] * 30], seg=2.0)
            r, _ = post(c, user, f"luyện câu {s['index']} (chấm)", f"/api/lessons/{lid}/practice",
                        params={"section": s["index"]},
                        files={"file": ("u.wav", wav, "audio/wav")})
            if r.status_code == 200 and r.json().get("user_midi"):
                mid = r.json()["user_midi"]
                r2, _ = get(c, user, "tải MIDI bản luyện", f"/api/lessons/practice-midi/{mid}")

    r, _ = get(c, user, "danh sách thang", "/api/lessons/scales")
    r, _ = get(c, user, "WAV mẫu thang", "/api/lessons/scales/bac/reference.wav")
    for i in range(2):
        r, _ = post(c, user, f"luyện thang lần {i+1}", "/api/lessons/scales/bac/practice",
                    files={"file": ("s.wav", tone_wav([261.63, 293.66, 349.23], seg=1.0, gap=0.1), "audio/wav")})

    wav = tone_wav([300.0, 350.0], seg=3.0, gap=0.2)
    r, _ = post(c, user, "ký âm (transcribe)", "/api/music/transcribe",
                files={"file": ("t.wav", wav, "audio/wav")}, data={"engine": "dsp", "bpm": "60"})
    if r.status_code == 200:
        sha = r.json().get("sha", "")
        if sha:
            r, _ = get(c, user, "tải MIDI ký âm", f"/api/music/midi/{sha}", params={"bpm": 60})
            r, _ = get(c, user, "tải MusicXML", f"/api/music/musicxml/{sha}", params={"bpm": 60})

    wav = tone_wav([250.0], seg=4.0)
    r, _ = post(c, user, "phục chế (restore)", "/api/music/restore", files={"file": ("r.wav", wav, "audio/wav")})
    if r.status_code == 200:
        sha = r.json().get("sha", "")
        if sha:
            r, _ = get(c, user, "tải bản phục chế", f"/api/music/restored/{sha}")

    r, _ = post(c, user, "phân tích nhạc cụ", "/api/music/instruments", files={"file": ("i.wav", tone_wav([400.0], seg=3.0), "audio/wav")})
    r, _ = post(c, user, "analyze-pitch", "/api/music/analyze-pitch", files={"file": ("a.wav", tone_wav([300.0], seg=5.0), "audio/wav")})
    if len(items) >= 1 and items[0].get("id"):
        wav = tone_wav([280.0], seg=3.0)
        r, _ = post(c, user, "so sánh hát (compare)", "/api/music/compare",
                    files=[("sample", ("a.wav", wav, "audio/wav")), ("user", ("b.wav", tone_wav([282.0], seg=3.0), "audio/wav"))])

    r, _ = get(c, user, "heritage-tunes", "/api/music/heritage-tunes")
    if lesson_ids:
        r, _ = post(c, user, "sinh nhạc (engine off → blocked)", "/api/music/sing-original",
                    params={"heritage_id": lesson_ids[0], "duration": 30})
        if r.status_code == 200 and r.json().get("id"):
            tid = r.json()["id"]
            r, _ = get(c, user, "xem task blocked", f"/api/music/task/{tid}")
            r, _ = post(c, user, "hủy task blocked", f"/api/music/task/{tid}/cancel")


def register_flow(c, username, code):
    print(f"\n─── ĐĂNG KÝ {username} (kèm lỗi người dùng hay mắc) ───", flush=True)
    r = c.post("/api/auth/register", json={"username": username, "email": f"{username}@yahoo.com", "password": "secret123", "invite_code": code})
    record(username, "đăng ký email không phải Gmail → chặn", r.status_code == 400, 0, f"HTTP {r.status_code}")
    r = c.post("/api/auth/register", json={"username": username, "email": f"{username}@gmail.com", "password": "123", "invite_code": code})
    record(username, "mật khẩu 3 ký tự → chặn", r.status_code == 400, 0, f"HTTP {r.status_code}")
    r = c.post("/api/auth/register", json={"username": username, "email": f"{username}@gmail.com", "password": "secret123", "invite_code": "SAI-MÃ"})
    record(username, "mã mời sai → chặn", r.status_code == 400, 0, f"HTTP {r.status_code}")
    t0 = time.perf_counter()
    r = c.post("/api/auth/register", json={"username": username, "email": f"{username}@gmail.com", "password": "secret123", "invite_code": code})
    ms = (time.perf_counter() - t0) * 1000
    record(username, "đăng ký đúng", r.status_code == 200, ms)
    reg_token = r.json().get("token", "")
    reg_id = r.json().get("id", "")
    r = c.post("/api/auth/register", json={"username": username, "email": f"x{username}@gmail.com", "password": "secret123", "invite_code": "SAI-LẠI-MÃ"})
    record(username, "đăng ký lại sau khi mã đã dùng → chặn", r.status_code == 400, 0, f"HTTP {r.status_code}")
    return {"token": reg_token, "id": reg_id}


def main():
    tmp = Path(tempfile.mkdtemp(prefix="hue_beta_e2e_"))
    env = dict(**__import__("os").environ)
    env.update({
        "DATABASE_URL": "sqlite:///" + (tmp / "db.sqlite").as_posix(),
        "STORAGE_DIR": str(tmp / "storage"),
        "MODELS_DIR": str(tmp / "models"),
        "AUTH_REQUIRED": "true",
        "SECRET_KEY": secrets.token_hex(32),
        "HUE_SECURITY_LOG": str(tmp / "security.log"),
    })
    proc = subprocess.Popen(
        [str(VENV_PY), "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8010", "--no-proxy-headers"],
        cwd=str(ROOT / "server"), env=env,
        stdout=open("/tmp/hue_logs/e2e_server.log", "w"), stderr=subprocess.STDOUT,
    )
    print("server E2E :8010 khởi động (DB tạm, AUTH ON)...", flush=True)
    time.sleep(4)

    try:
        seed = subprocess.run([str(VENV_PY), "-m", "app.database.seed_heritage"], cwd=str(ROOT / "server"), env=env,
                              capture_output=True, text=True)
        print("seed di sản mẫu:", "OK" if seed.returncode == 0 else "bỏ qua", flush=True)
        codes_seed = subprocess.run(
            [str(VENV_PY), "-c",
             "import secrets;\n"
             "from app.database.session import SessionLocal\n"
             "from app.database import crud\n"
             "db = SessionLocal()\n"
             "for i in range(4):\n"
             "    crud.create_invite_code(db, 'BETA-' + secrets.token_hex(4), 'e2e')\n"
             "db.close()\n"
             "print('codes ok')"],
            cwd=str(ROOT / "server"), env=env, capture_output=True, text=True)
        print("tạo mã mời:", codes_seed.stdout.strip() or codes_seed.stderr.strip()[-120:], flush=True)

        admin_c = httpx.Client(base_url=BASE, timeout=180.0)
        seed_codes = subprocess.run([str(VENV_PY), "-c", f"""
import sys; sys.path.insert(0, "server")
import secrets
from app.database.session import SessionLocal
from app.database import crud
db = SessionLocal()
for i in range(4):
    crud.create_invite_code(db, "BETA-" + secrets.token_hex(4), "e2e")
db.close()
print("codes ready")
"""], capture_output=True, text=True, cwd=str(ROOT))
        db = None

        import sqlite3
        dbp = tmp / "db.sqlite"
        conn = sqlite3.connect(dbp)
        codes = [r[0] for r in conn.execute("SELECT code FROM invite_codes ORDER BY created_at").fetchall()]
        conn.close()
        print(f"mã mời e2e: {len(codes)}", flush=True)

        # ADMIN TRƯỞNG là user đầu tiên — tạo qua register với mã đầu, khởi động lại để epoch đúng
        r = admin_c.post("/api/auth/register", json={"username": "ghitatruongle", "email": "admin@gmail.com", "password": "secret123", "invite_code": codes[0]})
        print("tạo admin:", r.status_code, flush=True)
        proc.terminate()
        proc.wait(timeout=10)
        proc = subprocess.Popen(
            [str(VENV_PY), "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8010", "--no-proxy-headers"],
            cwd=str(ROOT / "server"), env=env,
            stdout=open("/tmp/hue_logs/e2e_server.log", "a"), stderr=subprocess.STDOUT,
        )
        time.sleep(3)
        r = admin_c.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "secret123"})
        admin_tok = r.json()["token"] if r.status_code == 200 else ""
        print("admin login:", r.status_code, "role:", r.json().get("role"), flush=True)

        # 3 user dùng song song: A tuần tự, B và C thread
        uA, uB, uC = "ngoida", "trangvui", "minhthu"
        regA = register_flow(admin_c, uA, codes[1])
        regB = register_flow(admin_c, uB, codes[2])
        regC = register_flow(admin_c, uC, codes[3])

        tokA = admin_c.post("/api/auth/login", json={"identifier": uA, "password": "secret123"}).json()["token"]

        def run_B():
            cB = httpx.Client(base_url=BASE, timeout=180.0, headers={"Authorization": f"Bearer {regB['token']}"})
            journey(cB, uB, round_no=1)
            cB.close()

        def run_C():
            cC = httpx.Client(base_url=BASE, timeout=180.0, headers={"Authorization": f"Bearer {regC['token']}"})
            journey(cC, uC, round_no=1)
            cC.close()

        cA = httpx.Client(base_url=BASE, timeout=180.0, headers={"Authorization": f"Bearer {tokA}"})
        t0 = time.perf_counter()
        with ThreadPoolExecutor(max_workers=3) as ex:
            fB = ex.submit(run_B)
            fC = ex.submit(run_C)
            journey(cA, uA, round_no=1)
            fB.result()
            fC.result()
        print(f"\n3 user song song xong trong {time.perf_counter()-t0:.0f}s", flush=True)

        # VÒNG 2: A và B dùng tiếp (đổi tài khoản)
        print("\n─── CHUYỂN TÀI KHOẢN: A → B ───", flush=True)
        meA = admin_c.get("/api/auth/me", headers={"Authorization": f"Bearer {tokA}"}).json()
        uidA = meA["id"]
        tokB = admin_c.post("/api/auth/login", json={"identifier": uB, "password": "secret123"}).json()["token"]
        cB2 = httpx.Client(base_url=BASE, timeout=180.0, headers={"Authorization": f"Bearer {tokB}"})
        r, _ = get(cB2, uB, "B xem task của mình (cô lập)", "/api/task", params={"limit": 50})
        my_ids = {t["id"] for t in r.json()}
        r, _ = get(cA, uA, "A xem task của mình (cô lập)", "/api/task", params={"limit": 50})
        leaked = [t["id"] for t in r.json() if t.get("user_id") and t["user_id"] != uidA]
        record(uA, "không rò task của user khác", not leaked, 0, f"rò: {len(leaked)}")

        cA2 = httpx.Client(base_url=BASE, timeout=180.0, headers={"Authorization": f"Bearer {tokA}"})
        journey(cA2, uA, round_no=2)
        journey(cB2, uB, round_no=2)

        # Admin quản lý: danh sách TK + khóa
        meA2 = admin_c.get("/api/auth/me", headers={"Authorization": f"Bearer {tokA}"}).json()
        admin_c.headers["Authorization"] = f"Bearer {admin_c.post('/api/auth/login', json={'identifier': 'ghitatruongle', 'password': 'secret123'}).json()['token']}"
        r, _ = get(admin_c, "admin", "danh sách tài khoản", "/api/auth/users")
        accounts = r.json() if r.status_code == 200 else []
        target = next((a for a in accounts if a["username"] == uC), None)
        if target:
            r, _ = patch(admin_c, "admin", "khóa tài khoản C", f"/api/auth/users/{target['id']}/active", json={"active": False})
            cC3 = httpx.Client(base_url=BASE, timeout=60.0, headers={"Authorization": f"Bearer {regC['token']}"})
            r, _ = get(cC3, uC, "C token cũ sau khóa → 401/403", "/api/auth/me", expect=(401, 403))
            r, _ = patch(admin_c, "admin", "mở lại C", f"/api/auth/users/{target['id']}/active", json={"active": True})

        # Lỗi 500 bất kỳ?
        errs = [(u, s, n) for (u, s, ok, ms, n) in results if not ok and ("500" in n or "502" in n or "503" in n)]
        print(f"\n══ TỔNG KẾT ══")
        total = len(results)
        ok_n = sum(1 for r in results if r[2])
        lags = [(u, s, ms) for (u, s, ok, ms, n) in results if ms > LAG_MS]
        errs = [(u, s, n) for (u, s, ok, ms, n) in results if not ok]
        print(f"bước: {total} | ok: {ok_n} | lỗi: {len(errs)} | lag >{LAG_MS:.0f}ms: {len(lags)}")
        if lags:
            print("LAG:")
            for u, s, ms in sorted(lags, key=lambda x: -x[2])[:10]:
                print(f"  ⚡ {u}: {s} — {ms:.0f}ms")
        if errs:
            print("LỖI:")
            for u, s, n in errs[:15]:
                print(f"  ✗ {u}: {s} — {n[:90]}")
        lags_file = tmp / "lag_report.json"
        lags_file.write_text(json.dumps({"lags": lags, "errors": errs}, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"chi tiết: {lags_file}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
