"""Real provider: Claude with structured output.

`messages.parse(output_format=...)` constrains the response to VerdictOutput and
validates it, so malformed JSON cannot reach the database. Refusals arrive as a
200 with `stop_reason == "refusal"` — they are checked explicitly, not inferred
from the content.
"""

from __future__ import annotations

import logging

import anthropic

from app.config import get_settings
from app.llm.base import (
    LLMError,
    LLMInvalidOutputError,
    LLMProvider,
    LLMRefusalError,
    LLMTimeoutError,
    VerdictGeneration,
    VerdictRequest,
)
from app.prompts.verdict_prompt import PROMPT_VERSION, SYSTEM_PROMPT, build_user_message
from app.schemas.verdict import VerdictOutput

logger = logging.getLogger(__name__)


class RealLLMProvider(LLMProvider):
    def __init__(self, client: anthropic.Anthropic | None = None) -> None:
        settings = get_settings()
        self._settings = settings
        self.name = settings.llm_model
        self._client = client or anthropic.Anthropic(
            api_key=settings.anthropic_api_key,
            timeout=settings.llm_timeout_seconds,
            # Retries are owned by VerdictService so attempts are counted and
            # capped per case; the SDK must not add an invisible second loop.
            max_retries=0,
        )

    def generate_verdict(self, request: VerdictRequest) -> VerdictGeneration:
        user_message = build_user_message(
            title=request.title,
            category=request.category,
            accusation=request.accusation,
            defense=request.defense,
            plaintiff_name=request.plaintiff_name,
            defendant_name=request.defendant_name,
            plaintiff_record=request.plaintiff_record,
            defendant_record=request.defendant_record,
            jury_summary=request.jury_summary,
        )
        try:
            response = self._client.messages.parse(
                model=self._settings.llm_model,
                max_tokens=self._settings.llm_max_tokens,
                system=SYSTEM_PROMPT,
                output_config={"effort": self._settings.llm_effort},
                messages=[{"role": "user", "content": user_message}],
                output_format=VerdictOutput,
            )
        except anthropic.APITimeoutError as exc:
            raise LLMTimeoutError(str(exc)) from exc
        except anthropic.APIStatusError as exc:
            error = LLMError(f"provider returned {exc.status_code}")
            # 4xx other than 429 will fail identically on retry.
            error.retryable = exc.status_code == 429 or exc.status_code >= 500
            raise error from exc
        except anthropic.APIConnectionError as exc:
            raise LLMError(str(exc)) from exc

        if getattr(response, "stop_reason", None) == "refusal":
            category = getattr(getattr(response, "stop_details", None), "category", None)
            raise LLMRefusalError(category)

        parsed = getattr(response, "parsed_output", None)
        if not isinstance(parsed, VerdictOutput):
            raise LLMInvalidOutputError("model output did not satisfy VerdictOutput")

        logger.info(
            "verdict.generated",
            extra={"model": self._settings.llm_model,
                   "input_tokens": getattr(response.usage, "input_tokens", None),
                   "output_tokens": getattr(response.usage, "output_tokens", None)},
        )
        return VerdictGeneration(
            output=parsed,
            model_version=self._settings.llm_model,
            prompt_version=PROMPT_VERSION,
        )
