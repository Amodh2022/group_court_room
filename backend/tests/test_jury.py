"""The jury: seating, one ballot each, and the reveal gate."""

from __future__ import annotations

import uuid

import pytest

from app.models import CaseStatus


def juror(n: int = 1) -> str:
    """A stable per-juror device key. Same n, same juror."""
    return f"juror-device-key-{n:04d}"


@pytest.fixture
def jury_case(defended_case):
    """A defended case plus its jury token."""
    case, headers = defended_case()
    return case, headers, case["jury_token"]


# --- seating ---------------------------------------------------------------


def test_case_creation_mints_a_jury_link(make_case):
    case, _ = make_case()
    assert case["jury_token"].startswith("jry_")
    assert case["jury_url"].endswith(case["jury_token"])
    # The three capabilities are distinct tokens.
    assert case["jury_token"] != case["invite_token"]


def test_jury_room_shows_both_sides_once_the_defense_is_in(client, jury_case):
    _, _, token = jury_case
    room = client.get(f"/api/v1/jury/{token}").json()
    assert room["accusation"]
    assert room["defense"]
    assert room["jury_open"] is True
    assert room["your_vote"] is None
    # No running count before you commit.
    assert room["tally"] is None


def test_jury_room_withholds_the_defense_until_it_exists(client, make_case):
    case, _ = make_case()
    room = client.get(f"/api/v1/jury/{case['jury_token']}").json()
    assert room["accusation"]
    assert room["defense"] is None


def test_bad_jury_token_is_indistinguishable_from_any_other_dead_link(client):
    res = client.get("/api/v1/jury/jry_not-a-real-token-at-all")
    assert res.status_code == 404
    assert res.json()["error"] == "invalid_link"


# --- voting ----------------------------------------------------------------


def test_vote_is_recorded_and_returns_the_tally(client, jury_case):
    _, _, token = jury_case
    res = client.post(
        f"/api/v1/jury/{token}/vote",
        json={"voter_key": juror(1), "juror_name": "Priya", "vote": "guilty"},
    )
    assert res.status_code == 201
    body = res.json()
    assert body["your_vote"] == "guilty"
    assert body["tally"]["guilty"] == 1
    assert body["tally"]["total"] == 1


def test_one_ballot_per_juror(client, jury_case):
    _, _, token = jury_case
    key = juror(2)
    first = client.post(
        f"/api/v1/jury/{token}/vote", json={"voter_key": key, "vote": "guilty"}
    )
    assert first.status_code == 201

    second = client.post(
        f"/api/v1/jury/{token}/vote", json={"voter_key": key, "vote": "not_guilty"}
    )
    assert second.status_code == 409
    assert "already voted" in second.json()["message"].lower()


def test_tally_appears_only_after_this_juror_has_voted(client, jury_case):
    _, _, token = jury_case
    key = juror(3)
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": key, "vote": "not_guilty"})

    mine = client.get(f"/api/v1/jury/{token}", params={"voter": key}).json()
    assert mine["your_vote"] == "not_guilty"
    assert mine["tally"]["total"] == 1

    stranger = client.get(f"/api/v1/jury/{token}", params={"voter": juror(99)}).json()
    assert stranger["tally"] is None


def test_majority_and_summary_read_correctly(client, jury_case):
    _, _, token = jury_case
    for i, vote in enumerate(["guilty", "guilty", "not_guilty"]):
        client.post(
            f"/api/v1/jury/{token}/vote", json={"voter_key": juror(10 + i), "vote": vote}
        )
    tally = client.get(
        f"/api/v1/jury/{token}", params={"voter": juror(10)}
    ).json()["tally"]
    assert (tally["guilty"], tally["not_guilty"]) == (2, 1)
    assert tally["majority"] == "guilty"
    assert "2–1" in tally["summary"]


def test_a_tied_jury_has_no_majority(client, jury_case):
    _, _, token = jury_case
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": juror(20), "vote": "guilty"})
    client.post(
        f"/api/v1/jury/{token}/vote", json={"voter_key": juror(21), "vote": "not_guilty"}
    )
    tally = client.get(
        f"/api/v1/jury/{token}", params={"voter": juror(20)}
    ).json()["tally"]
    assert tally["majority"] is None
    assert "deadlock" in tally["summary"].lower()


# --- the reveal gate -------------------------------------------------------


def test_voting_closes_once_the_court_has_ruled(client, jury_case, drain):
    case, headers, token = jury_case
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    late = client.post(
        f"/api/v1/jury/{token}/vote", json={"voter_key": juror(30), "vote": "guilty"}
    )
    assert late.status_code == 409
    assert "after the verdict" in late.json()["message"].lower()


def test_a_juror_who_voted_sees_the_verdict(client, jury_case, drain):
    case, headers, token = jury_case
    key = juror(40)
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": key, "vote": "guilty"})

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    res = client.get(f"/api/v1/jury/{token}/verdict", params={"voter": key})
    assert res.status_code == 200
    body = res.json()
    assert body["verdict"] in {"guilty", "not_guilty", "both_guilty", "insufficient_evidence"}
    assert body["jury"]["total"] == 1
    # The jury's own ruling is published as counts only.
    assert "juror_name" not in body


def test_a_juror_who_never_voted_is_refused_the_verdict(client, jury_case, drain):
    case, headers, token = jury_case
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    res = client.get(f"/api/v1/jury/{token}/verdict", params={"voter": juror(50)})
    assert res.status_code == 403
    assert "never voted" in res.json()["message"].lower()


def test_no_verdict_to_reveal_before_the_court_rules(client, jury_case):
    _, _, token = jury_case
    key = juror(60)
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": key, "vote": "guilty"})
    res = client.get(f"/api/v1/jury/{token}/verdict", params={"voter": key})
    assert res.status_code == 409


# --- the creator's view ----------------------------------------------------


def test_creator_sees_the_jury_count_without_voting(client, jury_case):
    case, headers, token = jury_case
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": juror(70), "vote": "guilty"})

    detail = client.get(f"/api/v1/cases/{case['id']}", headers=headers).json()
    assert detail["jury_count"] == 1
    assert detail["jury_tally"]["guilty"] == 1


def test_deleting_a_case_kills_the_jury_link_too(client, jury_case):
    case, headers, token = jury_case
    assert client.delete(f"/api/v1/cases/{case['id']}", headers=headers).status_code == 204
    assert client.get(f"/api/v1/jury/{token}").status_code == 404


def test_expired_case_seats_no_jury(client, jury_case, db):
    from app.models import Case

    case, _, token = jury_case
    row = db.get(Case, uuid.UUID(case["id"]))
    row.status = CaseStatus.expired
    db.commit()

    res = client.post(
        f"/api/v1/jury/{token}/vote", json={"voter_key": juror(80), "vote": "guilty"}
    )
    assert res.status_code == 409


# --- judge vs jury ---------------------------------------------------------


def test_overruling_is_flagged_when_the_judge_breaks_with_the_jury(client, jury_case, drain, db):
    """`jury_overruled` is computed from the stored verdict, not guessed at."""
    from app.models import Case, Verdict

    case, headers, token = jury_case
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": juror(90), "vote": "guilty"})
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    row = db.get(Case, uuid.UUID(case["id"]))
    verdict = db.query(Verdict).filter(Verdict.case_id == row.id).one()
    verdict.result = {**verdict.result, "verdict": "not_guilty"}
    db.commit()

    body = client.get(f"/api/v1/jury/{token}/verdict", params={"voter": juror(90)}).json()
    assert body["jury"]["majority"] == "guilty"
    assert body["verdict"] == "not_guilty"
    assert body["jury_overruled"] is True


def test_agreeing_with_the_jury_is_not_an_overrule(client, jury_case, drain, db):
    from app.models import Case, Verdict

    case, headers, token = jury_case
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": juror(91), "vote": "guilty"})
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    row = db.get(Case, uuid.UUID(case["id"]))
    verdict = db.query(Verdict).filter(Verdict.case_id == row.id).one()
    verdict.result = {**verdict.result, "verdict": "both_guilty"}
    db.commit()

    body = client.get(f"/api/v1/jury/{token}/verdict", params={"voter": juror(91)}).json()
    assert body["jury_overruled"] is False


def test_a_mistrial_never_counts_as_overruling_the_jury(client, jury_case, drain, db):
    from app.models import Case, Verdict

    case, headers, token = jury_case
    client.post(f"/api/v1/jury/{token}/vote", json={"voter_key": juror(92), "vote": "guilty"})
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    row = db.get(Case, uuid.UUID(case["id"]))
    verdict = db.query(Verdict).filter(Verdict.case_id == row.id).one()
    verdict.result = {**verdict.result, "verdict": "insufficient_evidence"}
    db.commit()

    body = client.get(f"/api/v1/jury/{token}/verdict", params={"voter": juror(92)}).json()
    assert body["jury_overruled"] is False


def test_the_jury_reaches_the_judges_prompt(client, jury_case, db):
    from app.llm.mock import MockLLMProvider
    from app.models import Case
    from app.services.verdict_service import VerdictService

    case, _, token = jury_case
    for i, vote in enumerate(["guilty", "guilty", "not_guilty"]):
        client.post(
            f"/api/v1/jury/{token}/vote", json={"voter_key": juror(100 + i), "vote": vote}
        )

    row = db.get(Case, uuid.UUID(case["id"]))
    request = VerdictService(MockLLMProvider())._build_request(db, row)
    assert "2–1" in request.jury_summary
