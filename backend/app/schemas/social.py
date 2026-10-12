from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field


class UserBrief(BaseModel):
    user_id: uuid.UUID
    handle: str
    display_name: str


class CourtCreate(BaseModel):
    name: Annotated[str, Field(min_length=2, max_length=40)]


class CourtJoin(BaseModel):
    invite_code: Annotated[str, Field(min_length=4, max_length=16)]


class MemberAdd(BaseModel):
    user_id: uuid.UUID


class CourtOut(BaseModel):
    id: uuid.UUID
    name: str
    invite_code: str
    owner_id: uuid.UUID
    members: list[UserBrief]


class CaseMemberAdd(BaseModel):
    user_id: uuid.UUID
    role: Literal["accused", "juror"]


class SharedCase(BaseModel):
    case_id: uuid.UUID
    title: str
    category: str
    status: str
    role: str
    creator_name: str
    link_kind: Literal["invite", "jury"]
    token: str


class NotificationOut(BaseModel):
    id: uuid.UUID
    kind: str
    text: str
    created_at: datetime
    read: bool
    case_id: uuid.UUID | None
    court_id: uuid.UUID | None
    link_kind: str | None
    token: str | None


class NotificationList(BaseModel):
    unread: int
    items: list[NotificationOut]
