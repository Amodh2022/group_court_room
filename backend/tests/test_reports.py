from __future__ import annotations

from app.models import Report


def test_report_is_accepted_from_a_public_viewer(client, db):
    res = client.post(
        "/api/v1/reports",
        json={"reason": "harassment", "details": "This verdict targets a real person."},
    )
    assert res.status_code == 202
    assert db.query(Report).count() == 1


def test_report_with_a_share_token_is_linked_to_the_case(client, defended_case, drain, db):
    import uuid as _uuid

    case, headers = defended_case()
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]

    client.post("/api/v1/reports", json={"reason": "private_info", "share_token": token})
    report = db.query(Report).one()
    assert report.case_id == _uuid.UUID(case["id"])


def test_unknown_share_token_still_returns_202(client, db):
    """Reporting must not become an oracle for which tokens exist."""
    res = client.post(
        "/api/v1/reports",
        json={"reason": "other", "share_token": "shr_this_token_does_not_exist"},
    )
    assert res.status_code == 202
    assert db.query(Report).one().case_id is None


def test_report_validates_its_reason(client):
    res = client.post("/api/v1/reports", json={"reason": "because_i_said_so"})
    assert res.status_code == 422
