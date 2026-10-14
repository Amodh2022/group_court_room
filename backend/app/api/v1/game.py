"""The player's own game state.

`GET /me/game` is the call the app makes on launch, so it is also where the
daily streak is recorded and the day's quests are opened. That is deliberate:
"you showed up" is only true because you asked.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Path
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import Case
from app.models.game import XP_PER_LEVEL
from app.schemas.game import (
    BadgeOut,
    CaseRewards,
    GameState,
    PlayerOut,
    QuestOut,
    RewardOut,
)
from app.security.auth import CurrentUser
from app.services import errors, game_rules, game_service

router = APIRouter(prefix="/me", tags=["game"])

DbDep = Annotated[Session, Depends(get_db)]


@router.get("/game", response_model=GameState)
def game_state(user: CurrentUser, db: DbDep) -> GameState:
    profile = game_service.touch_day(db, user)
    earned = {b.code: b.awarded_at for b in game_service.badges_for(db, user)}
    quests = game_service.quests_for(db, user)

    return GameState(
        player=PlayerOut(
            display_name=user.display_name,
            level=profile.level,
            xp=profile.xp,
            xp_into_level=profile.xp_into_level,
            xp_per_level=XP_PER_LEVEL,
            xp_to_next_level=profile.xp_to_next_level,
            coins=profile.coins,
            streak_days=profile.streak_days,
            longest_streak_days=profile.longest_streak_days,
            badges_earned=len(earned),
            badges_total=game_rules.BADGE_TOTAL,
        ),
        quests=[
            QuestOut(
                code=q.code,
                text=(
                    game_rules.QUESTS_BY_CODE[q.code].text
                    if q.code in game_rules.QUESTS_BY_CODE
                    else q.code
                ),
                progress=q.progress,
                target=q.target,
                xp=q.xp,
                done=q.done,
            )
            for q in quests
        ],
        badges=[
            BadgeOut(
                code=spec.code,
                name=spec.name,
                glyph=spec.glyph,
                hint=spec.hint,
                earned=spec.code in earned,
                earned_at=earned.get(spec.code),
            )
            for spec in game_rules.BADGES
        ],
    )


@router.get("/rewards/{case_id}", response_model=CaseRewards)
def case_rewards(
    user: CurrentUser,
    db: DbDep,
    case_id: Annotated[uuid.UUID, Path()],
) -> CaseRewards:
    """What this case earned you. The verdict screen's rewards card.

    Readable only by a player the case actually paid, which is the same thing
    as having rows: somebody else's case simply has none of yours in it.
    """
    case = db.get(Case, case_id)
    if case is None or case.deleted_at is not None:
        raise errors.not_found("No such case.")

    events = game_service.events_for_case(db, user, case_id)
    level = next((e.level_reached for e in reversed(events) if e.level_reached), None)
    return CaseRewards(
        case_id=str(case_id),
        total_xp=sum(e.xp for e in events),
        total_coins=sum(e.coins for e in events),
        level_reached=level,
        items=[
            RewardOut(
                kind=e.kind,
                detail=e.detail,
                xp=e.xp,
                coins=e.coins,
                badge_code=e.badge_code,
                badge_name=(
                    game_rules.BADGES_BY_CODE[e.badge_code].name
                    if e.badge_code in game_rules.BADGES_BY_CODE
                    else None
                ),
                level_reached=e.level_reached,
            )
            for e in events
        ],
    )
