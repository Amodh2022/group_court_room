"""The game engine: who earned what, and when.

Called from the services that already own the real events — a case being filed,
a juror voting, the judge ruling — never the other way round. Every entry point
is written so that a failure here costs a payout and nothing else: the court
must keep working if the game breaks, so callers run these inside their own
`try` after their own commit.

Nothing is ever invented. A number on a screen came from a row written here at
the moment it was earned, and a player who has done nothing has zeros.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.base import utcnow
from app.models import Case, CaseMember, JuryVote, User
from app.models.game import (
    XP_PER_LEVEL,
    DailyQuest,
    GameEvent,
    PlayerBadge,
    PlayerProfile,
)
from app.services import errors
from app.services import game_rules as rules

logger = logging.getLogger(__name__)

# Verdict kinds that convict each side, mirroring offender_service.
_DEFENDANT_GUILTY = {"guilty", "both_guilty"}
_PLAINTIFF_GUILTY = {"not_guilty", "both_guilty"}
_MISTRIAL = "insufficient_evidence"


# --- the profile ----------------------------------------------------------


def profile_for(db: Session, user: User) -> PlayerProfile:
    """This player's profile, opening one the first time they are seen."""
    profile = db.get(PlayerProfile, user.id)
    if profile is not None:
        return profile

    profile = PlayerProfile(user_id=user.id)
    db.add(profile)
    try:
        db.flush()
    except IntegrityError:
        # Two requests arrived together on a brand-new account.
        db.rollback()
        profile = db.get(PlayerProfile, user.id)
        if profile is None:  # pragma: no cover - the row must exist by now
            raise
    return profile


def touch_day(db: Session, user: User, *, today: date | None = None) -> PlayerProfile:
    """Record that the player showed up, and seed the day's quests.

    Called from the one endpoint the app reads on every launch. Idempotent
    within a day, so opening the app twice is not a two-day streak.
    """
    today = today or utcnow().date()
    profile = profile_for(db, user)

    if profile.last_active_on != today:
        yesterday = today - timedelta(days=1)
        # A missed day resets to 1 — today still counts, it just starts over.
        profile.streak_days = (
            profile.streak_days + 1 if profile.last_active_on == yesterday else 1
        )
        profile.longest_streak_days = max(
            profile.longest_streak_days, profile.streak_days
        )
        profile.last_active_on = today

    _seed_quests(db, user, today)
    db.commit()

    # Showing up is itself a quest, and it is already true by now.
    advance_quest(db, user, "show_up", day=today)
    if profile.streak_days >= 7:
        award_badge(db, user, "week_streak")
    return profile


# --- experience and coins -------------------------------------------------


def _grant(
    db: Session,
    user: User,
    *,
    kind: str,
    detail: str = "",
    xp: int = 0,
    coins: int = 0,
    case: Case | None = None,
    badge_code: str | None = None,
) -> GameEvent:
    """Move the totals and write the row that explains the move."""
    profile = profile_for(db, user)
    before = profile.level
    profile.xp = max(0, profile.xp + xp)
    profile.coins = max(0, profile.coins + coins)
    after = profile.level

    event = GameEvent(
        id=uuid.uuid4(),
        user_id=user.id,
        case_id=case.id if case is not None else None,
        kind=kind,
        detail=detail[:120],
        xp=xp,
        coins=coins,
        badge_code=badge_code,
        level_reached=after if after > before else None,
    )
    db.add(event)
    return event


def spend_coins(db: Session, user: User, amount: int, *, reason: str) -> None:
    """Charge the player, or refuse the action outright.

    Refusing is the point: a cost that silently goes negative is not a cost.
    """
    profile = profile_for(db, user)
    if profile.coins < amount:
        raise errors.conflict(
            f"You need {amount} coins to {reason}, and you have {profile.coins}. "
            "Vote on a case or win one to earn more."
        )
    _grant(db, user, kind="spend", detail=reason, coins=-amount)


# --- badges ---------------------------------------------------------------


def award_badge(db: Session, user: User, code: str) -> bool:
    """Award a badge once. Returns whether this call was the one that did it."""
    if code not in rules.BADGES_BY_CODE:
        return False

    existing = db.execute(
        select(PlayerBadge.id).where(
            PlayerBadge.user_id == user.id, PlayerBadge.code == code
        )
    ).scalar_one_or_none()
    if existing is not None:
        return False

    spec = rules.BADGES_BY_CODE[code]
    db.add(PlayerBadge(id=uuid.uuid4(), user_id=user.id, code=code))
    _grant(
        db,
        user,
        kind="badge",
        detail=spec.name,
        coins=rules.BADGE_COINS,
        badge_code=code,
    )
    try:
        db.commit()
    except IntegrityError:
        # Two events awarded the same badge at once; the other won.
        db.rollback()
        return False
    return True


def badges_for(db: Session, user: User) -> list[PlayerBadge]:
    return list(
        db.execute(
            select(PlayerBadge)
            .where(PlayerBadge.user_id == user.id)
            .order_by(PlayerBadge.awarded_at.asc())
        ).scalars()
    )


# --- daily quests ---------------------------------------------------------


def _seed_quests(db: Session, user: User, day: date) -> None:
    """Open today's quest slots, if they are not open already."""
    have = set(
        db.execute(
            select(DailyQuest.code).where(
                DailyQuest.user_id == user.id, DailyQuest.quest_date == day
            )
        ).scalars()
    )
    for spec in rules.DAILY_QUESTS:
        if spec.code in have:
            continue
        db.add(
            DailyQuest(
                id=uuid.uuid4(),
                user_id=user.id,
                quest_date=day,
                code=spec.code,
                target=spec.target,
                xp=spec.xp,
            )
        )


def quests_for(db: Session, user: User, *, day: date | None = None) -> list[DailyQuest]:
    """Today's quests, in the order the rulebook lists them."""
    day = day or utcnow().date()
    rows = {
        q.code: q
        for q in db.execute(
            select(DailyQuest).where(
                DailyQuest.user_id == user.id, DailyQuest.quest_date == day
            )
        ).scalars()
    }
    return [rows[s.code] for s in rules.DAILY_QUESTS if s.code in rows]


def advance_quest(
    db: Session, user: User, code: str, *, by: int = 1, day: date | None = None
) -> None:
    """Move a quest forward, paying it out the moment it completes.

    A quest that was never seeded is not advanced: you cannot complete a quest
    that was not offered to you today.
    """
    day = day or utcnow().date()
    quest = db.execute(
        select(DailyQuest).where(
            DailyQuest.user_id == user.id,
            DailyQuest.quest_date == day,
            DailyQuest.code == code,
        )
    ).scalar_one_or_none()
    if quest is None or quest.completed_at is not None:
        return

    quest.progress = min(quest.target, quest.progress + by)
    if quest.progress >= quest.target:
        quest.completed_at = utcnow()
        spec = rules.QUESTS_BY_CODE.get(code)
        _grant(
            db,
            user,
            kind="quest",
            detail=spec.text if spec else code,
            xp=quest.xp,
        )
    db.commit()


# --- the events a case produces -------------------------------------------


def after_case_filed(db: Session, user: User, case: Case) -> None:
    """The part that runs after the case exists, where a failure is harmless."""
    advance_quest(db, user, "file_case")
    award_badge(db, user, "first_blood")

    filed = db.execute(
        select(func.count(Case.id)).where(
            Case.creator_id == user.id, Case.deleted_at.is_(None)
        )
    ).scalar_one()
    if filed >= 10:
        award_badge(db, user, "serial_filer")


def on_jury_vote(db: Session, case: Case, *, user: User | None) -> None:
    """A signed-in juror voted. Anonymous jurors play, they just do not score."""
    if user is None:
        return
    advance_quest(db, user, "vote_jury")

    cast = db.execute(
        select(func.count(JuryVote.id)).where(JuryVote.juror_user_id == user.id)
    ).scalar_one()
    if cast >= 10:
        award_badge(db, user, "jury_duty")


def settle_case(db: Session, case: Case, verdict_kind: str) -> None:
    """Pay out everything one ruling owes: both sides, then the jury.

    Runs once. `case.game_settled_at` is the guard, so a retried verdict job
    cannot pay twice.
    """
    if case.game_settled_at is not None:
        return
    case.game_settled_at = utcnow()
    db.commit()

    multiplier = rules.petty_multiplier(case.petty_level)
    mistrial = verdict_kind == _MISTRIAL

    creator = db.get(User, case.creator_id)
    if creator is not None:
        # The creator is the plaintiff; they lose when the judge finds for the
        # defence, which in this court means finding the plaintiff guilty.
        plaintiff_convicted = verdict_kind in _PLAINTIFF_GUILTY
        if mistrial:
            _grant(
                db,
                creator,
                kind="case_mistrial",
                detail="The court could not decide",
                xp=rules.CASE_MISTRIAL_XP,
                case=case,
            )
        elif plaintiff_convicted:
            _grant(
                db,
                creator,
                kind="case_lost",
                detail="The court found against you",
                xp=rules.CASE_LOSS_XP * multiplier,
                case=case,
            )
        else:
            _grant(
                db,
                creator,
                kind="case_won",
                detail="You won your case",
                xp=rules.CASE_WIN_XP * multiplier,
                case=case,
            )
        db.commit()
        if not mistrial and not plaintiff_convicted:
            award_badge(db, creator, "first_win")
            _check_clean_sweep(db, creator)

    _settle_defence(db, case, verdict_kind, multiplier=multiplier, mistrial=mistrial)
    _settle_jury(db, case, verdict_kind)


def _settle_defence(
    db: Session, case: Case, verdict_kind: str, *, multiplier: int, mistrial: bool
) -> None:
    """Pay the accused, when the accused is somebody with an account.

    Most defendants are a nickname and nothing more — they hold a link, not a
    profile, and there is nobody to pay. One who was seated on the case is a
    real player and answered a real charge.
    """
    seat = db.execute(
        select(CaseMember).where(
            CaseMember.case_id == case.id, CaseMember.role == "accused"
        )
    ).scalar_one_or_none()
    if seat is None:
        return
    accused = db.get(User, seat.user_id)
    if accused is None:
        return

    convicted = verdict_kind in _DEFENDANT_GUILTY
    if mistrial:
        _grant(
            db,
            accused,
            kind="case_mistrial",
            detail="The court could not decide",
            xp=rules.CASE_MISTRIAL_XP,
            case=case,
        )
    elif convicted:
        _grant(
            db,
            accused,
            kind="case_lost",
            detail="The court found against you",
            xp=rules.CASE_LOSS_XP * multiplier,
            case=case,
        )
    else:
        _grant(
            db,
            accused,
            kind="case_won",
            detail="You won your defence",
            xp=rules.CASE_WIN_XP * multiplier,
            case=case,
        )
    db.commit()
    if not mistrial and not convicted:
        award_badge(db, accused, "defender")
        _check_clean_sweep(db, accused)


def _check_clean_sweep(db: Session, user: User) -> None:
    """Three wins in a row, newest first, with no loss between them."""
    recent = db.execute(
        select(GameEvent.kind)
        .where(
            GameEvent.user_id == user.id,
            GameEvent.kind.in_(["case_won", "case_lost"]),
        )
        .order_by(GameEvent.created_at.desc())
        .limit(3)
    ).scalars().all()
    if len(recent) == 3 and all(k == "case_won" for k in recent):
        award_badge(db, user, "clean_sweep")


def _settle_jury(db: Session, case: Case, verdict_kind: str) -> None:
    """Pay the jurors who called it like the judge.

    A mistrial pays nobody: there was no call to match. The first ballot cast
    doubles, which is why the tally stays sealed until the ruling.
    """
    if verdict_kind == _MISTRIAL:
        return

    judge_said = "guilty" if verdict_kind in _DEFENDANT_GUILTY else "not_guilty"
    ballots = list(
        db.execute(
            select(JuryVote)
            .where(JuryVote.case_id == case.id, JuryVote.juror_user_id.is_not(None))
            .order_by(JuryVote.created_at.asc(), JuryVote.id.asc())
        ).scalars()
    )
    # Who was first is decided over every ballot, signed in or not: being
    # second to an anonymous juror is still being second.
    first_id = db.execute(
        select(JuryVote.id)
        .where(JuryVote.case_id == case.id)
        .order_by(JuryVote.created_at.asc(), JuryVote.id.asc())
        .limit(1)
    ).scalar_one_or_none()

    for ballot in ballots:
        if ballot.vote != judge_said:
            continue
        juror = db.get(User, ballot.juror_user_id)
        if juror is None:
            continue
        first = ballot.id == first_id
        xp = rules.JURY_CORRECT_XP * (
            rules.JURY_FIRST_VOTE_MULTIPLIER if first else 1
        )
        _grant(
            db,
            juror,
            kind="jury_first" if first else "jury_correct",
            detail=(
                "First juror to vote · 2×" if first else "You called it like the judge"
            ),
            xp=xp,
            coins=rules.JURY_CORRECT_COINS,
            case=case,
        )
        db.commit()
        _check_juror_badges(db, juror, was_first=first)


def _check_juror_badges(db: Session, user: User, *, was_first: bool) -> None:
    correct = db.execute(
        select(func.count(GameEvent.id)).where(
            GameEvent.user_id == user.id,
            GameEvent.kind.in_(["jury_correct", "jury_first"]),
        )
    ).scalar_one()
    if correct >= 5:
        award_badge(db, user, "oracle")
    if was_first:
        firsts = db.execute(
            select(func.count(GameEvent.id)).where(
                GameEvent.user_id == user.id, GameEvent.kind == "jury_first"
            )
        ).scalar_one()
        if firsts >= 5:
            award_badge(db, user, "quick_draw")


def note_hung_jury(db: Session, case: Case) -> None:
    creator = db.get(User, case.creator_id)
    if creator is not None:
        award_badge(db, creator, "hung_jury")


def note_overruled(db: Session, case: Case) -> None:
    creator = db.get(User, case.creator_id)
    if creator is not None:
        award_badge(db, creator, "overruled")


# --- reading it back ------------------------------------------------------


def events_for_case(db: Session, user: User, case_id: uuid.UUID) -> list[GameEvent]:
    """What this one case earned this one player, for the rewards card."""
    return list(
        db.execute(
            select(GameEvent)
            .where(GameEvent.user_id == user.id, GameEvent.case_id == case_id)
            .order_by(GameEvent.created_at.asc())
        ).scalars()
    )


def level_progress(profile: PlayerProfile) -> tuple[int, int, int]:
    """`(level, xp into this level, XP per level)` — what the card draws."""
    return profile.level, profile.xp_into_level, XP_PER_LEVEL
