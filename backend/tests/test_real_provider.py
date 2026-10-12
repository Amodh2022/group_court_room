"""Contract tests for RealLLMProvider.

Exercised against a fake Anthropic client, so the suite needs no API key and
costs nothing — while still covering the paths that only the real provider has:
structured-output parsing, refusals, timeouts and status-code classification.
"""

from __future__ import annotations

import types

import anthropic
import pytest

from app.llm.anthropic_provider import RealLLMProvider
from app.llm.base import (
    LLMError,
    LLMInvalidOutputError,
    LLMRefusalError,
    LLMTimeoutError,
    VerdictRequest,
)
from app.llm.mock import MockLLMProvider
from app.prompts.verdict_prompt import PROMPT_VERSION

REQUEST = VerdictRequest(
    title="The Last Pizza Slice",
    category="food",
    accusation="My friend ate the last slice after saying they were full.",
    defense="Nobody claimed it, so I assumed it was abandoned.",
    plaintiff_name="Alex",
    defendant_name="Sam",
)


class FakeMessages:
    def __init__(self, response=None, error: Exception | None = None) -> None:
        self._response = response
        self._error = error
        self.calls: list[dict] = []

    def parse(self, **kwargs):
        self.calls.append(kwargs)
        if self._error:
            raise self._error
        return self._response


class FakeClient:
    def __init__(self, response=None, error: Exception | None = None) -> None:
        self.messages = FakeMessages(response, error)


def _ok_response():
    output = MockLLMProvider().generate_verdict(REQUEST).output
    return types.SimpleNamespace(
        parsed_output=output,
        stop_reason="end_turn",
        stop_details=None,
        usage=types.SimpleNamespace(input_tokens=500, output_tokens=300),
    )


def _api_status_error(code: int) -> anthropic.APIStatusError:
    request = __import__("httpx2").Request("POST", "https://api.anthropic.com/v1/messages")
    response = __import__("httpx2").Response(code, request=request)
    return anthropic.APIStatusError("boom", response=response, body=None)


def test_successful_generation_returns_validated_output():
    client = FakeClient(_ok_response())
    generation = RealLLMProvider(client=client).generate_verdict(REQUEST)

    assert generation.prompt_version == PROMPT_VERSION
    assert generation.output.verdict in {
        "guilty", "not_guilty", "both_guilty", "insufficient_evidence"
    }

    sent = client.messages.calls[0]
    # Structured output is requested, not hoped for.
    assert sent["output_format"].__name__ == "VerdictOutput"
    assert "UNTRUSTED INPUT" in sent["system"]
    assert "<accusation>" in sent["messages"][0]["content"]


def test_refusal_stop_reason_is_surfaced_and_not_retried():
    response = types.SimpleNamespace(
        parsed_output=None,
        stop_reason="refusal",
        stop_details=types.SimpleNamespace(category="general_harms"),
        usage=types.SimpleNamespace(input_tokens=1, output_tokens=0),
    )
    with pytest.raises(LLMRefusalError) as exc:
        RealLLMProvider(client=FakeClient(response)).generate_verdict(REQUEST)
    assert exc.value.category == "general_harms"
    assert exc.value.retryable is False


def test_unparsable_output_raises_invalid_output():
    response = types.SimpleNamespace(
        parsed_output=None, stop_reason="end_turn", stop_details=None,
        usage=types.SimpleNamespace(input_tokens=1, output_tokens=1),
    )
    with pytest.raises(LLMInvalidOutputError):
        RealLLMProvider(client=FakeClient(response)).generate_verdict(REQUEST)


def test_timeout_is_typed_as_a_timeout():
    error = anthropic.APITimeoutError(
        request=__import__("httpx2").Request("POST", "https://api.anthropic.com")
    )
    with pytest.raises(LLMTimeoutError):
        RealLLMProvider(client=FakeClient(error=error)).generate_verdict(REQUEST)


@pytest.mark.parametrize("code,retryable", [(429, True), (500, True), (503, True),
                                            (400, False), (401, False), (404, False)])
def test_status_errors_are_classified_for_retry(code, retryable):
    with pytest.raises(LLMError) as exc:
        RealLLMProvider(client=FakeClient(error=_api_status_error(code))).generate_verdict(
            REQUEST
        )
    assert exc.value.retryable is retryable


def test_provider_does_not_add_its_own_retry_loop():
    """Retries are counted by VerdictService; a hidden SDK loop would break the cap."""
    client = FakeClient(_ok_response())
    provider = RealLLMProvider(client=client)
    provider.generate_verdict(REQUEST)
    assert len(client.messages.calls) == 1


def test_factory_refuses_to_start_without_credentials(monkeypatch):
    from app.config import get_settings
    from app.llm.factory import get_llm_provider

    settings = get_settings()
    monkeypatch.setattr(settings, "llm_provider", "anthropic")
    monkeypatch.setattr(settings, "anthropic_api_key", None)
    get_llm_provider.cache_clear()
    try:
        with pytest.raises(RuntimeError, match="ANTHROPIC_API_KEY"):
            get_llm_provider()
    finally:
        get_llm_provider.cache_clear()
