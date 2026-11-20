import inspect

from app.ai import basic_pitch_amt as bp
from app.main import create_app


def test_stalled_accessor_does_not_call_status():
    source = inspect.getsource(bp.stalled)
    assert "status(" not in source
    assert "available(" not in source


def test_extended_health_uses_stalled_accessor():
    app = create_app()
    route = next(r for r in app.routes if getattr(r, "path", "") == "/health")
    source = inspect.getsource(route.endpoint)
    assert "basic_pitch_amt.stalled()" in source
    assert 'basic_pitch_amt.status()["stalled"]' not in source
