import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "server" / "tools" / "db_backup.sh"


@pytest.mark.skipif(shutil.which("sqlite3") is None, reason="sqlite3 CLI unavailable")
def test_db_backup_script_roundtrip(tmp_path):
    db = tmp_path / "src.db"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE t(x)")
    conn.execute("INSERT INTO t VALUES (1)")
    conn.commit()
    conn.close()
    out = tmp_path / "backups"
    result = subprocess.run(
        ["bash", str(SCRIPT), str(db), str(out), "2"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stderr
    backups = list(out.glob("hue_heritage_*.db"))
    assert len(backups) == 1
    conn = sqlite3.connect(backups[0])
    rows = conn.execute("SELECT x FROM t").fetchall()
    conn.close()
    assert rows == [(1,)]


@pytest.mark.skipif(shutil.which("sqlite3") is None, reason="sqlite3 CLI unavailable")
def test_db_backup_script_rotates(tmp_path):
    db = tmp_path / "src.db"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE t(x)")
    conn.commit()
    conn.close()
    out = tmp_path / "backups"
    for _ in range(4):
        result = subprocess.run(
            ["bash", str(SCRIPT), str(db), str(out), "2"],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, result.stderr
    backups = list(out.glob("hue_heritage_*.db"))
    assert len(backups) <= 2
