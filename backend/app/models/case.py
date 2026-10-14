from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampTZ, UUIDColumn, created_at_column, uuid_pk
from app.models.enums import CaseStatus


class Case(Base):
    __tablename__ = "cases"
    __table_args__ = (
        Index("ix_cases_creator_created", "creator_id", "created_at"),
        # Public verdict tokens are looked up on every share-link open.
        Index("ix_cases_share_token_hash", "share_token_hash"),
        # The jury link is opened once per juror, every time a case is filed.
        Index("ix_cases_jury_token_hash", "jury_token_hash"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    creator_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )

    court_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("courts.id", ondelete="SET NULL"), nullable=True, index=True
    )

    title: Mapped[str] = mapped_column(String(80))
    category: Mapped[str] = mapped_column(String(32))
    accusation: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(24), default=CaseStatus.draft, index=True)

    expires_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True, index=True)

    # Public verdict sharing. Separate capability from the invite token:
    # revoking one must never affect the other.
    share_token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)
    share_enabled_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
    share_revoked_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)

    # Jury summons. A third capability, independent of the invite and the
    # share link: the group can be seated without being able to defend or to
    # publish, and revoking one link never touches the others.
    jury_token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)
    jury_closed_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)

    # Criminal records touched by this case, resolved once at filing so a later
    # rename of a nickname cannot retarget an already-recorded conviction.
    plaintiff_offender_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("offenders.id", ondelete="SET NULL"), nullable=True
    )
    defendant_offender_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("offenders.id", ondelete="SET NULL"), nullable=True
    )

    # How petty the plaintiff said it was, 1-3. Multiplies the XP the case
    # pays out, so the claim is a bet rather than a label.
    petty_level: Mapped[int] = mapped_column(default=1)

    # Set once, when the game has paid this case out. A retried verdict job
    # must not pay twice.
    game_settled_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)

    generation_attempts: Mapped[int] = mapped_column(default=0)
    failure_reason: Mapped[str | None] = mapped_column(String(120), nullable=True)

    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = mapped_column(
        TimestampTZ, server_default=func.now(), onupdate=func.now()
    )

    creator: Mapped[User] = relationship(back_populates="cases")  # noqa: F821
    participants: Mapped[list[Participant]] = relationship(  # noqa: F821
        back_populates="case", cascade="all, delete-orphan", lazy="selectin"
    )
    verdict: Mapped[Verdict | None] = relationship(  # noqa: F821
        back_populates="case", cascade="all, delete-orphan", uselist=False
    )
    chat_messages: Mapped[list[ChatMessage]] = relationship(  # noqa: F821
        cascade="all, delete-orphan", passive_deletes=True
    )
    jury_votes: Mapped[list[JuryVote]] = relationship(  # noqa: F821
        back_populates="case", cascade="all, delete-orphan", lazy="selectin"
    )

    @property
    def share_is_active(self) -> bool:
        return self.share_token_hash is not None and self.share_revoked_at is None

    @property
    def jury_is_open(self) -> bool:
        return self.jury_token_hash is not None and self.jury_closed_at is None
