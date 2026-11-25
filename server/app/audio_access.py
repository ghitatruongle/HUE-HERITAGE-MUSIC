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
from .storage import manager
from .api.auth import parse_token, resolve_bearer_user

SIGNED_URL_TTL_SECONDS = max(60, int(settings.signed_url_ttl_seconds))

HERITAGE_AUDIO_RE = re.compile(r"^/api/heritage/([A-Za-z0-9-]+)/audio$")
GENERATED_AUDIO_RE = re.compile(r"^/api/music/generated/([A-Za-z0-9_-]{1,80}\.mp3)$")


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


def generated_audio_task_id(path: str) -> Optional[str]:
    m = GENERATED_AUDIO_RE.match(path)
    if not m:
        return None
    return m.group(1).split(".")[0]


def require_audio_access(request: Request, db: Session = Depends(get_db)) -> Optional[str]:
    item_id = heritage_audio_item_id(request.url.path)
    item = crud.get_item(db, item_id) if item_id else None
    gen_task_id = generated_audio_task_id(request.url.path) if item is None else None
    gen_task = crud.get_task(db, gen_task_id) if gen_task_id else None
    user = resolve_bearer_user(request, db)
    if user is not None:
        if item is not None and not crud.can_view_item(item, user):
            raise HTTPException(status_code=404, detail="not found")
        if gen_task is not None and gen_task.user_id and user.id != gen_task.user_id and not crud.is_admin_user(user):
            raise HTTPException(status_code=404, detail="not found")
        return user.id
    if not settings.auth_required:
        if item is not None and (getattr(item, "visibility", None) or "public") != "public":
            raise HTTPException(status_code=404, detail="not found")
        return None
    if item is not None:
        scope = f"vis:{getattr(item, 'visibility', None) or 'public'}"
    elif gen_task is not None and gen_task.user_id:
        scope = f"gen:{gen_task.user_id}"
    else:
        scope = ""
    if verify_path(request.url.path, request.query_params.get("e"), request.query_params.get("s"), scope=scope):
        return "signed"
    raise HTTPException(status_code=401, detail="authentication or signed url required")


def sha_access_scope(db: Session, sha: str) -> str:
    from .database.models import HeritageItem

    item = db.query(HeritageItem).filter(HeritageItem.sha256 == sha).first()
    if item is not None:
        return f"vis:{getattr(item, 'visibility', None) or 'public'}"
    owner = crud.get_artifact_owner(db, sha)
    if owner is not None and owner.user_id:
        return f"ao:{owner.user_id}"
    return ""


def sha_viewable(db: Session, request: Request, sha: str, viewer=None) -> bool:
    from .database.models import HeritageItem

    item = db.query(HeritageItem).filter(HeritageItem.sha256 == sha).first()
    if item is not None:
        if viewer is None:
            viewer = resolve_bearer_user(request, db)
        return crud.can_view_item(item, viewer)
    owner = crud.get_artifact_owner(db, sha)
    if owner is None:
        return True
    if owner.user_id is None:
        return True
    if viewer is None:
        viewer = resolve_bearer_user(request, db)
    if viewer is None:
        return False
    if crud.is_admin_user(viewer):
        return True
    return viewer.id == owner.user_id or crud.has_artifact_access(db, sha, viewer.id)


def require_sha_audio_access(request: Request, db: Session, sha: str) -> str:
    if not manager.is_sha256(sha):
        raise HTTPException(status_code=404, detail="not found")
    viewer = resolve_bearer_user(request, db)
    if viewer is not None:
        if not sha_viewable(db, request, sha, viewer=viewer):
            raise HTTPException(status_code=404, detail="not found")
        return viewer.id
    if not settings.auth_required:
        if not sha_viewable(db, request, sha, viewer=None):
            raise HTTPException(status_code=404, detail="not found")
        return "public"
    scope = sha_access_scope(db, sha)
    if verify_path(
        request.url.path,
        request.query_params.get("e"),
        request.query_params.get("s"),
        scope=scope,
    ):
        return "signed"
    raise HTTPException(status_code=401, detail="authentication or signed url required")
