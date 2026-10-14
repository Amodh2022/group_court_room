from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.v1.deps import VerdictServiceDep
from app.config import get_settings
from app.db.base import utcnow
from app.db.session import get_db
from app.models import Case, CaseStatus, Court, User, Verdict
from app.schemas.case import (
    CaseCreate,
    CaseCreated,
    CaseDetail,
    CaseSummary,
    ShareLink,
    VerdictResponse,
)
from app.schemas.common import OkResponse
from app.schemas.jury import RapSheetEntry
from app.schemas.social import CaseMemberAdd, SharedCase
from app.security.auth import CurrentUser
from app.security.rate_limit import RateLimit
from app.security.tokens import generate_token
from app.services import (
    case_service,
    chat_service,
    errors,
    offender_service,
    serializers,
    social_service,
)
from app.services.job_runner import run_pending_jobs

router = APIRouter(prefix="/cases", tags=["cases"])

DbDep = Annotated[Session, Depends(get_db)]


@router.post(
    "",
    response_model=CaseCreated,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(RateLimit("case_create"))],
)
def create_case(payload: CaseCreate, user: CurrentUser, db: DbDep) -> CaseCreated:
    court = None
    if payload.court_id is not None:
        court = social_service.get_court_for_member(db, payload.court_id, user)
    accused = None
    if payload.accused_user_id is not None:
        accused = db.get(User, payload.accused_user_id)
        if accused is None or accused.id == user.id:
            raise errors.not_found("User")
        if court is not None and not social_service.is_member(court, accused.id):
            raise errors.conflict("The accused must be a member of that court.")
    nickname = payload.defendant_nickname or (accused.display_name if accused else None)
    case, raw_token, raw_jury_token = case_service.create_case(
        db,
        user=user,
        title=payload.title,
        category=payload.category,
        accusation=payload.accusation,
        defendant_nickname=nickname,
        court_id=court.id if court else None,
        petty_level=payload.petty_level,
    )
    if accused is not None:
        social_service.seat_member(db, case, user, accused.id, "accused")
    if court is not None:
        for m in court.members:
            if m.user_id not in {user.id, payload.accused_user_id}:
                social_service.seat_member(db, case, user, m.user_id, "juror")
    chat_service.open_courtroom(db, case, user.display_name, f"user:{user.id}")
    detail = serializers.case_detail(
        case, raw_invite_token=raw_token, raw_jury_token=raw_jury_token
    )
    fields = detail.model_dump(exclude={"invite_url", "jury_url"})
    return CaseCreated(
        **fields,
        invite_token=raw_token,
        invite_url=serializers.invite_url(raw_token),
        jury_token=raw_jury_token,
        jury_url=serializers.jury_url(raw_jury_token),
    )


@router.get("", response_model=list[CaseSummary])
def list_cases(
    user: CurrentUser,
    db: DbDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[CaseSummary]:
    return [serializers.case_summary(c) for c in case_service.list_cases(db, user, limit, offset)]


@router.get("/rap-sheet", response_model=list[RapSheetEntry])
def rap_sheet(
    user: CurrentUser,
    db: DbDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[RapSheetEntry]:
    """Standings in this user's court: who keeps getting convicted."""
    return serializers.rap_sheet(
        offender_service.leaderboard(db, user, limit),
        you=offender_service.slugify(user.display_name or ""),
    )


@router.get("/shared", response_model=list[SharedCase])
def shared_with_me(user: CurrentUser, db: DbDep) -> list[SharedCase]:
    """Cases where someone seated me directly (as accused or juror)."""
    return [SharedCase(**row) for row in social_service.shared_cases(db, user)]


@router.post("/{case_id}/members", status_code=status.HTTP_204_NO_CONTENT)
def add_case_member(
    case_id: uuid.UUID, payload: CaseMemberAdd, user: CurrentUser, db: DbDep
) -> Response:
    case = case_service.get_owned_case(db, case_id, user)
    if case.court_id is not None:
        court = db.get(Court, case.court_id)
        if court is not None and not social_service.is_member(court, payload.user_id):
            raise errors.conflict("That person is not a member of this case's court.")
    social_service.seat_member(db, case, user, payload.user_id, payload.role)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{case_id}", response_model=CaseDetail)
def get_case(case_id: uuid.UUID, user: CurrentUser, db: DbDep) -> CaseDetail:
    case = case_service.get_owned_case(db, case_id, user)
    detail = serializers.case_detail(case)
    if case.share_is_active:
        # The raw share token is unrecoverable by design; the client keeps the
        # URL it was handed when sharing was enabled.
        detail.share_url = None
    return detail


@router.delete("/{case_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_case(case_id: uuid.UUID, user: CurrentUser, db: DbDep) -> Response:
    case = case_service.get_owned_case(db, case_id, user)
    case_service.delete_case(db, case)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- verdict ---------------------------------------------------------------


@router.post(
    "/{case_id}/verdict",
    response_model=VerdictResponse,
    dependencies=[Depends(RateLimit("verdict"))],
)
def request_verdict(
    case_id: uuid.UUID,
    user: CurrentUser,
    db: DbDep,
    background: BackgroundTasks,
    response: Response,
    service: VerdictServiceDep,
) -> VerdictResponse:
    """Idempotent. Claims the generation job; the worker does the work.

    Calling this twice returns the same case state rather than producing two
    verdicts: the claim is a conditional UPDATE, so the second caller loses.
    """
    case = case_service.get_owned_case(db, case_id, user)

    if case.status == CaseStatus.completed:
        return _verdict_response(db, case)
    if case.status == CaseStatus.expired:
        raise errors.conflict("This case has expired.")
    if case.status in {CaseStatus.draft, CaseStatus.awaiting_defense}:
        raise errors.conflict("The defendant has not submitted a defense yet.")

    if case.status == CaseStatus.generating:
        response.status_code = status.HTTP_202_ACCEPTED
        return VerdictResponse(case_id=case.id, status=case.status)

    if not case_service.claim_generation(db, case):
        db.refresh(case)
        if case.status == CaseStatus.completed:
            return _verdict_response(db, case)
        response.status_code = status.HTTP_202_ACCEPTED
        return VerdictResponse(case_id=case.id, status=case.status)

    chat_service.court_retires(db, case)

    # The job row is already durable; this only shortens the happy-path wait.
    if get_settings().run_jobs_inline:
        background.add_task(run_pending_jobs, service, None, 1)
    response.status_code = status.HTTP_202_ACCEPTED
    return VerdictResponse(case_id=case.id, status=CaseStatus.generating)


@router.get("/{case_id}/verdict", response_model=VerdictResponse)
def get_verdict(case_id: uuid.UUID, user: CurrentUser, db: DbDep) -> VerdictResponse:
    case = case_service.get_owned_case(db, case_id, user)
    return _verdict_response(db, case)


def _verdict_response(db: Session, case: Case) -> VerdictResponse:
    verdict = db.execute(select(Verdict).where(Verdict.case_id == case.id)).scalar_one_or_none()
    if verdict is None:
        return VerdictResponse(case_id=case.id, status=case.status)
    return VerdictResponse(
        case_id=case.id,
        status=case.status,
        result=verdict.result,
        model_version=verdict.model_version,
        prompt_version=verdict.prompt_version,
        created_at=verdict.created_at,
    )


# --- sharing ---------------------------------------------------------------


@router.post("/{case_id}/share", response_model=ShareLink, status_code=status.HTTP_201_CREATED)
def enable_share(case_id: uuid.UUID, user: CurrentUser, db: DbDep) -> ShareLink:
    """Opt-in public sharing. A fresh token each time, so a revoked link is dead."""
    case = case_service.get_owned_case(db, case_id, user)
    if case.status != CaseStatus.completed:
        raise errors.conflict("Only a completed verdict can be shared.")

    raw_token, token_hash = generate_token("share")
    case.share_token_hash = token_hash
    case.share_enabled_at = utcnow()
    case.share_revoked_at = None
    db.commit()
    return ShareLink(share_token=raw_token, share_url=serializers.share_url(raw_token))


@router.delete("/{case_id}/share", response_model=OkResponse)
def revoke_share(case_id: uuid.UUID, user: CurrentUser, db: DbDep) -> OkResponse:
    case = case_service.get_owned_case(db, case_id, user)
    case.share_token_hash = None
    case.share_revoked_at = utcnow()
    db.commit()
    return OkResponse()
