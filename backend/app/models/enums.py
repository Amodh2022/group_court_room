from __future__ import annotations

from enum import StrEnum


class CaseStatus(StrEnum):
    draft = "draft"
    awaiting_defense = "awaiting_defense"
    ready = "ready"
    generating = "generating"
    completed = "completed"
    failed = "failed"
    expired = "expired"

    @property
    def is_terminal(self) -> bool:
        return self in {CaseStatus.completed, CaseStatus.expired}

    @property
    def accepts_submissions(self) -> bool:
        return self in {CaseStatus.draft, CaseStatus.awaiting_defense}


class ParticipantRole(StrEnum):
    creator = "creator"
    defendant = "defendant"


class JuryVoteKind(StrEnum):
    guilty = "guilty"
    not_guilty = "not_guilty"


class JobStatus(StrEnum):
    queued = "queued"
    running = "running"
    succeeded = "succeeded"
    failed = "failed"


CASE_CATEGORIES: tuple[str, ...] = (
    "food",
    "roommates",
    "group_chat",
    "travel",
    "money",
    "pets",
    "gaming",
    "other",
)
