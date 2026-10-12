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

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

PBKDF2_ITERATIONS = 600_000
LEGACY_PBKDF2_ITERATIONS = 100_000

AUTH_FAILURE_LIMIT = 5
AUTH_FAILURE_WINDOW = 900.0
_auth_failures: dict = {}
_auth_failures_lock = threading.Lock()


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


def get_valid_invite_codes() -> List[str]:
    codes_path = Path(__file__).resolve().parent.parent.parent / "INVITATION_CODES.json"
    if codes_path.exists():
        try:
            data = json.loads(codes_path.read_text(encoding="utf-8"))
            codes = data.get("valid_codes", [])
            if isinstance(codes, list) and codes:
                return [str(c).strip() for c in codes if str(c).strip()]
            logger.warning("INVITATION_CODES.json has no usable valid_codes list")
        except Exception:
            logger.warning(
                "INVITATION_CODES.json is malformed; falling back to configured invite codes",
                exc_info=True,
            )
    if settings.invite_codes:
        return [c.strip() for c in settings.invite_codes.split(",") if c.strip()]
    return ["QHH2026"]


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


def _validate_registration(db: Session, u: str, e: str, p: str, c: str) -> None:
    if not u or len(u) < 3:
        raise HTTPException(status_code=400, detail="username must be at least 3 characters")
    if not e.endswith("@gmail.com") or len(e) <= 10:
        raise HTTPException(status_code=400, detail="only @gmail.com addresses are supported")
    if len(p) < 6:
        raise HTTPException(status_code=400, detail="password must be at least 6 characters")
    if c not in get_valid_invite_codes():
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
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")
    try:
        _validate_registration(db, u, e, p, c)
    except HTTPException:
        _record_failure(key)
        raise

    try:
        user = crud.create_user(db, username=u, email=e, password_hash=hash_password(p))
    except IntegrityError:
        _record_failure(key)
        raise HTTPException(status_code=409, detail="username or email already exists")

    _clear_failures(key)
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "token": make_token(user.id),
    }


@router.post("/login")
def login(req: LoginRequest, request: Request, db: Session = Depends(get_db)):
    login_id = (req.identifier or req.username or "").strip()
    if not login_id or not req.password:
        raise HTTPException(status_code=400, detail="identifier and password required")

    key = f"login:{_client_ip(request)}:{login_id.lower()}"
    if _attempts_exceeded(key):
        raise HTTPException(status_code=429, detail="too many failed attempts, try again later")

    user = crud.get_user_by_identifier(db, login_id)
    if not user or not verify_password(req.password, user.password_hash):
        _record_failure(key)
        raise HTTPException(status_code=401, detail="wrong credentials")

    _clear_failures(key)
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
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
    }
