from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, UUIDColumn, created_at_column, uuid_pk


class Submission(Base):
    __tablename__ = "submissions"

    id: Mapped[uuid.UUID] = uuid_pk()
    # UNIQUE, not just indexed: the database is what guarantees one defense per
    # defendant, even if two requests race past the application-level check.
    participant_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("participants.id", ondelete="CASCADE"), unique=True
    )
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at_column()

    participant: Mapped[Participant] = relationship(back_populates="submission")  # noqa: F821
