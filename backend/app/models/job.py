from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampTZ, UUIDColumn, created_at_column, uuid_pk
from app.models.enums import JobStatus


class VerdictJob(Base):
    """Durable job row.

    The queue lives in the database, not in process memory, so a restart
    mid-generation leaves a reclaimable `running` row rather than a case stuck
    in `generating` forever.
    """

    __tablename__ = "verdict_jobs"
    __table_args__ = (Index("ix_verdict_jobs_status_created", "status", "created_at"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), unique=True
    )
    status: Mapped[str] = mapped_column(String(16), default=JobStatus.queued, index=True)
    attempts: Mapped[int] = mapped_column(default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    locked_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
    locked_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = mapped_column(TimestampTZ, nullable=True)
