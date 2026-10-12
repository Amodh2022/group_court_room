from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import Court
from app.schemas.social import CourtCreate, CourtJoin, CourtOut, MemberAdd, UserBrief
from app.security.auth import CurrentUser
from app.services import social_service

router = APIRouter(prefix="/courts", tags=["courts"])

DbDep = Annotated[Session, Depends(get_db)]


def _out(db: Session, court: Court) -> CourtOut:
    members = []
    for m in court.members:
        social_service.ensure_handle(db, m.user)
        members.append(UserBrief(
            user_id=m.user_id, handle=m.user.handle or "", display_name=m.user.display_name
        ))
    return CourtOut(
        id=court.id, name=court.name, invite_code=court.invite_code,
        owner_id=court.owner_id, members=members,
    )


@router.post("", response_model=CourtOut, status_code=status.HTTP_201_CREATED)
def create(payload: CourtCreate, user: CurrentUser, db: DbDep) -> CourtOut:
    return _out(db, social_service.create_court(db, user, payload.name))


@router.get("", response_model=list[CourtOut])
def mine(user: CurrentUser, db: DbDep) -> list[CourtOut]:
    return [_out(db, c) for c in social_service.list_courts(db, user)]


@router.post("/join", response_model=CourtOut)
def join(payload: CourtJoin, user: CurrentUser, db: DbDep) -> CourtOut:
    return _out(db, social_service.join_court(db, user, payload.invite_code))


@router.get("/{court_id}", response_model=CourtOut)
def get_one(court_id: uuid.UUID, user: CurrentUser, db: DbDep) -> CourtOut:
    return _out(db, social_service.get_court_for_member(db, court_id, user))


@router.post("/{court_id}/members", response_model=CourtOut)
def add_member(court_id: uuid.UUID, payload: MemberAdd, user: CurrentUser, db: DbDep) -> CourtOut:
    court = social_service.get_court_for_member(db, court_id, user)
    return _out(db, social_service.add_court_member(db, court, user, payload.user_id))


@router.delete("/{court_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(court_id: uuid.UUID, user_id: uuid.UUID, user: CurrentUser, db: DbDep) -> Response:
    court = social_service.get_court_for_member(db, court_id, user)
    social_service.remove_court_member(db, court, user, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
