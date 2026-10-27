"""Mô phỏng người dùng ở các tầng tải — mỗi worker một token riêng (bucket rate limit riêng như thực tế)."""
import argparse
import io
import json
import math
import threading
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

stop = threading.Event()
lock = threading.Lock()


def tone(freq, sr=16000, sec=1.5):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for i in range(int(sr * sec)):
            v = int(6000 * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def worker(idx, base, lesson_id, token, stats, max_req):
    c = httpx.Client(base_url=base, timeout=20.0,
                     headers={"Authorization": f"Bearer {token}"} if token else {})
    lat = []
    n = 0
    while not stop.is_set() and n < max_req:
        n += 1
        t0 = time.perf_counter()
        try:
            k = n % 6
            if k == 0:
                r = c.get("/api/heritage", params={"limit": 20})
            elif k == 1 and lesson_id:
                r = c.get(f"/api/lessons/{lesson_id}")
            elif k == 2:
                r = c.get("/api/music/models")
            elif k == 3 and lesson_id:
                r = c.post(f"/api/lessons/{lesson_id}/practice?section=0",
                           files={"file": ("u.wav", tone(280 + idx % 80), "audio/wav")})
            elif k == 4:
                r = c.get("/api/lessons/scales")
            else:
                r = c.get("/api/heritage")
            ms = (time.perf_counter() - t0) * 1000
            with lock:
                if r.status_code >= 500:
                    stats["5xx"] += 1
                elif r.status_code == 429:
                    stats["429"] += 1
                lat.append(ms)
                stats["n"] += 1
            if r.status_code == 429:
                time.sleep(1.2)
        except Exception:
            with lock:
                stats["exc"] += 1
    c.close()
    with lock:
        stats["lat"].extend(lat)
        stats["done"] += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8010")
    ap.add_argument("--tier", type=int, default=50)
    ap.add_argument("--seconds", type=int, default=15)
    ap.add_argument("--lesson-id", default="")
    ap.add_argument("--token", default="")
    ap.add_argument("--tokens-file", default="")
    ap.add_argument("--max-req", type=int, default=400)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    stop = threading.Event()
    stats = {"lat": [], "5xx": 0, "429": 0, "exc": 0, "n": 0, "done": 0}

    tokens = [args.token] if args.token else [""]
    if args.tokens_file:
        extra = [l.strip() for l in Path(args.tokens_file).read_text().splitlines() if l.strip()]
        if extra:
            tokens = extra
    print(f"tokens: {len(tokens)} (mỗi user một bucket riêng như thực tế)", flush=True)

    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=args.tier) as ex:
        futs = [ex.submit(worker, i, args.base, args.lesson_id,
                          tokens[i % len(tokens)], stats, args.max_req)
                for i in range(args.tier)]
        time.sleep(args.seconds)
        stop.set()
        for f in futs:
            f.result(timeout=300)
    dur = time.perf_counter() - t0

    lat = sorted(stats["lat"])
    p50 = lat[len(lat) // 2] if lat else 0
    p95 = lat[int(len(lat) * 0.95)] if lat else 0
    mx = lat[-1] if lat else 0
    out = {
        "tier": args.tier, "requests": stats["n"], "done": stats["done"], "dur_s": round(dur, 1),
        "5xx": stats["5xx"], "429": stats["429"], "exc": stats["exc"],
        "p50_ms": round(p50), "p95_ms": round(p95), "max_ms": round(mx),
    }
    print(json.dumps(out), flush=True)
    if args.out:
        Path(args.out).write_text(json.dumps(out), encoding="utf-8")


if __name__ == "__main__":
    main()
