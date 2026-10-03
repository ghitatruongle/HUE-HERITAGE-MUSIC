from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from .config import settings
from .api.router import api_router
from .database.session import init_db, SessionLocal
from .database import crud


def create_app() -> FastAPI:
    init_db()
    db = SessionLocal()
    try:
        crud.fail_stale_running_tasks(db)
    finally:
        db.close()
    application = FastAPI(title=settings.app_name, version="0.0.0-beta3")
    application.add_middleware(GZipMiddleware, minimum_size=1000)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in settings.allowed_origins.split(",") if o.strip()],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    application.include_router(api_router, prefix="/api")

    @application.get("/health")
    def health():
        return {"status": "ok", "app": settings.app_name, "version": "0.0.0-beta3", "stage": "GD0"}

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
                    "Clear-Site-Data": "\"cache\", \"storage\"",
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
                    "Clear-Site-Data": "\"cache\", \"storage\"",
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
