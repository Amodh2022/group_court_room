"""Hosted provider: Google Gemini with schema-constrained JSON output.

Talks to the REST API directly over httpx (already a dependency), so no SDK is
added. The API key travels in the `x-goog-api-key` header, never the query
string: a key in a URL ends up in proxy and access logs.

The response schema is VerdictOutput's own JSON schema, so malformed JSON should
not reach us — but it is validated anyway, because a schema is a request and not
a guarantee.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx
from pydantic import ValidationError

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

# finishReason values that mean Gemini's own safety system declined. Retrying the
# same input would only be declined again, at the same cost.
_REFUSAL_REASONS = {
    "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY",
}


def _strip_titles(node: Any) -> Any:
    """Pydantic adds a `title` to every property; the API has no use for them."""
    if isinstance(node, dict):
        return {k: _strip_titles(v) for k, v in node.items() if k != "title"}
    if isinstance(node, list):
        return [_strip_titles(item) for item in node]
    return node


class GeminiLLMProvider(LLMProvider):
    def __init__(self, client: httpx.Client | None = None) -> None:
        settings = get_settings()
        self._settings = settings
        self.name = settings.gemini_model
        self._client = client or httpx.Client(
            base_url=settings.gemini_base_url.rstrip("/"),
            timeout=settings.llm_timeout_seconds,
            headers={"x-goog-api-key": settings.gemini_api_key or ""},
        )

    def _payload(self, request: VerdictRequest) -> dict[str, Any]:
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
        generation: dict[str, Any] = {
            "temperature": self._settings.llm_temperature,
            "maxOutputTokens": self._settings.llm_max_tokens,
            "responseMimeType": "application/json",
            "responseJsonSchema": _strip_titles(VerdictOutput.model_json_schema()),
        }
        budget = self._settings.gemini_thinking_budget
        if budget is not None:
            # A comedy verdict does not need chain-of-thought, and thinking is
            # most of the latency. 0 turns it off; unset leaves the model's default.
            generation["thinkingConfig"] = {"thinkingBudget": budget}
        return {
            "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
            "contents": [{"role": "user", "parts": [{"text": user_message}]}],
            "generationConfig": generation,
        }

    def generate_verdict(self, request: VerdictRequest) -> VerdictGeneration:
        path = f"/models/{self._settings.gemini_model}:generateContent"
        try:
            response = self._client.post(path, json=self._payload(request))
            response.raise_for_status()
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError(str(exc)) from exc
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            error = LLMError(f"gemini returned {status}")
            # 429 and 5xx clear up on their own; a bad key, bad model name or bad
            # request fails identically every time.
            error.retryable = status == 429 or status >= 500
            raise error from exc
        except httpx.HTTPError as exc:
            raise LLMError(f"cannot reach gemini: {exc}") from exc

        body = response.json()

        blocked = (body.get("promptFeedback") or {}).get("blockReason")
        if blocked:
            raise LLMRefusalError(str(blocked))

        candidates = body.get("candidates") or []
        if not candidates:
            raise LLMInvalidOutputError("gemini returned no candidates")
        candidate = candidates[0]

        finish = candidate.get("finishReason")
        if finish in _REFUSAL_REASONS:
            raise LLMRefusalError(str(finish))
        if finish == "MAX_TOKENS":
            # Cut off mid-JSON. Retryable: sampling differs between attempts.
            raise LLMInvalidOutputError("gemini ran out of output tokens")

        parts = (candidate.get("content") or {}).get("parts") or []
        text = "".join(part.get("text", "") for part in parts if not part.get("thought"))
        if not text.strip():
            raise LLMInvalidOutputError("gemini returned an empty message")

        try:
            parsed = VerdictOutput.model_validate_json(text)
        except ValidationError as exc:
            raise LLMInvalidOutputError(
                f"model output did not satisfy VerdictOutput: {exc}"
            ) from exc

        usage = body.get("usageMetadata") or {}
        logger.info(
            "verdict.generated",
            extra={"model": self._settings.gemini_model,
                   "input_tokens": usage.get("promptTokenCount"),
                   "output_tokens": usage.get("candidatesTokenCount")},
        )
        return VerdictGeneration(
            output=parsed,
            model_version=self._settings.gemini_model,
            prompt_version=PROMPT_VERSION,
        )
