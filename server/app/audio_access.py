import hashlib
import hmac
import time
from typing import Optional

from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .config import settings
from .database import crud
from .database.session import get_db
from .api.auth import parse_token

SIGNED_URL_TTL_SECONDS = 6 * 3600


def _signature(path: str, expires: int) -> str:
    return hmac.new(settings.secret_key.encode(), f"{path}.{expires}".encode(), hashlib.sha256).hexdigest()[:32]


def sign_path(path: str, expires: int = 0) -> dict:
    exp = int(expires) if expires else int(time.time() + SIGNED_URL_TTL_SECONDS)
    return {"url": f"{path}?e={exp}&s={_signature(path, exp)}", "expires": exp}


def verify_path(path: str, e, s) -> bool:
    try:
        expires = int(e)
    except (TypeError, ValueError):
        return False
    if expires < time.time():
        return False
    if not s:
        return False
    return hmac.compare_digest(_signature(path, expires), str(s))


def require_audio_access(request: Request, db: Session = Depends(get_db)) -> Optional[str]:
    if not settings.auth_required:
        return None
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        user_id = None
        try:
            user_id = parse_token(header[7:].strip())
        except HTTPException:
            user_id = None
        if user_id and crud.get_user_by_id(db, user_id):
            return user_id
    if verify_path(request.url.path, request.query_params.get("e"), request.query_params.get("s")):
        return "signed"
    raise HTTPException(status_code=401, detail="authentication or signed url required")
