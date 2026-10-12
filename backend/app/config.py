"""Application settings. Everything configurable, nothing hardcoded."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Group Chat Court"
    environment: Literal["local", "test", "staging", "production"] = "local"
    debug: bool = False

    # Database -------------------------------------------------------------
    database_url: str = "postgresql+psycopg://gcc:gcc@localhost:5432/gcc"

    # Auth -----------------------------------------------------------------
    # Dev auth issues our own JWTs. Swap AUTH_PROVIDER to plug a managed IdP in.
    auth_provider: Literal["dev", "jwks"] = "dev"
    jwt_secret: str = "dev-only-insecure-secret-change-me"
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "group-chat-court"
    jwt_ttl_seconds: int = 60 * 60 * 24 * 30
    jwks_url: str | None = None
    jwks_audience: str | None = None

    # Public URLs used to build invite / verdict links ---------------------
    web_base_url: str = "http://localhost:5173"
    # Absolute origin of this API. Social crawlers need an absolute
    # og:image URL, and the share card is served from here, not the SPA.
    api_base_url: str = "http://localhost:8000"
    # Extra browser origins allowed to call this API (comma-separated).
    # web_base_url is always allowed; this covers preview deploys and
    # the 127.0.0.1 vs localhost split that browsers treat as distinct.
    extra_cors_origins: str = ""

    # Tokens / lifecycle ---------------------------------------------------
    token_bytes: int = 32
    invite_ttl_hours: int = 72

    # Limits ---------------------------------------------------------------
    max_title_length: int = 80
    max_accusation_length: int = 1000
    max_defense_length: int = 1000
    max_nickname_length: int = 40
    max_request_body_bytes: int = 64 * 1024
    max_open_cases_per_user: int = 50

    # Rate limits (requests per window, per client IP) ---------------------
    rate_limit_window_seconds: int = 60
    rate_limit_public_reads: int = 60
    rate_limit_public_writes: int = 5
    rate_limit_case_create: int = 10
    rate_limit_verdict: int = 10
    rate_limit_enabled: bool = True

    # LLM ------------------------------------------------------------------
    llm_provider: Literal["mock", "anthropic", "ollama", "gemini"] = "mock"
    anthropic_api_key: str | None = None
    # Gemini (LLM_PROVIDER=gemini). Has its own model name because LLM_MODEL
    # belongs to whichever other provider the .env was last pointed at.
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-2.5-flash"
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta"
    # 0 disables "thinking", which is most of the latency and not needed for a
    # joke. Set GEMINI_THINKING_BUDGET to empty/null for models that require it.
    gemini_thinking_budget: int | None = 0
    llm_model: str = "claude-opus-5-5"
    # Sampling temperature. Only the ollama provider reads this; the hosted
    # provider is steered by llm_effort instead.
    llm_temperature: float = 0.8
    # Local (ollama) provider -------------------------------------------
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_num_ctx: int = 8192
    # How long Ollama keeps the model in memory after a request. Its own default
    # is 5 minutes, after which the next verdict pays a ~12 s reload on top of
    # generating. A game is played in bursts with gaps, so hold it longer.
    ollama_keep_alive: str = "30m"
    llm_effort: Literal["low", "medium", "high", "xhigh", "max"] = "low"
    llm_max_tokens: int = 2000
    llm_timeout_seconds: float = 45.0
    llm_max_attempts: int = 3
    # Hard ceiling on generations per case, so a retry loop cannot burn budget.
    llm_max_attempts_per_case: int = 5

    # Worker ---------------------------------------------------------------
    # When true the API also drains the job it just enqueued, so a single
    # process needs no separate worker. The job row is durable either way.
    run_jobs_inline: bool = True
    worker_poll_seconds: float = 1.0
    worker_claim_batch: int = 5
    job_max_attempts: int = 3
    job_stale_seconds: int = 120

    # Push (FCM) -----------------------------------------------------------
    # Path to a Firebase service-account JSON. Unset/missing = pushes are skipped.
    firebase_credentials: str | None = None
    # Max pushes per user per rolling 24h (counted from in-app notifications).
    push_daily_cap: int = 20

    @property
    def cors_origins(self) -> list[str]:
        extra = [o.strip() for o in self.extra_cors_origins.split(",") if o.strip()]
        return list(dict.fromkeys([self.web_base_url.rstrip("/"), *extra]))

    @property
    def is_test(self) -> bool:
        return self.environment == "test"


@lru_cache
def get_settings() -> Settings:
    return Settings()
