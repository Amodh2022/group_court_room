from __future__ import annotations

import uuid

from tests.conftest import VALID_CASE


def _acct(client, email, name):
    res = client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "correct-horse", "display_name": name},
    )
    assert res.status_code == 201, res.text
    body = res.json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body


def test_handle_is_generated_and_unique(client):
    _, a = _acct(client, "sam@example.com", "Sam")
    _, b = _acct(client, "sam@other.com", "Sam2")
    assert a["handle"] == "sam"
    assert b["handle"] != "sam" and b["handle"].startswith("sam")


def test_search_by_handle_prefix_and_exact_email_never_leaks_email(client):
    ha, _ = _acct(client, "alex@example.com", "Alex")
    _acct(client, "jordan@example.com", "Jordan")
    res = client.get("/api/v1/users/search?q=jor", headers=ha).json()
    assert [u["handle"] for u in res] == ["jordan"]
    assert "email" not in res[0]
    by_email = client.get("/api/v1/users/search?q=Jordan@Example.com", headers=ha).json()
    assert len(by_email) == 1
    assert client.get("/api/v1/users/search?q=ale", headers=ha).json() == []  # excludes self
    assert client.get("/api/v1/users/search?q=j", headers=ha).json() == []  # min 2 chars


def test_court_flow_and_privacy(client):
    ha, _ = _acct(client, "alex@example.com", "Alex")
    hb, b = _acct(client, "jordan@example.com", "Jordan")
    hc, _ = _acct(client, "casey@example.com", "Casey")

    court = client.post("/api/v1/courts", json={"name": "The Roomies"}, headers=ha).json()
    assert [m["handle"] for m in court["members"]] == ["alex"]

    assert client.get(f"/api/v1/courts/{court['id']}", headers=hb).status_code == 404
    added = client.post(
        f"/api/v1/courts/{court['id']}/members", json={"user_id": b["user_id"]}, headers=ha
    )
    assert added.status_code == 200 and len(added.json()["members"]) == 2

    notes = client.get("/api/v1/notifications", headers=hb).json()
    assert notes["unread"] == 1 and notes["items"][0]["kind"] == "added_to_court"
    assert client.post("/api/v1/notifications/read-all", headers=hb).status_code == 204
    assert client.get("/api/v1/notifications", headers=hb).json()["unread"] == 0

    joined = client.post(
        "/api/v1/courts/join", json={"invite_code": court["invite_code"].lower()}, headers=hc
    )
    assert joined.status_code == 200
    assert len(client.get("/api/v1/courts", headers=hc).json()) == 1

    # Non-owner cannot remove others; owner can; anyone can leave.
    other = client.delete(f"/api/v1/courts/{court['id']}/members/{b['user_id']}", headers=hc)
    assert other.status_code == 403
    assert client.delete(
        f"/api/v1/courts/{court['id']}/members/{b['user_id']}", headers=ha
    ).status_code == 204
    me_c = client.get("/api/v1/auth/me", headers=hc).json()["user_id"]
    assert client.delete(f"/api/v1/courts/{court['id']}/members/{me_c}", headers=hc).status_code == 204


def test_case_in_court_seats_jury_and_accused_can_use_existing_screens(client):
    ha, _ = _acct(client, "alex@example.com", "Alex")
    hb, b = _acct(client, "jordan@example.com", "Jordan")
    hc, c = _acct(client, "casey@example.com", "Casey")
    court = client.post("/api/v1/courts", json={"name": "Crew"}, headers=ha).json()
    for u in (b, c):
        client.post(f"/api/v1/courts/{court['id']}/members", json={"user_id": u["user_id"]},
                    headers=ha)

    res = client.post(
        "/api/v1/cases",
        json={**VALID_CASE, "defendant_nickname": None, "court_id": court["id"],
              "accused_user_id": b["user_id"]},
        headers=ha,
    )
    assert res.status_code == 201, res.text

    shared_b = client.get("/api/v1/cases/shared", headers=hb).json()
    shared_c = client.get("/api/v1/cases/shared", headers=hc).json()
    assert [(s["role"], s["link_kind"]) for s in shared_b] == [("accused", "invite")]
    assert [(s["role"], s["link_kind"]) for s in shared_c] == [("juror", "jury")]
    assert client.get("/api/v1/cases/shared", headers=ha).json() == []

    # The member tokens open the existing token screens.
    assert client.get(f"/api/v1/invites/{shared_b[0]['token']}").status_code == 200
    assert client.get(f"/api/v1/jury/{shared_c[0]['token']}").status_code == 200
    # ...and a juror token is not an invite token.
    assert client.get(f"/api/v1/invites/{shared_c[0]['token']}").status_code == 404

    kinds = {n["kind"] for n in client.get("/api/v1/notifications", headers=hb).json()["items"]}
    assert {"added_to_court", "summoned"} <= kinds
    jn = client.get("/api/v1/notifications", headers=hc).json()["items"]
    assert any(n["kind"] == "jury_duty" and n["token"] == shared_c[0]["token"] for n in jn)


def test_court_rules_on_case_creation(client):
    ha, _ = _acct(client, "alex@example.com", "Alex")
    hb, b = _acct(client, "jordan@example.com", "Jordan")
    court = client.post("/api/v1/courts", json={"name": "Crew"}, headers=ha).json()
    # Not a member of that court
    bad = client.post("/api/v1/cases", json={**VALID_CASE, "court_id": court["id"]}, headers=hb)
    assert bad.status_code == 404
    # Accused outside the court
    out = client.post(
        "/api/v1/cases",
        json={**VALID_CASE, "court_id": court["id"], "accused_user_id": b["user_id"]},
        headers=ha,
    )
    assert out.status_code == 409
    assert client.post(
        "/api/v1/cases", json={**VALID_CASE, "court_id": str(uuid.uuid4())}, headers=ha
    ).status_code == 404


def test_direct_members_without_court_creator_only(client, make_case):
    ha, a = _acct(client, "alex@example.com", "Alex")
    hb, b = _acct(client, "jordan@example.com", "Jordan")
    hc, c = _acct(client, "casey@example.com", "Casey")
    case, _ = make_case(headers=ha)
    cid = case["id"]

    assert client.post(f"/api/v1/cases/{cid}/members",
                       json={"user_id": b["user_id"], "role": "juror"}, headers=hb).status_code == 404
    assert client.post(f"/api/v1/cases/{cid}/members",
                       json={"user_id": b["user_id"], "role": "juror"}, headers=ha).status_code == 204
    assert client.post(f"/api/v1/cases/{cid}/members",
                       json={"user_id": c["user_id"], "role": "accused"}, headers=ha).status_code == 204
    assert client.post(f"/api/v1/cases/{cid}/members",
                       json={"user_id": a["user_id"], "role": "juror"}, headers=ha).status_code == 409
    assert client.post(f"/api/v1/cases/{cid}/members",
                       json={"user_id": c["user_id"], "role": "bogus"}, headers=ha).status_code == 422
    assert client.get("/api/v1/cases/shared", headers=hb).json()[0]["role"] == "juror"
    assert client.get("/api/v1/cases/shared", headers=hc).json()[0]["link_kind"] == "invite"
