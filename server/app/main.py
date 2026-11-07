from pathlib import Path
import os
import shutil
import threading

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.datastructures import MutableHeaders
from .config import settings, INSECURE_SECRET_KEYS, MIN_SECRET_KEY_LENGTH
from .api.router import api_router
from .database.session import init_db, SessionLocal
from .database import crud
from . import rate_limit

AUDIO_SUFFIXES = (
    ".mp3",
    ".wav",
    ".flac",
    ".ogg",
    ".m4a",
    ".aac",
    ".opus",
    ".aiff",
    ".mid",
    ".midi",
    ".musicxml",
)

HEAVY_POST_PREFIXES = ("/api/music/", "/api/lessons/")
HEAVY_POST_PATHS = ("/api/task", "/api/heritage/upload")
LARGE_BODY_PREFIXES = ("/api/lessons/",)
LARGE_BODY_PATHS = ("/api/music/analyze-pitch", "/api/music/compare")
LARGE_BODY_LIMIT = 15 * 1024 * 1024


class SecurityHeadersMiddleware:
    CSP = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data: blob:; "
        "font-src 'self' data: https://fonts.gstatic.com; "
        "connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com; "
        "worker-src 'self' blob:; "
        "object-src 'none'; "
        "base-uri 'self'; "
        "form-action 'self'; "
        "frame-ancestors 'none'"
    )

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_wrapper(message):
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                headers.setdefault("X-Content-Type-Options", "nosniff")
                headers.setdefault("X-Frame-Options", "DENY")
                headers.setdefault("Referrer-Policy", "no-referrer")
                headers.setdefault("Content-Security-Policy", self.CSP)
            await send(message)

        await self.app(scope, receive, send_wrapper)


class NoGzipAudioMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            path = scope.get("path", "")
            if path.lower().endswith(AUDIO_SUFFIXES):
                headers = MutableHeaders(scope=scope)
                if "accept-encoding" in headers:
                    headers["accept-encoding"] = "identity"
        await self.app(scope, receive, send)


class HeavyRateLimitMiddleware:
    """Giới hạn POST nặng: ẩn danh theo IP (heavy_rate_limit/phút),
    người dùng đã đăng nhập (token HMAC hợp lệ) được hạn mức riêng rộng hơn."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http" and scope.get("method") == "POST":
            path = scope.get("path", "")
            heavy = path in HEAVY_POST_PATHS or any(path.startswith(p) for p in HEAVY_POST_PREFIXES)
            if heavy:
                headers = MutableHeaders(scope=scope)
                auth = headers.get("Authorization", "")
                if auth.startswith("Bearer "):
                    try:
                        from .api.auth import parse_token

                        user_id, _epoch = parse_token(auth[7:].strip())
                        bucket = f"heavy:user:{user_id}"
                        limit = max(1, settings.heavy_rate_limit) * 3
                    except HTTPException:
                        bucket = None
                        limit = 0
                else:
                    bucket = None
                    limit = 0
                if bucket is None:
                    client = scope.get("client") or ("unknown", 0)
                    bucket = f"heavy:{client[0]}"
                    limit = max(1, settings.heavy_rate_limit)
                if not rate_limit.hit_and_allow(bucket, limit):
                    from . import security_log

                    security_log.security_event("heavy_rate_limited", bucket=bucket, path=path)
                    response = JSONResponse(
                        {"detail": "too many requests, slow down"},
                        status_code=429,
                        headers={"Retry-After": "30"},
                    )
                    await response(scope, receive, send)
                    return
        await self.app(scope, receive, send)


class BodyLimitMiddleware:
    def __init__(self, app, default_limit=2 * 1024 * 1024):
        self.app = app
        self.default_limit = default_limit

    def _limit_for(self, path: str) -> int:
        if path.startswith("/api/heritage/upload"):
            return 50 * 1024 * 1024 + 2 * 1024 * 1024
        if path.startswith(LARGE_BODY_PREFIXES) or path in LARGE_BODY_PATHS:
            return LARGE_BODY_LIMIT
        return self.default_limit

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope.get("method") not in ("POST", "PUT", "PATCH"):
            await self.app(scope, receive, send)
            return
        path = scope.get("path", "")
        if not path.startswith("/api/"):
            await self.app(scope, receive, send)
            return
        limit = self._limit_for(path)
        if limit > LARGE_BODY_LIMIT:
            await self._stream_limit(scope, receive, send, limit)
            return
        body = b""
        over = False
        while True:
            msg = await receive()
            if msg["type"] == "http.request":
                chunk = msg.get("body", b"")
                if not over:
                    body += chunk
                    if len(body) > limit:
                        over = True
                        body = b""
                if not msg.get("more_body"):
                    break
            elif msg["type"] == "http.disconnect":
                return
        if over:
            response = JSONResponse({"detail": "request body too large"}, status_code=413)
            await response(scope, receive, send)
            return
        sent = {"done": False}

        async def replay_receive():
            if not sent["done"]:
                sent["done"] = True
                return {"type": "http.request", "body": body, "more_body": False}
            return {"type": "http.disconnect"}

        await self.app(scope, replay_receive, send)

    async def _stream_limit(self, scope, receive, send, limit):
        from fastapi import HTTPException

        total = 0

        async def counting_receive():
            nonlocal total
            msg = await receive()
            if msg["type"] == "http.request":
                total += len(msg.get("body", b""))
                if total > limit:
                    raise HTTPException(status_code=413, detail="file too large")
            return msg

        await self.app(scope, counting_receive, send)


class SheddingMiddleware:
    def __init__(self, app, max_in_flight=0):
        self.app = app
        self.max_in_flight = max_in_flight
        self.in_flight = 0

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or self.max_in_flight <= 0:
            await self.app(scope, receive, send)
            return
        if self.in_flight >= self.max_in_flight:
            response = JSONResponse(
                {"detail": "server busy, retry shortly"},
                status_code=503,
                headers={"Retry-After": "5", "Connection": "close"},
            )
            await response(scope, receive, send)
            return
        self.in_flight += 1
        try:
            await self.app(scope, receive, send)
        finally:
            self.in_flight -= 1


def _validate_secret_key() -> None:
    if not settings.auth_required:
        return
    key = settings.secret_key
    if key in INSECURE_SECRET_KEYS:
        raise RuntimeError(
            "AUTH_REQUIRED=true refuses a well-known placeholder SECRET_KEY; "
            "generate a long random value (e.g. python -c \"import secrets;print(secrets.token_hex(32))\") "
            "and set it in server/.env"
        )
    if len(key) < MIN_SECRET_KEY_LENGTH:
        raise RuntimeError(
            f"AUTH_REQUIRED=true requires SECRET_KEY of at least {MIN_SECRET_KEY_LENGTH} characters"
        )


def _warmup_lessons():
    import time as _time

    from .services import lesson_service

    _time.sleep(3.0)
    db = SessionLocal()
    try:
        items = crud.get_creation_tunes(db)
        if not items:
            items = crud.list_items(db, limit=100)
        ids = [item.id for item in items]
    except Exception:
        db.close()
        return
    db.close()
    for item_id in ids:
        db = SessionLocal()
        try:
            item = crud.get_item(db, item_id)
            if item is None:
                continue
            if lesson_service._lesson_cache_path(item).exists():
                continue
            try:
                lesson_service.build_lesson(item)
            except Exception:
                continue
        finally:
            db.close()


def _raise_fd_limit():
    try:
        import resource

        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        target = 262144 if hard > 262144 else hard
        if soft < target:
            resource.setrlimit(resource.RLIMIT_NOFILE, (target, hard))
    except Exception:
        pass


def create_app() -> FastAPI:
    _raise_fd_limit()
    _validate_secret_key()
    init_db()
    db = SessionLocal()
    try:
        crud.fail_stale_running_tasks(db)
        crud.prune_old_tasks(db, settings.task_retention_days)
    finally:
        db.close()
    docs_open = settings.enable_docs
    application = FastAPI(
        title=settings.app_name,
        version="0.0.2-beta1",
        docs_url="/docs" if docs_open else None,
        redoc_url="/redoc" if docs_open else None,
        openapi_url="/openapi.json" if docs_open else None,
    )
    application.add_middleware(GZipMiddleware, minimum_size=1000)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in settings.allowed_origins.split(",") if o.strip()],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    application.add_middleware(SecurityHeadersMiddleware)
    application.add_middleware(NoGzipAudioMiddleware)
    application.add_middleware(HeavyRateLimitMiddleware)
    application.add_middleware(BodyLimitMiddleware)
    application.add_middleware(SheddingMiddleware, max_in_flight=settings.shed_concurrency)
    if settings.auth_required and settings.allowed_origins.strip() == "*":
        import logging

        logging.getLogger(__name__).warning(
            "ALLOWED_ORIGINS=* while AUTH_REQUIRED=true; set an explicit origin list for production"
        )
    application.include_router(api_router, prefix="/api")

    @application.on_event("startup")
    async def _post_startup():
        import anyio.to_thread

        limiter = anyio.to_thread.current_default_thread_limiter()
        limiter.total_tokens = 192
        threading.Thread(target=_warmup_lessons, daemon=True).start()

    @application.get("/health")
    async def health():
        payload = {
            "status": "ok",
            "app": settings.app_name,
            "version": "0.0.2-beta1",
            "stage": "0.0.2-beta1",
        }
        if os.environ.get("HUE_HEALTH_EXTENDED") == "1":
            import asyncio

            def _extended():
                from .ai import ace_step_engine

                with SessionLocal() as db:
                    running = crud.list_tasks(db, status="running", limit=500)
                    queued = crud.list_tasks(db, status="queued", limit=500)
                try:
                    disk_free_gb = shutil.disk_usage(settings.storage_dir).free / 1024**3
                except Exception:
                    disk_free_gb = None
                return {
                    "engine_online": ace_step_engine.api_available(),
                    "tasks_running": len(running),
                    "tasks_queued": len(queued),
                    "disk_free_gb": round(disk_free_gb, 1) if disk_free_gb is not None else None,
                }

            payload.update(await asyncio.to_thread(_extended))
        return payload

    web_dir = Path(settings.web_dir)
    if web_dir.exists() and (web_dir / "index.html").exists():
        for sub in ("assets", "canvaskit", "icons"):
            sub_dir = web_dir / sub
            if sub_dir.exists():
                application.mount(f"/{sub}", StaticFiles(directory=str(sub_dir)), name=f"web_{sub}")

        @application.api_route("/", methods=["GET", "HEAD"])
        def serve_root():
            return FileResponse(
                web_dir / "index.html",
                headers={
                    "Cache-Control": "no-cache, no-store, must-revalidate, max-age=0",
                    "Pragma": "no-cache",
                    "Expires": "0",
                },
            )

        @application.api_route("/{full_path:path}", methods=["GET", "HEAD"])
        def serve_web(full_path: str):
            if full_path.startswith("api/") or full_path == "api":
                raise HTTPException(status_code=404, detail="Not Found")
            if ".." in full_path or "%2e" in full_path.lower():
                raise HTTPException(status_code=400, detail="bad path")
            target = (web_dir / full_path).resolve()
            if not target.is_relative_to(web_dir.resolve()):
                raise HTTPException(status_code=400, detail="bad path")
            if full_path and target.is_file():
                if target.suffix in (".html", ".json", ".js", ".mjs", ".wasm", ".map") or target.name in ("index.html", "version.json", "flutter_bootstrap.js", "flutter_service_worker.js", "main.dart.js"):
                    headers = {
                        "Cache-Control": "no-cache, no-store, must-revalidate, max-age=0",
                        "Pragma": "no-cache",
                        "Expires": "0",
                    }
                else:
                    headers = {"Cache-Control": "public, max-age=3600"}
                return FileResponse(target, headers=headers)
            return FileResponse(
                web_dir / "index.html",
                headers={
                    "Cache-Control": "no-cache, no-store, must-revalidate, max-age=0",
                    "Pragma": "no-cache",
                    "Expires": "0",
                },
            )
    else:
        @application.get("/")
        def no_web():
            return {
                "status": "ok",
                "message": "Hue Heritage Music API running. Build Flutter Web app in app/ to enable web UI.",
            }

    return application


app = create_app()
