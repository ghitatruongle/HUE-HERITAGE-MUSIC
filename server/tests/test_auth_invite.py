from fastapi.testclient import TestClient
from app.main import app
from app.database.session import SessionLocal
from app.database.models import User


def test_auth_registration_with_invite_and_login():
    db = SessionLocal()
    for u in db.query(User).filter(User.username.like("test_user_%")).all():
        db.delete(u)
    db.commit()
    db.close()

    client = TestClient(app)

    r_bad_code = client.post("/api/auth/register", json={
        "username": "test_user_1",
        "email": "test1@gmail.com",
        "password": "password123",
        "invite_code": "WRONG_CODE"
    })
    assert r_bad_code.status_code == 400
    assert "invalid invitation code" in r_bad_code.json()["detail"]

    r_bad_mail = client.post("/api/auth/register", json={
        "username": "test_user_1",
        "email": "test1@yahoo.com",
        "password": "password123",
        "invite_code": "TESTINVITE"
    })
    assert r_bad_mail.status_code == 400
    assert "only @gmail.com" in r_bad_mail.json()["detail"]

    r_ok = client.post("/api/auth/register", json={
        "username": "test_user_1",
        "email": "test1@gmail.com",
        "password": "password123",
        "invite_code": "TESTINVITE"
    })
    assert r_ok.status_code == 200
    data = r_ok.json()
    assert data["username"] == "test_user_1"
    assert data["email"] == "test1@gmail.com"
    assert "token" in data

    r_dup_user = client.post("/api/auth/register", json={
        "username": "test_user_1",
        "email": "test2@gmail.com",
        "password": "password123",
        "invite_code": "TESTINVITE"
    })
    assert r_dup_user.status_code == 409

    r_dup_mail = client.post("/api/auth/register", json={
        "username": "test_user_2",
        "email": "test1@gmail.com",
        "password": "password123",
        "invite_code": "TESTINVITE"
    })
    assert r_dup_mail.status_code == 409

    r_login_user = client.post("/api/auth/login", json={
        "identifier": "test_user_1",
        "password": "password123"
    })
    assert r_login_user.status_code == 200
    assert r_login_user.json()["username"] == "test_user_1"

    r_login_mail = client.post("/api/auth/login", json={
        "identifier": "test1@gmail.com",
        "password": "password123"
    })
    assert r_login_mail.status_code == 200
    assert r_login_mail.json()["username"] == "test_user_1"

    r_login_fail = client.post("/api/auth/login", json={
        "identifier": "test_user_1",
        "password": "wrongpassword"
    })
    assert r_login_fail.status_code == 401
