from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, JSONColumn, UUIDColumn, created_at_column, uuid_pk


class Verdict(Base):
    __tablename__ = "verdicts"

    id: Mapped[uuid.UUID] = uuid_pk()
    case_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), unique=True
    )
    result: Mapped[dict[str, Any]] = mapped_column(JSONColumn)
    model_version: Mapped[str] = mapped_column(String(64))
    prompt_version: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = created_at_column()

    case: Mapped[Case] = relationship(back_populates="verdict")  # noqa: F821
