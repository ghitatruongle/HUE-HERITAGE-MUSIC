"""HACKER ADVANCED-SUITE — tấn công nâng cao khó đoán: unlock brute-force, oracle đăng ký,
smuggling CL+TE, bpm tràn số, epoch chữ số unicode, sig biến thể, WAV hostile, XFF bypass."""
import argparse
import io
import secrets
import struct
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402

INVITE = "CHAOS-CODE"


def tiny_wav(sr=16000, channels=1, bits=16, frames=8):
    channels = channels & 0xFFFF
    bits = bits & 0xFFFF
    data = b"\x00\x00" * max(1, channels) * frames
    byte_rate = (sr * max(1, channels) * bits // 8) & 0xFFFFFFFF
    block_align = (max(1, channels) * bits // 8) & 0xFFFF
    sr = sr & 0xFFFFFFFF
    hdr = (
        b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt "
        + struct.pack("<IHHIIHH", 16, 1, channels, sr, byte_rate, block_align, bits)
        + b"data" + struct.pack("<I", len(data))
    )
    return hdr + data


def raw_request(base_host, port, raw: bytes, timeout=6.0):
    import socket

    s = socket.create_connection((base_host, port), timeout=timeout)
    s.settimeout(timeout)
    try:
        s.sendall(raw)
        chunks = []
        try:
            while True:
                b = s.recv(4096)
                if not b:
                    break
                chunks.append(b)
                if len(chunks) > 32:
                    break
        except socket.timeout:
            pass
        return b"".join(chunks)
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8013")
    ap.add_argument("--admin-password", default="")
    ap.add_argument("--rounds", type=int, default=1)
    args = ap.parse_args()
    base = args.base
    attempts = 0
    breaches = []

    u = register_user(base)
    if not u:
        verdict("ADVANCED-SUITE", 0, [("không đăng ký được user", "")])
        return
    c = client(base, u["token"])

    print("== X1. UNLOCK BRUTE-FORCE (5 sai → 429, không brute được step-up) ==")
    if args.admin_password:
        la = httpx.Client(base_url=base, timeout=30.0)
        r = la.post("/api/auth/login", json={"identifier": "ghitatruongle", "password": args.admin_password})
        if r.status_code == 200:
            ah = {"Authorization": f"Bearer {r.json()['token']}"}
            codes = []
            for i in range(8):
                r = la.post("/api/auth/admin-unlock", json={"password": f"wrong-{i}"}, headers=ah)
                codes.append(r.status_code)
                attempts += 1
                if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
                    breaches.append((f"unlock sai #{i} → {r.status_code}", "5xx"))
            if 429 not in codes:
                breaches.append((f"unlock brute không bị trần: {codes}", "thiếu rate limit"))
            r = la.post("/api/auth/admin-unlock", json={"password": args.admin_password}, headers=ah)
            attempts += 1
            if r.status_code == 200:
                breaches.append(("unlock ĐÚNG mật khẩu vẫn 200 sau khi trần khóa", "trần khóa cả mật khẩu đúng"))
        la.close()
    else:
        print("  (bỏ qua — không có --admin-password)")

    print("== X2. ORACLE ĐĂNG KÝ: mã sai KHÔNG được đăng ký được, không 5xx (trần 429 do env cấu hình) ==")
    codes = []
    for i in range(40):
        r = httpx.post(
            base + "/api/auth/register",
            json={
                "username": f"oracle{i}{secrets.token_hex(3)}",
                "email": f"oracle{i}{secrets.token_hex(3)}@gmail.com",
                "password": "secret123",
                "invite_code": "HUE-KHONGTONTAI",
            },
            timeout=30.0,
        )
        codes.append(r.status_code)
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"oracle probe #{i} → {r.status_code}", "5xx"))
        if r.status_code == 200:
            breaches.append((f"oracle probe #{i} → 200", "đăng ký được với mã sai — hỏng cổng mời"))
    print(f"  mã trả về: {sorted(set(codes))} (429 = trần thất bại/IP đang bật ở env này)")

    print("== X3. BPM TRÀN SỐ trên route artifact (inf/nan/1e309) ==")
    sha = "a" * 64
    for bpm in ("1e309", "nan", "-inf", "1e400"):
        r = c.get("/api/music/midi/" + sha, params={"bpm": bpm})
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"midi bpm={bpm} → {r.status_code}", "5xx"))
        r = c.get("/api/music/musicxml/" + sha, params={"bpm": bpm})
        attempts += 1
        if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
            breaches.append((f"musicxml bpm={bpm} → {r.status_code}", "5xx"))

    print("== X4. HTTP SMUGGLING (CL+TE, TE+CL, CL xung đột) ==")
    host = base.split("//")[1].split(":")[0]
    port = int(base.rsplit(":", 1)[1])
    smuggles = {
        "CL+TE": (
            b"POST /api/auth/login HTTP/1.1\r\nHost: h\r\nContent-Type: application/json\r\n"
            b"Content-Length: 2\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            b"8\r\n{\"a\":1}\r\n0\r\n\r\n"
        ),
        "TE+CL": (
            b"POST /api/auth/login HTTP/1.1\r\nHost: h\r\nContent-Type: application/json\r\n"
            b"Transfer-Encoding: chunked\r\nContent-Length: 2\r\nConnection: close\r\n\r\n"
            b"8\r\n{\"a\":1}\r\n0\r\n\r\n"
        ),
        "CL-conflict": (
            b"POST /api/auth/login HTTP/1.1\r\nHost: h\r\nContent-Type: application/json\r\n"
            b"Content-Length: 5\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{\"a\":1}"
        ),
    }
    for label, raw in smuggles.items():
        resp = raw_request(host, port, raw)
        attempts += 1
        head = resp[:200]
        if b" 200 " in head and b"token" in resp:
            breaches.append((f"smuggling {label} → 200 có token", "parser chấp nhận body mơ hồ"))
        if not resp:
            breaches.append((f"smuggling {label} → không phản hồi", "kết nối treo"))

    print("== X5. XFF KHÔNG RESET 429 (rate limit theo IP thật) ==")
    for i in range(6):
        r = httpx.post(base + "/api/auth/login", json={"identifier": "xffuser-x", "password": "sai-qua"}, timeout=30.0)
        attempts += 1
    got429 = r.status_code == 429
    for xff in ("8.8.8.8", "1.1.1.1, 2.2.2.2"):
        r = httpx.post(
            base + "/api/auth/login",
            json={"identifier": "xffuser-x", "password": "sai-qua"},
            headers={"X-Forwarded-For": xff},
            timeout=30.0,
        )
        attempts += 1
        if r.status_code == 401:
            breaches.append((f"XFF {xff} reset được 429 → 401", "rate limit tin header giả"))

    print("== X6. EPOCH BYTE KHÔNG-ASCII qua raw socket (⑤ vẫn phải sig mismatch) ==")
    tok = u["token"]
    parts = tok.split(".")
    if len(parts) >= 4:
        raw = (
            f"GET /api/auth/me HTTP/1.1\r\nHost: h\r\n"
            f"Authorization: Bearer {parts[0]}.{parts[1]}.\xd9\xa5.{parts[3]}\r\n"
            f"Connection: close\r\n\r\n"
        ).encode("latin-1")
        resp = raw_request(host, port, raw)
        attempts += 1
        head = resp[:60].decode("latin-1", "replace")
        if " 200 " in head:
            breaches.append(("epoch byte unicode accepted", ""))
        if not resp:
            breaches.append(("epoch unicode → kết nối chết không phản hồi", ""))
        if " 500 " in head:
            breaches.append(("epoch unicode → 500", "5xx"))

    print("== X7. SIGNED-URL SIG BIẾN THỂ (HOA, 0x, unicode đuôi) ==")
    r = c.post("/api/heritage/upload", files={"file": ("adv.wav", tiny_wav(), "audio/wav")}, data={"title": "AdvA"})
    if r.status_code == 200:
        iid = r.json()["id"]
        url = c.get(f"/api/heritage/{iid}/audio-url").json().get("url", "")
        exp = url.split("e=")[1].split("&")[0]
        sig = url.split("s=")[-1]
        anon = httpx.Client(base_url=base, timeout=30.0)
        for s in (sig.upper(), "0x" + sig, sig + "ف", sig[:-1] + ("0" if sig[-1] != "0" else "1")):
            r = anon.get(f"/api/heritage/{iid}/audio?e={exp}&s={s}")
            attempts += 1
            if r.status_code == 200:
                breaches.append((f"sig biến thể {s[:12]}... → 200", "so khớp sig lỏng"))
            if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
                breaches.append((f"sig biến thể → {r.status_code}", "5xx"))
        r = anon.get(f"/api/heritage/{iid}/audio?e={exp}&s={sig}&e=1")
        attempts += 1
        if r.status_code == 200:
            pass
        r = anon.get(f"/api/heritage/{iid}/audio", params=[("e", exp), ("s", sig), ("e", "1"), ("s", "x")])
        attempts += 1
        if r.status_code == 200:
            breaches.append(("e/s trùng lặp chọn giá trị attacker → 200", "param pollution lấy giá trị sau"))
        anon.close()

    print("== X8. WAV HOSTILE HEADER (sr/channels/bits cực trị) → analyze phải 4xx nhanh ==")
    for label, wav in {
        "sr-max": tiny_wav(sr=2147483647),
        "ch-65535": tiny_wav(channels=65535),
        "bits-8k": tiny_wav(bits=8192),
        "zero-sr": tiny_wav(sr=0),
    }.items():
        try:
            r = httpx.post(
                base + "/api/music/analyze-pitch",
                files={"file": (f"{label}.wav", wav, "audio/wav")},
                timeout=25.0,
            )
            attempts += 1
            if r.status_code >= 500 and not (r.status_code == 503 and r.headers.get("retry-after")):
                breaches.append((f"WAV {label} → {r.status_code}", "5xx"))
        except httpx.TimeoutException:
            breaches.append((f"WAV {label} → timeout 25s", "treo server"))

    print("== X9. REPLAY LOGIN 2 LẦN (nhất quán) ==")
    body = {"identifier": u["username"], "password": "secret123"}
    r1 = httpx.post(base + "/api/auth/login", json=body, timeout=30.0)
    r2 = httpx.post(base + "/api/auth/login", json=body, timeout=30.0)
    attempts += 2
    if r1.status_code != r2.status_code or r1.status_code >= 500:
        breaches.append((f"replay login {r1.status_code}/{r2.status_code}", "không nhất quán"))

    print(f"\n(attempts={attempts})")
    verdict("ADVANCED-SUITE", attempts, breaches)


if __name__ == "__main__":
    main()
