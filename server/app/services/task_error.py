import re

_PATH_RE = re.compile(r"/(?:Users|home|root)/[^\s'\"]+")
_FILE_RE = re.compile(r"[A-Za-z0-9_/.\-]+\.py")


def safe_task_error(e: BaseException) -> str:
    text = _PATH_RE.sub("<path>", str(e))
    text = _FILE_RE.sub("<file>", text)
    return f"{type(e).__name__}: {text}"[:300]
