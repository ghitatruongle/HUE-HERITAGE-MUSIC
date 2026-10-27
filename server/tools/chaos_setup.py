"""Chuẩn bị DB cho chaos test: admin + 300 mã mời one-time (raw sqlite, không phụ thuộc import app)."""
import argparse
import hashlib
import secrets as _s
import sqlite3
import uuid as _u
from datetime import datetime
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--codes-out", required=True)
    ap.add_argument("--codes", type=int, default=300)
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    cur = conn.cursor()

    cols = {r[1] for r in cur.execute("PRAGMA table_info(users)")}
    if "role" not in cols:
        cur.execute("ALTER TABLE users ADD COLUMN role VARCHAR(16) DEFAULT 'user' NOT NULL")
    if "active" not in cols:
        cur.execute("ALTER TABLE users ADD COLUMN active INTEGER DEFAULT 1 NOT NULL")
    if "token_epoch" not in cols:
        cur.execute("ALTER TABLE users ADD COLUMN token_epoch INTEGER DEFAULT 0 NOT NULL")

    if cur.execute("SELECT COUNT(*) FROM users WHERE username='ghitatruongle'").fetchone()[0] == 0:
        salt = _s.token_hex(16)
        digest = hashlib.pbkdf2_hmac("sha256", b"AdminPass99!", salt.encode(), 600000).hex()
        cur.execute(
            "INSERT INTO users (id, username, email, password_hash, role, active, token_epoch, created_at) VALUES (?,?,?,?,?,?,?,?)",
            (str(_u.uuid4()), "ghitatruongle", "admin@gmail.com",
             f"pbkdf2$600000${salt}${digest}", "admin", 1, 0, datetime.now().isoformat()),
        )

    codes = []
    i = 0
    while len(codes) < args.codes and i < args.codes * 2:
        code = "CHS-" + _s.token_hex(4)
        try:
            cur.execute("INSERT INTO invite_codes (id, code, note) VALUES (?,?,?)",
                        (str(_u.uuid4()), code, "chaos"))
            codes.append(code)
        except sqlite3.IntegrityError:
            conn.rollback()
        i += 1
    conn.commit()

    Path(args.codes_out).write_text("\n".join(codes) + "\n", encoding="utf-8")
    print(f"SETUP_OK {len(codes)} codes, admin ready")
    conn.close()


if __name__ == "__main__":
    main()
