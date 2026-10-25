import argparse
import io
import math
import statistics
import threading
import time
import wave
from concurrent.futures import ThreadPoolExecutor

import httpx


def make_tone_wav(seconds=2.0, freq=220.0, sr=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        n = int(seconds * sr)
        for i in range(n):
            env = min(1.0, i / (sr * 0.05), (n - i) / (sr * 0.05))
            v = int(8000 * env * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def summarize(name, results, elapsed):
    codes = {}
    lat = []
    for status, ms in results:
        key = str(status)
        codes[key] = codes.get(key, 0) + 1
        if status == 200:
            lat.append(ms)
    line = f"{name}: tổng {len(results)} req trong {elapsed:.1f}s | mã: {codes}"
    if lat:
        lat.sort()
        p50 = statistics.median(lat)
        p95 = lat[max(0, int(len(lat) * 0.95) - 1)]
        line += f" | 200: p50={p50:.0f}ms p95={p95:.0f}ms max={lat[-1]:.0f}ms"
    errors = [c for c in codes if c.startswith("EXC") or (c.isdigit() and int(c) >= 500)]
    if errors:
        line += f" | !!! LỖI: {errors}"
    print(line)
    return codes


def run_concurrent(name, base, n, fn):
    barrier = threading.Barrier(n)
    out = [None] * n

    def worker(i):
        barrier.wait()
        t0 = time.perf_counter()
        try:
            with httpx.Client(base_url=base, timeout=180.0) as c:
                status, ms = fn(c, i)
        except Exception as e:
            status, ms = f"EXC:{type(e).__name__}", (time.perf_counter() - t0) * 1000
        out[i] = (status, ms)

    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=n) as ex:
        list(ex.map(worker, range(n)))
    elapsed = time.perf_counter() - t0
    return summarize(name, out, elapsed), out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--lesson-id", default="")
    ap.add_argument("--n", type=int, default=50)
    args = ap.parse_args()
    base = args.base

    c = httpx.Client(base_url=base, timeout=60.0)
    r = c.get("/health")
    print(f"health trước test: {r.status_code}")
    lesson_id = args.lesson_id
    if not lesson_id:
        lessons = c.get("/api/lessons").json()
        if lessons:
            lesson_id = lessons[0]["id"]
    print(f"lesson dùng cho practice: {lesson_id}\n")

    def timed(c, req):
        t0 = time.perf_counter()
        r = req()
        return r.status_code, (time.perf_counter() - t0) * 1000

    run_concurrent(f"A1. {args.n} GET /health", base, args.n, lambda c, i: timed(c, lambda: c.get("/health")))
    run_concurrent(f"A2. {args.n} GET /api/heritage", base, args.n, lambda c, i: timed(c, lambda: c.get("/api/heritage")))
    run_concurrent(f"A3. {args.n} GET /api/music/models", base, args.n, lambda c, i: timed(c, lambda: c.get("/api/music/models")))
    run_concurrent(f"A4. {args.n} GET /api/lessons", base, args.n, lambda c, i: timed(c, lambda: c.get("/api/lessons")))

    if lesson_id:
        detail = c.get(f"/api/lessons/{lesson_id}")
        print(f"build/đọc chi tiết bài học (1 lần): {detail.status_code}\n")
        wav = make_tone_wav(2.0)
        run_concurrent(
            f"B. {args.n} POST practice câu 0 (CPU DTW)",
            base,
            args.n,
            lambda c, i: timed(c, lambda: c.post(f"/api/lessons/{lesson_id}/practice?section=0", files={"file": ("u.wav", wav, "audio/wav")})),
        )
        run_concurrent(
            f"C. {args.n} GET chi tiết bài học (cache)",
            base,
            args.n,
            lambda c, i: timed(c, lambda: c.get(f"/api/lessons/{lesson_id}")),
        )

    small = make_tone_wav(1.0)
    run_concurrent(
        f"D. {args.n} POST analyze-pitch (burst, kỳ vọng 429 sau 30)",
        base,
        args.n,
        lambda c, i: timed(c, lambda: c.post("/api/music/analyze-pitch", files={"file": ("a.wav", small, "audio/wav")})),
    )

    r = c.get("/health")
    print(f"\nhealth sau test: {r.status_code}")
    c.close()


if __name__ == "__main__":
    main()
