"""One juror's vote on one case.

The jury link is a shared capability — anyone holding it can be seated — so a
juror is identified by a client-generated key rather than an account. The unique
constraint makes ballot-stuffing take deliberate effort instead of a refresh.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, UUIDColumn, created_at_column, uuid_pk


class JuryVote(Base):
    __tablename__ = "jury_votes"
    __table_args__ = (
        UniqueConstraint("case_id", "voter_key", name="uq_jury_votes_case_voter"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), index=True
    )
    # Hash of the juror's device key. Stored hashed for the same reason tokens
    # are: a database dump should not identify who voted which way.
    voter_key: Mapped[str] = mapped_column(String(64))
    juror_name: Mapped[str | None] = mapped_column(String(40), nullable=True)
    # Set when the ballot arrived with a bearer token. The jury link stays a
    # capability anyone can hold — this only says who to pay if they were
    # signed in, and stays null for everyone else.
    juror_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    vote: Mapped[str] = mapped_column(String(16))
    created_at: Mapped[datetime] = created_at_column()

    case: Mapped[Case] = relationship(back_populates="jury_votes")  # noqa: F821
