from typing import Optional, List
from pathlib import Path
import asyncio
import hashlib
import hmac
import json
import logging
import math
import re
import secrets
import os
import tempfile
import threading
import time

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import acquire_write_slot, get_db, SessionLocal, write_slot
from ..database import crud
from .. import rate_limit
from .. import rate_limit, security_log
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS
from ..services import user_inflight

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

PBKDF2_ITERATIONS = max(1, int(settings.pbkdf2_iterations))
if PBKDF2_ITERATIONS < 600_000:
    logger.warning(
        "PBKDF2_ITERATIONS=%d is below the production value 600000; "
        "lower values are only safe in isolated load-test sandboxes",
        PBKDF2_ITERATIONS,
    )
LEGACY_PBKDF2_ITERATIONS = 100_000
RESERVED_USERNAMES = {"admin", "administrator", "moderator", "root", "system", "support", "official"}

AUTH_FAILURE_LIMIT = 5
AUTH_FAILURE_WINDOW = 900.0
_auth_failures: dict = {}
_auth_failures_lock = threading.Lock()
_identifier_failures: dict = {}
_IDENTIFIER_FAILURE_LIMIT = 20
_ADMIN_UNLOCK_FAILURE_LIMIT = 5
_admin_unlock_failures: dict = {}
_register_ip_failures: dict = {}
_invite_lock = threading.Lock()

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")

_admin_unlocks: dict = {}


def _must_change(user) -> bool:
    return bool(getattr(user, "must_change_password", 0))


def _token_ttl_for(user) -> int:
    if _role_of(user) == "admin":
        return min(settings.admin_token_ttl_hours, settings.token_ttl_hours)
    return settings.token_ttl_hours


_DUMMY_HASH: Optional[str] = None
_dummy_hash_lock = threading.Lock()


def _uniform_verify(password: str, stored: Optional[str]) -> bool:
    global _DUMMY_HASH
    dummy = _DUMMY_HASH
    if dummy is None:
        with _dummy_hash_lock:
            if _DUMMY_HASH is None:
                _DUMMY_HASH = hash_password("timing-uniform-dummy-verification-hash")
            dummy = _DUMMY_HASH
    ok = verify_password(password, stored or dummy)
    time.sleep((2 + secrets.randbelow(5)) / 1000)
    return ok


def _admin_password_ok(password: str) -> bool:
    if len(password) < 12:
        return False
    return any(c.isalpha() for c in password) and any(c.isdigit() for c in password)


def make_token_for(user) -> str:
    expires = int(time.time()) + _token_ttl_for(user) * 3600
    epoch = user.token_epoch or 0
    payload = f"{user.id}.{expires}.{epoch}"
    sig = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"



def _user_password_ok(pw: str) -> bool:
    if len(pw) < 8:
        return False
    return any(c.isalpha() for c in pw) and any(c.isdigit() for c in pw)


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _attempts_exceeded(key: str) -> bool:
    now = time.time()
    with _auth_failures_lock:
        stamps = [t for t in _auth_failures.get(key, []) if now - t < AUTH_FAILURE_WINDOW]
        _auth_failures[key] = stamps
        return len(stamps) >= AUTH_FAILURE_LIMIT


def _record_failure(key: str) -> None:
    now = time.time()
    with _auth_failures_lock:
        if len(_auth_failures) > 20000:
            for k in [k for k, v in _auth_failures.items() if not v or now - v[-1] > AUTH_FAILURE_WINDOW]:
                _auth_failures.pop(k, None)
        stamps = [t for t in _auth_failures.get(key, []) if now - t < AUTH_FAILURE_WINDOW]
        stamps.append(now)
        _auth_failures[key] = stamps


def _identifier_exceeded(identifier: str) -> bool:
    """Chống brute force cùng 1 tài khoản từ NHIỀU IP khác nhau."""
    now = time.time()
    with _auth_failures_lock:
        stamps = [t for t in _identifier_failures.get(identifier, []) if now - t < AUTH_FAILURE_WINDOW]
        _identifier_failures[identifier] = stamps
        return len(stamps) >= _IDENTIFIER_FAILURE_LIMIT


def _record_identifier_failure(identifier: str) -> None:
    with _auth_failures_lock:
        if len(_identifier_failures) > 20000:
            for k in [k for k, v in _identifier_failures.items() if not v or time.time() - v[-1] > AUTH_FAILURE_WINDOW]:
                _identifier_failures.pop(k, None)
        _identifier_failures.setdefault(identifier, []).append(time.time())


def _clear_failures(key: str) -> None:
    with _auth_failures_lock:
        _auth_failures.pop(key, None)


def _ip_failures_exceeded(store: dict, key: str, limit: int) -> bool:
    now = time.time()
    with _auth_failures_lock:
        stamps = [t for t in store.get(key, []) if now - t < AUTH_FAILURE_WINDOW]
        store[key] = stamps
        return len(stamps) >= limit


def _record_ip_failure(store: dict, key: str) -> None:
    now = time.time()
    with _auth_failures_lock:
        if len(store) > 20000:
            for k in [k for k, v in store.items() if not v or now - v[-1] > AUTH_FAILURE_WINDOW]:
                store.pop(k, None)
        store.setdefault(key, []).append(now)


def get_valid_invite_codes(db=None) -> List[str]:
    codes: List[str] = []
    if db is not None:
        try:
            codes.extend(crud.unused_invite_codes(db))
        except Exception:
            logger.warning("failed to read invite codes from database", exc_info=True)
    codes_path = Path(__file__).resolve().parent.parent.parent / "INVITATION_CODES.json"
    if codes_path.exists():
        try:
            data = json.loads(codes_path.read_text(encoding="utf-8"))
            file_codes = data.get("valid_codes", [])
            if isinstance(file_codes, list):
                codes.extend(str(c).strip() for c in file_codes if str(c).strip())
        except Exception:
            logger.warning(
                "INVITATION_CODES.json is malformed; falling back to configured invite codes",
                exc_info=True,
            )
    if settings.invite_codes:
        codes.extend(c.strip() for c in settings.invite_codes.split(",") if c.strip())
    seen = set()
    return [c for c in codes if not (c in seen or seen.add(c))]


_PBKDF2_GATE = threading.Semaphore(max(2, min(8, os.cpu_count() or 4)))


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    with _PBKDF2_GATE:
        digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ITERATIONS).hex()
    return f"pbkdf2${PBKDF2_ITERATIONS}${salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    parts = stored.split("$")
    if len(parts) == 4 and parts[0] == "pbkdf2":
        try:
            iterations = int(parts[1])
        except ValueError:
            return False
        salt, digest = parts[2], parts[3]
    elif len(parts) == 2:
        iterations = LEGACY_PBKDF2_ITERATIONS
        salt, digest = parts
    else:
        return False
    with _PBKDF2_GATE:
        calc = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), iterations).hex()
    return hmac.compare_digest(calc, digest)


def _password_iterations(stored: str) -> int:
    parts = stored.split("$")
    if len(parts) == 4 and parts[0] == "pbkdf2":
        try:
            return int(parts[1])
        except ValueError:
            return 0
    if len(parts) == 2:
        return LEGACY_PBKDF2_ITERATIONS
    return 0


def make_token(user_id: str, epoch: int = 0) -> str:
    expires = int(time.time()) + settings.token_ttl_hours * 3600
    payload = f"{user_id}.{expires}.{epoch}"
    sig = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"


def _token_payload(token: str):
    parts = token.split(".")
    if len(parts) == 4:
        return parts[0], int(parts[1]), int(parts[2]), ".".join(parts[:3])
    if len(parts) == 3:
        return parts[0], int(parts[1]), 0, ".".join(parts[:2])
    raise ValueError("bad token shape")


def parse_token(token: str) -> tuple:
    try:
        user_id, expires, epoch, payload = _token_payload(token)
    except (ValueError, IndexError):
        raise HTTPException(status_code=401, detail="invalid token")
    sig = token.rsplit(".", 1)[1]
    expected = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig.encode("utf-8", "replace"), expected.encode("ascii")):
        raise HTTPException(status_code=401, detail="invalid token")
    if expires < time.time():
        raise HTTPException(status_code=401, detail="token expired")
    return user_id, epoch


class RegisterRequest(BaseModel):
    username: str
    email: str
    password: str
    invite_code: str


class LoginRequest(BaseModel):
    identifier: Optional[str] = None
    username: Optional[str] = None
    password: str


FORCE_CHANGE_ALLOWED_PATHS = ("/api/auth/change-password", "/api/auth/revoke-all")


def _generate_temp_password(min_len: int = 12) -> str:
    body_len = max(12, int(min_len))
    rng = secrets.SystemRandom()
    uppers = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    lowers = "abcdefghijkmnopqrstuvwxyz"
    digits = "23456789"
    pool = uppers + lowers + digits
    chars = [
        rng.choice(uppers),
        rng.choice(lowers),
        rng.choice(digits),
        rng.choice(digits),
    ]
    chars.extend(rng.choice(pool) for _ in range(body_len - len(chars)))
    rng.shuffle(chars)
    return "hue-" + "".join(chars)


def _enforce_must_change(request: Request, user) -> None:
    if getattr(user, "must_change_password", 0) and request.method not in ("GET", "HEAD", "OPTIONS"):
        path = request.url.path
        if not any(path == p or path.startswith(p + "/") for p in FORCE_CHANGE_ALLOWED_PATHS):
            raise HTTPException(status_code=403, detail="password change required")


def require_user(request: Request) -> Optional[str]:
    if not settings.auth_required:
        return None
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id, epoch = parse_token(header[7:].strip())
    db = SessionLocal()
    try:
        user = crud.get_user_by_id(db, user_id)
        if not user:
            raise HTTPException(status_code=401, detail="unknown user")
        if epoch != (user.token_epoch or 0):
            raise HTTPException(status_code=401, detail="token revoked")
        if getattr(user, "active", 1) == 0:
            raise HTTPException(status_code=403, detail="account disabled")
        _enforce_must_change(request, user)
    finally:
        db.close()
    return user_id


def require_admin(request: Request, db: Session = Depends(get_db)) -> str:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id, epoch = parse_token(header[7:].strip())
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="unknown user")
    if epoch != (user.token_epoch or 0):
        raise HTTPException(status_code=401, detail="token revoked")
    if getattr(user, "active", 1) == 0:
        raise HTTPException(status_code=403, detail="account disabled")
    _enforce_must_change(request, user)
    if (user.role or "user") != "admin" or user.username != settings.admin_truong_username:
        raise HTTPException(status_code=403, detail="admin truong only")
    return user.id


def require_admin_fresh(admin_id: str = Depends(require_admin)) -> str:
    ts = _admin_unlocks.get(admin_id)
    if ts is None or time.time() - ts > settings.admin_unlock_window_seconds:
        raise HTTPException(status_code=403, detail="admin reauth required")
    return admin_id


def require_staff(request: Request, db: Session = Depends(get_db)) -> str:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id, epoch = parse_token(header[7:].strip())
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="unknown user")
    if epoch != (user.token_epoch or 0):
        raise HTTPException(status_code=401, detail="token revoked")
    if getattr(user, "active", 1) == 0:
        raise HTTPException(status_code=403, detail="account disabled")
    _enforce_must_change(request, user)
    if (user.role or "user") != "worker" and not crud.is_admin_user(user):
        raise HTTPException(status_code=403, detail="staff only")
    return user.id


def _bearer_user(request: Request, db: Session):
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id, epoch = parse_token(header[7:].strip())
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="unknown user")
    if epoch != (user.token_epoch or 0):
        raise HTTPException(status_code=401, detail="token revoked")
    if getattr(user, "active", 1) == 0:
        raise HTTPException(status_code=403, detail="account disabled")
    return user


def resolve_bearer_user(request: Request, db: Session):
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    try:
        user_id, epoch = parse_token(header[7:].strip())
    except HTTPException:
        return None
    user = crud.get_user_by_id(db, user_id)
    if user is None or epoch != (user.token_epoch or 0):
        return None
    if getattr(user, "active", 1) == 0:
        raise HTTPException(status_code=403, detail="account disabled")
    return user


def _role_of(user) -> str:
    if crud.is_admin_user(user):
        return "admin"
    if (user.role or "user") == "worker":
        return "worker"
    return "user"


USERNAME_RE = re.compile(r"^[A-Za-z0-9._-]{3,32}$")


def _validate_registration(db: Session, u: str, e: str, p: str, c: str) -> None:
    if not u or len(u) < 3 or len(u) > 32:
        raise HTTPException(status_code=400, detail="username must be 3-32 characters")
    if not USERNAME_RE.fullmatch(u):
        raise HTTPException(status_code=400, detail="username may only contain letters, digits, dot, underscore, hyphen")
    if u.lower() in RESERVED_USERNAMES:
        raise HTTPException(status_code=400, detail="username is reserved")
    admin_lower = settings.admin_truong_username.lower()
    if u.lower() == admin_lower and u != settings.admin_truong_username:
        raise HTTPException(status_code=400, detail="username conflicts with the admin truong account")
    if u.lower().replace(".", "").replace("_", "") == admin_lower and u.lower() != admin_lower:
        raise HTTPException(status_code=400, detail="username impersonates the admin truong account")
    if not EMAIL_RE.fullmatch(e):
        raise HTTPException(status_code=400, detail="invalid email address")
    if not _user_password_ok(p):
        raise HTTPException(
            status_code=400,
            detail="password must be at least 8 characters and contain letters and digits",
        )
    if c not in get_valid_invite_codes(db):
        raise HTTPException(status_code=400, detail="invalid invitation code")
    if crud.get_user(db, u):
        raise HTTPException(status_code=409, detail="username already exists")
    if crud.get_user_by_email(db, e):
        raise HTTPException(status_code=409, detail="email already registered")


@router.post("/register")
def register(req: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    u = req.username.strip()
    e = req.email.strip().lower()
    p = req.password
    c = req.invite_code.strip()

    if not rate_limit.hit_and_allow(f"register-ip:{_client_ip(request)}", max(1, settings.register_ip_rate_limit)):
        security_log.security_event("register_ip_flood", ip=_client_ip(request))
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)

    fail_key = f"regfail:{_client_ip(request)}"
    if _ip_failures_exceeded(_register_ip_failures, fail_key, max(1, settings.register_failure_ip_limit)):
        security_log.security_event("register_failures_ip_limited", ip=_client_ip(request))
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)

    key = f"register:{_client_ip(request)}:{u.lower()}"
    if _attempts_exceeded(key):
        security_log.security_event("register_rate_limited", ip=_client_ip(request), username=u)
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)

    pw_hash = ""
    try:
        pw_hash = hash_password(p)
    except Exception:
        pw_hash = ""

    with _invite_lock:
        try:
            _validate_registration(db, u, e, p, c)
        except HTTPException as exc:
            _record_failure(key)
            _record_ip_failure(_register_ip_failures, fail_key)
            security_log.security_event("register_failed", ip=_client_ip(request), username=u, detail=exc.detail)
            raise

        from sqlalchemy import update
        from ..database.models import InviteCode, User

        with write_slot:
            try:
                if crud.get_invite_code(db, c) is not None:
                    now = crud._utc_now()
                    res = db.execute(
                        update(InviteCode)
                        .where(InviteCode.code == c, *crud._active_invite_filters(InviteCode, now))
                        .values(used_count=InviteCode.used_count + 1, used_by=u, used_at=now)
                    )
                    if res.rowcount == 0:
                        db.rollback()
                        security_log.security_event("invite_code_conflict", code=c, username=u)
                        raise HTTPException(status_code=409, detail="invitation code unavailable")
                safe_email = e or f"{u}@no-email.local"
                user = User(
                    username=u,
                    email=safe_email,
                    password_hash=pw_hash or hash_password(p),
                    must_change_password=0,
                    role="user",
                )
                db.add(user)
                db.commit()
                db.refresh(user)
            except IntegrityError:
                db.rollback()
                _record_failure(key)
                _record_ip_failure(_register_ip_failures, fail_key)
                security_log.security_event("register_failed", ip=_client_ip(request), username=u, detail="duplicate")
                raise HTTPException(status_code=409, detail="username or email already exists")

    _clear_failures(key)
    security_log.security_event("register_success", ip=_client_ip(request), username=u, user_id=user.id)
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
        "must_change_password": _must_change(user),
        "token": make_token_for(user),
    }


@router.post("/login")
def login(req: LoginRequest, request: Request, db: Session = Depends(get_db)):
    login_id = (req.identifier or req.username or "").strip()
    if not login_id or not req.password:
        raise HTTPException(status_code=400, detail="identifier and password required")

    ip_allowed = rate_limit.hit_and_allow(f"login-ip:{_client_ip(request)}", max(1, settings.auth_flood_ip_limit))
    user = crud.get_user_by_identifier(db, login_id)
    is_admin_truong = (
        user is not None
        and user.username == settings.admin_truong_username
        and (user.role or "user") == "admin"
    )
    if not ip_allowed and not is_admin_truong:
        security_log.security_event("login_ip_flood", ip=_client_ip(request))
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    ident_key = str(user.id) if user else login_id.lower()
    key = f"login:{_client_ip(request)}:{ident_key}"
    password_ok = _uniform_verify(req.password, user.password_hash if user else None)
    if not user or not password_ok:
        _record_failure(key)
        _record_identifier_failure(ident_key)
        locked = _attempts_exceeded(key) or _identifier_exceeded(ident_key)
        security_log.security_event("login_failed", ip=_client_ip(request), identifier=login_id)
        if locked:
            security_log.security_event("login_rate_limited", ip=_client_ip(request), identifier=login_id)
            raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
        raise HTTPException(status_code=401, detail="wrong credentials")
    if getattr(user, "active", 1) == 0:
        security_log.security_event("login_blocked_disabled", ip=_client_ip(request), identifier=login_id)
        raise HTTPException(status_code=403, detail="account disabled")

    if _password_iterations(user.password_hash) < PBKDF2_ITERATIONS:
        crud.update_user_password(db, user.id, hash_password(req.password))
        security_log.security_event("password_rehashed", user_id=user.id, username=user.username)

    _clear_failures(key)
    security_log.security_event("login_success", ip=_client_ip(request), username=user.username, user_id=user.id)
    if _role_of(user) == "admin":
        security_log.security_event("admin_login", ip=_client_ip(request), user_id=user.id)
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
        "must_change_password": _must_change(user),
        "avatar": _avatar_public_url(user),
        "token": make_token_for(user),
    }


@router.get("/me")
def get_me(request: Request, db: Session = Depends(get_db)):
    user = _bearer_user(request, db)
    quota_mb = settings.user_storage_quota_mb
    storage_quota_bytes = None if (crud.is_admin_user(user) or quota_mb <= 0) else quota_mb * 1024 * 1024
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
        "must_change_password": _must_change(user),
        "avatar": _avatar_public_url(user),
        "storage_used_bytes": crud.user_storage_bytes(db, user.id),
        "storage_quota_bytes": storage_quota_bytes,
        "token": make_token_for(user),
    }


AVATAR_MAX_BYTES = max(1, int(settings.avatar_max_bytes))
AVATAR_CONTENT_TYPES = {"image/png": "png", "image/jpeg": "jpg"}
AVATAR_MAX_PIXELS = max(1, int(settings.avatar_max_pixels))


def _avatar_public_url(user) -> str:
    if not (getattr(user, "avatar", "") or ""):
        return ""
    return f"/api/avatars/{user.id}"


def _avatar_magic_ok(raw: bytes, ext: str) -> bool:
    if ext == "png":
        return raw.startswith(b"\x89PNG\r\n\x1a\n")
    return raw.startswith(b"\xff\xd8\xff")


def _save_avatar_file(user_id: str, raw: bytes, ext: str) -> str:
    from io import BytesIO

    from PIL import Image

    try:
        image = Image.open(BytesIO(raw))
        if image.width * image.height > AVATAR_MAX_PIXELS:
            raise HTTPException(status_code=400, detail="image too large")
        if ext == "jpg":
            image = image.convert("RGB")
        image.thumbnail((256, 256))
        image.load()
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="invalid image")
    target_dir = Path(settings.storage_dir) / "avatars"
    target_dir.mkdir(parents=True, exist_ok=True)
    name = f"{user_id}.{ext}"
    fd, tmp_name = tempfile.mkstemp(dir=str(target_dir), suffix=f".{ext}.part")
    os.close(fd)
    tmp_path = Path(tmp_name)
    try:
        if ext == "jpg":
            image.save(tmp_path, format="JPEG", quality=85)
        else:
            image.save(tmp_path, format="PNG")
        os.replace(tmp_path, target_dir / name)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    return name


def _authorize_staff_short(request: Request):
    db = SessionLocal()
    try:
        staff_id = require_staff(request, db)
        user = crud.get_user_by_id(db, staff_id)
        if not user:
            raise HTTPException(status_code=401, detail="unknown user")
        return user.id, user.username, user.avatar or ""
    finally:
        db.close()


def _commit_avatar_db(user_id: str, name: str):
    with write_slot:
        db = SessionLocal()
        try:
            user = crud.get_user_by_id(db, user_id)
            if not user:
                return None, ""
            old = user.avatar or ""
            updated = crud.set_user_avatar(db, user_id, name)
            return old, _avatar_public_url(updated or user)
        finally:
            db.close()


@router.post("/me/avatar")
async def upload_avatar(
    request: Request,
    file: UploadFile = File(...),
):
    uid, username, _ = await asyncio.to_thread(_authorize_staff_short, request)
    if not user_inflight.try_acquire(user_inflight.user_key("avatar", uid)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        raw = await file.read(AVATAR_MAX_BYTES + 1)
        if len(raw) > AVATAR_MAX_BYTES:
            raise HTTPException(status_code=413, detail="file too large")
        ext = AVATAR_CONTENT_TYPES.get((file.content_type or "").lower())
        if ext is None or not _avatar_magic_ok(raw, ext):
            raise HTTPException(status_code=400, detail="avatar must be png or jpeg")
        name = await asyncio.to_thread(_save_avatar_file, uid, raw, ext)
        old, avatar_url = await asyncio.to_thread(_commit_avatar_db, uid, name)
        if old is None:
            raise HTTPException(status_code=401, detail="unknown user")
        if old and old != name:
            try:
                (Path(settings.storage_dir) / "avatars" / Path(old).name).unlink(missing_ok=True)
            except OSError:
                pass
        security_log.security_event("avatar_updated", user_id=uid, username=username)
    finally:
        user_inflight.release(user_inflight.user_key("avatar", uid))
    return {"avatar": avatar_url, "name": name}


avatar_router = APIRouter(prefix="/avatars", tags=["avatars"])


@avatar_router.get("/{user_id}")
def get_avatar(user_id: str, request: Request, db: Session = Depends(get_db)):
    _bearer_user(request, db)
    target = crud.get_user_by_id(db, user_id)
    if not target or not (target.avatar or ""):
        raise HTTPException(status_code=404, detail="avatar not found")
    path = Path(settings.storage_dir) / "avatars" / Path(target.avatar).name
    if not path.exists():
        raise HTTPException(status_code=404, detail="avatar not found")
    media = "image/png" if path.suffix == ".png" else "image/jpeg"
    return FileResponse(path, media_type=media)


class InviteCreateRequest(BaseModel):
    code: str = ""
    note: str = ""
    max_uses: int = 1
    expires_minutes: Optional[int] = None
    expires_hours: Optional[float] = None


def _generate_invite_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "HUE-" + "".join(secrets.choice(alphabet) for _ in range(8))


def _invite_to_dict(row, now=None) -> dict:
    ref = now or crud._utc_now()
    max_uses = 1 if getattr(row, "max_uses", None) is None else int(row.max_uses)
    used_count = int(getattr(row, "used_count", 0) or 0)
    if max_uses == 1 and used_count == 0 and row.used_by is not None:
        used_count = 1
    expired = bool(row.expires_at is not None and row.expires_at <= ref)
    exhausted = max_uses > 0 and used_count >= max_uses
    remaining_uses = None if max_uses == 0 else max(0, max_uses - used_count)
    return {
        "id": row.id,
        "code": row.code,
        "note": row.note or "",
        "max_uses": max_uses,
        "used_count": used_count,
        "remaining_uses": remaining_uses,
        "used": exhausted,
        "expired": expired,
        "active": not expired and not exhausted,
        "expires_at": (row.expires_at.isoformat() + "Z") if row.expires_at else None,
        "used_at": str(row.used_at) if row.used_at else None,
        "created_at": str(row.created_at),
    }


def _resolve_invite_expiry(expires_minutes: Optional[int], expires_hours: Optional[float]):
    from datetime import timedelta

    if expires_minutes is not None:
        if expires_minutes < 1 or expires_minutes > 525600:
            raise HTTPException(status_code=400, detail="invalid invite expiration")
        return crud._utc_now() + timedelta(minutes=expires_minutes)
    if expires_hours is not None:
        if not math.isfinite(expires_hours) or expires_hours <= 0 or expires_hours > 8760:
            raise HTTPException(status_code=400, detail="invalid invite expiration")
        return crud._utc_now() + timedelta(seconds=max(60, int(round(expires_hours * 3600))))
    return None


@router.get("/invites")
def list_invites(limit: int = 50, offset: int = 0, admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    from ..database.models import InviteCode

    now = crud._utc_now()
    base = db.query(InviteCode).order_by(InviteCode.created_at.desc())
    total = base.count()
    safe_offset = max(0, min(int(offset), 10**9))
    rows = base.offset(safe_offset).limit(max(1, min(limit, 200))).all()
    return {
        "total": total,
        "items": [_invite_to_dict(r, now=now) for r in rows],
    }


@router.post("/invites")
def create_invite(req: InviteCreateRequest, staff_id: str = Depends(require_staff), db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    code = req.code.strip() or _generate_invite_code()
    if len(code) < 4 or len(code) > 64:
        raise HTTPException(status_code=400, detail="code must be 4-64 characters")
    if req.max_uses < 0 or req.max_uses > 10000:
        raise HTTPException(status_code=400, detail="max_uses must be 0 or 1-10000")
    expires_at = _resolve_invite_expiry(req.expires_minutes, req.expires_hours)
    if crud.get_invite_code(db, code):
        raise HTTPException(status_code=409, detail="code already exists")
    try:
        if req.max_uses == 1 and expires_at is None:
            row = crud.create_invite_code(db, code, req.note.strip())
        else:
            row = crud.create_invite_code(
                db,
                code,
                req.note.strip(),
                max_uses=req.max_uses,
                expires_at=expires_at,
            )
    except IntegrityError:
        raise HTTPException(status_code=409, detail="code already exists")
    security_log.security_event(
        "invite_created",
        actor=staff_id,
        code=code,
        max_uses=req.max_uses,
        expires_at=expires_at.isoformat() if expires_at else "never",
    )
    return _invite_to_dict(row)


@router.delete("/invites/{invite_id}")
def delete_invite(invite_id: str, admin_id: str = Depends(require_admin), db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    from ..database.models import InviteCode

    row = db.get(InviteCode, invite_id)
    if not row:
        raise HTTPException(status_code=404, detail="invite not found")
    db.delete(row)
    db.commit()
    security_log.security_event("invite_deleted", admin=admin_id, invite_id=invite_id)
    return {"deleted": invite_id}


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str


@router.post("/change-password")
def change_password(req: ChangePasswordRequest, request: Request, db: Session = Depends(get_db)):
    user = _bearer_user(request, db)
    if not _user_password_ok(req.new_password):
        raise HTTPException(
            status_code=400,
            detail="password must be at least 8 characters and contain letters and digits",
        )
    if _role_of(user) == "admin" and not _admin_password_ok(req.new_password):
        raise HTTPException(
            status_code=400,
            detail="admin password must be at least 12 characters and contain letters and digits",
        )
    if not _uniform_verify(req.old_password, user.password_hash):
        chg_key = f"chg:{_client_ip(request)}:{user.id}"
        _record_ip_failure(_auth_failures, chg_key)
        locked = _ip_failures_exceeded(_auth_failures, chg_key, AUTH_FAILURE_LIMIT)
        security_log.security_event("change_password_failed", user_id=user.id, username=user.username)
        if locked:
            raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
        raise HTTPException(status_code=401, detail="wrong password")
    _clear_failures(f"chg:{_client_ip(request)}:{user.id}")
    new_hash = hash_password(req.new_password)
    with write_slot:
        new_epoch = crud.change_password_cas(db, user.id, user.password_hash, new_hash)
    if new_epoch is None:
        security_log.security_event("change_password_stale_race", user_id=user.id, username=user.username)
        chg_key = f"chg:{_client_ip(request)}:{user.id}"
        _record_ip_failure(_auth_failures, chg_key)
        raise HTTPException(status_code=401, detail="wrong password")
    security_log.security_event("password_changed", user_id=user.id, username=user.username)
    db.refresh(user)
    user.token_epoch = new_epoch
    return {"changed": True, "token": make_token_for(user)}


def _ensure_worker_capacity(db: Session) -> None:
    from ..database.models import User

    active_workers = db.query(User).filter(User.role == "worker", User.active == 1).count()
    if active_workers >= max(1, int(settings.worker_max_active)):
        raise HTTPException(status_code=409, detail="worker limit reached")


class ActiveRequest(BaseModel):
    active: bool


class RoleRequest(BaseModel):
    role: str


@router.patch("/users/{user_id}/active")
def set_user_active(user_id: str, req: ActiveRequest, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="user not found")
    if user.username == settings.admin_truong_username and not req.active:
        raise HTTPException(status_code=400, detail="cannot disable admin truong")
    if req.active and getattr(user, "active", 1) == 0 and (user.role or "user") == "worker":
        _ensure_worker_capacity(db)
    crud.set_user_active(db, user_id, req.active)
    if not req.active:
        crud.bump_token_epoch(db, user_id)
    security_log.security_event(
        "user_active_changed", admin=admin_id, user_id=user_id, username=user.username, active=req.active
    )
    return {"id": user_id, "username": user.username, "active": req.active}


@router.patch("/users/{user_id}/role")
def set_user_role(user_id: str, req: RoleRequest, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="user not found")
    if user.username == settings.admin_truong_username:
        raise HTTPException(status_code=400, detail="cannot change admin truong role")
    target_role = (req.role or "").strip().lower()
    if target_role not in ("user", "worker"):
        raise HTTPException(status_code=400, detail="role must be user or worker")
    old_role = _role_of(user)
    if target_role != old_role:
        if target_role == "worker" and getattr(user, "active", 1) == 1:
            _ensure_worker_capacity(db)
        crud.set_user_role(db, user_id, target_role)
        crud.bump_token_epoch(db, user_id)
        security_log.security_event(
            "user_role_changed",
            admin=admin_id,
            user_id=user_id,
            username=user.username,
            old_role=old_role,
            new_role=target_role,
        )
    return {"id": user_id, "username": user.username, "role": target_role}


@router.delete("/users/{user_id}")
def delete_user(user_id: str, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="user not found")
    if user.username == settings.admin_truong_username:
        raise HTTPException(status_code=400, detail="cannot delete admin truong")
    username = user.username
    crud.delete_user_everything(db, user_id)
    security_log.security_event("user_deleted", admin=admin_id, user_id=user_id, username=username)
    return {"deleted": user_id, "username": username}


class AdminCreateUserRequest(BaseModel):
    username: str
    email: str = ""
    password: str = ""
    note: str = ""
    role: str = "user"


class AdminUnlockRequest(BaseModel):
    password: str


@router.post("/admin-unlock")
def admin_unlock(req: AdminUnlockRequest, request: Request, db: Session = Depends(get_db), admin_id: str = Depends(require_admin)):
    unlock_key = f"unlock:{_client_ip(request)}:{admin_id}"
    unlock_ident_key = f"unlock-ident:{admin_id}"
    if not rate_limit.hit_and_allow(f"unlock-try:{_client_ip(request)}", 20):
        security_log.security_event("admin_unlock_rate_limited", admin=admin_id, ip=_client_ip(request))
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    user = crud.get_user_by_id(db, admin_id)
    if user and _uniform_verify(req.password, user.password_hash):
        with _auth_failures_lock:
            _admin_unlock_failures.pop(unlock_key, None)
            _admin_unlock_failures.pop(unlock_ident_key, None)
        _admin_unlocks[admin_id] = time.time()
        security_log.security_event("admin_unlock", admin=admin_id)
        return {"unlocked": True, "window_seconds": settings.admin_unlock_window_seconds}
    ident_exceeded = _ip_failures_exceeded(_admin_unlock_failures, unlock_ident_key, _ADMIN_UNLOCK_FAILURE_LIMIT)
    ip_exceeded = _ip_failures_exceeded(_admin_unlock_failures, unlock_key, _ADMIN_UNLOCK_FAILURE_LIMIT)
    if ident_exceeded or ip_exceeded:
        security_log.security_event("admin_unlock_rate_limited", admin=admin_id, ip=_client_ip(request))
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    _record_ip_failure(_admin_unlock_failures, unlock_key)
    _record_ip_failure(_admin_unlock_failures, unlock_ident_key)
    security_log.security_event("admin_unlock_failed", admin=admin_id, ip=_client_ip(request))
    raise HTTPException(status_code=401, detail="wrong password")


@router.post("/users")
def admin_create_user(req: AdminCreateUserRequest, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    u = req.username.strip()
    if not u or len(u) < 3 or len(u) > 32:
        raise HTTPException(status_code=400, detail="username must be 3-32 characters")
    if not USERNAME_RE.fullmatch(u):
        raise HTTPException(status_code=400, detail="username may only contain letters, digits, dot, underscore, hyphen")
    if u.lower() in RESERVED_USERNAMES:
        raise HTTPException(status_code=400, detail="username is reserved")
    admin_lower = settings.admin_truong_username.lower()
    if u.lower() == admin_lower and u != settings.admin_truong_username:
        raise HTTPException(status_code=400, detail="username conflicts with the admin truong account")
    if u.lower().replace(".", "").replace("_", "") == admin_lower and u.lower() != admin_lower:
        raise HTTPException(status_code=400, detail="username impersonates the admin truong account")
    role = (req.role or "user").strip().lower()
    if role not in ("user", "worker"):
        raise HTTPException(status_code=400, detail="role must be user or worker")
    if role == "worker":
        _ensure_worker_capacity(db)
    e = req.email.strip().lower()
    if e and not EMAIL_RE.fullmatch(e):
        raise HTTPException(status_code=400, detail="invalid email address")
    generated = not req.password.strip()
    p = req.password.strip() or _generate_temp_password(12)
    if not _user_password_ok(p):
        raise HTTPException(
            status_code=400,
            detail="password must be at least 8 characters and contain letters and digits",
        )
    if crud.get_user(db, u):
        raise HTTPException(status_code=409, detail="username already exists")
    if e and crud.get_user_by_email(db, e):
        raise HTTPException(status_code=409, detail="email already registered")
    try:
        user = crud.create_user(db, username=u, email=e, password_hash=hash_password(p), must_change_password=True, role=role)
    except IntegrityError:
        raise HTTPException(status_code=409, detail="username or email already exists")
    security_log.security_event("user_created_by_admin", admin=admin_id, username=u, user_id=user.id, role=role, note=req.note.strip())
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
        "temp_password": p,
        "generated": generated,
        "must_change_password": True,
    }


@router.post("/users/{user_id}/reset-password")
def admin_reset_password(user_id: str, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db)):
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="user not found")
    if user.username == settings.admin_truong_username:
        temp = _generate_temp_password(16)
    else:
        temp = _generate_temp_password(12)
    temp_hash = hash_password(temp)
    with write_slot:
        crud.reset_user_password(db, user_id, temp_hash)
        crud.set_must_change_password(db, user_id, True)
        crud.bump_token_epoch(db, user_id)
    security_log.security_event("password_reset_by_admin", admin=admin_id, user_id=user_id, username=user.username)
    return {"id": user_id, "temp_password": temp, "must_change_password": True}


@router.post("/revoke-all")
def revoke_all_tokens(request: Request, db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    user = _bearer_user(request, db)
    crud.bump_token_epoch(db, user.id)
    security_log.security_event("tokens_revoked", user_id=user.id, username=user.username)
    return {"revoked": True}


@router.get("/users")
def list_users(limit: int = 50, offset: int = 0, staff_id: str = Depends(require_staff), db: Session = Depends(get_db)):
    total, rows = crud.list_users(db, limit=max(1, min(limit, 200)), offset=max(0, offset))
    return {"items": rows, "total": total}
