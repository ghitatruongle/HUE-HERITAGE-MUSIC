import hashlib
import hmac
import re
import time
from typing import Optional

from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .config import settings
from .database import crud
from .database.session import get_db
from .api.auth import parse_token, resolve_bearer_user

SIGNED_URL_TTL_SECONDS = 6 * 3600

HERITAGE_AUDIO_RE = re.compile(r"^/api/heritage/([A-Za-z0-9-]+)/audio$")


def _signature(path: str, expires: int, scope: str = "") -> str:
    payload = f"{path}|{scope}.{expires}" if scope else f"{path}.{expires}"
    return hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()[:32]


def sign_path(path: str, expires: int = 0, scope: str = "") -> dict:
    exp = int(expires) if expires else int(time.time() + SIGNED_URL_TTL_SECONDS)
    return {"url": f"{path}?e={exp}&s={_signature(path, exp, scope)}", "expires": exp}


def verify_path(path: str, e, s, scope: str = "") -> bool:
    try:
        expires = int(e)
    except (TypeError, ValueError):
        return False
    if expires < time.time():
        return False
    if not s:
        return False
    return hmac.compare_digest(
        _signature(path, expires, scope).encode("ascii"),
        str(s).encode("utf-8", "replace"),
    )


def heritage_audio_item_id(path: str) -> Optional[str]:
    m = HERITAGE_AUDIO_RE.match(path)
    if not m:
        return None
    return m.group(1)


def require_audio_access(request: Request, db: Session = Depends(get_db)) -> Optional[str]:
    item_id = heritage_audio_item_id(request.url.path)
    item = crud.get_item(db, item_id) if item_id else None
    user = resolve_bearer_user(request, db)
    if user is not None:
        if item is not None and not crud.can_view_item(item, user):
            raise HTTPException(status_code=404, detail="not found")
        return user.id
    if not settings.auth_required:
        if item is not None and (getattr(item, "visibility", None) or "public") != "public":
            raise HTTPException(status_code=404, detail="not found")
        return None
    scope = f"vis:{getattr(item, 'visibility', None) or 'public'}" if item is not None else ""
    if verify_path(request.url.path, request.query_params.get("e"), request.query_params.get("s"), scope=scope):
        return "signed"
    raise HTTPException(status_code=401, detail="authentication or signed url required")
