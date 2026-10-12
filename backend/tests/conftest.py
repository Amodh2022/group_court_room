from __future__ import annotations

import os
import tempfile
import uuid
from pathlib import Path

import pytest

# Must be set before anything imports app.config / app.db.session.
_TMP = Path(tempfile.mkdtemp(prefix="gcc-test-"))
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("DATABASE_URL", f"sqlite:///{_TMP / 'test.db'}")
os.environ.setdefault("LLM_PROVIDER", "mock")
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("WEB_BASE_URL", "http://testweb.local")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
# Tests drive the worker explicitly so job scheduling is deterministic.
os.environ.setdefault("RUN_JOBS_INLINE", "false")

from fastapi.testclient import TestClient

from app.db.base import Base
from app.db.session import SessionLocal, engine
from app.llm.factory import get_llm_provider
from app.llm.mock import MockLLMProvider
from app.main import app
from app.security.rate_limit import counter
from app.services.job_runner import run_pending_jobs
from app.services.verdict_service import VerdictService


@pytest.fixture(autouse=True)
def fresh_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    counter.reset()
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture
def provider():
    return MockLLMProvider()


@pytest.fixture
def use_provider():
    """Install a provider for the duration of a test."""
    def _install(p):
        app.dependency_overrides[get_llm_provider] = lambda: p
        return p
    yield _install
    app.dependency_overrides.pop(get_llm_provider, None)


@pytest.fixture
def drain():
    """Run the durable worker until the queue is empty."""
    def _drain(p=None):
        return run_pending_jobs(VerdictService(p or MockLLMProvider()))
    return _drain


# --- helpers ---------------------------------------------------------------


@pytest.fixture
def auth_headers(client):
    def _auth(subject: str | None = None, name: str = "Alex"):
        subject = subject or f"dev|{uuid.uuid4().hex[:8]}"
        res = client.post(
            "/api/v1/auth/dev-login",
            json={"auth_subject": subject, "display_name": name},
        )
        assert res.status_code == 200, res.text
        return {"Authorization": f"Bearer {res.json()['access_token']}"}
    return _auth


VALID_CASE = {
    "title": "The Last Pizza Slice",
    "category": "food",
    "accusation": "My friend ate the last pizza slice right after saying they were full.",
    "defendant_nickname": "SliceBandit",
}


@pytest.fixture
def make_case(client, auth_headers):
    def _make(headers=None, **overrides):
        headers = headers or auth_headers()
        payload = {**VALID_CASE, **overrides}
        res = client.post("/api/v1/cases", json=payload, headers=headers)
        assert res.status_code == 201, res.text
        return res.json(), headers
    return _make


@pytest.fixture
def defended_case(client, make_case):
    """A case that has reached `ready`."""
    def _make(headers=None, **overrides):
        case, headers = make_case(headers, **overrides)
        res = client.post(
            f"/api/v1/invites/{case['invite_token']}/defense",
            json={"nickname": "Sam", "body": "Nobody claimed it, so I assumed it was abandoned."},
        )
        assert res.status_code == 201, res.text
        return case, headers
    return _make
