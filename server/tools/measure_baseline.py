import argparse
import io
import math
import statistics
import time
import wave

import httpx


def make_tone_wav(seconds, freq, sr=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        n = int(seconds * sr)
        for i in range(n):
            env = 0.6 + 0.4 * math.sin(2 * math.pi * 0.5 * i / sr)
            v = int(9000 * env * math.sin(2 * math.pi * freq * i / sr))
            frames += v.to_bytes(2, "little", signed=True)
        w.writeframes(bytes(frames))
    return buf.getvalue()


def run_case(client, label, fn, repeats):
    results = []
    status = ""
    for _ in range(repeats):
        t0 = time.perf_counter()
        ok, status = fn(client)
        elapsed = (time.perf_counter() - t0) * 1000.0
        if ok:
            results.append(elapsed)
        else:
            results.append(float("nan"))
    valid = [v for v in results if v == v]
    if valid:
        med = statistics.median(valid)
        lo = min(valid)
        hi = max(valid)
        return f"| {label} | {len(valid)}/{repeats} | {med:.0f} | {lo:.0f} | {hi:.0f} | {status} |"
    return f"| {label} | 0/{repeats} | - | - | - | {status} |"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--repeats", type=int, default=5)
    ap.add_argument("--dsp-repeats", type=int, default=3)
    args = ap.parse_args()

    client = httpx.Client(base_url=args.base, timeout=120.0)

    def get_health(c):
        r = c.get("/health")
        return r.status_code == 200, f"GET /health -> {r.status_code}"

    def get_models(c):
        r = c.get("/api/music/models")
        return r.status_code == 200, f"GET /api/music/models -> {r.status_code}"

    def post_analyze(c):
        data = make_tone_wav(15.0, 440.0)
        r = c.post("/api/music/analyze-pitch", files={"file": ("t.wav", data, "audio/wav")})
        return r.status_code == 200, f"POST analyze-pitch 15s -> {r.status_code}"

    def post_compare(c):
        a = make_tone_wav(10.0, 440.0)
        b = make_tone_wav(10.0, 466.16)
        r = c.post(
            "/api/music/compare",
            files=[
                ("sample", ("a.wav", a, "audio/wav")),
                ("user", ("b.wav", b, "audio/wav")),
            ],
        )
        return r.status_code == 200, f"POST compare 2x10s -> {r.status_code}"

    def post_transcribe_dsp(c):
        data = make_tone_wav(10.0, 330.0)
        r = c.post(
            "/api/music/transcribe",
            files={"file": ("t.wav", data, "audio/wav")},
            data={"engine": "dsp", "bpm": "60"},
        )
        return r.status_code == 200, f"POST transcribe dsp 10s -> {r.status_code}"

    def post_generate(c):
        r = c.post(
            "/api/music/sing-original",
            params={"heritage_id": "none", "vocal": "Nữ", "duration": 30},
        )
        return r.status_code in (200, 400), f"POST sing-original (submit) -> {r.status_code}"

    rows = []
    rows.append(run_case(client, "GET /health", get_health, args.repeats))
    rows.append(run_case(client, "GET /api/music/models", get_models, args.repeats))
    rows.append(run_case(client, "POST analyze-pitch (15s WAV)", post_analyze, args.dsp_repeats))
    rows.append(run_case(client, "POST compare (2x10s WAV)", post_compare, args.dsp_repeats))
    rows.append(run_case(client, "POST transcribe dsp (10s WAV)", post_transcribe_dsp, args.dsp_repeats))
    rows.append(run_case(client, "POST sing-original (submit)", post_generate, args.dsp_repeats))
    print("| Trường hợp | OK | Trung vị (ms) | Nhất (ms) | Chậm nhất (ms) | Ghi chú |")
    print("|---|---|---|---|---|---|")
    for row in rows:
        print(row)


if __name__ == "__main__":
    main()
