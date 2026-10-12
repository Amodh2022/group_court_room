"""Persistent criminal record for a person inside one court.

Defendants are anonymous — they never hold an account — so a record is keyed by
(court owner, normalised nickname). "Rohan" in your court and "Rohan" in someone
else's are deliberately different people.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampTZ, UUIDColumn, created_at_column, uuid_pk


class Offender(Base):
    __tablename__ = "offenders"
    __table_args__ = (
        UniqueConstraint("owner_id", "slug", name="uq_offenders_owner_slug"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )

    # Normalised nickname. The display form is kept separately so the record
    # survives "rohan" / "Rohan " / "ROHAN" being typed on different days.
    slug: Mapped[str] = mapped_column(String(60))
    display_name: Mapped[str] = mapped_column(String(40))

    cases_total: Mapped[int] = mapped_column(default=0)
    convictions: Mapped[int] = mapped_column(default=0)
    acquittals: Mapped[int] = mapped_column(default=0)
    mistrials: Mapped[int] = mapped_column(default=0)

    # Consecutive convictions. Reset by any acquittal; a mistrial leaves it be.
    current_streak: Mapped[int] = mapped_column(default=0)
    longest_streak: Mapped[int] = mapped_column(default=0)

    last_verdict_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)
    created_at: Mapped[datetime] = created_at_column()

    @property
    def conviction_rate(self) -> float:
        decided = self.convictions + self.acquittals + self.mistrials
        return round(self.convictions / decided, 2) if decided else 0.0

    @property
    def is_repeat_offender(self) -> bool:
        return self.convictions >= 3
