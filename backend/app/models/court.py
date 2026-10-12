"""Persistent friend groups, direct case members and in-app notifications."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampTZ, UUIDColumn, created_at_column, uuid_pk


class Court(Base):
    __tablename__ = "courts"

    id: Mapped[uuid.UUID] = uuid_pk()
    name: Mapped[str] = mapped_column(String(40))
    invite_code: Mapped[str] = mapped_column(String(16), unique=True, index=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = created_at_column()

    members: Mapped[list[CourtMember]] = relationship(
        back_populates="court", cascade="all, delete-orphan", lazy="selectin"
    )


class CourtMember(Base):
    __tablename__ = "court_members"
    __table_args__ = (UniqueConstraint("court_id", "user_id", name="uq_court_member"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    court_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("courts.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = created_at_column()

    court: Mapped[Court] = relationship(back_populates="members")
    user = relationship("User", lazy="joined")


class CaseMember(Base):
    """A signed-in user seated directly on a case (accused or juror).

    `access_token` is this member's own capability, minted for them and shown
    only to them by `GET /cases/shared`. It resolves through the ordinary
    invite / jury endpoints, so the existing screens work unchanged, and it can
    be revoked without touching the links the creator shared.
    """

    __tablename__ = "case_members"
    __table_args__ = (UniqueConstraint("case_id", "user_id", name="uq_case_member"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(String(16))  # accused | juror
    access_token: Mapped[str] = mapped_column(String(128))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    created_at: Mapped[datetime] = created_at_column()


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(24))
    text: Mapped[str] = mapped_column(Text)
    case_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), nullable=True
    )
    court_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("courts.id", ondelete="CASCADE"), nullable=True
    )
    read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = created_at_column()
    read_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
