"""Local provider: a model served by Ollama on this machine.

Ollama constrains generation to a JSON Schema via the `format` field, so the
same VerdictOutput contract the hosted provider enforces is enforced here too —
malformed JSON cannot reach the database. Unlike the hosted provider there is
no refusal signal: a local model expresses refusal through the schema itself
(the WHEN TO DECLINE branch of the system prompt), so no stop_reason is checked.
"""

from __future__ import annotations

import logging

import httpx
from pydantic import ValidationError

from app.config import get_settings
from app.llm.base import (
    LLMError,
    LLMInvalidOutputError,
    LLMProvider,
    LLMTimeoutError,
    VerdictGeneration,
    VerdictRequest,
)
from app.prompts.verdict_prompt import PROMPT_VERSION, SYSTEM_PROMPT, build_user_message
from app.schemas.verdict import VerdictOutput

logger = logging.getLogger(__name__)


class OllamaLLMProvider(LLMProvider):
    def __init__(self, client: httpx.Client | None = None) -> None:
        settings = get_settings()
        self._settings = settings
        self.name = settings.llm_model
        self._client = client or httpx.Client(
            base_url=str(settings.ollama_base_url).rstrip("/"),
            timeout=settings.llm_timeout_seconds,
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
        payload = {
            "model": self._settings.llm_model,
            "stream": False,
            "keep_alive": self._settings.ollama_keep_alive,
            # The schema is the hard constraint; the prompt only describes tone.
            "format": VerdictOutput.model_json_schema(),
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
            "options": {
                "temperature": self._settings.llm_temperature,
                "num_predict": self._settings.llm_max_tokens,
                # Must hold system prompt + case + full JSON answer, or Ollama
                # silently truncates the context and the JSON comes back cut off.
                "num_ctx": self._settings.ollama_num_ctx,
            },
        }

        try:
            response = self._client.post("/api/chat", json=payload)
            response.raise_for_status()
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError(str(exc)) from exc
        except httpx.HTTPStatusError as exc:
            error = LLMError(f"ollama returned {exc.response.status_code}")
            # A missing model or bad request fails identically on retry.
            error.retryable = exc.response.status_code >= 500
            raise error from exc
        except httpx.HTTPError as exc:
            raise LLMError(f"cannot reach ollama: {exc}") from exc

        body = response.json()
        content = (body.get("message") or {}).get("content")
        if not content:
            raise LLMInvalidOutputError("ollama returned an empty message")

        try:
            parsed = VerdictOutput.model_validate_json(content)
        except ValidationError as exc:
            # Schema-constrained decoding still lets a small model overrun a
            # max_length, so this stays a retryable invalid-output error.
            raise LLMInvalidOutputError(f"model output did not satisfy VerdictOutput: {exc}") from exc

        logger.info(
            "verdict.generated",
            extra={"model": self._settings.llm_model,
                   "input_tokens": body.get("prompt_eval_count"),
                   "output_tokens": body.get("eval_count")},
        )
        return VerdictGeneration(
            output=parsed,
            model_version=self._settings.llm_model,
            prompt_version=PROMPT_VERSION,
        )
