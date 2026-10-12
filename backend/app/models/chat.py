"""One line spoken in a case's courtroom.

The room is a log, not a socket: every message is a row, and a connection is
just a reader that tails it. That is what lets a judge announcement written by
the verdict worker — a different process — reach a juror connected to the API.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import (
    Base,
    JSONColumn,
    TimestampTZ,
    UUIDColumn,
    created_at_column,
    uuid_pk,
)


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    __table_args__ = (
        # `n` is the per-case order. The constraint, not the application, is
        # what stops two simultaneous posts from sharing a position.
        UniqueConstraint("case_id", "n", name="uq_chat_case_n"),
        Index("ix_chat_case_author_created", "case_id", "author_ref", "created_at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), index=True
    )
    n: Mapped[int] = mapped_column()

    # plaintiff | defendant | juror | judge | system
    kind: Mapped[str] = mapped_column(String(12))
    author_name: Mapped[str] = mapped_column(String(40))
    # Short stable reference for "is this me?" and per-person rate limits.
    # Derived from a hashed key, so it identifies a seat, not a person.
    author_ref: Mapped[str] = mapped_column(String(16))
    body: Mapped[str] = mapped_column(Text)
    meta: Mapped[dict[str, Any] | None] = mapped_column(JSONColumn, nullable=True)

    hidden_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
    created_at: Mapped[datetime] = created_at_column()
