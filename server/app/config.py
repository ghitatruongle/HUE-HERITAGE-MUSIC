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
    secret_key: str = INSECURE_DEFAULT_SECRET_KEY
    auth_required: bool = True
    token_ttl_hours: int = 24
    admin_token_ttl_hours: int = 8
    admin_unlock_window_seconds: int = 600
    worker_max_active: int = 5
    auth_flood_ip_limit: int = 120
    register_ip_rate_limit: int = 20
    register_failure_ip_limit: int = 30
    allowed_origins: str = "*"
    redis_url: str = "redis://127.0.0.1:6379/0"
    use_rq: bool = False
    acestep_api_url: str = ""
    invite_codes: str = ""
    admin_truong_username: str = "ghitatruongle"
    pbkdf2_iterations: int = 600_000
    avatar_max_bytes: int = 2 * 1024 * 1024
    avatar_max_pixels: int = 40_000_000
    compare_max_seconds: float = 35.0
    large_body_limit: int = 15 * 1024 * 1024
    signed_url_ttl_seconds: int = 6 * 3600
    heritage_upload_max_bytes: int = 50 * 1024 * 1024
    thread_limiter_tokens: int = 192
    generation_concurrency: int = 1
    enable_docs: bool = False
    heavy_rate_limit: int = 30
    shed_concurrency: int = 480
    task_retention_days: int = 30
    generated_retention_days: int = 14
    practice_midi_retention_days: int = 7
    lesson_cache_retention_days: int = 30
    analysis_retention_days: int = 30
    reference_segmentation: str = "v2"
    web_dir: Path = BASE_DIR / "app" / "build" / "web"
    uvicorn_limit_concurrency: int = 1024
    uvicorn_backlog: int = 2048
    db_pool_size: int = 64
    db_max_overflow: int = 160
    db_write_slots: int = 8
    restored_retention_days: int = 30
    musicxml_retention_days: int = 30
    user_storage_quota_mb: int = 500
    maintenance_interval_hours: int = 6
    worker_threads: int = 8
    basic_pitch_lock_wait_timeout: float = 90.0
    basic_pitch_run_timeout: float = 600.0
    basic_pitch_warmup: bool = False
    heavy_inflight_per_user: int = 2
    crash_report_retention_days: int = 30


settings = Settings()
