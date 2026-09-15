import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--metadata", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    meta_path = Path(args.metadata).resolve()
    root = meta_path.parent
    data = json.loads(meta_path.read_text(encoding="utf-8"))
    entries = data.get("entries", [])

    written = 0
    problems = []
    for e in entries:
        audio = root / e.get("audio", "")
        if not str(e.get("audio", "")).strip():
            problems.append("entry missing audio field")
            continue
        if not audio.is_file():
            problems.append(f"missing audio: {audio.name}")
            continue
        stem = audio.stem
        ann = {
            "caption": e.get("caption", ""),
            "bpm": e.get("bpm"),
            "keyscale": e.get("tonal", e.get("keyscale", "")),
            "timesignature": e.get("timesignature", ""),
            "language": e.get("language", ""),
        }
        ann = {k: v for k, v in ann.items() if v not in (None, "")}
        lyrics = (e.get("lyrics") or "").strip()
        if args.dry_run:
            print(f"{stem}: json={list(ann.keys())} lyrics={'yes' if lyrics else 'no'}")
        else:
            (root / f"{stem}.json").write_text(
                json.dumps(ann, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            if lyrics:
                (root / f"{stem}.lyrics.txt").write_text(lyrics + "\n", encoding="utf-8")
            written += 1

    print(json.dumps({"entries": len(entries), "written": written, "problems": problems}, ensure_ascii=False, indent=2))
    if problems:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
