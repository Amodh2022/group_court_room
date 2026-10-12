"""Invitation tokens, the defence submission, and expiry."""

from __future__ import annotations

from datetime import timedelta

from app.db.base import utcnow
from app.models import Case, CaseStatus, Participant

DEFENSE = {"nickname": "Sam", "body": "Nobody claimed it, so I assumed it was abandoned."}


def test_invite_preview_shows_accusation_and_nothing_private(client, make_case):
    case, _ = make_case()
    res = client.get(f"/api/v1/invites/{case['invite_token']}")
    assert res.status_code == 200
    body = res.json()

    assert body["case_title"] == case["title"]
    assert body["accusation"] == case["accusation"]
    assert body["already_submitted"] is False
    # No identifiers and no account data reach an unauthenticated visitor.
    for leaked in ("id", "case_id", "creator_id", "invite_token", "status"):
        assert leaked not in body


def test_invalid_and_unknown_tokens_are_generic_404(client):
    for token in ("inv_totally_made_up_token_value", "shr_wrong_capability_token"):
        res = client.get(f"/api/v1/invites/{token}")
        assert res.status_code == 404
        assert res.json() == {
            "error": "invalid_link",
            "message": "This link is invalid or has expired.",
        }


def test_submit_defense_moves_case_to_ready(client, make_case, db):
    case, headers = make_case()
    res = client.post(f"/api/v1/invites/{case['invite_token']}/defense", json=DEFENSE)
    assert res.status_code == 201
    assert res.json()["nickname"] == "Sam"

    detail = client.get(f"/api/v1/cases/{case['id']}", headers=headers).json()
    assert detail["status"] == CaseStatus.ready
    assert detail["defense_submitted"] is True
    assert detail["defendant_nickname"] == "Sam"


def test_defense_requires_no_account(client, make_case):
    case, _ = make_case()
    # No Authorization header anywhere in this flow.
    assert client.post(
        f"/api/v1/invites/{case['invite_token']}/defense", json=DEFENSE
    ).status_code == 201


def test_duplicate_defense_is_rejected(client, make_case):
    case, _ = make_case()
    assert client.post(
        f"/api/v1/invites/{case['invite_token']}/defense", json=DEFENSE
    ).status_code == 201
    second = client.post(
        f"/api/v1/invites/{case['invite_token']}/defense",
        json={"nickname": "Sam Again", "body": "Actually let me revise my whole story."},
    )
    assert second.status_code == 409
    assert second.json()["error"] == "conflict"


def test_duplicate_defense_blocked_by_database_constraint(client, make_case, db):
    """The application check is not the only guard; the UNIQUE is."""
    import uuid as _uuid

    from sqlalchemy.exc import IntegrityError

    from app.models import Submission

    case, _ = make_case()
    client.post(f"/api/v1/invites/{case['invite_token']}/defense", json=DEFENSE)

    defendant = db.query(Participant).filter(
        Participant.case_id == _uuid.UUID(case["id"]), Participant.role == "defendant"
    ).one()
    db.add(Submission(id=_uuid.uuid4(), participant_id=defendant.id, body="second row"))
    try:
        db.commit()
        raised = False
    except IntegrityError:
        db.rollback()
        raised = True
    assert raised, "submissions.participant_id must be UNIQUE"


def test_defense_validation(client, make_case):
    case, _ = make_case()
    for payload in (
        {"nickname": "", "body": "A perfectly reasonable defense statement."},
        {"nickname": "Sam", "body": "short"},
        {"nickname": "Sam", "body": "x" * 5000},
        {"body": "Missing the nickname field entirely."},
    ):
        res = client.post(f"/api/v1/invites/{case['invite_token']}/defense", json=payload)
        assert res.status_code == 422, res.text


def test_expired_invite_is_rejected(client, make_case, db):
    import uuid as _uuid

    case, headers = make_case()
    past = utcnow() - timedelta(hours=1)
    db.query(Participant).filter(Participant.case_id == _uuid.UUID(case["id"])).update(
        {"invite_expires_at": past}
    )
    db.query(Case).filter(Case.id == _uuid.UUID(case["id"])).update({"expires_at": past})
    db.commit()

    assert client.get(f"/api/v1/invites/{case['invite_token']}").status_code == 404
    assert client.post(
        f"/api/v1/invites/{case['invite_token']}/defense", json=DEFENSE
    ).status_code == 404

    # The creator sees the case flip to `expired` rather than hanging forever.
    detail = client.get(f"/api/v1/cases/{case['id']}", headers=headers).json()
    assert detail["status"] == CaseStatus.expired


def test_expired_case_cannot_generate_a_verdict(client, defended_case, db):
    import uuid as _uuid

    case, headers = defended_case()
    db.query(Case).filter(Case.id == _uuid.UUID(case["id"])).update(
        {"expires_at": utcnow() - timedelta(hours=1)}
    )
    db.commit()

    res = client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert res.status_code == 409
