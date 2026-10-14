"""The game layer: what a player earns, and what they are never given.

The rule these tests exist to hold is that nothing is invented. A player who
has done nothing has zeros; every number on a screen traces back to a row
written when it was earned.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest

from app.db.base import utcnow
from app.models import Case, JuryVote, User
from app.models.game import XP_PER_LEVEL, DailyQuest, PlayerProfile
from app.services import game_rules as rules
from app.services import game_service


def _state(client, headers) -> dict:
    res = client.get("/api/v1/me/game", headers=headers)
    assert res.status_code == 200, res.text
    return res.json()


# --- a player who has done nothing -----------------------------------------


def test_a_new_player_has_nothing_but_the_opening_balance(client, auth_headers):
    state = _state(client, auth_headers(name="Alex"))

    # The only XP a brand-new player has is for turning up, which they just
    # did by making this call. Nothing else is given away.
    assert state["player"]["xp"] == rules.QUESTS_BY_CODE["show_up"].xp
    assert state["player"]["level"] == 1
    assert state["player"]["badges_earned"] == 0
    assert state["player"]["badges_total"] == rules.BADGE_TOTAL
    # Coins are the one thing a player starts with: without them they could
    # never file the first case that earns them any.
    assert state["player"]["coins"] == 100
    assert all(b["earned"] is False for b in state["badges"])


def test_the_badge_catalogue_is_whole_and_unearned(client, auth_headers):
    state = _state(client, auth_headers())
    codes = [b["code"] for b in state["badges"]]
    assert codes == [b.code for b in rules.BADGES]
    assert all(b["hint"] for b in state["badges"])


# --- showing up -------------------------------------------------------------


def test_opening_the_app_starts_a_streak_once_a_day(client, auth_headers, db):
    headers = auth_headers()
    assert _state(client, headers)["player"]["streak_days"] == 1
    # Twice in one day is one day.
    assert _state(client, headers)["player"]["streak_days"] == 1


def test_a_missed_day_resets_the_streak(db, auth_headers, client):
    _state(client, auth_headers())
    user = db.query(User).one()

    profile = db.get(PlayerProfile, user.id)
    profile.streak_days = 4
    profile.longest_streak_days = 4
    profile.last_active_on = utcnow().date() - timedelta(days=3)
    db.commit()

    game_service.touch_day(db, user)
    db.refresh(profile)
    assert profile.streak_days == 1
    assert profile.longest_streak_days == 4


def test_a_consecutive_day_extends_the_streak(db, auth_headers, client):
    _state(client, auth_headers())
    user = db.query(User).one()

    profile = db.get(PlayerProfile, user.id)
    profile.streak_days = 6
    profile.last_active_on = utcnow().date() - timedelta(days=1)
    db.commit()

    game_service.touch_day(db, user)
    db.refresh(profile)
    assert profile.streak_days == 7
    # Seven running days is a badge.
    assert any(b.code == "week_streak" for b in game_service.badges_for(db, user))


# --- quests -----------------------------------------------------------------


def test_showing_up_completes_its_own_quest_and_pays_once(client, auth_headers):
    headers = auth_headers()
    first = _state(client, headers)
    show_up = next(q for q in first["quests"] if q["code"] == "show_up")
    assert show_up["done"] is True
    paid = first["player"]["xp"]
    assert paid == rules.QUESTS_BY_CODE["show_up"].xp

    # Asking again does not pay again.
    assert _state(client, headers)["player"]["xp"] == paid


def test_filing_a_case_moves_its_quest(client, auth_headers, make_case):
    headers = auth_headers()
    _state(client, headers)  # open today's quests
    make_case(headers)

    quests = {q["code"]: q for q in _state(client, headers)["quests"]}
    assert quests["file_case"]["done"] is True
    assert quests["file_case"]["progress"] == 1


def test_a_quest_that_was_never_offered_is_not_completed(db, auth_headers, client):
    """Progress on a day with no quest row is dropped, not back-dated."""
    auth_headers()
    user = db.query(User).one()
    game_service.advance_quest(db, user, "file_case")
    assert db.query(DailyQuest).count() == 0
    assert db.get(PlayerProfile, user.id) is None or db.get(PlayerProfile, user.id).xp == 0


# --- filing costs coins -----------------------------------------------------


def test_filing_charges_the_fee(client, auth_headers, make_case):
    headers = auth_headers()
    # The second case, not the first: the first also pays out a badge, and
    # this is a test about the fee rather than about the badge.
    make_case(headers)
    before = _state(client, headers)["player"]["coins"]
    make_case(headers)
    after = _state(client, headers)["player"]["coins"]
    assert after == before - rules.CASE_FILING_COST


def test_a_player_who_cannot_pay_cannot_file(db, client, auth_headers):
    headers = auth_headers()
    _state(client, headers)
    user = db.query(User).one()
    profile = db.get(PlayerProfile, user.id)
    profile.coins = 0
    db.commit()

    res = client.post(
        "/api/v1/cases",
        json={
            "title": "The Last Pizza Slice",
            "category": "food",
            "accusation": "They ate it right after saying they were full.",
            "defendant_nickname": "SliceBandit",
        },
        headers=headers,
    )
    assert res.status_code == 409
    assert "coins" in res.json()["message"]
    # And nothing was half-created.
    assert db.query(Case).count() == 0


def test_the_filing_badge_lands_on_the_first_case(client, auth_headers, make_case):
    headers = auth_headers()
    make_case(headers)
    badges = {b["code"]: b for b in _state(client, headers)["badges"]}
    assert badges["first_blood"]["earned"] is True
    assert badges["serial_filer"]["earned"] is False


# --- the petty multiplier ---------------------------------------------------


@pytest.mark.parametrize("level", [1, 2, 3])
def test_the_petty_level_is_kept_on_the_case(client, auth_headers, make_case, db, level):
    make_case(auth_headers(), petty_level=level)
    assert db.query(Case).one().petty_level == level


def test_an_out_of_range_petty_level_is_refused(client, auth_headers):
    headers = auth_headers()
    res = client.post(
        "/api/v1/cases",
        json={
            "title": "The Last Pizza Slice",
            "category": "food",
            "accusation": "They ate it right after saying they were full.",
            "petty_level": 9,
        },
        headers=headers,
    )
    assert res.status_code == 422


def test_winning_pays_the_multiplier(db, client, auth_headers, defended_case, drain):
    headers = auth_headers()
    _state(client, headers)
    case, _ = defended_case(headers, petty_level=3)
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    user = db.query(User).one()
    events = game_service.events_for_case(db, user, uuid.UUID(case["id"]))
    case_event = next(e for e in events if e.kind.startswith("case_"))
    expected = {
        "case_won": rules.CASE_WIN_XP * 3,
        "case_lost": rules.CASE_LOSS_XP * 3,
        "case_mistrial": rules.CASE_MISTRIAL_XP,
    }[case_event.kind]
    assert case_event.xp == expected


# --- the jury ---------------------------------------------------------------


def _vote(client, token, key, vote, headers=None):
    return client.post(
        f"/api/v1/jury/{token}/vote",
        json={"voter_key": key, "juror_name": "Priya", "vote": vote},
        headers=headers or {},
    )


def test_an_anonymous_juror_still_votes_and_is_simply_not_paid(
    db, client, auth_headers, make_case
):
    case, _ = make_case(auth_headers())
    assert _vote(client, case["jury_token"], "juror-key-one", "guilty").status_code == 201
    ballot = db.query(JuryVote).one()
    assert ballot.juror_user_id is None


def test_a_signed_in_juror_is_recorded_on_the_ballot(
    db, client, auth_headers, make_case
):
    case, _ = make_case(auth_headers(name="Alex"))
    juror = auth_headers(name="Priya")
    assert _vote(client, case["jury_token"], "juror-key-one", "guilty", juror).status_code == 201

    ballot = db.query(JuryVote).one()
    assert ballot.juror_user_id is not None
    priya = db.query(User).filter(User.display_name == "Priya").one()
    assert ballot.juror_user_id == priya.id


def test_calling_it_like_the_judge_pays_and_being_wrong_does_not(
    db, client, auth_headers, defended_case, drain
):
    owner = auth_headers(name="Alex")
    case, _ = defended_case(owner)

    right = auth_headers(name="Priya")
    wrong = auth_headers(name="Dev")
    # Whichever way the mock judge goes, one of these two matched it.
    _vote(client, case["jury_token"], "juror-key-one", "guilty", right)
    _vote(client, case["jury_token"], "juror-key-two", "not_guilty", wrong)

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=owner)
    drain()

    verdict = client.get(f"/api/v1/cases/{case['id']}/verdict", headers=owner).json()
    kind = verdict["result"]["verdict"]
    judge_said = "guilty" if kind in {"guilty", "both_guilty"} else "not_guilty"

    paid = db.query(User).filter(
        User.display_name == ("Priya" if judge_said == "guilty" else "Dev")
    ).one()
    unpaid = db.query(User).filter(
        User.display_name == ("Dev" if judge_said == "guilty" else "Priya")
    ).one()

    if kind == "insufficient_evidence":
        pytest.skip("A mistrial pays no juror; there was no call to match.")

    assert game_service.events_for_case(db, paid, uuid.UUID(case["id"]))
    assert not game_service.events_for_case(db, unpaid, uuid.UUID(case["id"]))


def test_the_first_juror_to_commit_doubles(
    db, client, auth_headers, defended_case, drain
):
    owner = auth_headers(name="Alex")
    case, _ = defended_case(owner)

    a = auth_headers(name="Priya")
    b = auth_headers(name="Dev")
    _vote(client, case["jury_token"], "juror-key-one", "guilty", a)
    _vote(client, case["jury_token"], "juror-key-two", "guilty", b)

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=owner)
    drain()

    verdict = client.get(f"/api/v1/cases/{case['id']}/verdict", headers=owner).json()
    if verdict["result"]["verdict"] not in {"guilty", "both_guilty"}:
        pytest.skip("Both jurors called it wrong; nobody was paid.")

    priya = db.query(User).filter(User.display_name == "Priya").one()
    dev = db.query(User).filter(User.display_name == "Dev").one()
    first = game_service.events_for_case(db, priya, uuid.UUID(case["id"]))[0]
    second = game_service.events_for_case(db, dev, uuid.UUID(case["id"]))[0]

    assert first.kind == "jury_first"
    assert second.kind == "jury_correct"
    assert first.xp == rules.JURY_CORRECT_XP * rules.JURY_FIRST_VOTE_MULTIPLIER
    assert second.xp == rules.JURY_CORRECT_XP


def test_a_ruling_pays_once_however_often_it_is_settled(
    db, client, auth_headers, defended_case, drain
):
    headers = auth_headers()
    case, _ = defended_case(headers)
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    user = db.query(User).one()
    before = db.get(PlayerProfile, user.id).xp
    row = db.query(Case).one()
    game_service.settle_case(db, row, "guilty")
    db.refresh(db.get(PlayerProfile, user.id))
    assert db.get(PlayerProfile, user.id).xp == before


# --- levels and the rewards card -------------------------------------------


def test_crossing_a_thousand_xp_is_a_level(db, auth_headers, client):
    headers = auth_headers()
    _state(client, headers)
    user = db.query(User).one()
    profile = db.get(PlayerProfile, user.id)

    profile.xp = XP_PER_LEVEL - 1
    db.commit()
    assert profile.level == 1
    assert profile.xp_to_next_level == 1

    profile.xp = XP_PER_LEVEL
    db.commit()
    assert profile.level == 2
    assert profile.xp_into_level == 0


def test_the_rewards_card_reads_back_what_the_case_paid(
    client, auth_headers, defended_case, drain
):
    headers = auth_headers()
    _state(client, headers)
    case, _ = defended_case(headers)
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    res = client.get(f"/api/v1/me/rewards/{case['id']}", headers=headers)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["items"], "a ruled case paid its plaintiff something"
    assert body["total_xp"] == sum(i["xp"] for i in body["items"])
    assert body["total_coins"] == sum(i["coins"] for i in body["items"])


def test_somebody_elses_case_pays_you_nothing(
    client, auth_headers, defended_case, drain
):
    owner = auth_headers(name="Alex")
    case, _ = defended_case(owner)
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=owner)
    drain()

    stranger = auth_headers(name="Nobody")
    body = client.get(f"/api/v1/me/rewards/{case['id']}", headers=stranger).json()
    assert body["items"] == []
    assert body["total_xp"] == 0


def test_the_rewards_of_a_case_that_does_not_exist_are_not_found(
    client, auth_headers
):
    res = client.get(f"/api/v1/me/rewards/{uuid.uuid4()}", headers=auth_headers())
    assert res.status_code == 404
