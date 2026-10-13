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

    # New codes never contain look-alike characters (0/O, 1/I/L).
    assert len(court["invite_code"]) == 8
    assert set(court["invite_code"]).isdisjoint("01IL")

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


def test_notifications_socket_pushes_changes(client, auth_headers):
    from app.db.session import SessionLocal
    from app.models import User
    from app.services import social_service

    headers = auth_headers(name="Sam")
    token = headers["Authorization"].split(" ", 1)[1]
    with client.websocket_connect("/api/v1/ws/notifications") as ws:
        ws.send_json({"type": "auth", "token": token})
        assert ws.receive_json()["unread"] == 0

        me = client.get("/api/v1/auth/me", headers=headers).json()["user_id"]
        db = SessionLocal()
        try:
            user = db.get(User, __import__("uuid").UUID(me))
            social_service.notify(db, user.id, "added_to_court", "You were added to a court")
            db.commit()
        finally:
            db.close()
        frame = ws.receive_json()
        assert frame["unread"] == 1 and frame["latest"] == "You were added to a court"


def test_notifications_socket_rejects_bad_token(client):
    with client.websocket_connect("/api/v1/ws/notifications") as ws:
        ws.send_json({"type": "auth", "token": "nope"})
        assert ws.receive_json()["type"] == "error"


def test_deleting_a_case_removes_it_for_everyone_seated_on_it(client, auth_headers):
    owner = auth_headers(name="Owner")
    friend = auth_headers(name="Friend")
    friend_id = client.get("/api/v1/auth/me", headers=friend).json()["user_id"]
    case = client.post(
        "/api/v1/cases",
        json={
            "title": "Pizza", "category": "food", "defendant_nickname": "Bob",
            "accusation": "He ate the last slice right after saying he was full.",
        },
        headers=owner,
    ).json()
    res = client.post(
        f"/api/v1/cases/{case['id']}/members",
        json={"user_id": friend_id, "role": "juror"},
        headers=owner,
    )
    assert res.status_code == 204
    assert len(client.get("/api/v1/cases/shared", headers=friend).json()) == 1
    assert client.get("/api/v1/notifications", headers=friend).json()["unread"] == 1

    assert client.delete(f"/api/v1/cases/{case['id']}", headers=owner).status_code == 204

    assert client.get("/api/v1/cases/shared", headers=friend).json() == []
    assert client.get("/api/v1/notifications", headers=friend).json()["items"] == []


def _kinds(client, headers):
    return [n["kind"] for n in client.get("/api/v1/notifications", headers=headers).json()["items"]]


def test_the_beats_of_a_case_notify_everyone_following_it(client, defended_case, drain):
    """Being summoned is not the only thing worth a notification.

    The defense landing and the ruling are the two moments a player is actually
    waiting on, and before this they produced nothing at all — not in the bell,
    and so not as a push either.
    """
    ha, _ = _acct(client, "alex@example.com", "Alex")
    hb, b = _acct(client, "jordan@example.com", "Jordan")
    hc, c = _acct(client, "casey@example.com", "Casey")
    court = client.post("/api/v1/courts", json={"name": "Crew"}, headers=ha).json()
    for u in (b, c):
        client.post(
            f"/api/v1/courts/{court['id']}/members", json={"user_id": u["user_id"]}, headers=ha
        )

    case, _ = defended_case(
        ha, defendant_nickname=None, court_id=court["id"], accused_user_id=b["user_id"]
    )

    # The plaintiff hears that the charge has been answered...
    assert "defense_filed" in _kinds(client, ha)
    # ...and so does the juror, who is waiting to vote on it.
    assert "defense_filed" in _kinds(client, hc)

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=ha)
    assert drain() == 1

    # The ruling reaches everyone following the case, including the accused.
    for headers in (ha, hb, hc):
        assert "verdict_ready" in _kinds(client, headers)


def test_a_refused_second_defense_announces_nothing(client, defended_case):
    """A refused second defense must not add another notification.

    This exercises the status guard, which refuses before any row is written.
    The other refusal path — losing the UNIQUE race on submissions — relies on
    the notification sharing the transaction that gets rolled back, and is not
    reachable from a single-threaded test.
    """
    ha, _ = _acct(client, "alex@example.com", "Alex")
    case, _ = defended_case(ha)

    before = _kinds(client, ha).count("defense_filed")
    again = client.post(
        f"/api/v1/invites/{case['invite_token']}/defense",
        json={"nickname": "Sam", "body": "Let me try that again, with feeling."},
    )
    assert again.status_code == 409
    assert _kinds(client, ha).count("defense_filed") == before
