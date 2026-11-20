import os

import pytest


def test_default_600k_when_env_absent(monkeypatch):
    monkeypatch.delenv("PBKDF2_ITERATIONS", raising=False)
    import app.config as config

    cfg = config.Settings(_env_file=None)
    assert cfg.pbkdf2_iterations == 600_000


def test_env_overrides_iterations(monkeypatch):
    monkeypatch.setenv("PBKDF2_ITERATIONS", "100000")
    import app.config as config

    cfg = config.Settings(_env_file=None)
    assert cfg.pbkdf2_iterations == 100_000


def test_hash_password_still_verifies(monkeypatch):
    monkeypatch.setenv("PBKDF2_ITERATIONS", "100000")
    from app.api.auth import hash_password, verify_password

    h = hash_password("Test#123x")
    assert verify_password("Test#123x", h)
