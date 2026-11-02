import secrets
import sys

import httpx

sys.path.insert(0, ".")
from app.api.auth import hash_password, make_token  # noqa: E402
from app.database import crud  # noqa: E402
from app.database.session import SessionLocal  # noqa: E402

PASS, FAIL, FINDINGS = [], [], []


def check(name, ok, note="", severity=None):
    (PASS if ok else FAIL).append(name)
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {name}" + (f" — {note}" if note else ""))
    if not ok and severity:
        FINDINGS.append((severity, name, note))


def main(base):
    c = httpx.Client(base_url=base, timeout=60.0)
    stamp = secrets.token_hex(3)

    print("\n== A. AUTH BYPASS ==")
    r = c.get("/api/auth/me")
    check("me không token → 401", r.status_code == 401)
    r = c.get("/api/auth/me", headers={"Authorization": "Bearer garbage"})
    check("token rác → 401", r.status_code == 401)
    r = c.get("/api/auth/me", headers={"Authorization": "Bearer a.b.c.d"})
    check("token sai shape → 401", r.status_code == 401)

    db = SessionLocal()
    u = "pentest" + stamp
    user = crud.create_user(db, username=u, email=f"{u}@gmail.com", password_hash=hash_password("secret123"))
    uid = user.id
    victim = crud.create_user(db, username="victim" + stamp, email=f"v{stamp}@gmail.com", password_hash=hash_password("secret123"))
    vid = victim.id
    db.close()
    _created_users = [uid, vid]
    tok = make_token(uid, 0)

    forged = tok[:-8] + ("0" * 8 if tok[-8:] != "0" * 8 else "f" * 8)
    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {forged}"})
    check("token giả chữ ký → 401", r.status_code == 401)

    parts = tok.split(".")
    tampered_epoch = f"{parts[0]}.{parts[1]}.{int(parts[2]) + 5}.{parts[3]}"
    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {tampered_epoch}"})
    check("nâng epoch thủ công (giả) → 401", r.status_code == 401)

    victim_tok = make_token(victim.id, 0)
    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {victim_tok}"})
    check("token user khác vẫn hợp lệ (đúng thiết kế stateless)", r.status_code == 200)

    r = c.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    check("token thật → 200", r.status_code == 200)

    print("\n== B. SQL INJECTION ==")
    payloads = ["' OR 1=1 --", "admin'--", "\" OR \"1\"=\"1", "'; DROP TABLE users;--", "1' UNION SELECT 1,2,3--"]
    leak = False
    for p in payloads:
        r = c.post("/api/auth/login", json={"identifier": p, "password": "x"})
        if r.status_code >= 500:
            leak = True
        if r.status_code == 200:
            leak = True
    check("login SQLi 5 payload → không 500/không đăng nhập", not leak)
    r = c.post("/api/auth/login", json={"identifier": "' OR 1=1 --", "password": "x"})
    check("SQLi login trả 401/400 (không lộ lỗi)", r.status_code in (400, 401), f"status={r.status_code}")

    r = c.get("/api/heritage", params={"q": "'; DROP TABLE heritage_items;--"})
    check("search SQLi DROP TABLE → 200 (parameterized)", r.status_code == 200)
    r2 = c.get("/api/heritage", params={"q": ""})
    heritage_items = r2.json().get("items", []) if isinstance(r2.json(), dict) else r2.json()
    check("bảng heritage còn nguyên sau DROP attempt", r2.status_code == 200 and isinstance(heritage_items, list))

    r = c.get("/api/lessons", params={})
    ok = r.status_code == 200
    check("lessons ổn sau SQLi search", ok)

    print("\n== C. PATH TRAVERSAL ==")
    attempts = [
        ("/api/music/generated/..%2f..%2f..%2fserver%2f.env", "encode traversal"),
        ("/api/music/generated/..%2f..%2f.env", "encode traversal 2"),
        ("/api/music/generated/../../.env", "raw traversal"),
        ("/api/music/generated/..%00/.env", "null byte"),
        ("/api/music/generated/%2e%2e%2f%2e%2e%2fserver%2f.env", "double encode"),
        ("/api/music/midi/..%2f..%2f..%2fserver%2f.env", "midi traversal"),
        ("/api/music/restored/..%2f..%2fserver%2f.env", "restored traversal"),
        ("/api/lessons/practice-midi/..%2f..%2fserver%2f.env", "practice-midi traversal"),
        ("/api/lessons/practice-midi/..%5C..%5Cserver%5C.env", "backslash traversal"),
    ]
    for path, label in attempts:
        r = c.get(path)
        if r.status_code == 200:
            check(f"traversal {label} → chặn", False, "TRẢ 200 — RÒ FILE!")
        elif b"SECRET" in r.content or b"DATABASE" in r.content or b"ACESTEP" in r.content:
            check(f"traversal {label} → chặn", False, "NỘI DUNG RÒ!")
        else:
            check(f"traversal {label} → {r.status_code}", r.status_code in (400, 401, 403, 404))

    r = c.get("/api/music/play-url", params={"path": "/api/../../../etc/passwd"})
    check("play-url chặn traversal", r.status_code in (400, 401))

    print("\n== D. UPLOAD ĐỘC ==")
    fake_wav = b"MZ\x90\x00" + b"A" * 500
    r = c.post("/api/heritage/upload", files={"file": ("evil.wav", fake_wav, "audio/wav")}, data={"title": "evil"})
    check("upload exe giấu .wav → chặn magic-bytes", r.status_code in (400, 413))
    php = b"<?php echo 'pwned'; ?>" * 50
    r = c.post("/api/heritage/upload", files={"file": ("shell.wav", php, "audio/wav")}, data={"title": "shell"})
    check("upload php giấu .wav → chặn magic-bytes", r.status_code in (400, 413))
    big = b"RIFFxxxxWAVE" + b"A" * (51 * 1024 * 1024)
    r = c.post("/api/heritage/upload", files={"file": ("big.wav", big, "audio/wav")}, data={"title": "big"})
    check("upload 51MB → 413", r.status_code == 413)
    r = c.post("/api/heritage/upload", files={"file": ("empty.wav", b"", "audio/wav")}, data={"title": "e"})
    check("upload rỗng → 400", r.status_code == 400)

    print("\n== E. SIGNED URL ==")
    r = c.get("/api/music/generated/nonexistent.mp3")
    check("generated không tồn tại (auth off) → 404", r.status_code == 404)

    print("\n== F. RATE LIMIT / BRUTE FORCE ==")
    codes = []
    for i in range(7):
        rr = c.post("/api/auth/login", json={"identifier": f"bruteforce{stamp}", "password": "wrong"})
        codes.append(rr.status_code)
    check("6 sai liên tiếp → 429", 429 in codes, f"codes={codes}")
    rr = c.post("/api/auth/login", json={"identifier": f"BRUTEFORCE{stamp.upper()}", "password": "wrong"})
    check("đổi CHỮ HOA identifier vẫn bị chặn", rr.status_code == 429)
    rr = c.post("/api/auth/login", json={"identifier": f"bruteforce{stamp}", "password": "wrong"}, headers={"X-Forwarded-For": "8.8.8.8"})
    check("giả X-Forwarded-For không né được rate limit", rr.status_code == 429, f"status={rr.status_code}")

    print("\n== G. IDOR / PHÂN QUYỀN (chạy khi auth ON mới đầy đủ) ==")

    print("\n== H. HEADERS & INFO LEAK ==")
    r = c.get("/health")
    check("X-Content-Type-Options nosniff", r.headers.get("X-Content-Type-Options") == "nosniff")
    check("X-Frame-Options DENY", r.headers.get("X-Frame-Options") == "DENY")
    check("Referrer-Policy no-referrer", r.headers.get("Referrer-Policy") == "no-referrer")
    r = c.post("/api/auth/login", json={"identifier": "x", "password": "x"})
    body = r.text.lower()
    check("lỗi đăng nhập không lộ traceback", "traceback" not in body and "sqlalchemy" not in body and ".py" not in body)
    r = c.get("/api/music/models")
    body = r.text
    check("models không lộ URL/địa chỉ engine", "127.0.0.1" not in body and "192.168." not in body and "localhost" not in body)
    r = c.get("/docs")
    is_swagger = r.status_code == 200 and ("swagger" in r.text.lower() or "openapi" in r.text.lower())
    check("/docs không lộ Swagger/OpenAPI (SPA shell)", not is_swagger)

    print("\n== G2. IDOR / PHÂN QUYỀN (auth ON) ==")
    db = SessionLocal()
    admin = crud.get_user(db, "ghitatruongle")
    db.close()
    if admin is not None:
        admin_tok = make_token(admin.id, admin.token_epoch or 0)
        hdr = {"Authorization": f"Bearer {admin_tok}"}
        r = c.get("/api/auth/users", headers=hdr)
        check("admin đọc danh sách TK → 200", r.status_code == 200)
        r = c.get("/api/auth/users")
        check("ẩn danh đọc danh sách TK → 401", r.status_code == 401)
        forUser = c.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
        user_tok = forUser.headers.get("x-token") or (forUser.text if False else None)
        rtok = c.post("/api/auth/login", json={"identifier": u, "password": "secret123"})
        utok = rtok.json().get("token", "")
        r = c.get("/api/auth/users", headers={"Authorization": f"Bearer {utok}"})
        check("user thường đọc danh sách TK → 403", r.status_code == 403)
        r = c.get("/api/auth/invites", headers={"Authorization": f"Bearer {utok}"})
        check("user thường đọc mã mời → 403", r.status_code == 403)
        r = c.get("/api/auth/invites")
        check("ẩn danh đọc mã mời → 401", r.status_code == 401)
        r = c.post("/api/auth/users/x/reset-password", headers={"Authorization": f"Bearer {utok}"})
        check("user thường reset mk hộ → 403", r.status_code == 403)
    else:
        check("bỏ qua IDOR (không có admin trong DB auth-off)", True)

    try:
        db2 = SessionLocal()
        for uid2 in _created_users:
            row = crud.get_user_by_id(db2, uid2)
            if row is not None:
                db2.delete(row)
        db2.commit()
        db2.close()
        print(f"(đã tự dọn {len(_created_users)} tài khoản pentest)")
    except Exception:
        pass

    print()
    print(f"KẾT QUẢ: {len(PASS)} pass / {len(FAIL)} fail")
    if FAIL:
        print("FAIL:", "; ".join(FAIL))
    if FINDINGS:
        print("FINDINGS:", FINDINGS)
    return len(FAIL) == 0


if __name__ == "__main__":
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    ok = main(base)
    sys.exit(0 if ok else 1)
