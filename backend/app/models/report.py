from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, UUIDColumn, created_at_column, uuid_pk


class Report(Base):
    """Abuse report raised from a public verdict page or an invite page."""

    __tablename__ = "reports"

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="SET NULL"), nullable=True, index=True
    )
    reason: Mapped[str] = mapped_column(String(32))
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    reporter_hint: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = created_at_column()
