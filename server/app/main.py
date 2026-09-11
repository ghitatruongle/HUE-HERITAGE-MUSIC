from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .api.router import api_router

app = FastAPI(title=settings.app_name, version="0.0.0-demo")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(api_router, prefix="/api")


@app.get("/health")
def health():
    return {"status": "ok", "app": settings.app_name, "stage": "GD0"}
