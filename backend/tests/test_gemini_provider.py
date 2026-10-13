"""The Gemini provider: what it asks for, what it trusts, and how it fails.

These run against a mock transport, so they pin the request shape and the error
mapping. They cannot prove Google accepts the schema; a live call with a real key
does that.
"""

from __future__ import annotations

import json

import httpx
import pytest

from app.config import get_settings
from app.llm.base import (
    LLMError,
    LLMInvalidOutputError,
    LLMRefusalError,
    LLMTimeoutError,
    VerdictRequest,
)
from app.llm.gemini_provider import GeminiLLMProvider
from app.schemas.verdict import VerdictOutput

REQUEST = VerdictRequest(
    title="The Last Pizza Slice", category="food",
    accusation="They ate the last slice.", defense="It was abandoned.",
    plaintiff_name="Alex", defendant_name="Sam",
    plaintiff_record="No prior record.", defendant_record="3 prior appearances.",
    jury_summary="The jury voted 3-1 for guilty.",
)

GOOD = VerdictOutput(
    case_title="The Last Pizza Slice", charge="Alleged food misconduct",
    prosecution_summary="p", defense_summary="d", verdict="guilty", reasoning="r",
    sentence="s", judge_roast="j", closing_line="c", share_caption="x",
).model_dump_json()


def reply(text: str = GOOD, finish: str = "STOP", **extra) -> httpx.Response:
    return httpx.Response(200, json={
        "candidates": [{"content": {"parts": [{"text": text}]}, "finishReason": finish}],
        "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5},
        **extra,
    })


def provider(handler):
    seen: list[httpx.Request] = []

    def wrapped(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    client = httpx.Client(
        base_url="https://gemini.test/v1beta",
        headers={"x-goog-api-key": "test-key-123"},
        transport=httpx.MockTransport(wrapped),
    )
    return GeminiLLMProvider(client=client), seen


def body_of(request: httpx.Request) -> dict:
    return json.loads(request.content)


# --- the request ------------------------------------------------------------


def test_the_key_travels_in_a_header_never_the_url():
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)

    assert seen[0].headers["x-goog-api-key"] == "test-key-123"
    assert "test-key-123" not in str(seen[0].url)
    assert "key=" not in str(seen[0].url)


def test_it_calls_the_configured_model():
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)
    assert seen[0].url.path.endswith(f"/models/{get_settings().gemini_model}:generateContent")


def test_the_system_prompt_and_the_case_are_sent_separately():
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)
    payload = body_of(seen[0])

    assert "Judge Byte" in payload["systemInstruction"]["parts"][0]["text"]
    user = payload["contents"][0]["parts"][0]["text"]
    assert "<accusation>They ate the last slice.</accusation>" in user
    # Untrusted text must not leak into the instruction channel.
    assert "They ate the last slice" not in json.dumps(payload["systemInstruction"])


def test_the_judge_is_handed_the_priors_and_the_jury():
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)
    user = body_of(seen[0])["contents"][0]["parts"][0]["text"]
    assert "3 prior appearances." in user
    assert "The jury voted 3-1 for guilty." in user


def test_it_asks_for_json_matching_the_verdict_schema():
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)
    cfg = body_of(seen[0])["generationConfig"]

    assert cfg["responseMimeType"] == "application/json"
    schema = cfg["responseJsonSchema"]
    assert set(schema["properties"]) == set(VerdictOutput.model_fields)
    assert schema["properties"]["verdict"]["enum"]
    # Pydantic's per-property titles are noise to the API.
    assert not any("title" in prop for prop in schema["properties"].values())


def test_thinking_is_off_by_default_because_it_is_most_of_the_latency():
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)
    assert body_of(seen[0])["generationConfig"]["thinkingConfig"] == {"thinkingBudget": 0}


def test_thinking_can_be_left_to_the_model(monkeypatch):
    monkeypatch.setattr(get_settings(), "gemini_thinking_budget", None)
    llm, seen = provider(lambda _: reply())
    llm.generate_verdict(REQUEST)
    assert "thinkingConfig" not in body_of(seen[0])["generationConfig"]


# --- the answer -------------------------------------------------------------


def test_a_good_answer_becomes_a_verdict():
    llm, _ = provider(lambda _: reply())
    generation = llm.generate_verdict(REQUEST)
    assert generation.output.verdict == "guilty"
    assert generation.model_version == get_settings().gemini_model
    assert generation.prompt_version == "v3"


def test_thought_parts_are_ignored():
    text = httpx.Response(200, json={"candidates": [{
        "finishReason": "STOP",
        "content": {"parts": [{"text": "let me think...", "thought": True}, {"text": GOOD}]},
    }]})
    llm, _ = provider(lambda _: text)
    assert llm.generate_verdict(REQUEST).output.verdict == "guilty"


# --- failures ---------------------------------------------------------------


@pytest.mark.parametrize("reason", ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "RECITATION"])
def test_a_safety_stop_is_a_refusal_and_is_not_retried(reason):
    llm, _ = provider(lambda _: reply(text="", finish=reason))
    with pytest.raises(LLMRefusalError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable is False


def test_a_blocked_prompt_is_a_refusal():
    blocked = httpx.Response(200, json={"promptFeedback": {"blockReason": "SAFETY"}})
    llm, _ = provider(lambda _: blocked)
    with pytest.raises(LLMRefusalError):
        llm.generate_verdict(REQUEST)


def test_running_out_of_tokens_is_retryable_not_silently_truncated():
    llm, _ = provider(lambda _: reply(text=GOOD[:40], finish="MAX_TOKENS"))
    with pytest.raises(LLMInvalidOutputError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, json={"candidates": []}),
        reply(text=""),
        reply(text="not json"),
        reply(text=json.dumps({"verdict": "guilty"})),
        reply(text=json.dumps({**json.loads(GOOD), "verdict": "banana"})),
    ],
)
def test_empty_or_invalid_output_is_rejected(response):
    llm, _ = provider(lambda _: response)
    with pytest.raises(LLMInvalidOutputError):
        llm.generate_verdict(REQUEST)


def test_a_timeout_is_retryable():
    def boom(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow")

    llm, _ = provider(boom)
    with pytest.raises(LLMTimeoutError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable


@pytest.mark.parametrize(("status", "retryable"), [
    (429, True), (500, True), (503, True),
    (400, False), (401, False), (403, False), (404, False),
])
def test_http_errors_retry_only_when_retrying_can_help(status, retryable):
    llm, _ = provider(lambda _: httpx.Response(status, json={"error": {"message": "no"}}))
    with pytest.raises(LLMError) as err:
        llm.generate_verdict(REQUEST)
    assert err.value.retryable is retryable


def test_the_error_never_echoes_the_key():
    llm, _ = provider(lambda _: httpx.Response(403, json={"error": {"message": "denied"}}))
    with pytest.raises(LLMError) as err:
        llm.generate_verdict(REQUEST)
    assert "test-key-123" not in str(err.value)


# --- wiring -----------------------------------------------------------------


def test_the_factory_refuses_to_start_without_a_key(monkeypatch):
    from app.llm.factory import get_llm_provider

    settings = get_settings()
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", None)
    get_llm_provider.cache_clear()
    try:
        with pytest.raises(RuntimeError, match="GEMINI_API_KEY"):
            get_llm_provider()
    finally:
        get_llm_provider.cache_clear()


def test_the_factory_builds_the_provider_when_a_key_is_set(monkeypatch):
    from app.llm.factory import get_llm_provider

    settings = get_settings()
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "k")
    get_llm_provider.cache_clear()
    try:
        assert isinstance(get_llm_provider(), GeminiLLMProvider)
    finally:
        get_llm_provider.cache_clear()
