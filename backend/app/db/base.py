"""Declarative base plus column types that work on PostgreSQL and SQLite.

Production runs on PostgreSQL (JSONB). The test suite runs on SQLite so the
suite needs no infrastructure; `with_variant` keeps one model definition.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import JSON, DateTime, Uuid, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, mapped_column

JSONColumn = JSONB().with_variant(JSON(), "sqlite")
UUIDColumn = Uuid(as_uuid=True)
TimestampTZ = DateTime(timezone=True)


class Base(DeclarativeBase):
    pass


def uuid_pk():
    return mapped_column(UUIDColumn, primary_key=True, default=uuid.uuid4)


def created_at_column():
    return mapped_column(TimestampTZ, nullable=False, server_default=func.now(),
                         default=lambda: datetime.now(UTC))


def utcnow() -> datetime:
    return datetime.now(UTC)


def as_aware(value: datetime | None) -> datetime | None:
    """SQLite round-trips datetimes without tzinfo; normalise to UTC-aware."""
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value
