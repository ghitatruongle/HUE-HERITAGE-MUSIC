import hashlib
import hmac
import secrets
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..database.session import get_db
from ..database import crud

router = APIRouter(prefix="/auth", tags=["auth"])

PBKDF2_ITERATIONS = 100_000


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ITERATIONS).hex()
    return f"{salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    try:
        salt, digest = stored.split("$", 1)
    except ValueError:
        return False
    calc = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ITERATIONS).hex()
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


class Credentials(BaseModel):
    username: str
    password: str


def require_user(request: Request, db: Session = Depends(get_db)) -> str | None:
    if not settings.auth_required:
        return None
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="authentication required")
    user_id = parse_token(header[7:].strip())
    if not crud.get_user_by_id(db, user_id):
        raise HTTPException(status_code=401, detail="unknown user")
    return user_id


@router.post("/register")
def register(creds: Credentials, db: Session = Depends(get_db)):
    if not creds.username.strip() or len(creds.password) < 4:
        raise HTTPException(status_code=400, detail="bad username or password")
    if crud.get_user(db, creds.username.strip()):
        raise HTTPException(status_code=409, detail="username exists")
    try:
        user = crud.create_user(db, creds.username.strip(), hash_password(creds.password))
    except IntegrityError:
        raise HTTPException(status_code=409, detail="username exists")
    return {"id": user.id, "username": user.username, "token": make_token(user.id)}


@router.post("/login")
def login(creds: Credentials, db: Session = Depends(get_db)):
    user = crud.get_user(db, creds.username.strip())
    if not user or not verify_password(creds.password, user.password_hash):
        raise HTTPException(status_code=401, detail="wrong credentials")
    return {"id": user.id, "username": user.username, "token": make_token(user.id)}
