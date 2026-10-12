from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import Case, Report
from app.schemas.case import ReportCreate
from app.schemas.common import OkResponse
from app.security.rate_limit import RateLimit
from app.security.tokens import hash_token

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post(
    "",
    response_model=OkResponse,
    status_code=status.HTTP_202_ACCEPTED,
    dependencies=[Depends(RateLimit("public_writes"))],
)
def create_report(
    payload: ReportCreate, db: Annotated[Session, Depends(get_db)]
) -> OkResponse:
    """Accept an abuse report from any viewer.

    Always returns 202, even for an unknown token: whether a share link exists
    is not something an unauthenticated reporter gets to learn.
    """
    case_id: uuid.UUID | None = None
    if payload.share_token:
        case_id = db.execute(
            select(Case.id).where(Case.share_token_hash == hash_token(payload.share_token))
        ).scalar_one_or_none()

    db.add(Report(
        id=uuid.uuid4(), case_id=case_id, reason=payload.reason, details=payload.details
    ))
    db.commit()
    return OkResponse()
