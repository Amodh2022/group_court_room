from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from app.schemas.verdict import VerdictOutput


class LLMError(Exception):
    """Base class for provider failures. Retryable unless stated otherwise."""

    retryable = True


class LLMTimeoutError(LLMError):
    pass


class LLMInvalidOutputError(LLMError):
    """Model returned something that does not satisfy VerdictOutput."""


class LLMRefusalError(LLMError):
    """Provider safety system declined the request. Retrying will not help."""

    retryable = False

    def __init__(self, category: str | None = None) -> None:
        super().__init__(f"provider refused: {category or 'unspecified'}")
        self.category = category


class LLMBudgetError(LLMError):
    retryable = False


@dataclass(frozen=True)
class VerdictRequest:
    title: str
    category: str
    accusation: str
    defense: str
    plaintiff_name: str
    defendant_name: str
    # Court records and the jury's vote. Facts about the game, supplied by us,
    # never by either party — unlike the accusation and the defence.
    plaintiff_record: str = ""
    defendant_record: str = ""
    jury_summary: str = ""


@dataclass(frozen=True)
class VerdictGeneration:
    output: VerdictOutput
    model_version: str
    prompt_version: str


class LLMProvider(Protocol):
    """Injected into VerdictService; MockLLMProvider is the test double."""

    name: str

    def generate_verdict(self, request: VerdictRequest) -> VerdictGeneration: ...
