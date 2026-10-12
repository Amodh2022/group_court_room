from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.social import UserBrief
from app.security.auth import CurrentUser
from app.services import social_service

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/search", response_model=list[UserBrief])
def search(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    q: Annotated[str, Query(max_length=60)] = "",
) -> list[UserBrief]:
    return [
        UserBrief(user_id=u.id, handle=u.handle or "", display_name=u.display_name)
        for u in social_service.search_users(db, user, q)
    ]
