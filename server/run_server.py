import uvicorn

from app.config import settings

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        proxy_headers=False,
        limit_concurrency=settings.uvicorn_limit_concurrency,
        backlog=settings.uvicorn_backlog,
    )
