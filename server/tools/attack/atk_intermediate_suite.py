"""HACKER INTERMEDIATE-SUITE — tấn công trung cấp: business logic, task lifecycle,
bypass force-change, token epoch giả, signed-URL cross-path, dedup, race nhẹ."""
import argparse
import concurrent.futures
import io
import math
import secrets
import struct
import sys
import wave
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402

INVITE = "CHAOS-CODE"


def tone_wav(freq=440.0, sr=16000, dur=0.5):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for i in range(int(sr * dur)):
            v = int(8000 * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8012")
    ap.add_argument("--admin-password", default="")
    ap.add_argument("--rounds", type=int, default=2)
    args = ap.parse_args()
    base = args.base
    attempts = 0
    breaches = []

    u1 = register_user(base)
    u2 = register_user(base)
    if not u1 or not u2:
        verdict("INTERMEDIATE-SUITE", 0, [("không đăng ký được user", "")])
        return
    c1 = client(base, u1["token"])
    c2 = client(base, u2["token"])

    print("== T1. TASK BOUNDARY (duration/strength méo) ==")
    for params in (
        {"prompt": "x", "duration": 9},
        {"prompt": "x", "duration": 301},
        {"prompt": "x", "duration": 60, "strength": 1.01},
        {"prompt": "x", "duration": 60, "strength": -0.1},
        {"prompt": "x", "duration": 60, "seed": 10**30},
    ):
        r = c1.post("/api/music/generate", params=params)
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"generate {params} → {r.status_code}", "5xx"))

    print("== T2. FOREIGN TASK ACCESS (đọc/hủy/SSE task của người khác) ==")
    r = c1.post("/api/music/generate", params={"prompt": "bai hat test", "duration": 60})
    task_id = r.json().get("id", "") if r.status_code == 200 else ""
    if task_id:
        r = c2.get(f"/api/music/task/{task_id}")
        attempts += 1
        if r.status_code not in (401, 403, 404):
            breaches.append((f"GET task người khác → {r.status_code}", "lộ trạng thái task"))
        r = c2.post(f"/api/music/task/{task_id}/cancel")
        attempts += 1
        if r.status_code not in (401, 403, 404):
            breaches.append((f"CANCEL task người khác → {r.status_code}", "hủy được task của người khác"))
        r = c2.get(f"/api/music/task/{task_id}/events")
        attempts += 1
        if r.status_code not in (401, 403, 404):
            breaches.append((f"SSE task người khác → {r.status_code}", "nghe trộm stream"))

    print("== T3. CANCEL CHUỖI (hủy 2 lần, hủy task lạ) ==")
    if task_id:
        for _ in range(2):
            r = c1.post(f"/api/music/task/{task_id}/cancel")
            attempts += 1
            if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
                breaches.append((f"cancel → {r.status_code}", "5xx"))
    r = c1.post("/api/music/task/00000000-0000-0000-0000-000000000000/cancel")
    attempts += 1
    if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
        breaches.append((f"cancel task lạ → {r.status_code}", "5xx"))

    print("== T4. PARAMS INJECTION (payload lớn, null bytes, unicode) ==")
    for params in (
        {"prompt": "x", "duration": 60, "vocal": "V" * 8000},
        {"prompt": "x", "duration": 60, "lyrics": "a\x00b\x00c"},
        {"prompt": "🎵" * 1000, "duration": 60},
    ):
        r = c1.post("/api/music/generate", params=params)
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"generate params méo → {r.status_code}", "5xx"))

    print("== T5. UPLOAD MÉO (tên file, title 300+ ký tự, lyrics 1MB, bpm nan/inf) ==")
    wav = tone_wav()
    for fname in ("a.wav.wav", "..wav", "nhạc cầu.wav", "CON.wav"):
        r = c1.post("/api/heritage/upload", files={"file": (fname, wav, "audio/wav")}, data={"title": f"T{secrets.token_hex(3)}"})
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"upload tên {fname} → {r.status_code}", "5xx"))
    for data in (
        {"title": "X" * 400},
        {"title": "Y", "bpm": "nan"},
        {"title": "Y", "bpm": "inf"},
        {"title": "Y", "bpm": "1e309"},
        {"title": "Z", "lyrics": "l" * 1000000},
    ):
        r = c1.post(
            "/api/heritage/upload",
            files={"file": (f"m{secrets.token_hex(2)}.wav", tone_wav(freq=300.0 + attempts), "audio/wav")},
            data=data,
        )
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"upload data méo {list(data)} → {r.status_code}", "5xx"))

    print("== T6. SHA DEDUP (cùng bytes khác title → 1 item) ==")
    same = tone_wav(220.0, dur=0.3)
    ids = []
    for t in ("Dedup A", "Dedup B"):
        r = c1.post("/api/heritage/upload", files={"file": ("dedup.wav", same, "audio/wav")}, data={"title": t})
        attempts += 1
        if r.status_code == 200:
            ids.append((r.json().get("id"), r.json().get("created")))
    if len(ids) == 2 and ids[0][0] != ids[1][0]:
        breaches.append(("dedup thất bại", f"2 item khác nhau cho cùng sha: {ids}"))
    if len(ids) == 2 and ids[1][1] is not False:
        breaches.append(("dedup cờ created sai", f"{ids}"))

    print("== T7. BYPASS FORCE-CHANGE (user do admin tạo, đuôi /, //, đổi hoa thường) ==")
    fc_user = None
    if args.admin_password:
        la = httpx.Client(base_url=base, timeout=30.0)
        r = la.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": args.admin_password})
        if r.status_code == 200:
            ah = {"Authorization": f"Bearer {r.json()['token']}"}
            la.post("/api/auth/admin-unlock", json={"password": args.admin_password}, headers=ah)
            r = la.post("/api/auth/users", json={"username": "fcvictim" + secrets.token_hex(2)}, headers=ah)
            if r.status_code == 200:
                temp = r.json()["temp_password"]
                r = la.post("/api/auth/login", json={"identifier": r.json()["username"], "password": temp})
                if r.status_code == 200:
                    fc_user = {"token": r.json()["token"], "username": r.json()["username"], "temp": temp}
                    if not r.json().get("must_change_password"):
                        breaches.append(("admin tạo user không có cờ force-change", ""))
        la.close()
    if fc_user:
        cfc = client(base, fc_user["token"])
        probes = [
            ("POST", "/api/heritage/upload", {"file": ("x.wav", b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00", "audio/wav")}),
            ("POST", "/api/auth/change-password/", None),
            ("POST", "//api/auth/change-password", None),
            ("POST", "/API/auth/change-password", None),
            ("POST", "/api/auth/change-password%2F", None),
        ]
        for method, path, files in probes:
            r = cfc.request(method, path, files=files)
            attempts += 1
            if r.status_code == 200:
                breaches.append((f"force-change bypass {path} → 200", "ghi thành công khi chưa đổi mật khẩu"))
        r = cfc.post("/api/auth/change-password", json={"old_password": fc_user["temp"], "new_password": "MatkhauMoi#77"})
        attempts += 1
        if r.status_code != 200:
            breaches.append(("đổi mật khẩu chính tắc bị chặn", f"{r.status_code}"))
        cfc.close()
    else:
        print("  (bỏ qua — không có --admin-password)")

    print("== T8. TOKEN EPOCH GIẢ (âm, khổng lồ) ==")
    tok = u1["token"]
    parts = tok.split(".")
    if len(parts) >= 4:
        for e in ("-1", "10" * 20):
            forged = f"{parts[0]}.{parts[1]}.{e}.{parts[3]}"
            r = c1.get("/api/auth/me", headers={"Authorization": f"Bearer {forged}"})
            attempts += 1
            if r.status_code == 200:
                breaches.append((f"token epoch {e[:8]}... chấp nhận", "sửa epoch vẫn hợp lệ"))

    print("== T9. SIGNED-URL CROSS-PATH (sig của item A dùng cho item B) ==")
    r = c1.post("/api/heritage/upload", files={"file": ("a1.wav", tone_wav(500.0), "audio/wav")}, data={"title": "SigA"})
    r2 = c1.post("/api/heritage/upload", files={"file": ("b1.wav", tone_wav(600.0), "audio/wav")}, data={"title": "SigB"})
    if r.status_code == 200 and r2.status_code == 200:
        ida, idb = r.json()["id"], r2.json()["id"]
        ur = c1.get(f"/api/heritage/{ida}/audio-url")
        url = ur.json().get("url", "")
        exp = url.split("e=")[1].split("&")[0]
        sig = url.split("s=")[-1]
        anon = httpx.Client(base_url=base, timeout=30.0)
        r = anon.get(f"/api/heritage/{idb}/audio?e={exp}&s={sig}")
        attempts += 1
        if r.status_code == 200:
            breaches.append(("sig tái dùng qua path khác (ẩn danh) → 200", "chữ ký không gắn path"))
        r = anon.get(f"/api/heritage/{ida}/audio?e={exp}&s={sig}")
        attempts += 1
        if r.status_code != 200:
            breaches.append((f"sig đúng path của item public → {r.status_code}", "signed URL chính tắc bị chặn"))
        anon.close()

    print("== T10. PRACTICE MIDI GUESS (tên legacy ngẫu nhiên) ==")
    hits = 0
    for _ in range(20):
        name = f"practice_{secrets.token_hex(4)}_0_{1700000000}.mid"
        r = c1.get(f"/api/lessons/practice-midi/{name}")
        attempts += 1
        if r.status_code == 200:
            hits += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"practice-midi {name[:20]} → {r.status_code}", "5xx"))
    if hits:
        breaches.append(("practice-midi đoán trúng", f"{hits}/20"))

    print("== T11. EMAIL CASE-INSENSITIVE LOGIN (nhất quán, không 5xx) ==")
    r = httpx.post(base + "/api/auth/login", json={"identifier": f"{u1['username']}@GMAIL.COM", "password": "secret123"}, timeout=30.0)
    attempts += 1
    if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
        breaches.append((f"login email HOA → {r.status_code}", "5xx"))

    print("== T12. INVITE BOUNDARIES (3 ký tự, 65 ký tự, unicode) ==")
    for code in ("ABC", "C" * 65, "mã-邀请-🎨"):
        r = c1.post("/api/auth/invites", json={"code": code, "note": "edge"})
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"invite code {code[:8]!r} → {r.status_code}", "5xx"))

    print("== T13. RACE NHẸ: 5 generate song song cùng user ==")
    def gen(i):
        cc = client(base, u1["token"])
        r = cc.post("/api/music/generate", params={"prompt": f"race {i}", "duration": 60})
        cc.close()
        return r.status_code

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:
        codes = list(ex.map(gen, range(5)))
    attempts += 5
    if any(x >= 500 for x in codes):
        breaches.append((f"5 generate song song → {codes}", "5xx"))

    print("== T14. SSE CỦA MÌNH (đọc được, không 5xx) ==")
    if task_id:
        with httpx.Client(base_url=base, timeout=10.0, headers={"Authorization": f"Bearer {u1['token']}"}) as cc:
            with cc.stream("GET", f"/api/music/task/{task_id}/events") as resp:
                attempts += 1
                if resp.status_code >= 500 and not (resp.status_code == 503 and resp.headers.get("retry-after")):
                    breaches.append((f"SSE task của mình → {resp.status_code}", "5xx"))
                else:
                    chunk = next(resp.iter_text(), "")
                    if "data:" not in chunk and "event:" not in chunk:
                        breaches.append(("SSE không có payload", chunk[:40]))

    print("== T15. VISIBILITY CROSS-PROBE (audio công khai của người khác + sig lệch item) ==")
    r = c1.post("/api/heritage/upload", files={"file": ("pub.wav", tone_wav(700.0), "audio/wav")}, data={"title": "PubItem"})
    if r.status_code == 200:
        pub_id = r.json()["id"]
        r = c2.get(f"/api/heritage/{pub_id}/audio")
        attempts += 1
        if r.status_code != 200:
            breaches.append((f"audio public của user khác → {r.status_code}", "user thường đọc không được item public"))

    print(f"\n(attempts={attempts})")
    verdict("INTERMEDIATE-SUITE", attempts, breaches)


if __name__ == "__main__":
    main()
