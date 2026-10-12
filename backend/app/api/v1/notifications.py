from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.social import NotificationList, NotificationOut
from app.security.auth import CurrentUser
from app.services import social_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=NotificationList)
def list_notifications(
    user: CurrentUser, db: Annotated[Session, Depends(get_db)]
) -> NotificationList:
    unread, rows = social_service.notifications_for(db, user)
    return NotificationList(
        unread=unread,
        items=[
            NotificationOut(
                id=n.id, kind=n.kind, text=n.text, created_at=n.created_at, read=n.read,
                case_id=n.case_id, court_id=n.court_id, **link,
            )
            for n, link in rows
        ],
    )


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
def read_all(user: CurrentUser, db: Annotated[Session, Depends(get_db)]) -> Response:
    social_service.mark_all_read(db, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
