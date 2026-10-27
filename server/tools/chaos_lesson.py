"""Tạo bài học chaos qua API (cần ADMIN_TOKEN env)."""
import io
import math
import os
import wave

import httpx


def tone(freq, sec=3.0, sr=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        for i in range(int(sr * sec)):
            v = int(6000 * math.sin(2 * math.pi * freq * i / sr))
            w.writeframes(v.to_bytes(2, "little", signed=True))
    return buf.getvalue()


def main():
    base = os.environ.get("CHAOS_BASE", "http://127.0.0.1:8010")
    out = os.environ["CHAOS_LESSON_OUT"]
    token = os.environ["CHAOS_ADMIN_TOKEN"]
    c = httpx.Client(base_url=base, timeout=60, headers={"Authorization": f"Bearer {token}"})
    r = c.post("/api/heritage/upload",
               files={"file": ("chaos.wav", tone(250.0), "audio/wav")},
               data={"title": "Chaos lesson", "type": "Ca Hue",
                     "featured_in_creation": "true", "mode_system": "Nam"})
    lid = r.json()["id"]
    c.get("/api/lessons/" + lid)
    open(out, "w").write(lid)
    print("lesson:", lid[:8])
    c.close()


if __name__ == "__main__":
    main()
