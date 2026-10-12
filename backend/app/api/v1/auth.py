from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import get_db
from app.models import User
from app.schemas.case import DevLoginRequest, LoginRequest, RegisterRequest, TokenResponse
from app.security.auth import CurrentUser, issue_dev_token
from app.security.passwords import hash_password, verify_password
from app.services import errors, social_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/dev-login", response_model=TokenResponse)
def dev_login(payload: DevLoginRequest, db: Annotated[Session, Depends(get_db)]) -> TokenResponse:
    """Development sign-in.

    Disabled outside local/test. In production set AUTH_PROVIDER=jwks and point
    JWKS_URL at the managed identity provider; this endpoint 404s there.
    """
    settings = get_settings()
    if settings.auth_provider != "dev" or settings.environment in {"staging", "production"}:
        raise errors.not_found("Endpoint")

    user = db.query(User).filter(User.auth_subject == payload.auth_subject).one_or_none()
    if user is None:
        user = User(
            id=uuid.uuid4(),
            auth_subject=payload.auth_subject,
            display_name=payload.display_name or "Anonymous Plaintiff",
        )
        db.add(user)
    elif payload.display_name:
        user.display_name = payload.display_name
    db.commit()
    db.refresh(user)

    return _token_for(user, db)


def _token_for(user: User, db: Session) -> TokenResponse:
    social_service.ensure_handle(db, user)
    token, expires_in = issue_dev_token(user.auth_subject)
    return TokenResponse(
        access_token=token,
        expires_in=expires_in,
        user_id=user.id,
        display_name=user.display_name,
        email=user.email,
        handle=user.handle,
    )


def _require_local_tokens() -> None:
    if get_settings().auth_provider != "dev":
        raise errors.not_found("Endpoint")


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(payload: RegisterRequest, db: Annotated[Session, Depends(get_db)]) -> TokenResponse:
    _require_local_tokens()
    email = payload.email.strip().lower()
    if db.query(User).filter(User.email == email).first() is not None:
        raise errors.conflict("An account with that email already exists.")
    uid = uuid.uuid4()
    user = User(
        id=uid,
        auth_subject=f"user|{uid}",
        email=email,
        password_hash=hash_password(payload.password),
        display_name=payload.display_name or email.split("@")[0][:40],
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _token_for(user, db)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Annotated[Session, Depends(get_db)]) -> TokenResponse:
    _require_local_tokens()
    user = db.query(User).filter(User.email == payload.email.strip().lower()).one_or_none()
    if not verify_password(payload.password, user.password_hash if user else None) or user is None:
        raise errors.unauthorized("Incorrect email or password.")
    return _token_for(user, db)


@router.get("/me", response_model=TokenResponse, response_model_exclude={"access_token"})
def me(user: CurrentUser, db: Annotated[Session, Depends(get_db)]) -> TokenResponse:
    social_service.ensure_handle(db, user)
    return TokenResponse(
        access_token="",
        expires_in=0,
        user_id=user.id,
        display_name=user.display_name,
        email=user.email,
        handle=user.handle,
    )
