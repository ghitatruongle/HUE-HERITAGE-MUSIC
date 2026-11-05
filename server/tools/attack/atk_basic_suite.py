"""HACKER BASIC-SUITE — tấn công tổng hợp dạng cơ bản: method matrix, path normalization,
docs exposure, JSON abuse (depth bomb / malformed / type confusion), header lies, static probe."""
import argparse
import json
import secrets
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import client, register_user, verdict  # noqa: E402

INVITE = "CHAOS-CODE"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8011")
    ap.add_argument("--rounds", type=int, default=2)
    args = ap.parse_args()
    base = args.base

    attempts = 0
    breaches = []

    u = register_user(base)
    tok = u.get("token", "") if u else ""
    auth = {"Authorization": f"Bearer {tok}"} if tok else {}
    c = client(base, tok)

    print("== B1. METHOD MATRIX (không được có 5xx) ==")
    for path in ("/health", "/api/heritage", "/api/auth/me", "/api/lessons", "/api/admin/stats"):
        for method in ("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"):
            r = c.request(method, path)
            attempts += 1
            if r.status_code >= 500 and r.status_code != 503:
                breaches.append((f"{method} {path} → {r.status_code}", "5xx trên method thường"))

    print("== B2. PATH NORMALIZATION (//, /./, /../, %2e, %00, dot-suffix) ==")
    paths = [
        "//api/heritage", "/api//heritage", "/api/./heritage", "/api/heritage/.",
        "/api/heritage/..", "/api/%2e%2e/heritage", "/api/heritage%00", "/api/heritage.",
        "/api/heritage%20", "/./../server/.env", "/%2e%2e/%2e%2e/.env", "/..%2f..%2f.env",
        "/api/heritage/../../../.env", "//../.env",
    ]
    for p in paths:
        r = c.get(p)
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"path {p} → {r.status_code}", "5xx"))
        if r.status_code == 200 and (".env" in p or ".." in p) and "SECRET" in r.text[:2000]:
            breaches.append((f"path {p} lộ .env", r.text[:60]))

    print("== B3. DOCS EXPOSURE (Swagger/ReDoc/openapi thật phải vắng khi ENABLE_DOCS tắt) ==")
    for p in ("/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"):
        r = c.get(p)
        attempts += 1
        body = r.text[:600]
        if r.status_code == 200 and ("Swagger UI" in body or "ReDoc" in body or '"openapi"' in body):
            breaches.append((f"{p} exposure", "docs thật mở khi production"))

    print("== B4. JSON ABUSE (depth bomb, malformed, unicode key, invalid utf8) ==")
    bomb = "[" * 20000 + "]" * 20000
    bodies = {
        "depth-bomb": bomb.encode(),
        "malformed": b"{not json at all",
        "truncated": b'{"identifier": "x", "passw',
        "bom-utf8": b"\xef\xbb\xbf{\"identifier\":\"x\",\"password\":\"y\"}",
        "invalid-utf8": b'{"identifier": "\xff\xfe", "password": "y"}',
        "json-strings-only": b'["a","b","c"]',
        "json-null": b"null",
    }
    for label, body in bodies.items():
        r = httpx.post(
            base + "/api/auth/login",
            content=body,
            headers={"Content-Type": "application/json"},
            timeout=30.0,
        )
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"JSON {label} → {r.status_code}", "500 thay vì 4xx"))
        if r.status_code == 200:
            breaches.append((f"JSON {label} login thành công?!", body[:40]))

    print("== B5. TYPE CONFUSION QUERY (mảng, object, số thực, âm, khổng lồ) ==")
    for qs in (
        {"limit": ["1", "2"]},
        {"limit": "1e999"},
        {"limit": "-99999999999999"},
        {"offset": "9" * 30},
        {"q": ["a", "b"]},
        {"visibility": "admin_only"},
        {"owner_user_id": "*"},
    ):
        r = c.get("/api/heritage", params=qs)
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"query {qs} → {r.status_code}", "5xx"))
    r = c.get("/api/heritage", params={"visibility": "admin_only"})
    if r.status_code == 200:
        rows = r.json().get("items", [])
        hidden = [x for x in rows if x.get("visibility") == "admin_only"]
        if hidden:
            breaches.append(("query visibility lọc tường minh thất bại", f"{len(hidden)} item ẩn lộ qua query"))

    print("== B6. HEADER LIES (Authorization sai kiểu, trùng, dài, XFF giả) ==")
    weird_auths = [
        ("Basic dXNlcjpwYXNz", "scheme Basic"),
        ("Bearer", "Bearer rỗng"),
        ("Bearer " + "A" * 8000, "Bearer 8KB"),
        ("bearer " + tok.lower().replace("-", "x") if tok else "bearer x", "bearer chữ thường"),
        ("Bearer " + tok + " extra" if tok else "Bearer x", "Bearer thừa phần"),
    ]
    for hv, label in weird_auths:
        r = httpx.get(base + "/api/auth/me", headers={"Authorization": hv}, timeout=30.0)
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"auth {label} → {r.status_code}", "5xx"))
    r = httpx.get(
        base + "/api/auth/me",
        headers=[("Authorization", f"Bearer {tok}"), ("Authorization", "Bearer junksig.junk.junk.junk")],
        timeout=30.0,
    )
    attempts += 1
    if r.status_code >= 500 and r.status_code != 503:
        breaches.append((f"double Authorization → {r.status_code}", "5xx"))
    for xff in ("1.2.3.4", "1.2.3.4, 5.6.7.8", "unknown"):
        r = httpx.get(base + "/health", headers={"X-Forwarded-For": xff}, timeout=30.0)
        attempts += 1
        if r.status_code != 200:
            breaches.append((f"XFF {xff} làm hỏng health", r.status_code))

    print("== B7. CONTENT-TYPE LIES (JSON payload mang text/plain / multipart) ==")
    r = httpx.post(
        base + "/api/auth/login",
        content=b'{"identifier":"x","password":"y"}',
        headers={"Content-Type": "text/plain"},
        timeout=30.0,
    )
    attempts += 1
    if r.status_code >= 500 and r.status_code != 503:
        breaches.append((f"login text/plain → {r.status_code}", "5xx"))
    r = httpx.post(
        base + "/api/auth/login",
        files={"identifier": (None, "x"), "password": (None, "y")},
        timeout=30.0,
    )
    attempts += 1
    if r.status_code >= 500 and r.status_code != 503:
        breaches.append((f"login multipart → {r.status_code}", "5xx"))

    print("== B8. STATIC / WEB PROBES (maps, version, service worker, assets traversal) ==")
    for p in (
        "/version.json", "/main.dart.js.map", "/flutter_bootstrap.js",
        "/assets/../.env", "/assets/%2e%2e/.env", "/canvaskit/", "/icons/",
        "/main.dart.js", "/index.html",
    ):
        r = c.get(p)
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"static {p} → {r.status_code}", "5xx"))

    print("== B9. UNICODE/NULL IN SEARCH (query q) ==")
    for q in ("酶%00", "%c0%ae", "👍" * 200, "a" * 5000, "'\"; DROP", "\x00\x01\x02"):
        r = c.get("/api/heritage", params={"q": q})
        attempts += 1
        if r.status_code >= 500 and r.status_code != 503:
            breaches.append((f"q unicode {q[:20]!r} → {r.status_code}", "5xx"))

    print("== B10. HEAD/OPTIONS + CORS PREFLIGHT CƠ BẢN ==")
    r = httpx.options(
        base + "/api/auth/login",
        headers={"Origin": "http://evil.example", "Access-Control-Request-Method": "POST"},
        timeout=30.0,
    )
    attempts += 1
    if r.status_code >= 500 and r.status_code != 503:
        breaches.append((f"preflight evil origin → {r.status_code}", "5xx"))
    allow = r.headers.get("access-control-allow-origin", "")
    if allow == "*" and r.status_code == 200:
        pass
    r = httpx.get(base + "/api/auth/me", headers={"Origin": "http://evil.example", **auth}, timeout=30.0)
    attempts += 1
    if r.status_code >= 500 and r.status_code != 503:
        breaches.append(("GET evil origin → 5xx", ""))

    print(f"\n(attempts={attempts})")
    verdict("BASIC-SUITE", attempts, breaches)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"mat ket noi client-side duoi tai: {type(e).__name__}: {e} — BI CHAN, khong phai loi server")
        sys.exit(2)
