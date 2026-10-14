from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.config import get_settings
from app.models.enums import CASE_CATEGORIES
from app.schemas.jury import JuryTally
from app.schemas.verdict import VerdictOutput

_settings = get_settings()

Title = Annotated[str, Field(min_length=3, max_length=_settings.max_title_length)]
Accusation = Annotated[str, Field(min_length=10, max_length=_settings.max_accusation_length)]
Nickname = Annotated[str, Field(min_length=1, max_length=_settings.max_nickname_length)]


def _strip(value: str | None) -> str | None:
    return value.strip() if isinstance(value, str) else value


class CaseCreate(BaseModel):
    title: Title
    category: str
    accusation: Accusation
    defendant_nickname: Nickname | None = None
    court_id: uuid.UUID | None = None
    accused_user_id: uuid.UUID | None = None
    #: How petty the plaintiff says it is, 1-3. Multiplies the XP the case pays.
    petty_level: int = Field(default=1, ge=1, le=3)

    _normalise = field_validator("title", "accusation", "defendant_nickname", mode="before")(
        _strip
    )

    @field_validator("category")
    @classmethod
    def _known_category(cls, value: str) -> str:
        if value not in CASE_CATEGORIES:
            raise ValueError(f"category must be one of: {', '.join(CASE_CATEGORIES)}")
        return value


class ParticipantSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    role: str
    display_name: str | None
    has_submitted: bool
    joined_at: datetime | None


class CaseSummary(BaseModel):
    """Dashboard card. No submission bodies."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    category: str
    status: str
    created_at: datetime
    expires_at: datetime | None
    defendant_nickname: str | None
    defense_submitted: bool
    verdict_ready: bool
    share_enabled: bool
    jury_count: int = 0


class CaseDetail(CaseSummary):
    """Creator-only view. The creator wrote the accusation, so they see it."""

    accusation: str
    participants: list[ParticipantSummary]
    invite_url: str | None = None
    jury_url: str | None = None
    share_url: str | None = None
    failure_reason: str | None = None
    jury_tally: JuryTally | None = None


class CaseCreated(CaseDetail):
    """Returned once, at creation: carries the raw invite token."""

    invite_token: str
    invite_url: str
    jury_token: str
    jury_url: str


class InvitePreview(BaseModel):
    """What an invited friend sees before writing a defence.

    Shows the accusation (they must know the charge) and nothing else — no
    creator account data, no case id, no other submissions.
    """

    case_title: str
    category: str
    accusation: str
    plaintiff_name: str
    defendant_nickname: str | None
    expires_at: datetime | None
    already_submitted: bool
    verdict_ready: bool
    jury_count: int = 0


class DefenseCreate(BaseModel):
    nickname: Nickname
    body: Annotated[str, Field(min_length=10, max_length=_settings.max_defense_length)]

    _normalise = field_validator("nickname", "body", mode="before")(_strip)


class DefenseAccepted(BaseModel):
    case_title: str
    nickname: str
    message: str = "Your defense has been entered into the record."


class ShareLink(BaseModel):
    share_token: str
    share_url: str


class VerdictResponse(BaseModel):
    case_id: uuid.UUID
    status: str
    result: VerdictOutput | None = None
    model_version: str | None = None
    prompt_version: str | None = None
    created_at: datetime | None = None
    share_url: str | None = None


class PublicVerdict(BaseModel):
    """Sanitized DTO for the public share page.

    Built by hand from the verdict JSON — never by serialising an ORM object —
    so a new private column cannot leak here by accident.
    """

    case_title: str
    charge: str
    prosecution_summary: str
    defense_summary: str
    verdict: str
    reasoning: str
    sentence: str
    judge_roast: str
    closing_line: str
    share_caption: str
    jury_note: str = ""
    jury: JuryTally | None = None
    # True when the judge landed on the opposite side of a jury that had a
    # majority. The best moment in the game, so it is its own field.
    jury_overruled: bool = False
    decided_at: datetime
    disclaimer: str = (
        "Sue Me is a comedy game. This verdict is entertainment, not a "
        "finding of fact and not legal advice."
    )


class ReportCreate(BaseModel):
    reason: Literal["harassment", "private_info", "hateful", "serious_matter", "other"]
    share_token: str | None = None
    details: Annotated[str | None, Field(max_length=500)] = None


class DevLoginRequest(BaseModel):
    auth_subject: Annotated[str, Field(min_length=3, max_length=64)]
    display_name: Nickname | None = None


class RegisterRequest(BaseModel):
    email: Annotated[str, Field(min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    password: Annotated[str, Field(min_length=8, max_length=128)]
    display_name: Nickname | None = None


class LoginRequest(BaseModel):
    email: Annotated[str, Field(min_length=3, max_length=254)]
    password: Annotated[str, Field(min_length=1, max_length=128)]


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user_id: uuid.UUID
    display_name: str
    email: str | None = None
    handle: str | None = None
