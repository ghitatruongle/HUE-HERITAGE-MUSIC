import argparse
import io
import json
import math
import secrets
import time
import wave

import httpx

PASS = []
FAIL = []


def check(name, ok, note=""):
    (PASS if ok else FAIL).append(name)
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {name}" + (f" — {note}" if note else ""))


def make_tone_wav(freqs, sr=16000, tone_len=2.0, gap=1.2):
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
                w.writeframes((0).to_bytes(2, "little", signed=True))
    return buf.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--cleanup-token", default="")
    args = ap.parse_args()
    c = httpx.Client(base_url=args.base, timeout=180.0)

    r = c.get("/health")
    check("health 200", r.status_code == 200, r.json().get("version", ""))

    import sqlite3
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(_P(__file__).resolve().parents[1]))
    from app.database.session import SessionLocal
    from app.database import crud
    _db = SessionLocal()
    _code = "SMOKE-" + secrets.token_hex(3)
    crud.create_invite_code(_db, _code, "smoke debug")
    _db.close()

    stamp = secrets.token_hex(3)
    username = f"debugsmoke{stamp}"

    r = c.post(
        "/api/auth/register",
        json={
            "username": username,
            "email": f"{username}@gmail.com",
            "password": "secret123",
            "invite_code": _code,
        },
    )
    check("register (file code) 200 + role=user", r.status_code == 200 and r.json().get("role") == "user")

    r = c.post("/api/auth/login", json={"identifier": username, "password": "secret123"})
    check("login 200 + role=user", r.status_code == 200 and r.json().get("role") == "user")

    r = c.get("/api/auth/me", headers={"Authorization": "Bearer " + r.json()["token"]})
    check("me 200 + role", r.status_code == 200 and r.json().get("role") == "user")

    r = c.get("/api/auth/users")
    check("auth/users without token 401", r.status_code == 401)

    audio = make_tone_wav([220.0, 330.0])
    r = c.post(
        "/api/heritage/upload",
        files={"file": ("smoke_lesson.wav", audio, "audio/wav")},
        data={
            "title": f"Bai hoc kiem thu {stamp}",
            "type": "Ca Hue",
            "lyrics_with_ornaments": "Câu một tình tang\nCâu hai a í a",
            "mode_system": "Nam",
        },
    )
    lesson_ok = r.status_code == 200
    check("heritage upload (ornaments+mode_system)", lesson_ok)
    lesson_id = r.json().get("id", "") if lesson_ok else ""

    r = c.get("/api/lessons")
    ids = [x["id"] for x in r.json()] if r.status_code == 200 else []
    check("lessons list 200 + contains upload", r.status_code == 200 and lesson_id in ids)

    r = c.get(f"/api/lessons/{lesson_id}")
    sections = r.json().get("sections", []) if r.status_code == 200 else []
    check(
        "lesson detail >=2 sections + contour",
        r.status_code == 200 and len(sections) >= 2 and bool(r.json().get("contour", {}).get("f0")),
        f"{len(sections)} câu",
    )

    r = c.post(
        f"/api/lessons/{lesson_id}/practice?section=0",
        files={"file": ("u.wav", make_tone_wav([220.0]), "audio/wav")},
    )
    body = r.json() if r.status_code == 200 else {}
    same_len = len(body.get("sample", {}).get("f0", [])) == len(body.get("user_warped", {}).get("f0", []))
    check(
        "lesson practice 200 + overlay same length + metrics",
        r.status_code == 200 and same_len and "score" in body.get("metrics", {}),
        f"score={body.get('metrics', {}).get('score')}",
    )

    r = c.get("/api/lessons/scales")
    check("scales list", r.status_code == 200 and "bac" in [s["id"] for s in r.json()])

    r = c.get("/api/lessons/scales/bac/reference.wav")
    check("scale reference RIFF", r.status_code == 200 and r.content[:4] == b"RIFF", f"{len(r.content)} bytes")

    r = c.post(
        "/api/lessons/scales/bac/practice",
        files={"file": ("s.wav", make_tone_wav([261.63, 293.66, 349.23, 392.0, 440.0], tone_len=1.0, gap=0.2), "audio/wav")},
    )
    check("scale practice on-scale score>=70", r.status_code == 200 and r.json().get("score", 0) >= 70, str(r.json().get("score")))

    if lesson_ok:
        r = c.get("/api/music/play-url", params={"path": f"/api/heritage/{lesson_id}/audio"})
        check("play-url without auth-mode works (auth off)", r.status_code == 200 and "s=" in r.json().get("url", ""))

    r = c.post("/api/music/sing-original", params={"heritage_id": lesson_id, "duration": 30})
    blocked = r.status_code == 200 and r.json().get("status") == "blocked"
    tid = r.json().get("id", "") if r.status_code == 200 else ""
    check("generate engine-offline -> blocked task", blocked)

    if tid:
        with c.stream("GET", f"/api/music/task/{tid}/events", headers={"Accept": "text/event-stream"}) as s:
            events = []
            for line in s.iter_lines():
                if line.startswith("data: "):
                    events.append(line[6:])
            check(
                "SSE returns terminal event then closes",
                bool(events) and '"blocked"' in events[-1],
                f"{len(events)} event(s)",
            )

    r = c.post("/api/music/task/nonexistent-id/cancel")
    check("cancel unknown 404", r.status_code == 404)

    ok200 = 0
    got429 = None
    for i in range(35):
        rr = c.post("/api/music/sing-original", params={"heritage_id": "x"})
        if rr.status_code == 429:
            got429 = i + 1
            break
        ok200 += 1
    r = c.get("/health")
    check(
        "heavy rate limit 429 after 30 then health still OK",
        got429 is not None and r.status_code == 200,
        f"429 tại lần thứ {got429}",
    )

    print()
    print(f"KẾT QUẢ: {len(PASS)} pass / {len(FAIL)} fail")
    if FAIL:
        print("FAIL:", "; ".join(FAIL))
        raise SystemExit(1)
    print(f" lesson_id={lesson_id} user_debug={username} (ghi lại để dọn dẹp sau)")


if __name__ == "__main__":
    main()
