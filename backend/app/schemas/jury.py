"""Jury box and criminal record DTOs."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator

from app.config import get_settings

_settings = get_settings()

VoterKey = Annotated[str, Field(min_length=8, max_length=128)]


class JuryTally(BaseModel):
    guilty: int
    not_guilty: int
    total: int
    majority: str | None
    summary: str


class JuryRoom(BaseModel):
    """What a juror sees. Both sides of the argument and nothing else.

    `tally` stays null until this juror has voted: seeing the running count
    first would turn a vote into a poll, and the whole point is committing
    before you know.
    """

    case_title: str
    category: str
    accusation: str
    defense: str | None
    plaintiff_name: str
    defendant_name: str
    status: str
    jury_open: bool
    verdict_ready: bool
    your_vote: str | None
    tally: JuryTally | None


class JuryVoteCreate(BaseModel):
    voter_key: VoterKey
    juror_name: Annotated[str | None, Field(max_length=_settings.max_nickname_length)] = None
    vote: Literal["guilty", "not_guilty"]

    @field_validator("juror_name", mode="before")
    @classmethod
    def _strip(cls, value: str | None) -> str | None:
        return value.strip() or None if isinstance(value, str) else value


class JuryVoteAccepted(BaseModel):
    your_vote: str
    tally: JuryTally
    message: str = "You have been seated. Your vote is on the record."


class RapSheetEntry(BaseModel):
    """One person's standing in one court."""

    id: uuid.UUID
    display_name: str
    rank: int
    title: str
    cases_total: int
    convictions: int
    acquittals: int
    mistrials: int
    current_streak: int
    longest_streak: int
    conviction_rate: float
    last_verdict_at: datetime | None
    # True for the caller's own record in their own court, so the client can
    # draw "where you stand" without guessing which row is them.
    is_you: bool = False
