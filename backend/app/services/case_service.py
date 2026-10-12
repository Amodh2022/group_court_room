"""Case lifecycle. Every state change happens inside a transaction."""

from __future__ import annotations

import logging
import uuid
from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.config import get_settings
from app.db.base import as_aware, utcnow
from app.models import (
    Case,
    CaseMember,
    CaseStatus,
    JobStatus,
    Participant,
    ParticipantRole,
    Submission,
    User,
    VerdictJob,
)
from app.security.tokens import generate_token, hash_token
from app.services import errors, offender_service

logger = logging.getLogger(__name__)


# --- queries ---------------------------------------------------------------


def _live_case_query():
    return select(Case).where(Case.deleted_at.is_(None)).options(
        selectinload(Case.participants).selectinload(Participant.submission)
    )


def get_owned_case(db: Session, case_id: uuid.UUID, user: User) -> Case:
    case = db.execute(_live_case_query().where(Case.id == case_id)).scalar_one_or_none()
    if case is None:
        # 404 rather than 403 for a case owned by someone else: existence of a
        # case id should not be confirmable by a non-owner.
        raise errors.not_found()
    if case.creator_id != user.id:
        raise errors.not_found()
    return refresh_expiry(db, case)


def list_cases(db: Session, user: User, limit: int = 50, offset: int = 0) -> list[Case]:
    cases = db.execute(
        _live_case_query()
        .where(Case.creator_id == user.id)
        .order_by(Case.created_at.desc())
        .limit(min(limit, 100))
        .offset(offset)
    ).scalars().all()
    return [refresh_expiry(db, case) for case in cases]


def refresh_expiry(db: Session, case: Case) -> Case:
    """Lazily flip an elapsed case to `expired`.

    Cheaper and more reliable than a sweeper for an MVP: a case cannot be read
    or written without passing through here first.
    """
    expires_at = as_aware(case.expires_at)
    if (
        expires_at
        and expires_at <= utcnow()
        and case.status in {CaseStatus.draft, CaseStatus.awaiting_defense, CaseStatus.ready}
    ):
        db.execute(
            update(Case)
            .where(Case.id == case.id, Case.status == case.status)
            .values(status=CaseStatus.expired)
        )
        db.commit()
        db.refresh(case)
    return case


def participant(case: Case, role: ParticipantRole) -> Participant | None:
    return next((p for p in case.participants if p.role == role), None)


# --- creation --------------------------------------------------------------


def create_case(
    db: Session,
    *,
    user: User,
    title: str,
    category: str,
    accusation: str,
    defendant_nickname: str | None,
    court_id: uuid.UUID | None = None,
) -> tuple[Case, str, str]:
    """Create a case. Returns `(case, raw_invite_token, raw_jury_token)`.

    Both raw tokens are returned exactly once, here. Only their hashes are
    stored, and they are independent capabilities: the invite lets one person
    answer the charge, the jury link lets the rest of the group vote on it.
    """
    settings = get_settings()

    open_cases = db.execute(
        select(Case.id).where(
            Case.creator_id == user.id,
            Case.deleted_at.is_(None),
            Case.status.in_([CaseStatus.awaiting_defense, CaseStatus.ready,
                             CaseStatus.generating]),
        )
    ).scalars().all()
    if len(open_cases) >= settings.max_open_cases_per_user:
        raise errors.conflict(
            "You have too many open cases. Finish or delete some before filing another."
        )

    now = utcnow()
    raw_token, token_hash = generate_token("invite")
    raw_jury_token, jury_token_hash = generate_token("jury")
    expires_at = now + timedelta(hours=settings.invite_ttl_hours)

    # Records are resolved now, not at verdict time: the nickname on the case
    # is the one the conviction attaches to, whatever gets typed later.
    plaintiff_record = offender_service.get_or_create(
        db, owner=user, display_name=user.display_name
    )
    defendant_record = offender_service.get_or_create(
        db, owner=user, display_name=defendant_nickname
    )

    case = Case(
        id=uuid.uuid4(),
        creator_id=user.id,
        court_id=court_id,
        title=title,
        category=category,
        accusation=accusation,
        status=CaseStatus.draft,
        expires_at=expires_at,
        jury_token_hash=jury_token_hash,
        plaintiff_offender_id=plaintiff_record.id if plaintiff_record else None,
        defendant_offender_id=defendant_record.id if defendant_record else None,
    )
    db.add(case)
    db.flush()

    db.add(Participant(
        id=uuid.uuid4(), case_id=case.id, role=ParticipantRole.creator,
        display_name=user.display_name, joined_at=now,
    ))
    db.add(Participant(
        id=uuid.uuid4(), case_id=case.id, role=ParticipantRole.defendant,
        display_name=defendant_nickname, invite_token_hash=token_hash,
        invite_expires_at=expires_at,
    ))

    # draft -> awaiting_defense: the invite now exists, so the case is live.
    case.status = CaseStatus.awaiting_defense
    db.commit()
    db.refresh(case)

    logger.info("case.created", extra={"case_id": str(case.id), "user_id": str(user.id)})
    return case, raw_token, raw_jury_token


def delete_case(db: Session, case: Case) -> None:
    """Soft delete. Revokes both capabilities in the same transaction.

    Clearing the hashes matters as much as setting `deleted_at`: a leaked link
    must stop resolving immediately, not merely be filtered out later.
    """
    now = utcnow()
    case.deleted_at = now
    case.share_token_hash = None
    case.share_revoked_at = now
    case.jury_token_hash = None
    case.jury_closed_at = now
    for p in case.participants:
        p.invite_token_hash = None
    db.commit()
    logger.info("case.deleted", extra={"case_id": str(case.id)})


# --- invites ---------------------------------------------------------------


def resolve_invite(db: Session, raw_token: str) -> tuple[Case, Participant]:
    """Resolve an invite token or raise the generic invalid-link error."""
    token_hash = hash_token(raw_token)
    row = db.execute(
        select(Participant).where(Participant.invite_token_hash == token_hash)
    ).scalar_one_or_none()
    if row is None:
        # A signed-in accused seated directly on a case holds their own token.
        member = db.execute(
            select(CaseMember).where(
                CaseMember.token_hash == token_hash, CaseMember.role == "accused"
            )
        ).scalar_one_or_none()
        if member is not None:
            row = db.execute(
                select(Participant).where(
                    Participant.case_id == member.case_id,
                    Participant.role == ParticipantRole.defendant,
                )
            ).scalar_one_or_none()
    if row is None:
        raise errors.invalid_link()

    case = db.execute(_live_case_query().where(Case.id == row.case_id)).scalar_one_or_none()
    if case is None:
        raise errors.invalid_link()

    case = refresh_expiry(db, case)
    invite_expires = as_aware(row.invite_expires_at)
    if invite_expires and invite_expires <= utcnow():
        raise errors.invalid_link()
    if case.status == CaseStatus.expired:
        raise errors.invalid_link()
    return case, row


def submit_defense(
    db: Session, *, case: Case, defendant: Participant, nickname: str, body: str
) -> Submission:
    """Record the defence and move the case to `ready`, atomically."""
    if not CaseStatus(case.status).accepts_submissions:
        raise errors.conflict("This case is no longer accepting a defense.")

    submission = Submission(id=uuid.uuid4(), participant_id=defendant.id, body=body)
    db.add(submission)
    defendant.display_name = nickname
    defendant.joined_at = utcnow()

    # Conditional update: if a concurrent request already moved the case on,
    # this matches zero rows and we roll back rather than double-submitting.
    result = db.execute(
        update(Case)
        .where(Case.id == case.id, Case.status == CaseStatus.awaiting_defense)
        .values(status=CaseStatus.ready)
    )
    if result.rowcount != 1:
        db.rollback()
        raise errors.conflict("This case is no longer accepting a defense.")

    try:
        db.commit()
    except IntegrityError:
        # The UNIQUE on submissions.participant_id fired: another request won.
        db.rollback()
        raise errors.conflict("A defense has already been submitted for this case.") from None

    db.refresh(case)
    logger.info("defense.submitted", extra={"case_id": str(case.id)})
    return submission


# --- verdict generation claim ---------------------------------------------


def claim_generation(db: Session, case: Case) -> bool:
    """Atomically move `ready`/`failed` -> `generating` and enqueue the job.

    Returns True if this caller won the claim. Two concurrent requests cannot
    both win: the conditional UPDATE is the lock, and the unique `case_id` on
    verdict_jobs is the backstop.
    """
    settings = get_settings()
    if case.generation_attempts >= settings.llm_max_attempts_per_case:
        raise errors.conflict("This case has exhausted its verdict attempts.")

    result = db.execute(
        update(Case)
        .where(
            Case.id == case.id,
            Case.status.in_([CaseStatus.ready, CaseStatus.failed]),
            Case.deleted_at.is_(None),
        )
        .values(
            status=CaseStatus.generating,
            generation_attempts=Case.generation_attempts + 1,
            failure_reason=None,
        )
    )
    if result.rowcount != 1:
        db.rollback()
        return False

    existing = db.execute(
        select(VerdictJob).where(VerdictJob.case_id == case.id)
    ).scalar_one_or_none()
    if existing is None:
        db.add(VerdictJob(id=uuid.uuid4(), case_id=case.id, status=JobStatus.queued))
    else:
        # A creator-driven retry is a fresh run: reset the per-job attempt
        # counter, or a previously exhausted job would never be claimed again.
        # `generation_attempts` on the case is the ceiling that still applies.
        existing.status = JobStatus.queued
        existing.attempts = 0
        existing.locked_at = None
        existing.locked_by = None
        existing.last_error = None

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return False

    db.refresh(case)
    logger.info("verdict.claimed", extra={"case_id": str(case.id)})
    return True
