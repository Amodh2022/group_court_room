"""Authentication for creator-owned endpoints.

`AUTH_PROVIDER=dev` issues and verifies our own HS256 JWTs — enough to build and
test the full product without a managed IdP account. `AUTH_PROVIDER=jwks`
verifies RS256 tokens from an external issuer instead; the rest of the app only
ever sees a resolved `User`, so swapping providers touches this file alone.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated

import httpx
from fastapi import Depends, Header, HTTPException, status
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import get_db
from app.models import User

_INVALID = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail={"error": "unauthorized", "message": "Missing or invalid credentials."},
    headers={"WWW-Authenticate": "Bearer"},
)

_jwks_cache: dict[str, object] = {}


def issue_dev_token(auth_subject: str) -> tuple[str, int]:
    settings = get_settings()
    expires_in = settings.jwt_ttl_seconds
    now = datetime.now(UTC)
    claims = {
        "sub": auth_subject,
        "iss": settings.jwt_issuer,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=expires_in)).timestamp()),
    }
    return jwt.encode(claims, settings.jwt_secret, algorithm=settings.jwt_algorithm), expires_in


def _decode(token: str) -> dict:
    settings = get_settings()
    if settings.auth_provider == "dev":
        return jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
        )
    if not settings.jwks_url:
        raise RuntimeError("AUTH_PROVIDER=jwks requires JWKS_URL")
    if "keys" not in _jwks_cache:
        _jwks_cache["keys"] = httpx.get(settings.jwks_url, timeout=5.0).json()
    return jwt.decode(
        token,
        _jwks_cache["keys"],
        algorithms=["RS256"],
        audience=settings.jwks_audience,
    )


def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise _INVALID
    return authorization.split(" ", 1)[1].strip()


def user_from_token(db: Session, token: str) -> User:
    """Resolve a bearer token to a user. Shared by HTTP and websocket auth."""
    try:
        claims = _decode(token)
    except JWTError:
        raise _INVALID from None

    subject = claims.get("sub")
    if not subject:
        raise _INVALID

    user = db.query(User).filter(User.auth_subject == subject).one_or_none()
    if user is None:
        # First call after sign-in provisions the local user record.
        user = User(
            id=uuid.uuid4(),
            auth_subject=subject,
            display_name=claims.get("name") or "Anonymous Plaintiff",
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


def get_current_user(
    db: Annotated[Session, Depends(get_db)],
    authorization: Annotated[str | None, Header()] = None,
) -> User:
    return user_from_token(db, _bearer(authorization))


CurrentUser = Annotated[User, Depends(get_current_user)]
