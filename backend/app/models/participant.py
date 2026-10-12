from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampTZ, UUIDColumn, uuid_pk
from app.models.enums import ParticipantRole


class Participant(Base):
    __tablename__ = "participants"
    __table_args__ = (
        # One creator seat and one defendant seat per case in the MVP.
        UniqueConstraint("case_id", "role", name="uq_participants_case_role"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(String(16), default=ParticipantRole.defendant)
    display_name: Mapped[str | None] = mapped_column(String(40), nullable=True)

    invite_token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)
    invite_expires_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
    joined_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)

    case: Mapped[Case] = relationship(back_populates="participants")  # noqa: F821
    submission: Mapped[Submission | None] = relationship(  # noqa: F821
        back_populates="participant", cascade="all, delete-orphan", uselist=False,
        lazy="selectin",
    )
