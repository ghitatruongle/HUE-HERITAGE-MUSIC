from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .api.router import api_router
from .database.session import init_db


def create_app() -> FastAPI:
    init_db()
    application = FastAPI(title=settings.app_name, version="0.0.0-alpha2")
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
        return {"status": "ok", "app": settings.app_name, "stage": "GD0"}

    return application


app = create_app()
