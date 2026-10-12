"""The local-model provider: what it asks Ollama for, and how it fails."""

from __future__ import annotations

import json

import httpx
import pytest

from app.config import get_settings
from app.llm.base import LLMError, LLMInvalidOutputError, LLMTimeoutError, VerdictRequest
from app.llm.ollama_provider import OllamaLLMProvider
from app.schemas.verdict import VerdictOutput

REQUEST = VerdictRequest(
    title="The Last Pizza Slice", category="food",
    accusation="They ate the last slice.", defense="It was abandoned.",
    plaintiff_name="Alex", defendant_name="Sam",
)

GOOD = VerdictOutput(
    case_title="The Last Pizza Slice", charge="Alleged food misconduct",
    prosecution_summary="p", defense_summary="d", verdict="guilty", reasoning="r",
    sentence="s", judge_roast="j", closing_line="c", share_caption="x",
).model_dump_json()


def provider(handler) -> tuple[OllamaLLMProvider, list[dict]]:
    seen: list[dict] = []

    def wrapped(request: httpx.Request) -> httpx.Response:
        seen.append(json.loads(request.content))
        return handler(request)

    client = httpx.Client(base_url="http://ollama.test", transport=httpx.MockTransport(wrapped))
    return OllamaLLMProvider(client=client), seen


def ok(_: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json={"message": {"content": GOOD}, "eval_count": 5})


def test_the_model_is_asked_to_stay_loaded():
    llm, seen = provider(ok)
    llm.generate_verdict(REQUEST)
    # Without this Ollama unloads after 5 minutes and the next verdict pays a
    # ~12 second reload before it generates a single token.
    assert seen[0]["keep_alive"] == get_settings().ollama_keep_alive == "30m"


def test_keep_alive_follows_configuration(monkeypatch):
    monkeypatch.setattr(get_settings(), "ollama_keep_alive", "2h")
    llm, seen = provider(ok)
    llm.generate_verdict(REQUEST)
    assert seen[0]["keep_alive"] == "2h"


def test_the_schema_and_limits_are_sent():
    llm, seen = provider(ok)
    llm.generate_verdict(REQUEST)
    payload = seen[0]
    assert payload["stream"] is False
    assert payload["format"]["properties"]["verdict"]
    assert payload["options"]["num_ctx"] == get_settings().ollama_num_ctx


def test_a_good_answer_is_returned_as_a_verdict():
    llm, _ = provider(ok)
    generation = llm.generate_verdict(REQUEST)
    assert generation.output.verdict == "guilty"
    assert generation.prompt_version == "v2"


def test_a_timeout_is_retryable():
    def boom(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow")

    llm, _ = provider(boom)
    with pytest.raises(LLMTimeoutError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable


def test_a_missing_model_is_not_retried():
    llm, _ = provider(lambda _: httpx.Response(404, json={"error": "model not found"}))
    with pytest.raises(LLMError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable is False


def test_a_server_error_is_retried():
    llm, _ = provider(lambda _: httpx.Response(503))
    with pytest.raises(LLMError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable is True


def test_an_empty_or_malformed_answer_is_an_invalid_output():
    for content in ("", "not json", json.dumps({"verdict": "guilty"})):
        llm, _ = provider(lambda _, c=content: httpx.Response(200, json={"message": {"content": c}}))
        with pytest.raises(LLMInvalidOutputError):
            llm.generate_verdict(REQUEST)
