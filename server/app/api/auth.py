from typing import Optional, List
from pathlib import Path
import hashlib
import hmac
import json
import logging
import re
import secrets
import threading
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import acquire_write_slot, get_db, SessionLocal
from ..database import crud
from .. import rate_limit, security_log

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

PBKDF2_ITERATIONS = 600_000
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


def _uniform_verify(password: str, stored: Optional[str]) -> bool:
    global _DUMMY_HASH
    if _DUMMY_HASH is None:
        _DUMMY_HASH = hash_password("timing-uniform-dummy-verification-hash")
    ok = verify_password(password, stored or _DUMMY_HASH)
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


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
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
        if epoch < (user.token_epoch or 0):
            raise HTTPException(status_code=401, detail="token revoked")
        if getattr(user, "active", 1) == 0:
            raise HTTPException(status_code=403, detail="account disabled")
        if getattr(user, "must_change_password", 0) and request.method not in ("GET", "HEAD", "OPTIONS"):
            path = request.url.path
            if not any(path == p or path.startswith(p + "/") for p in FORCE_CHANGE_ALLOWED_PATHS):
                raise HTTPException(status_code=403, detail="password change required")
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
    if epoch < (user.token_epoch or 0):
        raise HTTPException(status_code=401, detail="token revoked")
    if getattr(user, "active", 1) == 0:
        raise HTTPException(status_code=403, detail="account disabled")
    if (user.role or "user") != "admin" or user.username != settings.admin_truong_username:
        raise HTTPException(status_code=403, detail="admin truong only")
    return user.id


def require_admin_fresh(admin_id: str = Depends(require_admin)) -> str:
    ts = _admin_unlocks.get(admin_id)
    if ts is None or time.time() - ts > settings.admin_unlock_window_seconds:
        raise HTTPException(status_code=403, detail="admin reauth required")
    return admin_id


def _bearer_user(request: Request, db: Session):
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id, epoch = parse_token(header[7:].strip())
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="unknown user")
    if epoch < (user.token_epoch or 0):
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
    if user is None or epoch < (user.token_epoch or 0):
        return None
    if getattr(user, "active", 1) == 0:
        raise HTTPException(status_code=403, detail="account disabled")
    return user


def _role_of(user) -> str:
    return user.role or "user"


USERNAME_RE = re.compile(r"^[A-Za-z0-9._-]{3,32}$")


def _validate_registration(db: Session, u: str, e: str, p: str, c: str) -> None:
    if not u or len(u) < 3 or len(u) > 32:
        raise HTTPException(status_code=400, detail="username must be 3-32 characters")
    if not USERNAME_RE.fullmatch(u):
        raise HTTPException(status_code=400, detail="username may only contain letters, digits, dot, underscore, hyphen")
    if u.lower() in RESERVED_USERNAMES:
        raise HTTPException(status_code=400, detail="username is reserved")
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
def register(req: RegisterRequest, request: Request, db: Session = Depends(get_db), _write_slot: None = Depends(acquire_write_slot)):
    u = req.username.strip()
    e = req.email.strip().lower()
    p = req.password
    c = req.invite_code.strip()

    if not rate_limit.hit_and_allow(f"register-ip:{_client_ip(request)}", max(1, settings.register_ip_rate_limit)):
        security_log.security_event("register_ip_flood", ip=_client_ip(request))
        raise HTTPException(status_code=429, detail="too many requests, slow down")

    fail_key = f"regfail:{_client_ip(request)}"
    if _ip_failures_exceeded(_register_ip_failures, fail_key, max(1, settings.register_failure_ip_limit)):
        security_log.security_event("register_failures_ip_limited", ip=_client_ip(request))
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")

    key = f"register:{_client_ip(request)}:{u.lower()}"
    if _attempts_exceeded(key):
        security_log.security_event("register_rate_limited", ip=_client_ip(request), username=u)
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")
    with _invite_lock:
        try:
            _validate_registration(db, u, e, p, c)
        except HTTPException as exc:
            _record_failure(key)
            _record_ip_failure(_register_ip_failures, fail_key)
            security_log.security_event("register_failed", ip=_client_ip(request), username=u, detail=exc.detail)
            raise

        if crud.get_invite_code(db, c) is not None:
            if not crud.mark_invite_used(db, c, u):
                security_log.security_event("invite_code_conflict", code=c, username=u)
                raise HTTPException(status_code=409, detail="invitation code already used")

        try:
            user = crud.create_user(db, username=u, email=e, password_hash=hash_password(p))
        except IntegrityError:
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
        raise HTTPException(status_code=429, detail="too many requests, slow down")
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
            raise HTTPException(status_code=429, detail="too many failed attempts, try again later")
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
        "storage_used_bytes": crud.user_storage_bytes(db, user.id),
        "storage_quota_bytes": storage_quota_bytes,
        "token": make_token_for(user),
    }


class InviteCreateRequest(BaseModel):
    code: str = ""
    note: str = ""


def _generate_invite_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "HUE-" + "".join(secrets.choice(alphabet) for _ in range(8))


@router.get("/invites")
def list_invites(limit: int = 50, offset: int = 0, admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    from ..database.models import InviteCode

    base = db.query(InviteCode).order_by(InviteCode.created_at.desc())
    total = base.count()
    safe_offset = max(0, min(int(offset), 10**9))
    rows = base.offset(safe_offset).limit(max(1, min(limit, 200))).all()
    return {
        "total": total,
        "items": [
            {
                "id": r.id,
                "code": r.code,
                "note": r.note or "",
                "used": r.used_by is not None,
                "used_at": str(r.used_at) if r.used_at else None,
                "created_at": str(r.created_at),
            }
            for r in rows
        ],
    }


@router.post("/invites")
def create_invite(req: InviteCreateRequest, admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    code = req.code.strip() or _generate_invite_code()
    if len(code) < 4 or len(code) > 64:
        raise HTTPException(status_code=400, detail="code must be 4-64 characters")
    if crud.get_invite_code(db, code):
        raise HTTPException(status_code=409, detail="code already exists")
    row = crud.create_invite_code(db, code, req.note.strip())
    security_log.security_event("invite_created", admin=admin_id, code=code)
    return {
        "id": row.id,
        "code": row.code,
        "note": row.note or "",
        "used": False,
        "used_at": None,
        "created_at": str(row.created_at),
    }


@router.delete("/invites/{invite_id}")
def delete_invite(invite_id: str, admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
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
        security_log.security_event("change_password_failed", user_id=user.id, username=user.username)
        raise HTTPException(status_code=401, detail="wrong password")
    crud.update_user_password(db, user.id, hash_password(req.new_password))
    crud.set_must_change_password(db, user.id, False)
    new_epoch = crud.bump_token_epoch(db, user.id)
    security_log.security_event("password_changed", user_id=user.id, username=user.username)
    db.refresh(user)
    user.token_epoch = new_epoch
    return {"changed": True, "token": make_token_for(user)}


class ActiveRequest(BaseModel):
    active: bool


@router.patch("/users/{user_id}/active")
def set_user_active(user_id: str, req: ActiveRequest, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db)):
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="user not found")
    if user.username == settings.admin_truong_username and not req.active:
        raise HTTPException(status_code=400, detail="cannot disable admin truong")
    crud.set_user_active(db, user_id, req.active)
    if not req.active:
        crud.bump_token_epoch(db, user_id)
    security_log.security_event(
        "user_active_changed", admin=admin_id, user_id=user_id, username=user.username, active=req.active
    )
    return {"id": user_id, "username": user.username, "active": req.active}


@router.delete("/users/{user_id}")
def delete_user(user_id: str, admin_id: str = Depends(require_admin_fresh), db: Session = Depends(get_db)):
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


class AdminUnlockRequest(BaseModel):
    password: str


@router.post("/admin-unlock")
def admin_unlock(req: AdminUnlockRequest, request: Request, db: Session = Depends(get_db), admin_id: str = Depends(require_admin)):
    unlock_key = f"unlock:{_client_ip(request)}:{admin_id}"
    if not rate_limit.hit_and_allow(f"unlock-try:{_client_ip(request)}", 20):
        security_log.security_event("admin_unlock_rate_limited", admin=admin_id, ip=_client_ip(request))
        raise HTTPException(status_code=429, detail="too many requests, slow down")
    user = crud.get_user_by_id(db, admin_id)
    if user and _uniform_verify(req.password, user.password_hash):
        with _auth_failures_lock:
            _admin_unlock_failures.pop(unlock_key, None)
        _admin_unlocks[admin_id] = time.time()
        security_log.security_event("admin_unlock", admin=admin_id)
        return {"unlocked": True, "window_seconds": settings.admin_unlock_window_seconds}
    if _ip_failures_exceeded(_admin_unlock_failures, unlock_key, _ADMIN_UNLOCK_FAILURE_LIMIT):
        security_log.security_event("admin_unlock_rate_limited", admin=admin_id, ip=_client_ip(request))
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")
    _record_ip_failure(_admin_unlock_failures, unlock_key)
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
    e = req.email.strip().lower()
    if e and not EMAIL_RE.fullmatch(e):
        raise HTTPException(status_code=400, detail="invalid email address")
    generated = not req.password.strip()
    p = req.password.strip() or ("hue-" + secrets.token_hex(4))
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
        user = crud.create_user(db, username=u, email=e, password_hash=hash_password(p), must_change_password=True)
    except IntegrityError:
        raise HTTPException(status_code=409, detail="username or email already exists")
    security_log.security_event("user_created_by_admin", admin=admin_id, username=u, user_id=user.id, note=req.note.strip())
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
        temp = "hue-" + secrets.token_urlsafe(12)
    else:
        temp = "hue-" + secrets.token_hex(4)
    crud.reset_user_password(db, user_id, hash_password(temp))
    crud.set_must_change_password(db, user_id, True)
    crud.bump_token_epoch(db, user_id)
    security_log.security_event("password_reset_by_admin", admin=admin_id, user_id=user_id, username=user.username)
    return {"id": user_id, "temp_password": temp, "must_change_password": True}


@router.post("/revoke-all")
def revoke_all_tokens(request: Request, db: Session = Depends(get_db)):
    user = _bearer_user(request, db)
    crud.bump_token_epoch(db, user.id)
    security_log.security_event("tokens_revoked", user_id=user.id, username=user.username)
    return {"revoked": True}


@router.get("/users")
def list_users(limit: int = 50, offset: int = 0, admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    total, rows = crud.list_users(db, limit=max(1, min(limit, 200)), offset=max(0, offset))
    return {"items": rows, "total": total}
