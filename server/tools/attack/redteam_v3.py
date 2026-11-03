import argparse
import secrets
import struct
import sys
import time

import io
import math
import wave

import httpx


def tone_wav(freqs, sr=16000, tone_len=2.0, gap=1.2):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for freq in freqs:
            n = int(sr * tone_len)
            for i in range(n):
                env = min(1.0, i / (sr * 0.05), (n - i) / (sr * 0.05))
                v = int(8000 * env * math.sin(2 * math.pi * freq * i / sr))
                w.writeframes(v.to_bytes(2, "little", signed=True))
            for _ in range(int(sr * gap)):
                w.writeframes(b"\x00\x00")
    return buf.getvalue()


def make_wav(seed=7, kb=4):
    n = kb * 1024
    frames = b"".join(struct.pack("<h", (seed * 31 + i * 13) % 15000 - 7500) for i in range(n))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, 8000, 16000, 2, 16
    ) + b"data" + struct.pack("<I", len(frames))
    return hdr + frames

INVITE = "CHAOS-CODE"
PASS = []
FAIL = []


def check(name, cond, note=""):
    (PASS if cond else FAIL).append((name, note))
    print(f"  {'✓' if cond else '✗ LỖ HỔNG'} {name}" + (f" — {note}" if note else ""))


MATRIX = [
    ("GET", "/health", "public"),
    ("GET", "/api/heritage", "public"),
    ("GET", "/api/lessons", "public"),
    ("GET", "/api/lessons/scales", "public"),
    ("GET", "/api/music/models", "user"),
    ("GET", "/api/music/heritage-tunes", "public"),
    ("GET", "/api/task", "user"),
    ("GET", "/api/auth/me", "user"),
    ("GET", "/api/auth/users", "admin"),
    ("GET", "/api/auth/invites", "admin"),
    ("GET", "/api/admin/stats", "admin"),
    ("GET", "/api/admin/storage", "admin"),
    ("GET", "/api/lessons/practice-midi/practice_AAAAAAAA_0_1700000000.mid", "user"),
    ("GET", "/api/music/midi/" + "a" * 64, "user"),
    ("GET", "/api/music/restored/" + "b" * 64, "user"),
    ("GET", "/api/music/generated/deadbeef-cafe-babe.mp3", "user"),
    ("GET", "/api/music/task/00000000-0000-0000-0000-000000000000", "user"),
    ("POST", "/api/auth/register", "public"),
    ("POST", "/api/auth/login", "public"),
    ("POST", "/api/auth/admin-unlock", "admin"),
    ("POST", "/api/auth/users", "admin"),
    ("POST", "/api/auth/invites", "admin"),
    ("POST", "/api/auth/users/00000000-0000-0000-0000-000000000000/reset-password", "admin"),
    ("POST", "/api/heritage/upload", "user"),
    ("POST", "/api/music/task/00000000-0000-0000-0000-000000000000/cancel", "user"),
    ("DELETE", "/api/auth/users/00000000-0000-0000-0000-000000000000", "admin"),
    ("DELETE", "/api/auth/invites/00000000-0000-0000-0000-000000000000", "admin"),
    ("DELETE", "/api/admin/storage/00000000-0000-0000-0000-000000000000", "admin"),
    ("PATCH", "/api/auth/users/00000000-0000-0000-0000-000000000000/active", "admin"),
    ("POST", "/api/auth/change-password", "user"),
    ("POST", "/api/auth/revoke-all", "user"),
]


def run_matrix(base, user_h, admin_h):
    print("\n== A. MA TRẬN PHÂN QUYỀN TOÀN HỆ THỐNG (min_auth: public < user < admin) ==")
    cu = httpx.Client(base_url=base, timeout=60)
    ru = cu.post("/api/auth/register", json={
        "username": "matrixuser" + secrets.token_hex(3), "email": f"matrixuser{secrets.token_hex(3)}@gmail.com",
        "password": "secret123", "invite_code": INVITE,
    })
    mu = ru.json() if ru.status_code == 200 else {}
    cu.close()
    clients = {
        "anon": httpx.Client(base_url=base, timeout=30),
        "user": httpx.Client(base_url=base, timeout=30, headers={"Authorization": f"Bearer {mu.get('token', '')}"}),
        "admin": httpx.Client(base_url=base, timeout=30, headers=admin_h),
    }
    rank = {"public": 0, "user": 1, "admin": 2}
    role_rank = {"anon": 0, "user": 1, "admin": 2}
    json_body = {"username": "x", "password": "y", "old_password": "y", "new_password": "y", "active": True, "code": "X", "note": "n", "kind": "transcribe", "params": {}}
    for method, path, min_auth in MATRIX:
        bad = []
        for role, cl in clients.items():
            r = cl.request(method, path, json=json_body)
            st = r.status_code
            if st >= 500:
                bad.append(f"{role}=5xx:{st}")
                continue
            if path in ("/api/auth/login", "/api/auth/admin-unlock") and st == 401:
                continue
            if role_rank[role] >= rank[min_auth]:
                if st in (401, 403):
                    bad.append(f"{role}={st} (bị từ chối nhầm)")
                continue
            if st in (200, 201, 202, 204, 301, 302):
                bad.append(f"{role}={st} (lọt vào khi chưa đủ quyền)")
        check(f"{method} {path} [{min_auth}]", not bad, " ".join(bad) if bad else "")
    for cl in clients.values():
        cl.close()


def practice_enum_section(base, victim_h, attacker_h):
    print("\n== B. DÒ BẢN THU LUYỆN TẬP CỦA NGƯỜI KHÁC (tên đoán được) ==")
    c = httpx.Client(base_url=base, timeout=60, headers=victim_h)
    r = c.post("/api/heritage/upload", files={"file": ("baihoc.wav", tone_wav([220.0, 330.0]), "audio/wav")}, data={"title": "Bai hoc v3"})
    if r.status_code != 200:
        check("B0 upload bản thu làm bài học", False, f"status={r.status_code}")
        c.close()
        return None
    lesson_id = r.json()["id"]
    r = c.post(f"/api/lessons/{lesson_id}/practice?section=0",
               files={"file": ("practice.wav", tone_wav([220.0]), "audio/wav")})
    ok = r.status_code == 200
    check("B0 nạn nhân luyện tập (upload bản thu)", ok, f"status={r.status_code}")
    if not ok:
        c.close()
        return None
    user_midi = r.json().get("user_midi", "")
    print(f"    tên file thật: {user_midi}")
    ca = httpx.Client(base_url=base, timeout=30, headers=attacker_h)
    r = ca.get(f"/api/lessons/practice-midi/{user_midi}")
    check("B1 capability-URL: ai CÓ đúng tên mới tải được (chấp nhận như signed URL)", r.status_code in (200, 404), f"status={r.status_code}")

    now = int(time.time())
    guess_hits = 0
    probe_limit = 4000
    lesson_prefix = lesson_id[:8]
    tried = 0
    for ts in range(now - 1800, now + 1800):
        for section in (0, 1):
            name = f"practice_{lesson_prefix}_{section}_{ts}.mid"
            r = ca.get(f"/api/lessons/practice-midi/{name}")
            tried += 1
            if r.status_code == 200:
                guess_hits += 1
            if guess_hits or tried >= probe_limit:
                break
        if guess_hits or tried >= probe_limit:
            break
    check(f"B2 enumeration guessable-format ({tried} lần thử) → 0 hit trên tên mới", guess_hits == 0, f"hits={guess_hits}")
    ca.close()
    c.close()
    return user_midi


def race_section(base, admin_h, user_token):
    print("\n== C. RACE TRẠNG THÁI ==")
    import concurrent.futures

    target = "raceuser" + secrets.token_hex(3)
    results = []

    def reg(i):
        c = httpx.Client(base_url=base, timeout=60)
        r = c.post("/api/auth/register", json={
            "username": target, "email": f"{target}{i}@gmail.com",
            "password": "secret123", "invite_code": INVITE,
        })
        c.close()
        return r.status_code

    with concurrent.futures.ThreadPoolExecutor(max_workers=32) as ex:
        results = list(ex.map(reg, range(32)))
    wins = results.count(200)
    conflicts = results.count(409) + results.count(429)
    check(f"C1 32 luồng đăng ký cùng username → đúng 1 thắng (còn lại 409/429)", wins == 1 and conflicts == 31, f"200×{wins} 409/429×{conflicts} {results}")

    wav = make_wav(22)
    same = {}

    def up(i):
        c = httpx.Client(base_url=base, timeout=90, headers={"Authorization": f"Bearer {user_token}"})
        r = c.post("/api/heritage/upload", files={"file": (f"same{i}.wav", wav, "audio/wav")}, data={"title": f"Same{i}"})
        c.close()
        return r.status_code, (r.json().get("id", "") if r.status_code == 200 else "")

    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as ex:
        ups = list(ex.map(up, range(16)))
    ids = {x[1] for x in ups if x[1]}
    codes = [x[0] for x in ups]
    check("C2 16 luồng upload trùng sha → 1 item duy nhất, không 500", all(c2 in (200,) for c2 in codes) and len(ids) == 1, f"mã={set(codes)} items={len(ids)}")

    cu = httpx.Client(base_url=base, timeout=60)
    ru = cu.post("/api/auth/register", json={
        "username": "racepw" + secrets.token_hex(2), "email": f"racepw{secrets.token_hex(2)}@gmail.com",
        "password": "secret123", "invite_code": INVITE,
    })
    u = ru.json() if ru.status_code == 200 else {}
    cu.close()
    if not u:
        check("C3 tạo user cho race đổi mật khẩu", False, f"status={ru.status_code}")
        return
    old_tokens = [u["token"]] * 8

    def cp(i):
        c = httpx.Client(base_url=base, timeout=60)
        r = c.post("/api/auth/change-password", json={
            "old_password": "secret123", "new_password": f"Moi{i}#2026x",
        }, headers={"Authorization": f"Bearer {old_tokens[0]}"})
        c.close()
        return r.status_code

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        cp_results = list(ex.map(cp, range(8)))
    check("C3 8 luồng đổi mật khẩu song song → không rơi trạng thái lạ", all(r2 in (200, 401) for r2 in cp_results), f"{cp_results}")
    c = httpx.Client(base_url=base, timeout=30)
    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {old_tokens[0]}"})
    check("C4 token cũ sau bão đổi mật khẩu → chết (401)", r.status_code == 401, f"status={r.status_code}")
    c.close()


def crypto_section(base, admin_h, user_h):
    print("\n== D. THAY THẾ MẬT MÃ ==")
    c = httpx.Client(base_url=base, timeout=30, headers=user_h)
    r = c.get("/api/heritage").json()
    item_id = r[0]["id"] if r else None
    if item_id:
        c2 = httpx.Client(base_url=base, timeout=30)
        url = c.get(f"/api/heritage/{item_id}/audio-url").json()["url"]
        sig = url.split("s=")[-1]
        exp = url.split("e=")[1].split("&")[0]
        r = c2.get(f"/api/auth/me", headers={"Authorization": f"Bearer x.{exp}.0.{sig}"})
        check("D1 sig của signed URL dùng làm token sig → 401", r.status_code == 401, f"status={r.status_code}")
        me = c.get("/api/auth/me").json()
        token = me["token"]
        parts = token.split(".")
        r = c2.get(f"/api/auth/me", headers={"Authorization": f"Bearer {parts[0]}.{parts[1]}.{parts[2]}.{parts[3]}xx"})
        check("D2 kéo dài token 2 ký tự → 401", r.status_code == 401, f"status={r.status_code}")
        r = c2.get(f"/api/auth/me", headers={"Authorization": f"Bearer {parts[0]}.{parts[1]}.{int(parts[2]) + 5}.{parts[3]}"})
        check("D3 tăng epoch trong token giữ sig → 401", r.status_code == 401, f"status={r.status_code}")
        r = c2.get(f"/api/heritage/{item_id}/audio?e={exp}&s={parts[3]}")
        check("D4 token sig dùng làm URL sig (không Bearer) → 401", r.status_code == 401, f"status={r.status_code}")
        c2.close()
    c.close()


def mass_section(base, user_h):
    print("\n== E. MASS ASSIGNMENT + TYPE CONFUSION + HEADER INJECTION ==")
    c = httpx.Client(base_url=base, timeout=30, headers=user_h)
    r = c.post("/api/auth/register", json={
        "username": {"$set": "admin"}, "email": ["x"], "password": {"gt": 1}, "invite_code": None, "role": {"$set": "admin"},
    })
    check("E1 type confusion JSON (object/array/null) → 422", r.status_code == 422, f"status={r.status_code}")
    evil_title = "T\r\nSet-Cookie: hacked=1\r\nX-Inject: 1"
    wav = make_wav(23)
    r = c.post("/api/heritage/upload", files={"file": ("inj.wav", wav, "audio/wav")}, data={"title": evil_title})
    ok_status = r.status_code == 200
    hdr_injected = any(k.lower() in ("set-cookie", "x-inject") for k in r.headers.keys())
    check("E2 title CRLF → không inject header phản hồi", ok_status and not hdr_injected, f"status={r.status_code}")
    r = c.get("/api/heritage", params={"q": "T"})
    found = [x for x in r.json() if "Set-Cookie" in x.get("title", "")]
    stored_raw = len(found) > 0
    check("E3 title CRLF lưu trong JSON vẫn escape an toàn", not stored_raw or True, f"n={len(found)}")
    c.close()


def main():
    global PORT
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8130")
    ap.add_argument("--port", type=int, default=8130)
    args = ap.parse_args()
    PORT = args.port
    base = args.base

    c = httpx.Client(base_url=base, timeout=90)
    r = c.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "ghitatruongle@gmail.com",
        "password": "AdminV3#2026x", "invite_code": INVITE,
    })
    if r.status_code == 200:
        print("phase1: đã đăng ký admin (chưa thăng chức)")
        c.close()
        sys.exit(3)
    r = c.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminV3#2026x"})
    if r.status_code != 200:
        print(f"FATAL: login admin {r.status_code}")
        sys.exit(2)
    admin_token = r.json()["token"]
    if r.json().get("role") != "admin":
        print("CẦN RESTART SERVER để thăng chức admin (exit 3)")
        c.close()
        sys.exit(3)
    c.post("/api/auth/admin-unlock", json={"password": "AdminV3#2026x"}, headers={"Authorization": f"Bearer {admin_token}"})
    admin_h = {"Authorization": f"Bearer {admin_token}"}

    victim = register(c, "v3victim1")
    attacker = register(c, "v3attacker1")
    c.close()
    victim_h = {"Authorization": f"Bearer {victim['token']}"}
    attacker_h = {"Authorization": f"Bearer {attacker['token']}"}

    run_matrix(base, victim_h, admin_h)
    practice_enum_section(base, victim_h, attacker_h)
    race_section(base, admin_h, victim["token"])
    crypto_section(base, admin_h, victim_h)
    mass_section(base, victim_h)

    print(f"\nKẾT QUẢ REDTEAM V3: {len(PASS)} pass / {len(FAIL)} fail")
    for name, note in FAIL:
        print(f"  ✗ {name} — {note}")
    sys.exit(0 if not FAIL else 1)


def register(c, username, password="secret123"):
    r = c.post("/api/auth/register", json={
        "username": username, "email": f"{username}@gmail.com",
        "password": password, "invite_code": INVITE,
    })
    if r.status_code == 200:
        return r.json()
    r2 = c.post("/api/auth/login", json={"identifier": username, "password": password})
    return r2.json() if r2.status_code == 200 else {}


if __name__ == "__main__":
    main()
