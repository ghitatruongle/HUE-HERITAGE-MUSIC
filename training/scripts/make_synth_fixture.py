import argparse
import io
import json
import math
import struct
import wave
from pathlib import Path

MELODY = [
    (440.00, 69),
    (493.88, 71),
    (523.25, 72),
    (587.33, 74),
    (659.25, 76),
]


def synth_wav(out_path: Path, sr: int = 16000, note_dur: float = 0.5, gap: float = 0.0, fade: float = 0.01):
    frames = []
    truth = []
    t0 = 0.0
    for freq, midi in MELODY:
        n = int(sr * note_dur)
        for i in range(n):
            t = i / sr
            amp = 1.0
            if t < fade:
                amp = t / fade
            elif note_dur - t < fade:
                amp = (note_dur - t) / fade
            v = int(amp * 0.8 * 32767 * math.sin(2 * math.pi * freq * t))
            frames.append(v)
        silence = int(sr * gap)
        frames.extend([0] * silence)
        truth.append({"midi": midi, "start": round(t0, 3), "end": round(t0 + note_dur, 3)})
        t0 += note_dur + gap
    bio = io.BytesIO()
    w = wave.open(bio, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(struct.pack("<%dh" % len(frames), *frames))
    w.close()
    out_path.write_bytes(bio.getvalue())
    return truth


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--sr", type=int, default=16000)
    ap.add_argument("--note-dur", type=float, default=0.5)
    ap.add_argument("--gap", type=float, default=0.05)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    truth = synth_wav(out / "melody.wav", sr=args.sr, note_dur=args.note_dur, gap=args.gap)
    (out / "truth.json").write_text(json.dumps(truth, indent=2), encoding="utf-8")
    print(json.dumps({"audio": str(out / "melody.wav"), "truth": str(out / "truth.json"), "notes": len(truth)}))


if __name__ == "__main__":
    main()
