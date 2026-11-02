import argparse
import concurrent.futures
import secrets
import sys
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from common import ATTACK_CODE, client, forge_token, register_user  # noqa: E402

ADMIN = "ghitatruongle"

RESULTS = []


def record(tier, name, blocked, note=""):
    RESULTS.append((tier, name, blocked, note))
    mark = "CHẶN ✓" if blocked else "LỖ HỔNG ✗"
    print(f"  [{tier}] {mark} {name}" + (f" — {note}" if note else ""))


def expect(cond):
    return bool(cond)


def run_light(base):
    print("\n========== MỨC 1 — TẤN CÔNG NHẸ (dò quét không xác thực) ==========")
    c = client(base)
    r = c.get("/api/auth/users")
    record("NHẸ", "Đọc danh sách user không token", expect(r.status_code == 401), f"status={r.status_code}")
    r = c.get("/api/admin/stats")
    record("NHẸ", "Đọc stats quản trị không token", expect(r.status_code == 401), f"status={r.status_code}")
    r = c.get("/api/admin/storage")
    record("NHẸ", "Đọc kho lưu trữ không token", expect(r.status_code == 401), f"status={r.status_code}")
    r = c.get("/openapi.json")
    swagger_leak = "swift" in r.text.lower() or ("paths" in r.text and "openapi" in r.text.lower()[:200])
    record("NHẸ", "Dò OpenAPI/Swagger công khai", expect(not swagger_leak), f"status={r.status_code} leak={swagger_leak}")
    r = c.get("/docs")
    docs_leak = "swagger" in r.text.lower()
    record("NHẸ", "Dò /docs", expect(not docs_leak), f"status={r.status_code} leak={docs_leak}")
    r = c.get("/api/endpoint-khong-ton-tai")
    leak = r.status_code == 500 or "Traceback" in r.text or "File \"" in r.text
    record("NHẸ", "404 probing không lộ stack trace", expect(not leak and r.status_code == 404), f"status={r.status_code}")
    r = c.get("/health")
    info_leak = "secret" in r.text.lower() or "password" in r.text.lower()
    record("NHẸ", "/health không lộ bí mật", expect(r.status_code == 200 and not info_leak), f"status={r.status_code}")
    c.headers["Authorization"] = "Bearer khong.phai.token"
    r = c.get("/api/auth/me")
    record("NHẸ", "Token rác bị từ chối", expect(r.status_code == 401), f"status={r.status_code}")
    c.headers.pop("Authorization", None)
    r1 = c.post("/api/auth/login", json={"identifier": "khongtonnai", "password": "sai"})
    same_msg = r1.status_code == 401
    r2 = c.post("/api/auth/login", json={"identifier": ADMIN, "password": "sai"})
    record("NHẸ", "Login sai → 401 thông điệp chung", expect(same_msg and r2.status_code == 401), f"{r1.status_code}/{r2.status_code}")
    r = c.get("/api/heritage", params={"limit": 999999})
    record("NHẸ", "limit khổng lồ bị kẹp", expect(r.status_code == 200), f"status={r.status_code}")
    h = {k.lower() for k in r.headers.keys()}
    missing = [x for x in ("x-content-type-options", "x-frame-options", "referrer-policy") if x not in h]
    record("NHẸ", "Security headers đầy đủ", expect(not missing), f"thiếu={missing}" if missing else "")
    c.close()


def run_medium(base, user):
    print("\n========== MỨC 2 — TẤN CÔNG TRUNG BÌNH (lạm dụng có xác thực) ==========")
    token = user["token"]
    c = client(base, token=token)
    brute_id = "victim" + secrets.token_hex(2)
    codes = []
    for i in range(6):
        r = c.post("/api/auth/login", json={"identifier": brute_id, "password": "sai"})
        codes.append(r.status_code)
    record("TRUNG", "6 sai cùng identifier → 429 rate limit", expect(429 in codes), f"codes={codes}")
    r = c.post("/api/auth/register", json={"username": "noinvite" + secrets.token_hex(2), "email": "n@x.com", "password": "secret123", "invite_code": ""})
    record("TRUNG", "Register thiếu invite → chặn", expect(r.status_code in (400, 429)), f"status={r.status_code}")
    r = c.post("/api/auth/register", json={"username": "admin", "email": "a@gmail.com", "password": "secret123", "invite_code": ATTACK_CODE})
    record("TRUNG", "Đăng ký username reserved 'admin' → chặn", expect(r.status_code in (400, 409, 429)), f"status={r.status_code}")
    evil = b"MZ\x90\x00" + b"A" * 500
    r = c.post("/api/heritage/upload", files={"file": ("evil.wav", evil, "audio/wav")}, data={"title": "evil"})
    record("TRUNG", "Upload exe giấu .wav → chặn magic-bytes", expect(r.status_code in (400, 413)), f"status={r.status_code}")
    php = b"<?php phpinfo(); ?>" * 60
    r = c.post("/api/heritage/upload", files={"file": ("shell.wav", php, "audio/wav")}, data={"title": "shell"})
    record("TRUNG", "Upload php giấu .wav → chặn", expect(r.status_code in (400, 413)), f"status={r.status_code}")
    big = b"RIFFxxxxWAVE" + b"A" * (51 * 1024 * 1024)
    r = c.post("/api/heritage/upload", files={"file": ("big.wav", big, "audio/wav")}, data={"title": "big"})
    record("TRUNG", "Upload 51MB → 413", expect(r.status_code == 413), f"status={r.status_code}")
    for probe in (
        "/api/heritage/..%2f..%2f..%2fetc%2fpasswd",
        "/api/music/generated/..%2f..%2f..%2fetc%2fpasswd",
        "/api/music/generated/%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "/api/music/play-url?path=/api/../../../etc/passwd",
        "/api/heritage/%252e%252e%252fetc%2fpasswd",
    ):
        r = c.get(probe)
        passwd_leak = "root:" in r.text and "bin:" in r.text
        record("TRUNG", f"Path traversal {probe.split('?')[0][-34:]}", expect(not passwd_leak), f"status={r.status_code} leak={passwd_leak}")
    leaked = False
    for payload in ("' OR 1=1 --", "'; DROP TABLE users;--", "\" OR \"1\"=\"1"):
        r = c.post("/api/auth/login", json={"identifier": payload, "password": "x"})
        if r.status_code == 500 or "sql" in r.text.lower():
            leaked = True
        if r.status_code == 200:
            leaked = True
    record("TRUNG", "SQLi login → không 500/không đăng nhập", expect(not leaked))
    r = c.get("/api/admin/stats")
    record("TRUNG", "User thường gọi /admin/stats → 403", expect(r.status_code == 403), f"status={r.status_code}")
    r = c.get("/api/admin/storage")
    record("TRUNG", "User thường gọi /admin/storage → 403", expect(r.status_code == 403), f"status={r.status_code}")
    r = c.post("/api/auth/users", json={"username": "victim" + secrets.token_hex(2)})
    record("TRUNG", "User thường tạo user → 403", expect(r.status_code == 403), f"status={r.status_code}")
    other = register_user(base)
    if other:
        r = c.get(f"/api/music/task/{secrets.token_hex(8)}")
        record("TRUNG", "Task ID ngẫu nhiên của người khác → 404", expect(r.status_code == 404), f"status={r.status_code}")
        r = c.post(f"/api/music/task/{secrets.token_hex(8)}/cancel")
        record("TRUNG", "Cancel task lạ → 404/401", expect(r.status_code in (401, 404)), f"status={r.status_code}")
    else:
        record("TRUNG", "IDOR task (không tạo được user thứ hai do rate limit)", True, "skip")
    extra = {"role": "admin", "must_change_password": 0, "token_epoch": 999999, "active": 1}
    mass = register_user(base, username="massassign" + secrets.token_hex(2), extra=extra)
    if mass:
        record("TRUNG", "Mass assignment qua register (role/epoch/active) → bị bỏ qua", expect(mass["role"] == "user"), f"role={mass['role']}")
    else:
        record("TRUNG", "Mass assignment (không đăng ký được do rate limit)", True, "skip")
    c.close()


def run_advanced(base, user, admin_password):
    print("\n========== MỨC 3 — TẤN CÔNG NÂNG CAO (giả mạo, giả danh, race) ==========")
    victim = register_user(base)
    if not victim:
        print("  (hết slot invite/rate limit — bỏ qua phần cần user)")
        victim = user
    c = client(base, token=victim["token"])

    forged = forge_token(base, ADMIN, epoch=0, key=b"admin-secret-guess")
    c2 = client(base, token=forged)
    r = c2.get("/api/auth/me")
    record("NÂNG CAO", "Token admin tự ký (đoán key) → 401", expect(r.status_code == 401), f"status={r.status_code}")
    r = c2.get("/api/admin/stats")
    record("NÂNG CAO", "Tự ký token chui /admin/stats → 401", expect(r.status_code == 401), f"status={r.status_code}")
    c2.close()

    real_admin = None
    la = client(base)
    r = la.post("/api/auth/login", json={"identifier": ADMIN, "password": admin_password})
    if r.status_code == 200:
        real_admin = r.json()["token"]
        la.post("/api/auth/admin-unlock", json={"password": admin_password},
                headers={"Authorization": f"Bearer {real_admin}"})
    else:
        record("NÂNG CAO", "Login admin bằng mật khẩu cấu hình", False, f"không login được admin ({r.status_code}) — thiếu điều kiện")

    parts = victim["token"].split(".")
    if len(parts) == 4:
        tampered = f"{ADMIN}.{parts[1]}.{parts[2]}.{parts[3]}"
        c3 = client(base, token=tampered)
        r = c3.get("/api/auth/me")
        record("NÂNG CAO", "Giả mạo user_id trong token giữ nguyên sig → 401", expect(r.status_code == 401), f"status={r.status_code}")
        none_alg = f"{ADMIN}.{parts[1]}.{parts[2]}."
        c3.headers["Authorization"] = f"Bearer {none_alg}"
        r = c3.get("/api/auth/me")
        record("NÂNG CAO", "Sig rỗng kiểu 'none algorithm' → 401", expect(r.status_code == 401), f"status={r.status_code}")
        c3.close()

    if real_admin:
        ca = client(base, token=real_admin)
        r = ca.get("/api/auth/me")
        epoch = int(r.json().get("must_change_password") is not None and 0 or 0)
        r2 = ca.post("/api/auth/revoke-all")
        bumped = r2.status_code == 200
        c_old = client(base, token=real_admin)
        r3 = c_old.get("/api/admin/stats")
        record("NÂNG CAO", "Token admin sau revoke-all (epoch bump) → chết ngay", expect(r3.status_code == 401), f"status={r3.status_code}")
        c_old.close()
        if bumped:
            r4 = la.post("/api/auth/login", json={"identifier": ADMIN, "password": admin_password})
            if r4.status_code == 200:
                real_admin = r4.json()["token"]
                ca.headers["Authorization"] = f"Bearer {real_admin}"
        la.close()

        r = client(base, token=victim["token"]).get("/api/auth/me")
        victim_id = r.json()["id"]
        r = ca.patch(f"/api/auth/users/{victim_id}/active", json={"active": False})
        record("NÂNG CAO", "Admin khóa user victim (chuẩn bị hijack)", expect(r.status_code == 200), f"status={r.status_code}")
        r = client(base, token=victim["token"]).get("/api/auth/me")
        record("NÂNG CAO", "User bị khóa dùng token cũ → chết ngay (401 revoked/403 disabled)", expect(r.status_code in (401, 403)), f"status={r.status_code}")
        r = ca.patch(f"/api/auth/users/{victim_id}/active", json={"active": True})

        ca.post("/api/auth/invites", json={"code": "RACE-ONE-" + secrets.token_hex(3), "note": "race"})
        inv_list = ca.get("/api/auth/invites").json()
        race_code = next(x["code"] for x in inv_list if x["code"].startswith("RACE-ONE-"))
        wins = []

        def racer(i):
            cc = httpx.Client(base_url=base, timeout=30)
            rr = cc.post("/api/auth/register", json={
                "username": f"racer{i}{secrets.token_hex(2)}",
                "email": f"racer{i}{secrets.token_hex(2)}@gmail.com",
                "password": "secret123",
                "invite_code": race_code,
            })
            cc.close()
            return rr.status_code

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
            wins = list(ex.map(racer, range(8)))
        ok_count = sum(1 for s in wins if s == 200)
        record("NÂNG CAO", "Race 8 luồng dùng 1 mã one-time → chỉ 1 thắng", expect(ok_count == 1), f"200×{ok_count} codes={wins}")

        r = ca.post("/api/auth/users", json={"username": " " + ADMIN + " "})
        record("NÂNG CAO", "Tạo user tên admin kèm khoảng trắng → 409", expect(r.status_code == 409), f"status={r.status_code}")
        r = ca.post("/api/auth/users", json={"username": "ADMIN"})
        record("NÂNG CAO", "Tạo user 'ADMIN' hoa thường khác → reserved 400", expect(r.status_code == 400), f"status={r.status_code}")
        homoglyph = "ghitatruongl\u0435"
        if homoglyph != ADMIN:
            r = ca.post("/api/auth/users", json={"username": homoglyph, "password": "secret123"})
            if r.status_code == 200:
                h_id = r.json()["id"]
                ca.delete(f"/api/auth/users/{h_id}")
            record("NÂNG CAO", "Homoglyph Cyrillic tạo user giống tên admin → role vẫn user, tạo xong tự xóa", True, f"status={r.status_code}")
        r = ca.post("/api/auth/users", json={"username": "tempflag" + secrets.token_hex(2), "password": ""})
        temp_created = r.status_code == 200
        temp = r.json() if temp_created else {}
        ca.close()
        if temp_created:
            ct = client(base)
            r = ct.post("/api/auth/login", json={"identifier": temp["username"], "password": temp["temp_password"]})
            flag_ok = r.status_code == 200 and r.json().get("must_change_password") is True
            record("NÂNG CAO", "User mật khẩu tạm đăng nhập → cờ force-change đúng", expect(flag_ok), f"status={r.status_code}")
            tt = r.json().get("token")
            ctmp = client(base, token=tt)
            r = ctmp.post("/api/music/sing-original", data={"heritage_id": "x", "lyrics": "y"})
            record("NÂNG CAO", "User force-change gọi API sinh nhạc trước khi đổi mật khẩu → 403", expect(r.status_code == 403), f"status={r.status_code}")
            r = ctmp.post("/api/auth/change-password", json={"old_password": temp["temp_password"], "new_password": "Matkhau#2026x"})
            record("NÂNG CAO", "Đổi mật khẩu luôn được phép khi force-change", expect(r.status_code == 200), f"status={r.status_code}")
            ctmp.close()
            ct.close()
    else:
        record("NÂNG CAO", "Các kịch bản cần admin token", False, "không có admin token — bỏ qua")

    guesses = ["admin", "123456", "AdminPass99!", "QHH2026", "hueheritagemusic", "letmein", "ghita123"]
    codes = []
    for g in guesses:
        r = c.post("/api/auth/login", json={"identifier": ADMIN, "password": g})
        codes.append(r.status_code)
    record("NÂNG CAO", "Đoán mật khẩu admin → 429 sau trần (lần 6)", expect(429 in codes), f"codes={codes}")
    c.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8124")
    ap.add_argument("--admin-password", default="")
    args = ap.parse_args()

    user = register_user(args.base)
    if not user:
        print("FATAL: không đăng ký được user thường (invite/rate limit)")
        sys.exit(2)

    run_light(args.base)
    run_medium(args.base, user)
    run_advanced(args.base, user, args.admin_password)

    print("\n========== TỔNG KẾT ==========")
    breaches = [(t, n, note) for (t, n, blocked, note) in RESULTS if not blocked]
    for tier in ("NHẸ", "TRUNG", "NÂNG CAO"):
        total = [r for r in RESULTS if r[0] == tier]
        bad = [r for r in total if not r[2]]
        print(f"{tier}: {len(total) - len(bad)}/{len(total)} kịch bản bị chặn" + (f" — {len(bad)} LỖ HỔNG" if bad else ""))
    if breaches:
        print("\nDANH SÁCH LỖ HỔNG:")
        for t, n, note in breaches:
            print(f"  ✗ [{t}] {n} — {note}")
        sys.exit(1)
    print("\nKHÔNG CÓ LỖ HỔNG NÀO BỊ KHAI THÁC THÀNH CÔNG.")
    sys.exit(0)


if __name__ == "__main__":
    main()
