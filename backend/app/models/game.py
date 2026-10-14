"""The game layer: experience, coins, streaks, daily quests and badges.

Everything here is bookkeeping *about* a player, never about a case. A case is
still the truth — who filed it, who answered, how the jury split, what the judge
said. These tables only say what that cost and what it earned, so that deleting
the whole schema would lose the game and not the court.

One profile row per account, created on first sight. Nothing is pre-seeded: a
player who has done nothing has zero of everything, which is exactly what the
screens show.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Date, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampTZ, UUIDColumn, created_at_column, uuid_pk

# A level is a flat 1000 XP. Flat, not a curve: the player card has to be able
# to say "640 / 1000" and have that mean the same thing at level 2 and level 20.
XP_PER_LEVEL = 1000


class PlayerProfile(Base):
    __tablename__ = "player_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )

    xp: Mapped[int] = mapped_column(default=0)

    # Coins are spent to file a case. A new player gets enough to file a few
    # before the economy matters at all.
    coins: Mapped[int] = mapped_column(default=100)

    # Consecutive days the player opened the app. `last_active_on` is a date,
    # not a timestamp: a streak is about days, and comparing timestamps makes
    # "yesterday" depend on the hour.
    streak_days: Mapped[int] = mapped_column(default=0)
    longest_streak_days: Mapped[int] = mapped_column(default=0)
    last_active_on: Mapped[date | None] = mapped_column(Date, nullable=True)

    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = mapped_column(
        TimestampTZ, server_default=func.now(), onupdate=func.now()
    )

    @property
    def level(self) -> int:
        return self.xp // XP_PER_LEVEL + 1

    @property
    def xp_into_level(self) -> int:
        return self.xp % XP_PER_LEVEL

    @property
    def xp_to_next_level(self) -> int:
        return XP_PER_LEVEL - self.xp_into_level


class PlayerBadge(Base):
    """One badge, awarded once, for good. Codes come from the catalogue in
    `app.services.game_rules`; unknown codes are ignored on read rather than
    constrained here, so retiring a badge never breaks an old row."""

    __tablename__ = "player_badges"
    __table_args__ = (
        UniqueConstraint("user_id", "code", name="uq_player_badges_user_code"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    code: Mapped[str] = mapped_column(String(40))
    awarded_at: Mapped[datetime] = created_at_column()


class DailyQuest(Base):
    """One player's progress on one quest on one day.

    Rows are written the first time a player is seen on a given day, so a quest
    that was never offered cannot be completed retroactively, and yesterday's
    progress stays on yesterday's row.
    """

    __tablename__ = "daily_quests"
    __table_args__ = (
        UniqueConstraint("user_id", "quest_date", "code", name="uq_daily_quests_slot"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    quest_date: Mapped[date] = mapped_column(Date, index=True)
    code: Mapped[str] = mapped_column(String(40))

    progress: Mapped[int] = mapped_column(default=0)
    target: Mapped[int] = mapped_column(default=1)
    xp: Mapped[int] = mapped_column(default=0)

    # Set the moment progress reaches target and the XP is paid out. A quest is
    # paid once; the row stays so the list can show it struck through.
    completed_at: Mapped[datetime | None] = mapped_column(TimestampTZ, nullable=True)

    @property
    def done(self) -> bool:
        return self.completed_at is not None


class GameEvent(Base):
    """Every payout, as it happened.

    The profile holds the running totals; this holds why they are what they
    are. The verdict screen reads it back to tell a player exactly what that
    case earned them — which is only honest if the rows were written at the
    time rather than recomputed afterwards from a rule that may since have
    changed.
    """

    __tablename__ = "game_events"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUIDColumn, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    case_id: Mapped[uuid.UUID | None] = mapped_column(
        UUIDColumn, ForeignKey("cases.id", ondelete="CASCADE"), nullable=True, index=True
    )

    #: What happened, from `game_service`: "case_won", "jury_correct", ...
    kind: Mapped[str] = mapped_column(String(40))
    #: Shown verbatim on the rewards card: "You called it like the judge".
    detail: Mapped[str] = mapped_column(String(120), default="")

    xp: Mapped[int] = mapped_column(default=0)
    coins: Mapped[int] = mapped_column(default=0)
    badge_code: Mapped[str | None] = mapped_column(String(40), nullable=True)
    #: The level the player reached on this event, when it took them up one.
    level_reached: Mapped[int | None] = mapped_column(nullable=True)

    created_at: Mapped[datetime] = created_at_column()
