"""Verdict generation: lifecycle, idempotency, concurrency, retries, failures."""

from __future__ import annotations

import uuid as _uuid

import pytest

from app.db.base import utcnow
from app.llm.base import (
    LLMError,
    LLMInvalidOutputError,
    LLMRefusalError,
    LLMTimeoutError,
    VerdictGeneration,
    VerdictRequest,
)
from app.llm.mock import MockLLMProvider
from app.models import Case, CaseStatus, JobStatus, Verdict, VerdictJob
from app.schemas.verdict import VerdictOutput
from app.services import case_service
from app.services.job_runner import run_pending_jobs
from app.services.verdict_service import VerdictService

VERDICT_FIELDS = set(VerdictOutput.model_fields)


class FlakyProvider:
    """Fails `failures` times, then succeeds. Counts every attempt."""

    name = "flaky-test-provider"

    def __init__(self, failures: int, error: Exception | None = None) -> None:
        self.failures = failures
        self.calls = 0
        self.error = error or LLMTimeoutError("upstream timed out")

    def generate_verdict(self, request: VerdictRequest) -> VerdictGeneration:
        self.calls += 1
        if self.calls <= self.failures:
            raise self.error
        return MockLLMProvider().generate_verdict(request)


class BrokenSchemaProvider:
    name = "broken-test-provider"

    def __init__(self) -> None:
        self.calls = 0

    def generate_verdict(self, request: VerdictRequest) -> VerdictGeneration:
        self.calls += 1
        # Exactly what a real provider does when the model returns junk: the
        # Pydantic validation failure is surfaced as a typed LLM error.
        raise LLMInvalidOutputError("model output did not satisfy VerdictOutput")


# --- happy path ------------------------------------------------------------


def test_full_flow_create_invite_defend_generate_reveal(client, defended_case, drain):
    case, headers = defended_case()

    requested = client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert requested.status_code == 202
    assert requested.json()["status"] == CaseStatus.generating

    assert drain() == 1

    res = client.get(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == CaseStatus.completed
    assert set(body["result"]) == VERDICT_FIELDS
    assert body["result"]["verdict"] in {
        "guilty", "not_guilty", "both_guilty", "insufficient_evidence"
    }
    assert body["model_version"] == "mock-judge-1"
    assert body["prompt_version"] == "v2"

    # The dashboard reflects it without a second request shape.
    summary = client.get("/api/v1/cases", headers=headers).json()[0]
    assert summary["status"] == CaseStatus.completed
    assert summary["verdict_ready"] is True


def test_verdict_output_respects_schema_limits(provider):
    generation = provider.generate_verdict(VerdictRequest(
        title="T" * 200, category="food", accusation="A" * 2000, defense="D" * 2000,
        plaintiff_name="P", defendant_name="D",
    ))
    # Round-tripping through the model is the validation.
    reparsed = VerdictOutput.model_validate(generation.output.model_dump())
    assert len(reparsed.case_title) <= 100
    assert len(reparsed.prosecution_summary) <= 300
    assert len(reparsed.reasoning) <= 500


# --- state transitions -----------------------------------------------------


def test_cannot_generate_before_defense(client, make_case):
    case, headers = make_case()
    res = client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert res.status_code == 409
    assert "defense" in res.json()["message"].lower()


def test_verdict_request_is_idempotent(client, defended_case, drain):
    case, headers = defended_case()
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    drain()

    # Asking again after completion returns the same verdict, not a new one.
    first = client.get(f"/api/v1/cases/{case['id']}/verdict", headers=headers).json()
    again = client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert again.status_code == 200
    assert again.json()["result"] == first["result"]
    assert again.json()["created_at"] == first["created_at"]


def test_concurrent_verdict_requests_produce_one_verdict(client, defended_case, db, drain):
    """Two claims race; only one may win, and only one verdict may exist."""
    case, _ = defended_case()
    case_id = _uuid.UUID(case["id"])
    row = db.get(Case, case_id)

    first = case_service.claim_generation(db, row)
    db.expire_all()
    row = db.get(Case, case_id)
    second = case_service.claim_generation(db, row)

    assert (first, second) == (True, False), "the second claim must lose"

    drain()
    assert db.query(Verdict).filter(Verdict.case_id == case_id).count() == 1
    assert db.query(VerdictJob).filter(VerdictJob.case_id == case_id).count() == 1


def test_in_flight_request_returns_202_not_a_second_job(client, defended_case, db):
    case, headers = defended_case()
    db.query(Case).filter(Case.id == _uuid.UUID(case["id"])).update(
        {"status": CaseStatus.generating}
    )
    db.commit()
    res = client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert res.status_code == 202
    assert res.json()["status"] == CaseStatus.generating


# --- failure and retry -----------------------------------------------------


def test_transient_error_is_retried_then_succeeds(client, defended_case, db, use_provider):
    case, headers = defended_case()
    flaky = use_provider(FlakyProvider(failures=2))

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    run_pending_jobs(VerdictService(flaky))

    assert flaky.calls == 3, "two timeouts should be retried inside one job attempt"
    assert client.get(
        f"/api/v1/cases/{case['id']}/verdict", headers=headers
    ).json()["status"] == CaseStatus.completed


def test_persistent_timeout_fails_the_case_and_can_be_retried(
    client, defended_case, db, use_provider
):
    case, headers = defended_case()
    always_failing = FlakyProvider(failures=99)
    use_provider(always_failing)

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    for _ in range(5):
        if run_pending_jobs(VerdictService(always_failing)) == 0:
            break

    row = db.get(Case, _uuid.UUID(case["id"]))
    db.refresh(row)
    assert row.status == CaseStatus.failed
    assert row.failure_reason

    # A failed case is retryable: a recovered provider completes it.
    use_provider(MockLLMProvider())
    retried = client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    assert retried.status_code == 202
    run_pending_jobs(VerdictService(MockLLMProvider()))
    assert client.get(
        f"/api/v1/cases/{case['id']}/verdict", headers=headers
    ).json()["status"] == CaseStatus.completed


def test_malformed_model_output_never_reaches_the_database(
    client, defended_case, db, use_provider
):
    case, headers = defended_case()
    broken = use_provider(BrokenSchemaProvider())

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    for _ in range(5):
        if run_pending_jobs(VerdictService(broken)) == 0:
            break

    assert db.query(Verdict).filter(Verdict.case_id == _uuid.UUID(case["id"])).count() == 0
    row = db.get(Case, _uuid.UUID(case["id"]))
    db.refresh(row)
    assert row.status == CaseStatus.failed


def test_provider_refusal_is_not_retried(client, defended_case, db, use_provider):
    case, headers = defended_case()
    refusing = FlakyProvider(failures=99, error=LLMRefusalError("general_harms"))
    use_provider(refusing)

    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    run_pending_jobs(VerdictService(refusing))

    assert refusing.calls == 1, "a refusal must not be retried"
    row = db.get(Case, _uuid.UUID(case["id"]))
    db.refresh(row)
    assert row.status == CaseStatus.failed


def test_non_retryable_provider_error_stops_immediately(defended_case, db, use_provider):
    case, _ = defended_case()
    error = LLMError("bad request")
    error.retryable = False
    provider = FlakyProvider(failures=99, error=error)

    row = db.get(Case, _uuid.UUID(case["id"]))
    case_service.claim_generation(db, row)
    with pytest.raises(LLMError):
        VerdictService(provider).generate_for_case(db, db.get(Case, _uuid.UUID(case["id"])))
    assert provider.calls == 1


# --- durability ------------------------------------------------------------


def test_job_survives_a_restart_via_stale_lock_reclaim(client, defended_case, db, drain):
    """Simulates a worker dying mid-generation: the row is reclaimed, not lost."""
    from datetime import timedelta

    case, headers = defended_case()
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)

    job = db.query(VerdictJob).filter(VerdictJob.case_id == _uuid.UUID(case["id"])).one()
    job.status = JobStatus.running
    job.locked_at = utcnow() - timedelta(hours=1)
    job.locked_by = "worker-that-died"
    db.commit()

    assert drain() == 1, "a stale running job must be reclaimed"
    db.refresh(job)
    assert job.status == JobStatus.succeeded


def test_job_is_enqueued_durably_before_any_work_happens(client, defended_case, db):
    case, headers = defended_case()
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)
    job = db.query(VerdictJob).filter(VerdictJob.case_id == _uuid.UUID(case["id"])).one()
    assert job.status in {JobStatus.queued, JobStatus.succeeded}


def test_inline_worker_completes_without_a_separate_process(
    client, defended_case, monkeypatch
):
    """With RUN_JOBS_INLINE=true the API drains its own job (single-process mode)."""
    from app.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "run_jobs_inline", True, raising=False)

    case, headers = defended_case()
    client.post(f"/api/v1/cases/{case['id']}/verdict", headers=headers)

    body = client.get(f"/api/v1/cases/{case['id']}/verdict", headers=headers).json()
    assert body["status"] == CaseStatus.completed
    assert set(body["result"]) == VERDICT_FIELDS
