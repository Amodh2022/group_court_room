from __future__ import annotations

from functools import lru_cache

from app.config import get_settings
from app.llm.base import LLMProvider
from app.llm.mock import MockLLMProvider


@lru_cache
def get_llm_provider() -> LLMProvider:
    """FastAPI dependency. Override in tests via `app.dependency_overrides`."""
    settings = get_settings()
    if settings.llm_provider == "anthropic":
        if not settings.anthropic_api_key:
            raise RuntimeError(
                "LLM_PROVIDER=anthropic requires ANTHROPIC_API_KEY. "
                "Leave LLM_PROVIDER=mock to run without credentials."
            )
        from app.llm.anthropic_provider import RealLLMProvider

        return RealLLMProvider()
    if settings.llm_provider == "gemini":
        if not settings.gemini_api_key:
            raise RuntimeError(
                "LLM_PROVIDER=gemini requires GEMINI_API_KEY (put it in .env, never in git)."
            )
        from app.llm.gemini_provider import GeminiLLMProvider

        return GeminiLLMProvider()
    if settings.llm_provider == "ollama":
        from app.llm.ollama_provider import OllamaLLMProvider

        return OllamaLLMProvider()
    return MockLLMProvider()
