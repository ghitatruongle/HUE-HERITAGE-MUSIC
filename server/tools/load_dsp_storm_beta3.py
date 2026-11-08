import argparse
import io
import math
import statistics
import sys
import threading
import time
import wave

import httpx


def make_wav(seconds, sr=44100, base=220.0):
    frames = bytearray()
    total = int(sr * seconds)
    for i in range(total):
        t = i / sr
        env = 0.4 + 0.6 * math.sin(math.pi * min(1.0, t / max(seconds, 0.001)))
        unvoiced = (i % (sr * 2)) < (sr * 0.3)
        if unvoiced:
            v = 0.15 * math.sin(2 * math.pi * 3.0 * t)
        else:
            v = 0.5 * math.sin(2 * math.pi * base * t) + 0.2 * math.sin(2 * math.pi * base * 2 * t) + 0.05 * math.sin(2 * math.pi * base * 3.7 * t)
        s = int(max(-1.0, min(1.0, v * env)) * 32767)
        frames += s.to_bytes(2, "little", signed=True)
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(bytes(frames))
    w.close()
    return bio.getvalue()


class Storm:
    def __init__(self, base, users, rounds, invite):
        self.base = base
        self.users = users
        self.rounds = rounds
        self.invite = invite
        self.lock = threading.Lock()
        self.results = {}
        self.status_5xx = 0
        self.status_other = 0
        self.health_bad = 0
        self.health_max_ms = 0.0
        self.errors = []
        self.stop = False

    def record(self, name, elapsed, status):
        with self.lock:
            self.results.setdefault(name, []).append((elapsed, status))
            if status >= 500:
                self.status_5xx += 1
                if len(self.errors) < 10:
                    self.errors.append(f"{name} -> {status}")
            elif status not in (200, 400, 401, 404, 413, 422, 429):
                self.status_other += 1

    def health_loop(self):
        c = httpx.Client(timeout=10)
        while not self.stop:
            t0 = time.perf_counter()
            try:
                r = c.get(self.base + "/health")
                ms = (time.perf_counter() - t0) * 1000
                with self.lock:
                    self.health_max_ms = max(self.health_max_ms, ms)
                    if r.status_code != 200:
                        self.health_bad += 1
            except Exception as e:
                with self.lock:
                    self.health_bad += 1
                    if len(self.errors) < 10:
                        self.errors.append(f"health: {e}")
            time.sleep(2)
        c.close()

    def worker(self, idx):
        c = httpx.Client(timeout=300)
        try:
            self._worker_inner(c, idx)
        finally:
            c.close()

    def _worker_inner(self, c, idx):
        r = c.post(self.base + "/api/auth/register", json={
            "username": f"dspuser{idx:02d}", "email": f"dspuser{idx:02d}@gmail.com",
            "password": "DspStorm#2026", "invite_code": self.invite}, timeout=60)
        if r.status_code not in (200, 409):
            with self.lock:
                self.errors.append(f"register {idx}: {r.status_code}")
            return
        r = c.post(self.base + "/api/auth/login", json={
            "identifier": f"dspuser{idx:02d}", "password": "DspStorm#2026"}, timeout=60)
        if r.status_code != 200:
            with self.lock:
                self.errors.append(f"login {idx}: {r.status_code}")
            return
        token = r.json()["token"]
        headers = {"Authorization": f"Bearer {token}"}

        wav_instrument = make_wav(60)
        wav_restore = make_wav(8)
        wav_pitch = make_wav(12)
        wav_cmp_a = make_wav(15, base=220.0)
        wav_cmp_b = make_wav(15, base=224.0)
        wav_transcribe = make_wav(20)

        jobs = [
            ("instruments", "/api/music/instruments", {"file": ("a.wav", wav_instrument, "audio/wav")}, {}),
            ("restore", "/api/music/restore", {"file": ("r.wav", wav_restore, "audio/wav")}, {}),
            ("analyze-pitch", "/api/music/analyze-pitch", {"file": ("p.wav", wav_pitch, "audio/wav")}, {}),
            ("compare", "/api/music/compare",
             {"sample": ("s.wav", wav_cmp_a, "audio/wav"), "user": ("u.wav", wav_cmp_b, "audio/wav")}, {}),
            ("transcribe", "/api/music/transcribe",
             {"file": ("t.wav", wav_transcribe, "audio/wav")}, {"data": {"bpm": "60", "engine": "dsp"}}),
        ]
        for _round in range(self.rounds):
            for name, path, files, extra in jobs:
                if self.stop:
                    return
                if _round % 2 == 1 and name == "analyze-pitch":
                    threads = [
                        threading.Thread(target=self._hit, args=(c, headers, name, path, files, extra))
                        for _ in range(3)
                    ]
                    for t in threads:
                        t.start()
                    for t in threads:
                        t.join()
                    continue
                self._hit(c, headers, name, path, files, extra)

    def _hit(self, c, headers, name, path, files, extra):
        t0 = time.perf_counter()
        try:
            r = c.post(self.base + path, files=files, headers=headers, timeout=600, **extra)
            self.record(name, time.perf_counter() - t0, r.status_code)
        except Exception as e:
            self.record(name, time.perf_counter() - t0, -1)
            with self.lock:
                if len(self.errors) < 10:
                    self.errors.append(f"{name}: {type(e).__name__}: {e}")

    def run(self):
        poller = threading.Thread(target=self.health_loop, daemon=True)
        poller.start()
        t0 = time.perf_counter()
        threads = [threading.Thread(target=self.worker, args=(i,)) for i in range(self.users)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.stop = True
        poller.join(timeout=5)
        wall = time.perf_counter() - t0
        print(f"\n== DSP STORM SUMMARY ({self.users} users x {self.rounds} rounds, {wall:.1f}s) ==")
        for name, entries in self.results.items():
            times = [e for e, _s in entries]
            codes = {}
            for _e, s in entries:
                codes[s] = codes.get(s, 0) + 1
            times_sorted = sorted(times)
            p50 = statistics.median(times_sorted) if times_sorted else 0.0
            p95 = times_sorted[int(len(times_sorted) * 0.95)] if times_sorted else 0.0
            print(f"  {name:15s} n={len(entries):3d} p50={p50:6.2f}s p95={p95:6.2f}s codes={codes}")
        print(f"  5xx={self.status_5xx} other={self.status_other} health_bad={self.health_bad} health_max={self.health_max_ms:.0f}ms")
        if self.errors:
            print("  errors:")
            for e in self.errors:
                print(f"    - {e}")
        ok = self.status_5xx == 0 and self.health_bad == 0 and self.status_other == 0
        print(f"  VERDICT: {'SONG/SACH' if ok else 'CO VAN DE'}")
        return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--users", type=int, default=6)
    ap.add_argument("--rounds", type=int, default=2)
    ap.add_argument("--invite", default="CHAOS-CODE")
    args = ap.parse_args()
    storm = Storm(args.base, args.users, args.rounds, args.invite)
    sys.exit(storm.run())


if __name__ == "__main__":
    main()
