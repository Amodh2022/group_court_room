"""Unauthenticated endpoints. The token IS the capability — nothing else."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Path, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import CaseStatus, Offender, ParticipantRole
from app.schemas.case import DefenseAccepted, DefenseCreate, InvitePreview
from app.security.rate_limit import RateLimit
from app.services import case_service, chat_service, errors, offender_service, serializers

router = APIRouter(prefix="/invites", tags=["invites"])

DbDep = Annotated[Session, Depends(get_db)]
TokenPath = Annotated[str, Path(min_length=8, max_length=128)]


@router.get(
    "/{token}",
    response_model=InvitePreview,
    dependencies=[Depends(RateLimit("public_reads"))],
)
def preview_invite(token: TokenPath, db: DbDep) -> InvitePreview:
    case, _ = case_service.resolve_invite(db, token)
    return serializers.invite_preview(case)


@router.post(
    "/{token}/defense",
    response_model=DefenseAccepted,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(RateLimit("public_writes"))],
)
def submit_defense(token: TokenPath, payload: DefenseCreate, db: DbDep) -> DefenseAccepted:
    case, defendant = case_service.resolve_invite(db, token)

    if defendant.role != ParticipantRole.defendant:
        raise errors.invalid_link()
    if defendant.submission is not None:
        raise errors.conflict("A defense has already been submitted for this case.")
    if case.status != CaseStatus.awaiting_defense:
        raise errors.conflict("This case is no longer accepting a defense.")

    case_service.submit_defense(
        db, case=case, defendant=defendant, nickname=payload.nickname, body=payload.body
    )
    record = db.get(Offender, case.defendant_offender_id) if case.defendant_offender_id else None
    chat_service.defense_entered(
        db, case, payload.nickname, payload.body, offender_service.priors_line(record)
    )
    return DefenseAccepted(case_title=case.title, nickname=payload.nickname)
