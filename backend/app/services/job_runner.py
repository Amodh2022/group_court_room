"""Database-backed job queue for verdict generation.

Why not `BackgroundTasks`: an in-process task dies with the process and the case
is stranded in `generating`. Here the queue is a table — a restart leaves a row
whose lock goes stale and is reclaimed by the next worker.

`run_pending_jobs` is the same code path in production (worker loop) and in
tests (called directly), so what the suite exercises is what ships.
"""

from __future__ import annotations

import logging
import os
import socket
import time
from datetime import timedelta

from sqlalchemy import or_, select, update
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.base import utcnow
from app.db.session import SessionLocal
from app.llm.base import LLMError, LLMRefusalError
from app.models import Case, JobStatus, VerdictJob
from app.services.verdict_service import VerdictService

logger = logging.getLogger(__name__)

WORKER_ID = f"{socket.gethostname()}:{os.getpid()}"


def claim_job(db: Session, worker_id: str = WORKER_ID) -> VerdictJob | None:
    """Claim one job with a conditional UPDATE.

    Two workers cannot claim the same row: the second one's UPDATE matches zero
    rows because the first already changed `status`/`locked_by`.
    """
    settings = get_settings()
    stale_before = utcnow() - timedelta(seconds=settings.job_stale_seconds)

    candidates = db.execute(
        select(VerdictJob)
        .where(
            or_(
                VerdictJob.status == JobStatus.queued,
                # Reclaim a job whose worker died mid-flight.
                (VerdictJob.status == JobStatus.running)
                & (VerdictJob.locked_at < stale_before),
            ),
            VerdictJob.attempts < settings.job_max_attempts,
        )
        .order_by(VerdictJob.created_at)
        .limit(settings.worker_claim_batch)
    ).scalars().all()

    for job in candidates:
        result = db.execute(
            update(VerdictJob)
            .where(VerdictJob.id == job.id, VerdictJob.status == job.status)
            .values(
                status=JobStatus.running,
                locked_at=utcnow(),
                locked_by=worker_id,
                attempts=VerdictJob.attempts + 1,
                updated_at=utcnow(),
            )
        )
        if result.rowcount == 1:
            db.commit()
            db.refresh(job)
            return job
        db.rollback()
    return None


def run_job(db: Session, job: VerdictJob, service: VerdictService) -> None:
    case = db.execute(
        select(Case).where(Case.id == job.case_id, Case.deleted_at.is_(None))
    ).scalar_one_or_none()

    if case is None:
        job.status = JobStatus.failed
        job.last_error = "case deleted"
        job.updated_at = utcnow()
        db.commit()
        return

    try:
        service.generate_for_case(db, case)
        job.status = JobStatus.succeeded
        job.last_error = None
    except LLMRefusalError as exc:
        service.mark_failed(db, case, f"provider_refusal:{exc.category}")
        job.status = JobStatus.failed
        job.last_error = str(exc)
    except (LLMError, Exception) as exc:
        settings = get_settings()
        exhausted = job.attempts >= settings.job_max_attempts
        job.last_error = f"{type(exc).__name__}: {exc}"[:500]
        if exhausted:
            job.status = JobStatus.failed
            service.mark_failed(db, case, type(exc).__name__)
        else:
            # Back to the queue; the case stays `generating` so the client keeps
            # polling rather than seeing a flicker of `failed`.
            job.status = JobStatus.queued
            job.locked_at = None
            job.locked_by = None
        logger.exception("job.error", extra={"case_id": str(case.id), "job_id": str(job.id)})
    finally:
        job.updated_at = utcnow()
        db.commit()


def run_pending_jobs(service: VerdictService, db: Session | None = None, limit: int = 10) -> int:
    """Drain up to `limit` jobs. Returns how many ran."""
    owns_session = db is None
    session = db or SessionLocal()
    processed = 0
    try:
        while processed < limit:
            job = claim_job(session)
            if job is None:
                break
            run_job(session, job, service)
            processed += 1
    finally:
        if owns_session:
            session.close()
    return processed


def worker_loop(stop_after: int | None = None) -> None:  # pragma: no cover - entrypoint
    from app.llm.factory import get_llm_provider

    settings = get_settings()
    service = VerdictService(get_llm_provider())
    logger.info("worker.started", extra={"worker_id": WORKER_ID})
    iterations = 0
    while stop_after is None or iterations < stop_after:
        try:
            if run_pending_jobs(service) == 0:
                time.sleep(settings.worker_poll_seconds)
        except Exception:
            logger.exception("worker.iteration_failed")
            time.sleep(settings.worker_poll_seconds)
        iterations += 1


if __name__ == "__main__":  # pragma: no cover
    from app.logging_config import configure_logging

    configure_logging()
    worker_loop()
