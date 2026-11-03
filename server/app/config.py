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
    auth_required: bool = True
    token_ttl_hours: int = 24
    admin_token_ttl_hours: int = 8
    admin_unlock_window_seconds: int = 600
    auth_flood_ip_limit: int = 120
    register_ip_rate_limit: int = 20
    register_failure_ip_limit: int = 30
    allowed_origins: str = "*"
    redis_url: str = "redis://127.0.0.1:6379/0"
    use_rq: bool = False
    acestep_api_url: str = ""
    invite_codes: str = ""
    admin_truong_username: str = "ghitatruongle"
    generation_concurrency: int = 1
    enable_docs: bool = False
    heavy_rate_limit: int = 30
    shed_concurrency: int = 480
    task_retention_days: int = 30
    generated_retention_days: int = 14
    practice_midi_retention_days: int = 7
    lesson_cache_retention_days: int = 30
    web_dir: Path = BASE_DIR / "app" / "build" / "web"


settings = Settings()
