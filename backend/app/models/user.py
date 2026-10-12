from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, created_at_column, uuid_pk


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = uuid_pk()
    auth_subject: Mapped[str] = mapped_column(unique=True, index=True)
    display_name: Mapped[str] = mapped_column(default="Anonymous Plaintiff")
    # Real accounts. Legacy device accounts keep both null.
    email: Mapped[str | None] = mapped_column(unique=True, index=True, default=None)
    password_hash: Mapped[str | None] = mapped_column(default=None)
    handle: Mapped[str | None] = mapped_column(String(20), unique=True, index=True, default=None)
    created_at: Mapped[datetime] = created_at_column()

    cases: Mapped[list[Case]] = relationship(  # noqa: F821
        back_populates="creator", cascade="all, delete-orphan"
    )
