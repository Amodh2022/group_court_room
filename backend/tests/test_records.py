"""Criminal records: what the court remembers between cases."""

from __future__ import annotations

import pytest

from app.models import Offender
from app.services import offender_service

# --- slugs -----------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("Rohan", "rohan"),
        ("  ROHAN  ", "rohan"),
        ("Rohan K.", "rohan-k"),
        ("rohan_k", "rohan-k"),
        ("José", "jose"),
    ],
)
def test_nicknames_fold_to_one_record_key(raw, expected):
    assert offender_service.slugify(raw) == expected


def test_a_nickname_with_no_letters_opens_no_record(db, auth_headers):
    from app.models import User

    auth_headers(name="Alex")
    user = db.query(User).one()
    assert offender_service.get_or_create(db, owner=user, display_name="!!!") is None
    assert offender_service.get_or_create(db, owner=user, display_name=None) is None


# --- accumulating a record -------------------------------------------------


def _record(db, nickname: str) -> Offender:
    return (
        db.query(Offender)
        .filter(Offender.slug == offender_service.slugify(nickname))
        .one()
    )


def _rule(db, case_id: str, kind: str) -> None:
    """Record a verdict directly, so a test can choose the outcome."""
    import uuid

    from app.models import Case

    case = db.get(Case, uuid.UUID(case_id))
    offender_service.record_verdict(db, case, kind)


def test_a_filed_case_opens_a_record_for_both_parties(client, make_case, db):
    make_case(defendant_nickname="SliceBandit")
    plaintiff = _record(db, "Alex")
    defendant = _record(db, "SliceBandit")
    # Opened, but nothing on it until a verdict lands.
    assert plaintiff.cases_total == 0
    assert defendant.cases_total == 0


def test_a_guilty_verdict_convicts_the_defendant_only(client, make_case, db):
    case, _ = make_case(defendant_nickname="SliceBandit")
    _rule(db, case["id"], "guilty")

    defendant = _record(db, "SliceBandit")
    assert (defendant.convictions, defendant.acquittals, defendant.cases_total) == (1, 0, 1)
    plaintiff = _record(db, "Alex")
    assert (plaintiff.convictions, plaintiff.acquittals) == (0, 1)


def test_not_guilty_convicts_the_plaintiff_for_wasting_the_courts_time(
    client, make_case, db
):
    case, _ = make_case(defendant_nickname="SliceBandit")
    _rule(db, case["id"], "not_guilty")

    assert _record(db, "SliceBandit").acquittals == 1
    assert _record(db, "Alex").convictions == 1


def test_both_guilty_convicts_both(client, make_case, db):
    case, _ = make_case(defendant_nickname="SliceBandit")
    _rule(db, case["id"], "both_guilty")

    assert _record(db, "SliceBandit").convictions == 1
    assert _record(db, "Alex").convictions == 1


def test_insufficient_evidence_is_a_mistrial_and_convicts_nobody(client, make_case, db):
    case, _ = make_case(defendant_nickname="SliceBandit")
    _rule(db, case["id"], "insufficient_evidence")

    record = _record(db, "SliceBandit")
    assert (record.mistrials, record.convictions, record.acquittals) == (1, 0, 0)
    assert record.cases_total == 1


def test_streaks_build_and_break(client, make_case, db, auth_headers):
    headers = auth_headers(name="Alex")
    for kind in ("guilty", "guilty", "guilty"):
        case, _ = make_case(headers, defendant_nickname="SliceBandit")
        _rule(db, case["id"], kind)

    record = _record(db, "SliceBandit")
    assert (record.convictions, record.current_streak, record.longest_streak) == (3, 3, 3)
    assert record.is_repeat_offender is True

    case, _ = make_case(headers, defendant_nickname="SliceBandit")
    _rule(db, case["id"], "not_guilty")
    db.refresh(record)
    assert record.current_streak == 0
    assert record.longest_streak == 3


def test_records_do_not_cross_between_courts(client, make_case, db, auth_headers):
    mine = auth_headers(name="Alex")
    theirs = auth_headers(name="Jordan")
    case_a, _ = make_case(mine, defendant_nickname="Sam")
    _rule(db, case_a["id"], "guilty")
    make_case(theirs, defendant_nickname="Sam")

    sams = db.query(Offender).filter(Offender.slug == "sam").all()
    assert len(sams) == 2
    assert sorted(s.convictions for s in sams) == [0, 1]


# --- priors, as the judge reads them ---------------------------------------


def test_priors_line_for_a_newcomer():
    assert "No prior record" in offender_service.priors_line(None)


def test_priors_line_names_streaks_and_repeat_offenders(client, make_case, db, auth_headers):
    headers = auth_headers(name="Alex")
    for _ in range(3):
        case, _ = make_case(headers, defendant_nickname="SliceBandit")
        _rule(db, case["id"], "guilty")

    line = offender_service.priors_line(_record(db, "SliceBandit"))
    assert "3 convictions" in line
    assert "guilty streak" in line
    assert "repeat offender" in line


def test_the_judge_is_handed_both_records_and_the_jury(client, defended_case, db):
    """The prompt input is built from the record, not from the submissions."""
    import uuid

    from app.llm.mock import MockLLMProvider
    from app.models import Case
    from app.services.verdict_service import VerdictService

    case, _ = defended_case()
    row = db.get(Case, uuid.UUID(case["id"]))
    request = VerdictService(MockLLMProvider())._build_request(db, row)

    assert "No prior record" in request.defendant_record
    assert "No prior record" in request.plaintiff_record
    assert request.jury_summary == "No jury was seated."


# --- the leaderboard -------------------------------------------------------


def test_rap_sheet_ranks_by_convictions(client, make_case, db, auth_headers):
    headers = auth_headers(name="Alex")
    for nickname, kinds in (("Sam", ["guilty", "guilty"]), ("Priya", ["guilty"])):
        for kind in kinds:
            case, _ = make_case(headers, defendant_nickname=nickname)
            _rule(db, case["id"], kind)

    sheet = client.get("/api/v1/cases/rap-sheet", headers=headers).json()
    names = [entry["display_name"] for entry in sheet]
    assert names[0] == "Sam"
    assert sheet[0]["rank"] == 1
    assert sheet[0]["convictions"] == 2
    assert "Priya" in names


def test_rap_sheet_omits_people_who_have_never_been_tried(client, make_case, auth_headers):
    headers = auth_headers(name="Alex")
    make_case(headers, defendant_nickname="NeverTried")
    assert client.get("/api/v1/cases/rap-sheet", headers=headers).json() == []


def test_rap_sheet_is_scoped_to_the_caller(client, make_case, db, auth_headers):
    mine = auth_headers(name="Alex")
    theirs = auth_headers(name="Jordan")
    case, _ = make_case(mine, defendant_nickname="Sam")
    _rule(db, case["id"], "guilty")

    assert client.get("/api/v1/cases/rap-sheet", headers=theirs).json() == []
    assert len(client.get("/api/v1/cases/rap-sheet", headers=mine).json()) >= 1


def test_rap_sheet_needs_a_credential(client):
    assert client.get("/api/v1/cases/rap-sheet").status_code in (401, 403)


def test_rap_sheet_marks_the_callers_own_row(client, make_case, db, auth_headers):
    """A row carries a record id, not an account id, so the server says which
    one is you. Without it the client cannot draw "where you stand"."""
    headers = auth_headers(name="Alex")
    case, _ = make_case(headers, defendant_nickname="Sam")
    _rule(db, case["id"], "both_guilty")

    sheet = client.get("/api/v1/cases/rap-sheet", headers=headers).json()
    mine = [entry["display_name"] for entry in sheet if entry["is_you"]]
    assert mine == ["Alex"]


def test_rap_sheet_marks_nobody_in_someone_elses_court(
    client, make_case, db, auth_headers
):
    mine = auth_headers(name="Alex")
    case, _ = make_case(mine, defendant_nickname="Jordan")
    _rule(db, case["id"], "both_guilty")

    # Jordan has a record in Alex's court, but reads their own court, which is
    # empty. The flag is never set on a name that merely matches.
    sheet = client.get("/api/v1/cases/rap-sheet", headers=mine).json()
    assert [e["is_you"] for e in sheet if e["display_name"] == "Jordan"] == [False]
