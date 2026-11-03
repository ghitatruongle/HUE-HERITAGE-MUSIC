import atexit
import os
import shutil
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

_tmp = Path(tempfile.mkdtemp(prefix="hue_heritage_test_"))
_fd, _db_path = tempfile.mkstemp(suffix=".db", dir=_tmp)
os.close(_fd)
os.environ["DATABASE_URL"] = "sqlite:///" + Path(_db_path).as_posix()
os.environ["STORAGE_DIR"] = str(_tmp / "storage")
os.environ["MODELS_DIR"] = str(_tmp / "models")
os.environ["HUE_SECURITY_LOG"] = str(_tmp / "security.log")


@pytest.fixture(autouse=True)
def _isolated_settings(monkeypatch):
    from app import rate_limit
    from app.config import settings

    monkeypatch.setattr(settings, "invite_codes", "TESTINVITE", raising=False)
    rate_limit.reset()
    yield


@atexit.register
def _cleanup():
    shutil.rmtree(_tmp, ignore_errors=True)
