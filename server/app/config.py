import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
SERVER_DIR = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(SERVER_DIR / ".env"))

    app_name: str = "Hue Heritage Music API"
    database_url: str = "sqlite:///" + (BASE_DIR / "hue_heritage.db").as_posix()
    storage_dir: Path = BASE_DIR / "storage"
    models_dir: Path = BASE_DIR / "models"
    datasets_dir: Path = BASE_DIR / "datasets"
    secret_key: str = "dev-insecure-secret-key"
    auth_required: bool = False
    token_ttl_hours: int = 72
    allowed_origins: str = "*"
    redis_url: str = "redis://127.0.0.1:6379/0"
    use_rq: bool = False
    acestep_api_url: str = ""


settings = Settings()
