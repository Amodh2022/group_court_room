from __future__ import annotations

from typing import Annotated

from fastapi import Depends

from app.llm.base import LLMProvider
from app.llm.factory import get_llm_provider
from app.services.verdict_service import VerdictService


def get_verdict_service(
    provider: Annotated[LLMProvider, Depends(get_llm_provider)],
) -> VerdictService:
    return VerdictService(provider)


VerdictServiceDep = Annotated[VerdictService, Depends(get_verdict_service)]
