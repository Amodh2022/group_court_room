"""Case creation, validation, ownership and deletion."""

from __future__ import annotations

import uuid

from tests.conftest import VALID_CASE


def test_create_case_returns_invite_token_once(client, auth_headers):
    headers = auth_headers()
    res = client.post("/api/v1/cases", json=VALID_CASE, headers=headers)
    assert res.status_code == 201
    body = res.json()

    assert body["status"] == "awaiting_defense"
    assert body["invite_token"].startswith("inv_")
    assert body["invite_url"].endswith(body["invite_token"])
    assert body["defense_submitted"] is False
    assert body["share_enabled"] is False

    # Re-reading the case never re-exposes the raw token.
    again = client.get(f"/api/v1/cases/{body['id']}", headers=headers).json()
    assert "invite_token" not in again
    assert again["invite_url"] is None


def test_create_case_requires_auth(client):
    assert client.post("/api/v1/cases", json=VALID_CASE).status_code == 401


def test_create_case_rejects_bad_payloads(client, auth_headers):
    headers = auth_headers()
    cases = [
        ({**VALID_CASE, "title": "x"}, "title too short"),
        ({**VALID_CASE, "title": "x" * 200}, "title too long"),
        ({**VALID_CASE, "accusation": "short"}, "accusation too short"),
        ({**VALID_CASE, "accusation": "x" * 5000}, "accusation too long"),
        ({**VALID_CASE, "category": "not_a_category"}, "unknown category"),
        ({"title": "Missing fields"}, "missing required fields"),
    ]
    for payload, label in cases:
        res = client.post("/api/v1/cases", json=payload, headers=headers)
        assert res.status_code == 422, f"{label}: {res.text}"
        assert res.json()["error"] == "validation_error"


def test_dashboard_lists_only_own_cases(client, make_case, auth_headers):
    alice = auth_headers("dev|alice", "Alice")
    bob = auth_headers("dev|bob", "Bob")
    make_case(alice)
    make_case(alice, title="Second Alice Case")
    make_case(bob, title="Bob's Case")

    alice_cases = client.get("/api/v1/cases", headers=alice).json()
    bob_cases = client.get("/api/v1/cases", headers=bob).json()
    assert len(alice_cases) == 2
    assert len(bob_cases) == 1
    assert bob_cases[0]["title"] == "Bob's Case"


def test_other_user_cannot_read_or_delete_case(client, make_case, auth_headers):
    case, _ = make_case(auth_headers("dev|alice"))
    bob = auth_headers("dev|bob")

    # 404 rather than 403: a non-owner should not be able to confirm the id exists.
    assert client.get(f"/api/v1/cases/{case['id']}", headers=bob).status_code == 404
    assert client.delete(f"/api/v1/cases/{case['id']}", headers=bob).status_code == 404
    assert client.post(f"/api/v1/cases/{case['id']}/verdict", headers=bob).status_code == 404


def test_unknown_case_id_is_404(client, auth_headers):
    res = client.get(f"/api/v1/cases/{uuid.uuid4()}", headers=auth_headers())
    assert res.status_code == 404
    assert res.json()["error"] == "not_found"


def test_delete_case_revokes_invite_and_hides_case(client, make_case, auth_headers):
    case, headers = make_case()
    token = case["invite_token"]
    assert client.get(f"/api/v1/invites/{token}").status_code == 200

    assert client.delete(f"/api/v1/cases/{case['id']}", headers=headers).status_code == 204

    assert client.get(f"/api/v1/cases/{case['id']}", headers=headers).status_code == 404
    assert client.get("/api/v1/cases", headers=headers).json() == []
    # The leaked invite link must stop working immediately, not just be filtered.
    assert client.get(f"/api/v1/invites/{token}").status_code == 404


def test_deleted_case_rejects_new_defense(client, make_case):
    case, headers = make_case()
    client.delete(f"/api/v1/cases/{case['id']}", headers=headers)
    res = client.post(
        f"/api/v1/invites/{case['invite_token']}/defense",
        json={"nickname": "Sam", "body": "I would like to argue my side please."},
    )
    assert res.status_code == 404
    assert res.json()["error"] == "invalid_link"
