import concurrent.futures

from fastapi.testclient import TestClient

from app.main import app


def test_multipart_binary_body_on_json_endpoint_returns_422_not_500():
    client = TestClient(app)
    r = client.post("/api/auth/register", json={
        "username": "val500user", "email": "val500@gmail.com",
        "password": "secret123", "invite_code": "TESTINVITE",
    })
    assert r.status_code == 200, r.text
    tok = r.json()["token"]
    H = {"Authorization": f"Bearer {tok}"}
    pad = b"0" * 120
    binpayload = pad + b"\xa4\xff\x90" + b"0" * 200
    boundary = "probe123"
    mp = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"b.wav\"\r\n"
          f"Content-Type: audio/wav\r\n\r\n").encode() + binpayload + f"\r\n--{boundary}--\r\n".encode()
    endpoints = [
        "/api/auth/change-password",
        "/api/auth/admin-unlock",
        "/api/auth/users",
        "/api/task",
    ]
    for ep in endpoints:
        r = client.post(ep, content=mp, headers={"Authorization": f"Bearer {tok}", "Content-Type": f"multipart/form-data; boundary={boundary}"})
        assert r.status_code in (401, 403, 422), f"{ep} → {r.status_code} (500 = crash encoder!)"
        if r.status_code == 422:
            assert "application/json" in r.headers.get("content-type", "")
            assert "detail" in r.json()


def test_concurrent_multipart_binary_bodies_never_500():
    client = TestClient(app)
    tok = client.post("/api/auth/register", json={
        "username": "val500user2", "email": "val500b@gmail.com",
        "password": "secret123", "invite_code": "TESTINVITE",
    }).json()["token"]
    H = {"Authorization": f"Bearer {tok}"}
    binpayload = b"\xa4" * 300
    boundary = "probe456"
    mp = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"f\"; filename=\"x\"\r\n\r\n").encode() + binpayload + f"\r\n--{boundary}--\r\n".encode()

    def fire(i):
        try:
            return client.post("/api/auth/change-password", content=mp,
                               headers={"Authorization": f"Bearer {tok}", "Content-Type": f"multipart/form-data; boundary={boundary}"}).status_code
        except Exception:
            return -1

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        codes = list(ex.map(fire, range(16)))
    assert all(c in (401, 403, 422) for c in codes), f"phát hiện 500 trong concurrent: {codes}"
