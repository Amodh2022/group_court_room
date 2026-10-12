from __future__ import annotations

from pydantic import BaseModel, Field


class ErrorResponse(BaseModel):
    error: str = Field(examples=["not_found"])
    message: str = Field(examples=["Case not found."])


class OkResponse(BaseModel):
    ok: bool = True
