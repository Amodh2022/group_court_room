from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class BadgeOut(BaseModel):
    """One badge in the catalogue, earned or not."""

    code: str
    name: str
    glyph: str
    hint: str
    earned: bool
    earned_at: datetime | None = None


class QuestOut(BaseModel):
    code: str
    text: str
    progress: int
    target: int
    xp: int
    done: bool


class PlayerOut(BaseModel):
    """The player card: everything the dashboard draws about one account."""

    display_name: str
    level: int
    xp: int = Field(description="Total XP earned, all levels")
    xp_into_level: int
    xp_per_level: int
    xp_to_next_level: int
    coins: int
    streak_days: int
    longest_streak_days: int
    badges_earned: int
    badges_total: int


class GameState(BaseModel):
    """One call, everything the game screens need on launch."""

    player: PlayerOut
    quests: list[QuestOut]
    badges: list[BadgeOut]


class RewardOut(BaseModel):
    """One line on the verdict's rewards card."""

    kind: str
    detail: str
    xp: int
    coins: int
    badge_code: str | None = None
    badge_name: str | None = None
    level_reached: int | None = None


class CaseRewards(BaseModel):
    """What one case paid one player. Empty until the judge has ruled."""

    case_id: str
    total_xp: int
    total_coins: int
    level_reached: int | None = None
    items: list[RewardOut]
