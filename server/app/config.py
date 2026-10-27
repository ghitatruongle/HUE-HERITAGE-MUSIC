import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
SERVER_DIR = Path(__file__).resolve().parents[1]

INSECURE_DEFAULT_SECRET_KEY = "dev-insecure-secret-key"
INSECURE_SECRET_KEYS = {
    INSECURE_DEFAULT_SECRET_KEY,
    "change-me",
    "changeme",
    "secret",
    "change-me-to-a-long-random-string",
}
MIN_SECRET_KEY_LENGTH = 32


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(SERVER_DIR / ".env"))

    app_name: str = "Hue Heritage Music API"
    database_url: str = "sqlite:///" + (BASE_DIR / "hue_heritage.db").as_posix()
    storage_dir: Path = BASE_DIR / "storage"
    models_dir: Path = BASE_DIR / "models"
    datasets_dir: Path = BASE_DIR / "datasets"
    secret_key: str = INSECURE_DEFAULT_SECRET_KEY
    auth_required: bool = False
    token_ttl_hours: int = 24
    allowed_origins: str = "*"
    redis_url: str = "redis://127.0.0.1:6379/0"
    use_rq: bool = False
    acestep_api_url: str = ""
    invite_codes: str = ""
    admin_truong_username: str = "ghitatruongle"
    generation_concurrency: int = 1
    enable_docs: bool = False
    heavy_rate_limit: int = 30
    web_dir: Path = BASE_DIR / "app" / "build" / "web"


settings = Settings()
