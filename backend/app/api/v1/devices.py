from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.device import DeviceToken
from app.security.auth import CurrentUser
from app.services import push_service

router = APIRouter(prefix="/devices", tags=["devices"])


class DeviceIn(BaseModel):
    token: Annotated[str, Field(min_length=8, max_length=512)]
    platform: Annotated[str, Field(pattern="^(android|ios|web)$")] = "android"


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
def register(
    payload: DeviceIn, user: CurrentUser, db: Annotated[Session, Depends(get_db)]
) -> Response:
    push_service.register_device(db, user.id, payload.token, payload.platform)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{token}", status_code=status.HTTP_204_NO_CONTENT)
def unregister(
    token: str, user: CurrentUser, db: Annotated[Session, Depends(get_db)]
) -> Response:
    db.execute(
        delete(DeviceToken).where(DeviceToken.token == token, DeviceToken.user_id == user.id)
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
