"""The jury: everyone else in the group chat.

A juror holds the jury link and nothing else. They are identified by a key their
own browser generates, which is hashed before storage — enough to stop a refresh
from stuffing the ballot box, not enough to identify anyone from the database.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.models import Case, CaseMember, CaseStatus, JuryVote, JuryVoteKind, Participant
from app.security.tokens import hash_token
from app.services import errors

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Tally:
    guilty: int
    not_guilty: int

    @property
    def total(self) -> int:
        return self.guilty + self.not_guilty

    @property
    def majority(self) -> str | None:
        if self.guilty == self.not_guilty:
            return None
        return (
            JuryVoteKind.guilty if self.guilty > self.not_guilty else JuryVoteKind.not_guilty
        ).value

    def summary(self) -> str:
        """Plain-language tally, for the judge's prompt and the share card."""
        if self.total == 0:
            return "No jury was seated."
        if self.majority is None:
            return f"The jury deadlocked {self.guilty}–{self.not_guilty}."
        side = "guilty" if self.majority == JuryVoteKind.guilty else "not guilty"
        high, low = max(self.guilty, self.not_guilty), min(self.guilty, self.not_guilty)
        return f"The jury voted {high}–{low} for {side}."


def resolve_jury_token(db: Session, raw_token: str) -> Case:
    """Resolve a jury link to its case, or raise the generic invalid-link error."""
    token_hash = hash_token(raw_token)
    case = db.execute(
        select(Case)
        .where(Case.jury_token_hash == token_hash, Case.deleted_at.is_(None))
        .options(selectinload(Case.participants).selectinload(Participant.submission))
    ).scalar_one_or_none()
    if case is None:
        # A signed-in juror seated directly on a case holds their own token.
        case = db.execute(
            select(Case)
            .join(CaseMember, CaseMember.case_id == Case.id)
            .where(
                CaseMember.token_hash == token_hash,
                CaseMember.role == "juror",
                Case.deleted_at.is_(None),
            )
            .options(selectinload(Case.participants).selectinload(Participant.submission))
        ).scalar_one_or_none()
    if case is None:
        raise errors.invalid_link()
    return case


def voter_hash(voter_key: str) -> str:
    return hash_token(voter_key)


def find_vote(db: Session, case: Case, voter_key: str) -> JuryVote | None:
    if not voter_key:
        return None
    return db.execute(
        select(JuryVote).where(
            JuryVote.case_id == case.id, JuryVote.voter_key == voter_hash(voter_key)
        )
    ).scalar_one_or_none()


def tally(case: Case) -> Tally:
    votes = case.jury_votes or []
    return Tally(
        guilty=sum(1 for v in votes if v.vote == JuryVoteKind.guilty),
        not_guilty=sum(1 for v in votes if v.vote == JuryVoteKind.not_guilty),
    )


def tally_for(db: Session, case: Case) -> Tally:
    """Tally straight from the database, for callers holding a stale case."""
    rows = db.execute(select(JuryVote.vote).where(JuryVote.case_id == case.id)).scalars().all()
    return Tally(
        guilty=sum(1 for v in rows if v == JuryVoteKind.guilty),
        not_guilty=sum(1 for v in rows if v == JuryVoteKind.not_guilty),
    )


def cast_vote(
    db: Session, *, case: Case, voter_key: str, juror_name: str | None, vote: str
) -> JuryVote:
    """Seat a juror and record their ballot. One ballot per juror, forever.

    A vote is refused once the verdict exists: the whole point of voting is that
    you committed before you knew.
    """
    if case.jury_closed_at is not None:
        raise errors.conflict("The jury in this case has been dismissed.")
    if case.status in {CaseStatus.completed, CaseStatus.expired}:
        raise errors.conflict(
            "The court has already ruled. You cannot join a jury after the verdict."
        )
    if vote not in {JuryVoteKind.guilty, JuryVoteKind.not_guilty}:
        raise errors.conflict("A juror votes guilty or not guilty. Nothing else.")

    existing = find_vote(db, case, voter_key)
    if existing is not None:
        raise errors.conflict("You have already voted on this case.")

    ballot = JuryVote(
        id=uuid.uuid4(),
        case_id=case.id,
        voter_key=voter_hash(voter_key),
        juror_name=(juror_name or None),
        vote=vote,
    )
    db.add(ballot)
    try:
        db.commit()
    except IntegrityError:
        # The unique (case_id, voter_key) fired: a double-submit raced itself.
        db.rollback()
        raise errors.conflict("You have already voted on this case.") from None

    db.refresh(case)
    logger.info("jury.vote", extra={"case_id": str(case.id)})
    return ballot
