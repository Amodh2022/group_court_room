from __future__ import annotations

REG = {"email": "Sam@Example.com", "password": "correct-horse", "display_name": "Sam"}


def test_register_login_and_me(client):
    res = client.post("/api/v1/auth/register", json=REG)
    assert res.status_code == 201, res.text
    assert res.json()["email"] == "sam@example.com"

    login = client.post(
        "/api/v1/auth/login", json={"email": "SAM@example.com", "password": "correct-horse"}
    )
    assert login.status_code == 200
    me = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {login.json()['access_token']}"}
    )
    assert me.json()["email"] == "sam@example.com"
    assert me.json()["user_id"] == res.json()["user_id"]


def test_wrong_password_and_unknown_email_look_identical(client):
    client.post("/api/v1/auth/register", json=REG)
    bad = client.post("/api/v1/auth/login", json={"email": REG["email"], "password": "nope-nope"})
    unknown = client.post("/api/v1/auth/login", json={"email": "x@y.com", "password": "nope-nope"})
    assert bad.status_code == unknown.status_code == 401
    assert bad.json() == unknown.json()


def test_duplicate_email_and_weak_password_rejected(client):
    assert client.post("/api/v1/auth/register", json=REG).status_code == 201
    assert client.post("/api/v1/auth/register", json=REG).status_code == 409
    weak = client.post("/api/v1/auth/register", json={**REG, "email": "a@b.co", "password": "short"})
    assert weak.status_code == 422


def test_account_token_works_on_cases(client, make_case):
    res = client.post("/api/v1/auth/register", json=REG)
    headers = {"Authorization": f"Bearer {res.json()['access_token']}"}
    make_case(headers=headers)
    assert len(client.get("/api/v1/cases", headers=headers).json()) == 1
