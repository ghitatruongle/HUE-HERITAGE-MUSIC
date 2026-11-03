import argparse
import secrets
import struct
import sys
import time

import httpx

INVITE = "CHAOS-CODE"
PASS = []
FAIL = []


def check(name, cond, note=""):
    (PASS if cond else FAIL).append((name, note))
    print(f"  {'✓' if cond else '✗ LỖ HỔNG'} {name}" + (f" — {note}" if note else ""))


def make_wav(seed=7, kb=4):
    n = kb * 1024
    frames = b"".join(struct.pack("<h", (seed * 31 + i * 13) % 15000 - 7500) for i in range(n))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, 8000, 16000, 2, 16
    ) + b"data" + struct.pack("<I", len(frames))
    return hdr + frames


def register(base, username, password="secret123"):
    c = httpx.Client(base_url=base, timeout=90)
    r = c.post("/api/auth/register", json={
        "username": username, "email": f"{username}@gmail.com",
        "password": password, "invite_code": INVITE,
    })
    c.close()
    if r.status_code == 200:
        return r.json()
    if r.status_code == 409:
        c = httpx.Client(base_url=base, timeout=60)
        lr = c.post("/api/auth/login", json={"identifier": username, "password": password})
        c.close()
        if lr.status_code == 200:
            return lr.json()
    return {}


def signed_section(base, admin_h, user_h):
    print("\n== A. SIGNED URL CHUYÊN SÂU (test URL bằng client không Authorization — đúng kịch bản player) ==")
    c = httpx.Client(base_url=base, timeout=30, headers=user_h)
    c2 = httpx.Client(base_url=base, timeout=30)
    wav = make_wav(3)
    r = c.post("/api/heritage/upload", files={"file": ("signed.wav", wav, "audio/wav")}, data={"title": "Signed Song"})
    item_id = r.json()["id"]
    r = c.get(f"/api/heritage/{item_id}/audio-url", headers=user_h)
    url = r.json()["url"]
    sep = "&" if "?" in url else "?"
    r = c2.get(f"{url}{sep}dummy=1")
    check("A1 signed URL gốc phát audio", r.status_code == 200, f"status={r.status_code}")
    r = c2.get(f"{url[:-1]}{'0' if url[-1] != '0' else '1'}")
    check("A2 sửa 1 ký tự chữ ký → 401", r.status_code == 401, f"status={r.status_code}")
    parts = url.split("e=")
    exp = parts[1].split("&")[0]
    r = c2.get(f"/api/heritage/{item_id}/audio?e={int(exp) + 1}&s={parts[1].split('&s=')[1] if '&s=' in url else url.split('s=')[-1]}")
    check("A3 dịch expiry +1s giữ sig cũ → 401", r.status_code == 401, f"status={r.status_code}")
    r2 = c.post("/api/heritage/upload", files={"file": ("other.wav", make_wav(9), "audio/wav")}, data={"title": "Other Song"})
    other_id = r2.json()["id"]
    other_url = c.get(f"/api/heritage/{other_id}/audio-url", headers=user_h).json()["url"]
    other_s = other_url.split("s=")[-1]
    r = c2.get(f"/api/heritage/{item_id}/audio?e={exp}&s={other_s}")
    check("A4 mang sig của item khác → 401", r.status_code == 401, f"status={r.status_code}")
    r = c2.get(f"/api/heritage/{item_id}/audio?e={int(time.time()) + 99999}&s={'a' * 32}")
    check("A5 expiry xa + sig random → 401", r.status_code == 401, f"status={r.status_code}")
    for bad_e in ("0", "-1", "abc", "1.5"):
        r = c2.get(f"/api/heritage/{item_id}/audio?e={bad_e}&s={'f' * 32}")
        if r.status_code != 401:
            check(f"A6 e={bad_e} → 401", False, f"status={r.status_code}")
            break
    else:
        check("A6 e méo (0/-1/abc/1.5) → 401", True)
    r = c2.get(f"/api/heritage/{item_id}/audio/?e={exp}&s={url.split('s=')[-1]}")
    check("A7 trailing slash lệch path sig → 401/404", r.status_code in (401, 404), f"status={r.status_code}")
    c_admin = httpx.Client(base_url=base, timeout=30, headers=admin_h)
    c_admin.post("/api/auth/admin-unlock", json={"password": "secret123"})
    c_admin.delete(f"/api/admin/storage/{item_id}", headers=admin_h)
    r = c2.get(url)
    check("A8 replay URL sau khi xóa item → 404", r.status_code == 404, f"status={r.status_code}")
    c.close()
    c2.close()
    c_admin.close()
    return other_id


def token_section(base, user_h):
    print("\n== B. TOKEN EDGE CASES ==")
    c = httpx.Client(base_url=base, timeout=30)
    bad_tokens = [
        ("B1 expires khổng lồ", f"abc.{99999999999999}.0.{secrets.token_hex(32)}"),
        ("B2 5 phần", f"a.b.c.d.{secrets.token_hex(16)}"),
        ("B3 epoch âm", f"abc.{int(time.time()) + 9999}.-1.{secrets.token_hex(32)}"),
    ]
    all_401 = True
    for name, tok in bad_tokens:
        r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
        if r.status_code != 401:
            all_401 = False
            check(name, False, f"status={r.status_code}")
            break
    else:
        check("B1/B2/B3 token méo → 401 toàn bộ", all_401)
    t0 = time.perf_counter()
    r = c.get("/api/auth/me", headers={"Authorization": "Bearer " + "a" * 100000})
    dt = time.perf_counter() - t0
    check("B4 token 100KB → 401 nhanh", r.status_code == 401 and dt < 1.0, f"status={r.status_code} {dt * 1000:.0f}ms")
    c.close()


def upload_section(base, admin_h, user_h):
    print("\n== C. UPLOAD EDGE CASES ==")
    c = httpx.Client(base_url=base, timeout=120, headers=user_h)
    long_name = "a" * 300 + ".wav"
    r = c.post("/api/heritage/upload", files={"file": (long_name, make_wav(11), "audio/wav")}, data={"title": "LongName"})
    check("C1 filename 300 ký tự → chặn/an toàn", r.status_code in (200, 400), f"status={r.status_code}")
    r = c.post("/api/heritage/upload", files={"file": ("bài hát việt.wav", make_wav(12), "audio/wav")}, data={"title": "Tên Việt"})
    check("C2 filename unicode → nhận bình thường", r.status_code == 200, f"status={r.status_code}")
    for name, bpm in (("C3 bpm NaN", "NaN"), ("C4 bpm 1e999", "1e999"), ("C5 bpm âm", "-5")):
        r = c.post("/api/heritage/upload", files={"file": (f"{name}.wav", make_wav(13), "audio/wav")}, data={"title": name, "bpm": bpm})
        ok = r.status_code == 400
        check(f"{name} → 400", ok, f"status={r.status_code}")
    r = c.post("/api/heritage/upload", files={"file": ("micro.wav", make_wav(13), "audio/wav")}, data={"title": "C6 bpm vi mô", "bpm": "0.000001"})
    check("C6 bpm vi mô dương hợp lệ → 200", r.status_code == 200, f"status={r.status_code}")
    poly = make_wav(14) + b"MZ" + secrets.token_bytes(500)
    r = c.post("/api/heritage/upload", files={"file": ("poly.wav", poly, "audio/wav")}, data={"title": "Poly"})
    check("C7 polyglot wav+MZ (magic đầu WAV) → theo thiết kế 200", r.status_code == 200, f"status={r.status_code}")
    r2 = c.post("/api/heritage/upload", files={"file": ("poly2.wav", poly, "audio/wav")}, data={"title": "Poly Again"})
    check("C8 upload trùng sha → dedup cùng item", r2.status_code == 200 and r2.json().get("created") is False, f"status={r2.status_code}")
    fields = {f"field{i}": "x" * 100 for i in range(25)}
    r = c.post("/api/heritage/upload", files={"file": ("flood.wav", make_wav(15), "audio/wav")}, data={"title": "Flood", **fields})
    check("C9 25 form fields lạ → bỏ qua an toàn", r.status_code == 200, f"status={r.status_code}")
    print("\n== C10. CHUNKED UPLOAD KHÔNG CONTENT-LENGTH (~55MB, vượt trần 50MB) ==")
    import socket
    token = user_h["Authorization"].split(" ")[1]
    sock = socket.create_connection(("127.0.0.1", PORT))
    sock.settimeout(180)
    head = (
        f"POST /api/heritage/upload HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\n"
        f"Authorization: Bearer {token}\r\n"
        f"Content-Type: multipart/form-data; boundary=BOUND\r\n"
        f"Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
    ).encode()
    sock.sendall(head)
    part = make_wav(16, kb=1024)
    first = b"--BOUND\r\nContent-Disposition: form-data; name=\"file\"; filename=\"huge.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
    resp = b""
    reset = False
    try:
        def send_chunk(data):
            sock.sendall(f"{len(data):x}\r\n".encode() + data + b"\r\n")
        send_chunk(first)
        sent = 0
        while sent < 55:
            send_chunk(part)
            sent += len(part) / 1024 / 1024
    except (BrokenPipeError, ConnectionResetError):
        reset = True
    try:
        sock.settimeout(30)
        while len(resp) < 8192:
            d = sock.recv(65536)
            if not d:
                break
            resp += d
            if b"413" in resp or b"HTTP/1.1" in resp:
                break
    except socket.timeout:
        pass
    sock.close()
    first_line = resp.split(b"\r\n")[0].decode(errors="replace") if resp else "KHÔNG PHẢN HỒI"
    check("C10 chunked 55MB không content-length → ngắt giữa stream (413 hoặc reset sau trần)", b"413" in resp or reset, first_line + f" reset={reset}")
    c.close()


def protocol_section(base, user_h):
    print("\n== D. GIAO THỨC HTTP ==")
    c = httpx.Client(base_url=base, timeout=30, headers=user_h)
    r = c.head("/api/auth/login")
    check("D1 HEAD /login → 404/405 (không bypass)", r.status_code in (404, 405), f"status={r.status_code}")
    try:
        r = c.request("TRACE", "/health")
        st = r.status_code
    except Exception:
        st = 0
    check("D2 TRACE → 405/chặn", st in (405, 0, 501), f"status={st}")
    r = c.get("//api/admin/stats")
    leak = r.status_code == 200 and "users" in r.text and "total" in r.text
    check("D3 //api/admin/stats không bypass", not leak, f"status={r.status_code}")
    r = c.get("/api/auth/me/")
    check("D4 trailing slash /auth/me/ → không bypass", r.status_code in (401, 404), f"status={r.status_code}")
    r = c.get("/api/./admin/stats")
    check("D5 /api/./admin/stats → không bypass (normalize về 403)", r.status_code in (401, 403, 404, 400), f"status={r.status_code}")
    r = c.post("/api/auth/login", json={"identifier": "x", "password": "y"}, headers={"Content-Type": "text/plain"})
    check("D6 content-type sai trên JSON → 422", r.status_code == 422, f"status={r.status_code}")
    print("\n== E. BODY DoS JSON ==")
    t0 = time.perf_counter()
    big = '{"identifier":"x","password":"y","pad":"' + "A" * (20 * 1024 * 1024) + '"}'
    try:
        r = c.post("/api/auth/login", content=big.encode(), headers={"Content-Type": "application/json"})
        st, note = r.status_code, f"status={r.status_code}"
    except Exception as ex:
        st, note = 0, str(ex)[:60]
    dt = time.perf_counter() - t0
    check("E1 JSON 20MB → bị chặn 413 (không nuốt vào RAM)", st == 413, f"{note} {dt:.1f}s")
    c.close()


def logic_section(base, admin_h, user_h):
    print("\n== F. BUSINESS LOGIC ==")
    c = httpx.Client(base_url=base, timeout=30, headers=user_h)
    r = c.post("/api/auth/change-password", json={"old_password": "secret123", "new_password": "secret123"})
    check("F1 đổi mật khẩu trùng cũ → cho phép 200", r.status_code == 200, f"status={r.status_code}")
    fresh = r.json().get("token", "")
    r = c.post("/api/auth/revoke-all", headers={"Authorization": f"Bearer {fresh}"})
    r2 = c.get("/api/auth/me", headers={"Authorization": f"Bearer {fresh}"})
    check("F2 revoke-all → 200 rồi token cũ chết ngay (401)", r.status_code == 200 and r2.status_code == 401, f"{r.status_code}/{r2.status_code}")
    c.close()
    c = httpx.Client(base_url=base, timeout=30)
    uname = f"case{secrets.token_hex(2)}"
    c.post("/api/auth/register", json={"username": uname, "email": f"{uname}@gmail.com", "password": "secret123", "invite_code": INVITE})
    r = c.post("/api/auth/register", json={"username": uname + "b", "email": f"{uname}@GMAIL.COM", "password": "secret123", "invite_code": INVITE})
    check("F3 email trùng khác HOA → 409", r.status_code == 409, f"status={r.status_code}")
    c.close()
    c = httpx.Client(base_url=base, timeout=30, headers=admin_h)
    r = c.get("/api/heritage", params={"q": "%" + "_" * 50 + "%"})
    check("F4 wildcard query → 200 rỗng an toàn", r.status_code == 200, f"status={r.status_code} n={len(r.json())}")
    c.close()


def main():
    global PORT
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8129")
    ap.add_argument("--port", type=int, default=8129)
    args = ap.parse_args()
    PORT = args.port
    base = args.base

    admin = register(base, "ghitatruongle", "AdminRt2#2026")
    user = register(base, "rt2user1")
    if not admin or not user:
        print("FATAL: setup thất bại (admin/admin?")
        sys.exit(2)
    c = httpx.Client(base_url=base, timeout=30)
    r = c.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": "AdminRt2#2026"})
    admin_token = r.json()["token"]
    c.post("/api/auth/admin-unlock", json={"password": "AdminRt2#2026"}, headers={"Authorization": f"Bearer {admin_token}"})
    c.close()
    if admin.get("role") != "admin":
        print("CẦN RESTART SERVER để thăng chức admin (exit 3)")
        sys.exit(3)
    admin_h = {"Authorization": f"Bearer {admin_token}"}
    user_h = {"Authorization": f"Bearer {user['token']}"}

    other_id = signed_section(base, admin_h, user_h)
    token_section(base, user_h)
    upload_section(base, admin_h, user_h)
    protocol_section(base, user_h)
    logic_section(base, admin_h, user_h)

    c = httpx.Client(base_url=base, timeout=30, headers=admin_h)
    c.delete(f"/api/admin/storage/{other_id}", headers=admin_h)
    c.close()

    print(f"\nKẾT QUẢ REDTEAM V2: {len(PASS)} pass / {len(FAIL)} fail")
    for name, note in FAIL:
        print(f"  ✗ {name} — {note}")
    sys.exit(0 if not FAIL else 1)


if __name__ == "__main__":
    main()
