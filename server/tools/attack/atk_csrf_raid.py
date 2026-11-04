import secrets
import sys
import threading
import time

import httpx

EVIL = "https://trang-doc-hai.example"

MUTATION_ROUTES = [
    ("POST", "/api/heritage/upload", "multipart"),
    ("POST", "/api/auth/register", "json"),
    ("POST", "/api/auth/invites", "json"),
    ("DELETE", "/api/auth/invites/test-id", "json"),
    ("POST", "/api/auth/change-password", "json"),
    ("POST", "/api/admin/maintenance/cleanup", "json"),
    ("PATCH", "/api/admin/storage/00000000-0000-0000-0000-000000000000/visibility", "json"),
    ("POST", "/api/admin/users", "json"),
    ("DELETE", "/api/admin/users/00000000-0000-0000-0000-000000000000", "json"),
    ("POST", "/api/music/sing-original", "json"),
    ("POST", "/api/auth/admin-unlock", "json"),
]

EVIL_HEADERS = {"Origin": EVIL, "Referer": EVIL + "/tan-cong"}


def sample_body(method, content_kind):
    if method == "DELETE":
        return None, None
    if content_kind == "json":
        return {"x": "1"}, "application/json"
    if content_kind == "form":
        return "title=pwned&x=1", "application/x-www-form-urlencoded"
    if content_kind == "text":
        return '{"title":"pwned"}', "text/plain"
    if content_kind == "multipart":
        return None, None
    return None, None


class Raid:
    def __init__(self):
        self.lock = threading.Lock()
        self.hits = []
        self.counts = {}
        self.statuses = {}
        self.cookies = {}

    def record(self, cls, status):
        with self.lock:
            self.counts[cls] = self.counts.get(cls, 0) + 1
            self.statuses[status] = self.statuses.get(status, 0) + 1

    def hit(self, cls, detail):
        with self.lock:
            self.hits.append((cls, detail[:200]))


def persona_no_auth(raid, base, stop):
    client = httpx.Client(timeout=15)
    i = 0
    while not stop.is_set():
        method, route, kind = MUTATION_ROUTES[i % len(MUTATION_ROUTES)]
        i += 1
        for content in ("json", "form", "text"):
            body, ct = sample_body(method, content)
            headers = dict(EVIL_HEADERS)
            if ct:
                headers["Content-Type"] = ct
            for token_mode in ("none", "empty", "forged"):
                if token_mode == "empty":
                    headers["Authorization"] = "Bearer "
                elif token_mode == "forged":
                    headers["Authorization"] = "Bearer " + secrets.token_hex(16)
                else:
                    headers.pop("Authorization", None)
                try:
                    if method == "POST" and kind == "multipart" and content == "multipart":
                        r = client.request(method, base + route, files={"file": ("x.wav", b"RIFFxxxxWAVE", "audio/wav")},
                                           data={"title": "pwned"}, headers=headers, timeout=15)
                    elif body is not None:
                        r = client.request(method, base + route, content=body, headers=headers, timeout=15)
                    else:
                        r = client.request(method, base + route, json={"x": "1"}, headers=headers, timeout=15)
                except Exception:
                    raid.record("no-auth-mutation", 0)
                    continue
                raid.record("no-auth-mutation", r.status_code)
                if 200 <= r.status_code < 300:
                    raid.hit("no-auth-mutation", f"{method} {route} THÀNH CÔNG KHÔNG TOKEN ({content}/{token_mode}): {r.text[:80]}")
        time.sleep(0.2)
    client.close()


def persona_cors(raid, base, stop):
    client = httpx.Client(timeout=15)
    probe_paths = ["/api/heritage", "/api/auth/login", "/api/heritage/upload", "/api/admin/stats", "/api/lessons"]
    while not stop.is_set():
        for path in probe_paths:
            try:
                r = client.options(base + path, headers={
                    "Origin": EVIL,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "content-type,authorization",
                }, timeout=15)
                raid.record("cors-probe", r.status_code)
                acao = r.headers.get("access-control-allow-origin", "")
                acac = r.headers.get("access-control-allow-credentials", "")
                if acao == EVIL:
                    raid.hit("cors-probe", f"ACAO PHẢN CHIẾU evil origin trên {path} (credentials={acac or 'khong'})")
                if acao == "*" and acac.lower() == "true":
                    raid.hit("cors-probe", f"ACAO=* + allow-credentials=true trên {path} — CSRF enabler")
                r2 = client.get(base + path, headers={"Origin": EVIL}, timeout=15)
                raid.record("cors-probe", r2.status_code)
                acao2 = r2.headers.get("access-control-allow-origin", "")
                if acao2 == EVIL:
                    raid.hit("cors-probe", f"GET {path} phản chiếu evil origin vào ACAO")
            except Exception:
                raid.record("cors-probe", 0)
        time.sleep(0.5)
    client.close()


def persona_cookie_hunt(raid, base, stop, invite):
    client = httpx.Client(timeout=15)
    while not stop.is_set():
        u = "csrf" + secrets.token_hex(3)
        try:
            r = client.post(f"{base}/api/auth/register", json={
                "username": u, "email": f"{u}@gmail.com",
                "password": "secret123", "invite_code": invite,
            }, timeout=15)
            raid.record("cookie-hunt", r.status_code)
            for k, v in client.cookies.items():
                if k not in raid.cookies:
                    with raid.lock:
                        raid.cookies[k] = v[:40]
                    raid.hit("cookie-hunt", f"server GÁN COOKIE '{k}' — bề mặt CSRF mới cần soát")
            r2 = client.post(f"{base}/api/auth/login", json={
                "identifier": u, "password": "secret123"}, timeout=15)
            raid.record("cookie-hunt", r2.status_code)
            for k, v in client.cookies.items():
                if k not in raid.cookies:
                    with raid.lock:
                        raid.cookies[k] = v[:40]
                    raid.hit("cookie-hunt", f"LOGIN GÁN COOKIE '{k}' — nếu là phiên auth thì CSRF khả thi")
            if r2.status_code == 200:
                tok = r2.json().get("token", "")
                r3 = client.post(f"{base}/api/admin/maintenance/cleanup",
                                 cookies={k: v for k, v in client.cookies.items()},
                                 headers=dict(EVIL_HEADERS), timeout=15)
                raid.record("cookie-hunt", r3.status_code)
                if r3.status_code == 200:
                    raid.hit("cookie-hunt", f"REQUEST ĐỔI TRẠNG THÁI THÀNH CÔNG CHỈ NHỜ COOKIE (không Bearer) — CSRF THẬT")
            if r.status_code == 429 or r2.status_code == 429:
                time.sleep(3)
        except Exception:
            raid.record("cookie-hunt", 0)
        time.sleep(0.3)
    client.close()


def persona_state_get(raid, base, stop, ta=""):
    client = httpx.Client(timeout=15)
    combos = [
        "/api/heritage?delete=1", "/api/heritage?action=drop&table=users",
        "/api/auth/users?purge=1", "/api/lessons?reset=1",
        "/api/admin/stats?reset=1", "/api/task?cancel=all",
        "/api/music/models?action=reload",
    ]
    baseline = None
    try:
        if ta:
            r = httpx.get(f"{base}/api/admin/stats", params={"refresh": 1},
                          headers={"Authorization": f"Bearer {ta}"}, timeout=15)
            if r.status_code == 200:
                baseline = r.json().get("heritage", {}).get("total")
    except Exception:
        pass
    while not stop.is_set():
        for path in combos:
            for origin in (EVIL, None):
                headers = {"Origin": origin} if origin else {}
                try:
                    r = client.get(base + path, headers=headers, timeout=15)
                except Exception:
                    raid.record("state-get", 0)
                    continue
                raid.record("state-get", r.status_code)
        time.sleep(0.4)
    if baseline is not None:
        try:
            r = httpx.get(f"{base}/api/admin/stats", params={"refresh": 1},
                          headers={"Authorization": f"Bearer {ta}"}, timeout=15)
            after = r.json().get("heritage", {}).get("total") if r.status_code == 200 else None
            if after is not None and after != baseline:
                raid.hit("state-get", f"STATE DRIFT thật: heritage total {baseline} -> {after} sau khi bắn GET lạ")
            else:
                print(f"  [state-get] đối chiếu trạng thái: heritage total {baseline} -> {after} — KHÔNG THAY ĐỔI (các GET lạ bị bỏ qua)")
        except Exception as e:
            print(f"  [state-get] không đối chiếu được: {type(e).__name__}")
    client.close()


def persona_browser_form(raid, base, stop):
    client = httpx.Client(timeout=15)
    forms = [
        ("POST", "/api/heritage/upload", {"file": ("pwned.wav", b"RIFFxxxxWAVEfmt ", "audio/wav")}, {"title": "pwned"}),
        ("POST", "/api/auth/login", None, {"identifier": "ghitatruongle", "password": "x"}),
        ("POST", "/api/auth/invites", None, {"x": "1"}),
        ("POST", "/api/admin/maintenance/cleanup", None, {"x": "1"}),
    ]
    i = 0
    while not stop.is_set():
        method, path, files, data = forms[i % len(forms)]
        i += 1
        content_types = ("application/x-www-form-urlencoded", "text/plain")
        try:
            if files:
                r = client.request(method, base + path, files=files, data=data,
                                   headers=dict(EVIL_HEADERS), timeout=15)
            else:
                encoded = "&".join(f"{k}={v}" for k, v in data.items())
                for ct in content_types:
                    r = client.request(method, base + path, content=encoded,
                                       headers={**EVIL_HEADERS, "Content-Type": ct}, timeout=15)
                    raid.record("browser-form", r.status_code)
                    if 200 <= r.status_code < 300 and "login" not in path:
                        raid.hit("browser-form", f"{method} {path} form chéo trang THÀNH CÔNG không token: {r.text[:80]}")
                    if "login" in path and r.status_code == 200:
                        sid = r.headers.get("set-cookie", "")
                        if sid:
                            raid.hit("browser-form", f"login CSRF gắn phiên cookie: {sid[:80]}")
                    time.sleep(0.1)
                continue
            raid.record("browser-form", r.status_code)
            if 200 <= r.status_code < 300:
                raid.hit("browser-form", f"{method} {path} form chéo trang THÀNH CÔNG không token")
        except Exception:
            raid.record("browser-form", 0)
        time.sleep(0.3)
    client.close()


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--seconds", type=int, default=45)
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--admin-password", default="")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    raid = Raid()
    print(f"CSRF RAID 6 persona dong thoi trong {args.seconds}s — target {base}")
    assert httpx.get(base + "/health", timeout=10).status_code == 200, "server khong san sang"

    stop = threading.Event()
    personas = [
        ("no-auth-mutation", persona_no_auth, ()),
        ("cors-probe", persona_cors, ()),
        ("cookie-hunt", persona_cookie_hunt, (args.invite,)),
        ("state-get", persona_state_get, (args.admin_password,)),
        ("browser-form", persona_browser_form, ()),
    ]
    threads = []
    for name, fn, extra in personas:
        th = threading.Thread(target=fn, args=(raid, base, stop, *extra), daemon=True)
        threads.append(th)
    for th in threads:
        th.start()
    t0 = time.time()
    while time.time() - t0 < args.seconds:
        time.sleep(2)
    stop.set()
    for th in threads:
        th.join(timeout=5)

    print(f"\n== TONG KET {int(time.time() - t0)}s ==")
    total = 0
    for name, _, _ in personas:
        n = raid.counts.get(name, 0)
        total += n
        hits = sum(1 for cn, _ in raid.hits if cn == name)
        print(f"  {name:<18} requests={n:<7} hits={hits}")
    print(f"  phan bo status: {dict(sorted(raid.statuses.items()))}")
    if raid.cookies:
        print(f"  cookie server gan: {raid.cookies}")
    else:
        print("  cookie: server KHONG gan cookie nao (khong co moi CSRF AutoSend)")
    print(f"  TONG requests={total} | HITS={len(raid.hits)}")
    for cn, d in raid.hits[:12]:
        print(f"  !!! [{cn}] {d}")

    ok = len(raid.hits) == 0
    print(f"\nVERDICT CSRF-RAID: {'CLEAN — KHONG CO LO HONG' if ok else 'CO PHAT HIEN'} | requests={total} | hits={len(raid.hits)}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
