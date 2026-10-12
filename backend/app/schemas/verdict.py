"""The structured contract the model must satisfy. Nothing else is accepted."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

VerdictResult = Literal["guilty", "not_guilty", "both_guilty", "insufficient_evidence"]


class VerdictOutput(BaseModel):
    case_title: str = Field(max_length=100)
    charge: str = Field(max_length=180)
    prosecution_summary: str = Field(max_length=300)
    defense_summary: str = Field(max_length=300)
    verdict: VerdictResult
    reasoning: str = Field(max_length=500)
    sentence: str = Field(max_length=250)
    judge_roast: str = Field(max_length=180)
    closing_line: str = Field(max_length=180)
    share_caption: str = Field(max_length=200)
    # Optional: the judge's word on the jury's vote, especially when overruling
    # it. Defaulted so a provider that omits it still satisfies the contract.
    jury_note: str = Field(default="", max_length=180)
