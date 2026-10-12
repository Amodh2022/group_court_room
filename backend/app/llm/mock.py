"""Deterministic provider so the whole workflow runs without an API key.

Not a stub: it produces schema-valid, case-specific output, which is what lets
the test suite assert on real behaviour.
"""

from __future__ import annotations

import hashlib

from app.llm.base import LLMProvider, VerdictGeneration, VerdictRequest
from app.prompts.verdict_prompt import PROMPT_VERSION
from app.schemas.verdict import VerdictOutput

_VERDICTS = ("guilty", "not_guilty", "both_guilty", "insufficient_evidence")

_SENTENCES = {
    "guilty": "Replace what you took, publicly, within seven days.",
    "not_guilty": "Accept one (1) apology and let the matter rest.",
    "both_guilty": "Write a one-page house policy together before this repeats.",
    "insufficient_evidence": "Both parties must retell this story to a neutral friend.",
}


def _clip(text: str, limit: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _scale(text: str) -> str:
    """Characterise a submission without quoting it.

    Summaries appear on the public share card, so they must never carry a
    verbatim span of what someone typed in private. The mock paraphrases for
    the same reason the real judge is told to: the card is published, the
    submission is not.
    """
    words = len(text.split())
    if words < 20:
        return "briefly and without ceremony"
    if words < 60:
        return "at moderate length"
    return "at considerable, unnecessary length"


class MockLLMProvider(LLMProvider):
    name = "mock-judge-1"

    def generate_verdict(self, request: VerdictRequest) -> VerdictGeneration:
        # Stable per-case so repeated runs in tests are reproducible.
        seed = hashlib.sha256(
            f"{request.title}|{request.accusation}|{request.defense}".encode()
        ).digest()
        verdict = _VERDICTS[seed[0] % len(_VERDICTS)]
        plaintiff, defendant = request.plaintiff_name, request.defendant_name

        output = VerdictOutput(
            case_title=_clip(request.title, 100),
            charge=_clip(f"Alleged {request.category.replace('_', ' ')} misconduct", 180),
            prosecution_summary=_clip(
                f"{plaintiff} brings a {request.category.replace('_', ' ')} complaint, "
                f"put {_scale(request.accusation)}, and asks the court to treat it "
                f"as the outrage they plainly believe it to be.",
                300,
            ),
            defense_summary=_clip(
                f"{defendant} disputes the framing, answers {_scale(request.defense)}, "
                f"and submits that no reasonable friend would have acted otherwise.",
                300,
            ),
            verdict=verdict,
            reasoning=_clip(
                f"The court has weighed the claim against the answer. Neither party "
                f"produced receipts, which is on brand. On the balance of vibes, the "
                f"court finds this matter resolves as {verdict.replace('_', ' ')}.",
                500,
            ),
            sentence=_clip(_SENTENCES[verdict], 250),
            judge_roast=_clip(
                f"{defendant}, the court notes you had a whole defence ready, "
                f"which is rarely the mark of an innocent party.",
                180,
            ),
            closing_line=_clip("This court is adjourned. Go outside.", 180),
            share_caption=_clip(f"The court has ruled: {verdict.replace('_', ' ')}.", 200),
        )
        return VerdictGeneration(
            output=output, model_version=self.name, prompt_version=PROMPT_VERSION
        )
