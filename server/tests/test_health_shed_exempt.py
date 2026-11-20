from app.main import SHED_EXEMPT_PATHS


def test_health_never_shed():
    assert "/health" in SHED_EXEMPT_PATHS


def test_auth_exempt_paths_preserved():
    assert "/api/auth/login" in SHED_EXEMPT_PATHS
    assert "/api/auth/admin-unlock" in SHED_EXEMPT_PATHS
