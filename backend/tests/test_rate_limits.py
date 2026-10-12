"""Rate limiting on the endpoints a stranger can reach."""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.security.rate_limit import counter


@pytest.fixture
def rate_limited():
    settings = get_settings()
    settings.rate_limit_enabled = True
    counter.reset()
    yield settings
    settings.rate_limit_enabled = False
    counter.reset()


def test_public_write_endpoint_is_rate_limited(client, make_case, rate_limited):
    rate_limited.rate_limit_public_writes = 3
    case, _ = make_case()
    payload = {"nickname": "Sam", "body": "Here is my considered defense of the matter."}
    url = f"/api/v1/invites/{case['invite_token']}/defense"

    statuses = [client.post(url, json=payload).status_code for _ in range(5)]
    assert 429 in statuses, f"expected a 429 within 5 attempts, got {statuses}"

    limited = next(s for s in statuses if s == 429)
    assert limited == 429


def test_rate_limited_response_shape_and_retry_after(client, make_case, rate_limited):
    rate_limited.rate_limit_public_reads = 2
    case, _ = make_case()
    url = f"/api/v1/invites/{case['invite_token']}"

    last = None
    for _ in range(5):
        last = client.get(url)
        if last.status_code == 429:
            break
    assert last.status_code == 429
    assert last.json()["error"] == "rate_limited"
    assert int(last.headers["Retry-After"]) >= 1


def test_case_creation_is_rate_limited(client, auth_headers, rate_limited):
    from tests.conftest import VALID_CASE

    rate_limited.rate_limit_case_create = 2
    headers = auth_headers()
    statuses = [
        client.post("/api/v1/cases", json=VALID_CASE, headers=headers).status_code
        for _ in range(4)
    ]
    assert statuses.count(201) <= 2
    assert 429 in statuses


def test_limits_are_per_client(client, make_case, rate_limited):
    rate_limited.rate_limit_public_reads = 2
    case, _ = make_case()
    url = f"/api/v1/invites/{case['invite_token']}"

    for _ in range(3):
        client.get(url, headers={"x-forwarded-for": "10.0.0.1"})
    # A different client must not inherit the first one's exhausted budget.
    assert client.get(url, headers={"x-forwarded-for": "10.0.0.2"}).status_code == 200


def test_oversized_request_body_is_rejected(client, auth_headers):
    from tests.conftest import VALID_CASE

    huge = {**VALID_CASE, "accusation": "x" * (get_settings().max_request_body_bytes + 1000)}
    res = client.post("/api/v1/cases", json=huge, headers=auth_headers())
    assert res.status_code == 413
    assert res.json()["error"] == "payload_too_large"
