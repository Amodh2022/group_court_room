"""Public sharing: opt-in, revocable, sanitized, and separate from the invite."""

from __future__ import annotations

import uuid as _uuid

import pytest

from app.models import Case
from app.schemas.case import PublicVerdict

ACCUSATION = "My friend ate the last pizza slice right after saying they were full."
DEFENSE_BODY = "Nobody claimed it, so I assumed it was abandoned property."


@pytest.fixture
def completed_case(client, defended_case, drain):
    case, headers = defended_case()
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()
    return case, headers


def test_sharing_is_opt_in(client, completed_case, db):
    case, headers = completed_case
    row = db.get(Case, _uuid.UUID(case["id"]))
    db.refresh(row)
    assert row.share_token_hash is None, "a completed case must not be public by default"
    assert client.get(f"/api/v1/cases/{case['id']}", headers=headers).json()[
        "share_enabled"
    ] is False


def test_share_link_is_a_separate_capability_from_the_invite(client, completed_case):
    case, headers = completed_case
    share = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()

    assert share["share_token"].startswith("shr_")
    assert share["share_token"] != case["invite_token"]

    # Each token only works on its own endpoint.
    assert client.get(f"/api/v1/public/verdicts/{share['share_token']}").status_code == 200
    assert client.get(f"/api/v1/public/verdicts/{case['invite_token']}").status_code == 404
    assert client.get(f"/api/v1/invites/{share['share_token']}").status_code == 404


def test_public_verdict_exposes_only_the_sanitized_dto(client, completed_case):
    """The share card carries the judge's write-up and nothing else.

    The prosecution/defense *summaries* are model-authored and are shared by
    design (spec §10). What must never cross this boundary is the raw submission
    text, any identifier, and anything about the accounts involved.
    """
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    res = client.get(f"/api/v1/public/verdicts/{token}")
    assert res.status_code == 200
    body = res.json()

    # Structural guarantee: the DTO is an allowlist, so a new private column on
    # Case or Verdict cannot widen this response by accident.
    assert set(body) == set(PublicVerdict.model_fields)

    blob = res.text
    for raw in (ACCUSATION, DEFENSE_BODY):
        assert raw not in blob, "raw submission text must never be republished verbatim"
    for identifier in (case["id"], token, case["invite_token"], "creator_id",
                       "auth_subject", "participant", "submission"):
        assert identifier not in blob, f"public page leaked: {identifier}"

    assert "comedy game" in body["disclaimer"]


def test_public_verdict_requires_no_authentication(client, completed_case):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    assert client.get(f"/api/v1/public/verdicts/{token}").status_code == 200


def test_cannot_share_an_incomplete_case(client, defended_case):
    case, headers = defended_case()
    res = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers)
    assert res.status_code == 409


def test_revoking_a_share_link_kills_it_immediately(client, completed_case):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    assert client.get(f"/api/v1/public/verdicts/{token}").status_code == 200

    assert client.delete(f"/api/v1/cases/{case['id']}/share", headers=headers).status_code == 200

    res = client.get(f"/api/v1/public/verdicts/{token}")
    assert res.status_code == 404
    assert res.json()["error"] == "invalid_link"


def test_resharing_mints_a_new_token_and_does_not_resurrect_the_old_one(
    client, completed_case
):
    case, headers = completed_case
    first = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    client.delete(f"/api/v1/cases/{case['id']}/share", headers=headers)
    second = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]

    assert first != second
    assert client.get(f"/api/v1/public/verdicts/{first}").status_code == 404
    assert client.get(f"/api/v1/public/verdicts/{second}").status_code == 200


def test_deleting_a_case_kills_the_public_link(client, completed_case):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    client.delete(f"/api/v1/cases/{case['id']}", headers=headers)
    assert client.get(f"/api/v1/public/verdicts/{token}").status_code == 404


def test_only_the_owner_can_share_or_revoke(client, completed_case, auth_headers):
    case, _ = completed_case
    bob = auth_headers("dev|bob")
    assert client.post(f"/api/v1/cases/{case['id']}/share", headers=bob).status_code == 404
    assert client.delete(f"/api/v1/cases/{case['id']}/share", headers=bob).status_code == 404


def test_tokens_are_stored_only_as_hashes(client, completed_case, db):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    row = db.get(Case, _uuid.UUID(case["id"]))
    db.refresh(row)

    assert row.share_token_hash != token
    assert len(row.share_token_hash) == 64  # sha256 hex
    from app.models import Participant

    defendant = db.query(Participant).filter(
        Participant.case_id == row.id, Participant.role == "defendant"
    ).one()
    assert defendant.invite_token_hash != case["invite_token"]


def test_share_card_renders_from_the_template(client, completed_case):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    res = client.get(f"/api/v1/public/verdicts/{token}/card.svg")
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("image/svg+xml")
    assert "<svg" in res.text
    assert DEFENSE_BODY not in res.text, "the card must not carry raw submissions"


def test_og_preview_carries_open_graph_tags(client, completed_case):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    res = client.get(f"/api/v1/public/verdicts/{token}/preview")
    assert res.status_code == 200
    for tag in ('property="og:title"', 'property="og:image"', 'property="og:description"',
                'name="twitter:card"'):
        assert tag in res.text, f"missing {tag}"
    assert f"/verdict/{token}" in res.text  # canonical points back into the SPA


def test_card_and_preview_respect_revocation(client, completed_case):
    case, headers = completed_case
    token = client.post(f"/api/v1/cases/{case['id']}/share", headers=headers).json()[
        "share_token"
    ]
    client.delete(f"/api/v1/cases/{case['id']}/share", headers=headers)
    assert client.get(f"/api/v1/public/verdicts/{token}/card.svg").status_code == 404
    assert client.get(f"/api/v1/public/verdicts/{token}/preview").status_code == 404


def test_html_is_escaped_in_the_share_card():
    """Verdict text is model output; it is escaped, never interpolated raw."""
    from app.templates.share_card import render_share_card

    svg = render_share_card({
        "case_title": '<script>alert("xss")</script>',
        "verdict": "guilty",
        "share_caption": "a & b <b>bold</b>",
        "sentence": "fine",
    })
    assert "<script>" not in svg
    assert "&lt;script&gt;" in svg
    assert "&amp;" in svg
