from typing import Optional, List
from pathlib import Path
import hashlib
import hmac
import json
import logging
import secrets
import threading
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import get_db
from ..database import crud
from .. import security_log

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

PBKDF2_ITERATIONS = 600_000
LEGACY_PBKDF2_ITERATIONS = 100_000

AUTH_FAILURE_LIMIT = 5
AUTH_FAILURE_WINDOW = 900.0
_auth_failures: dict = {}
_auth_failures_lock = threading.Lock()
_invite_lock = threading.Lock()


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
        stamps = [t for t in _auth_failures.get(key, []) if now - t < AUTH_FAILURE_WINDOW]
        stamps.append(now)
        _auth_failures[key] = stamps


def _clear_failures(key: str) -> None:
    with _auth_failures_lock:
        _auth_failures.pop(key, None)


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


def make_token(user_id: str) -> str:
    expires = int(time.time()) + settings.token_ttl_hours * 3600
    payload = f"{user_id}.{expires}"
    sig = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"


def parse_token(token: str) -> str:
    try:
        user_id, expires, sig = token.split(".", 2)
    except ValueError:
        raise HTTPException(status_code=401, detail="invalid token")
    payload = f"{user_id}.{expires}"
    expected = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected):
        raise HTTPException(status_code=401, detail="invalid token")
    if int(expires) < time.time():
        raise HTTPException(status_code=401, detail="token expired")
    return user_id


class RegisterRequest(BaseModel):
    username: str
    email: str
    password: str
    invite_code: str


class LoginRequest(BaseModel):
    identifier: Optional[str] = None
    username: Optional[str] = None
    password: str


def require_user(request: Request, db: Session = Depends(get_db)) -> Optional[str]:
    if not settings.auth_required:
        return None
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id = parse_token(header[7:].strip())
    if not crud.get_user_by_id(db, user_id):
        raise HTTPException(status_code=401, detail="unknown user")
    return user_id


def require_admin(request: Request, db: Session = Depends(get_db)) -> str:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id = parse_token(header[7:].strip())
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="unknown user")
    if (user.role or "user") != "admin" or user.username != settings.admin_truong_username:
        raise HTTPException(status_code=403, detail="admin truong only")
    return user.id


def _role_of(user) -> str:
    return user.role or "user"


def _validate_registration(db: Session, u: str, e: str, p: str, c: str) -> None:
    if not u or len(u) < 3:
        raise HTTPException(status_code=400, detail="username must be at least 3 characters")
    if not e.endswith("@gmail.com") or len(e) <= 10:
        raise HTTPException(status_code=400, detail="only @gmail.com addresses are supported")
    if len(p) < 6:
        raise HTTPException(status_code=400, detail="password must be at least 6 characters")
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

    key = f"register:{_client_ip(request)}:{u.lower()}"
    if _attempts_exceeded(key):
        security_log.security_event("register_rate_limited", ip=_client_ip(request), username=u)
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")
    with _invite_lock:
        try:
            _validate_registration(db, u, e, p, c)
        except HTTPException as exc:
            _record_failure(key)
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
            security_log.security_event("register_failed", ip=_client_ip(request), username=u, detail="duplicate")
            raise HTTPException(status_code=409, detail="username or email already exists")

    _clear_failures(key)
    security_log.security_event("register_success", ip=_client_ip(request), username=u, user_id=user.id)
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
        "token": make_token(user.id),
    }


@router.post("/login")
def login(req: LoginRequest, request: Request, db: Session = Depends(get_db)):
    login_id = (req.identifier or req.username or "").strip()
    if not login_id or not req.password:
        raise HTTPException(status_code=400, detail="identifier and password required")

    key = f"login:{_client_ip(request)}:{login_id.lower()}"
    if _attempts_exceeded(key):
        security_log.security_event("login_rate_limited", ip=_client_ip(request), identifier=login_id)
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")

    user = crud.get_user_by_identifier(db, login_id)
    if not user or not verify_password(req.password, user.password_hash):
        _record_failure(key)
        security_log.security_event("login_failed", ip=_client_ip(request), identifier=login_id)
        raise HTTPException(status_code=401, detail="wrong credentials")

    if _password_iterations(user.password_hash) < PBKDF2_ITERATIONS:
        crud.update_user_password(db, user.id, hash_password(req.password))
        security_log.security_event("password_rehashed", user_id=user.id, username=user.username)

    _clear_failures(key)
    security_log.security_event("login_success", ip=_client_ip(request), username=user.username, user_id=user.id)
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
        "token": make_token(user.id),
    }


@router.get("/me")
def get_me(request: Request, db: Session = Depends(get_db)):
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id = parse_token(header[7:].strip())
    user = crud.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="user not found")
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": _role_of(user),
    }


class InviteCreateRequest(BaseModel):
    code: str = ""
    note: str = ""


def _generate_invite_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "HUE-" + "".join(secrets.choice(alphabet) for _ in range(8))


@router.get("/invites")
def list_invites(admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    from ..database.models import InviteCode

    rows = db.query(InviteCode).order_by(InviteCode.created_at.desc()).all()
    return [
        {
            "id": r.id,
            "code": r.code,
            "note": r.note or "",
            "used": r.used_by is not None,
            "used_at": str(r.used_at) if r.used_at else None,
            "created_at": str(r.created_at),
        }
        for r in rows
    ]


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


@router.get("/users")
def list_users(admin_id: str = Depends(require_admin), db: Session = Depends(get_db)):
    return crud.list_users(db)
