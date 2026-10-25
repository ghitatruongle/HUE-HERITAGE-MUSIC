import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database.session import SessionLocal, init_db
from app.database import crud


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("code")
    ap.add_argument("--note", default="")
    args = ap.parse_args()
    init_db()
    db = SessionLocal()
    try:
        if crud.get_invite_code(db, args.code):
            print("code already exists")
            return 1
        row = crud.create_invite_code(db, args.code, args.note)
        print(f"created {row.code} (one-time)")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
