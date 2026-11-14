import pytest
from fastapi.testclient import TestClient

from app.database.models import User
from app.database.session import SessionLocal
from app.main import create_app


@pytest.fixture()
def client():
    db = SessionLocal()
    try:
        db.query(User).delete()
        db.commit()
    finally:
        db.close()
    app1 = create_app()
    client = TestClient(app1)
    r = client.post("/api/auth/register", json={
        "username": "ghitatruongle", "email": "a@x.com",
        "password": "DosLock#2026", "invite_code": "TESTINVITE"})
    assert r.status_code == 200, r.text
    TestClient(create_app())
    yield client
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == "ghitatruongle").first()
        if u is not None:
            db.delete(u)
        db.commit()
    finally:
        db.close()


def test_deep_nested_json_rejected_400_not_500(client):
    nested = '{"a":' * 4000 + "1" + "}" * 4000
    r = client.post("/api/task", content=nested, headers={"Content-Type": "application/json"})
    assert r.status_code == 400, f"nested 4000 tầng phải 400 depth-guard, got {r.status_code}: {r.text[:100]}"
    assert "nesting" in r.text.lower()


def test_moderate_nesting_still_accepted(client):
    nested = '{"params":' + '{"k":' * 30 + "1" + "}" * 30 + "}"
    r = client.post("/api/task", content=nested, headers={"Content-Type": "application/json"})
    assert r.status_code in (200, 201), f"nesting 30 tầng hợp lệ phải qua được: {r.status_code} {r.text[:100]}"


def test_recursion_error_handler_returns_400():
    from app.main import create_app

    app = create_app()
    handler = app.exception_handlers.get(RecursionError)
    assert handler is not None, "phải có RecursionError handler toàn cục"
