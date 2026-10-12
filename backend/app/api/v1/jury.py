"""The jury box. Unauthenticated: the jury link is the whole capability.

Jurors never see the running tally before they vote, and they cannot be seated
once the verdict exists. Both rules exist for the same reason: a vote has to be
a commitment, or the reveal is worth nothing.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import CaseStatus, Verdict
from app.schemas.case import PublicVerdict
from app.schemas.jury import JuryRoom, JuryVoteAccepted, JuryVoteCreate
from app.security.rate_limit import RateLimit
from app.services import chat_service, errors, jury_service, serializers

router = APIRouter(prefix="/jury", tags=["jury"])

DbDep = Annotated[Session, Depends(get_db)]
TokenPath = Annotated[str, Path(min_length=8, max_length=128)]
VoterQuery = Annotated[str, Query(max_length=128)]


@router.get(
    "/{token}",
    response_model=JuryRoom,
    dependencies=[Depends(RateLimit("public_reads"))],
)
def jury_room(token: TokenPath, db: DbDep, voter: VoterQuery = "") -> JuryRoom:
    case = jury_service.resolve_jury_token(db, token)
    vote = jury_service.find_vote(db, case, voter)
    return serializers.jury_room(case, your_vote=vote.vote if vote else None)


@router.post(
    "/{token}/vote",
    response_model=JuryVoteAccepted,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(RateLimit("public_writes"))],
)
def cast_vote(token: TokenPath, payload: JuryVoteCreate, db: DbDep) -> JuryVoteAccepted:
    case = jury_service.resolve_jury_token(db, token)
    ballot = jury_service.cast_vote(
        db,
        case=case,
        voter_key=payload.voter_key,
        juror_name=payload.juror_name,
        vote=payload.vote,
    )
    tally = jury_service.tally_for(db, case)
    chat_service.juror_voted(db, case, payload.juror_name or "A juror", tally.total)
    return JuryVoteAccepted(your_vote=ballot.vote, tally=serializers.jury_tally(tally))


@router.get(
    "/{token}/verdict",
    response_model=PublicVerdict,
    dependencies=[Depends(RateLimit("public_reads"))],
)
def jury_verdict(token: TokenPath, db: DbDep, voter: VoterQuery = "") -> PublicVerdict:
    """The reveal — gated on having voted.

    This is the one rule that turns a link into a game: you do not get to read
    the ruling until you have put your own name to a side.
    """
    case = jury_service.resolve_jury_token(db, token)
    if case.status != CaseStatus.completed:
        raise errors.conflict("The court has not ruled on this case yet.")
    if jury_service.find_vote(db, case, voter) is None:
        raise errors.forbidden(
            "The court does not release a ruling to a juror who never voted."
        )

    verdict = db.query(Verdict).filter(Verdict.case_id == case.id).one_or_none()
    if verdict is None:
        raise errors.conflict("The court has not ruled on this case yet.")
    return serializers.public_verdict(verdict, case)
