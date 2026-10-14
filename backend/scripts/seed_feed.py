"""Fill one account's feed with cases at every stage of their life.

Everything here goes in through the ordinary services — filing charges the
coins, a defence moves the case to `ready`, jurors are seated one ballot each,
and the verdicts are written by the real judge, not by this file. So the feed
you end up looking at is the feed the app actually produces; only the stories
are made up, the way a friend group's would be.

    python -m scripts.seed_feed --email you@example.com
    python -m scripts.seed_feed --email you@example.com --no-rule   # skip the judge
    python -m scripts.seed_feed --email you@example.com --clear

Ruling takes a while: each verdict is a real generation against the configured
provider, one case at a time.
"""

from __future__ import annotations

import argparse
import sys
import uuid
from dataclasses import dataclass, field

from sqlalchemy import select

from app.db.session import SessionLocal
from app.llm.factory import get_llm_provider
from app.models import Case, CaseMember, User
from app.models.enums import ParticipantRole
from app.services import (
    case_service,
    game_service,
    jury_service,
    safety,
    social_service,
)
from app.services.verdict_service import VerdictService


@dataclass(frozen=True)
class Scenario:
    title: str
    category: str
    defendant: str
    accusation: str
    # None leaves the case awaiting a defence, which is a state the feed draws.
    defence: str | None = None
    ballots: list[tuple[str, str]] = field(default_factory=list)
    # Whether the judge is asked to rule. False leaves it on the docket.
    judge: bool = False

SCENARIOS: list[Scenario] = [
    Scenario(
        title="The Last Pizza Slice",
        category="food",
        defendant="Dev",
        accusation=(
            "Dev ate the last slice after announcing, out loud, that he was "
            "full. Three witnesses. One slice. No remorse."
        ),
        defence=(
            "Nobody claimed it for eleven minutes. At that point it is "
            "abandoned property and I was performing a public service."
        ),
        ballots=[("Maya", "guilty"), ("Priya", "guilty"),
                 ("Arjun", "not_guilty"), ("Sam", "guilty")],
        judge=True,
    ),
    Scenario(
        title="Left On Read For Four Days",
        category="friendship",
        defendant="Maya",
        accusation=(
            "Maya opened my message about the trip, posted twice that evening, "
            "and replied on Thursday with a thumbs up."
        ),
        defence=(
            "I read it in a lift, lost signal, and my brain filed it under "
            "done. The thumbs up was sincere."
        ),
        ballots=[("Dev", "guilty"), ("Priya", "not_guilty"), ("Arjun", "guilty")],
        judge=True,
    ),
    Scenario(
        title="The Great Aux Cord Hijack",
        category="petty",
        defendant="Arjun",
        accusation=(
            "Arjun took the aux at the start of a two hour drive and played "
            "eleven minutes of a podcast about shipping containers."
        ),
        defence=(
            "It was a fascinating podcast and nobody said a single word "
            "against it until we arrived."
        ),
        ballots=[("Maya", "not_guilty"), ("Dev", "guilty")],
        judge=True,
    ),
    Scenario(
        title="Who Owes Whom For The Cab",
        category="money",
        defendant="Priya",
        accusation=(
            "Priya split the cab four ways in the app and then paid in cash so "
            "the app never settled. That was in March."
        ),
        defence=(
            "I handed the cash to Dev at the door. He was meant to pass it "
            "on. Take it up with him."
        ),
        ballots=[("Sam", "guilty"), ("Maya", "guilty"), ("Arjun", "guilty")],
        judge=True,
    ),
    # Nobody has answered this one: the feed draws it as waiting on Sam.
    Scenario(
        title="The Unwashed Pan Standoff",
        category="roommates",
        defendant="Sam",
        accusation=(
            "The pan has been soaking since Sunday. It is Thursday. The water "
            "has developed opinions."
        ),
    ),
    # Answered, no verdict: the case that is ready for the judge.
    Scenario(
        title="Booked Over My Birthday Dinner",
        category="friendship",
        defendant="Rhea",
        accusation=(
            "I said I was booking that place for my birthday. Rhea booked it "
            "for hers. Two weeks earlier. Same table."
        ),
        defence="I booked first and said so in the group. Scroll up.",
    ),
]

# Filed by a friend against the account, so the feed's "summoned" row and the
# boss card have something real behind them.
AGAINST_ME: list[tuple[Scenario, str]] = [
    (
        Scenario(
            title="You Said Five Minutes An Hour Ago",
            category="friendship",
            defendant="",  # filled in with the target's own name
            accusation=(
                "Said five minutes. Arrived an hour later. Then said traffic, "
                "which there was not, because I drove the same road."
            ),
        ),
        "accused",
    ),
    (
        Scenario(
            title="The Group Trip Spreadsheet Scandal",
            category="money",
            defendant="Kabir",
            accusation=(
                "Kabir built the spreadsheet, put himself down for the cheap "
                "room, and locked the sheet before anyone else read it."
            ),
            defence="I built the entire thing. There is a finder's fee.",
        ),
        "juror",
    ),
]

PARTNER = ("seed|courtroom-partner", "Priya", "priya.seed@sueme.test")

# The room the cases are filed in. Members get accounts so the court tile has
# faces on it and the switcher has something to switch to.
COURT_NAME = "The Group Chat"
COURT_CAST = ["Dev", "Maya", "Arjun", "Sam", "Rhea"]

STARTING_COINS_TOPUP = 200


def _clear(db, owner: User) -> int:
    titles = [s.title for s in SCENARIOS] + [s.title for s, _ in AGAINST_ME]
    cases = list(
        db.execute(
            select(Case)
            .outerjoin(CaseMember, CaseMember.case_id == Case.id)
            .where(
                (Case.creator_id == owner.id) | (CaseMember.user_id == owner.id),
                Case.title.in_(titles),
                Case.deleted_at.is_(None),
            )
            .distinct()
        ).scalars()
    )
    for case in cases:
        case_service.delete_case(db, case)
    return len(cases)


def seed_feed(db, owner: User, *, rule: bool) -> tuple[int, int]:
    # Filing costs coins, and an empty wallet would fail the seed halfway.
    profile = game_service.profile_for(db, owner)
    profile.coins += STARTING_COINS_TOPUP
    db.commit()

    verdicts = VerdictService(get_llm_provider()) if rule else None
    filed = ruled = 0

    for s in SCENARIOS:
        if db.execute(
            select(Case.id).where(
                Case.creator_id == owner.id,
                Case.title == s.title,
                Case.deleted_at.is_(None),
            )
        ).first():
            print(f"  already filed: {s.title}")
            continue

        case, invite_token, _jury_token = case_service.create_case(
            db,
            user=owner,
            title=s.title,
            category=s.category,
            accusation=s.accusation,
            defendant_nickname=s.defendant,
            petty_level=min(3, 1 + len(s.ballots) // 2),
        )
        filed += 1
        print(f"  filed: {s.title}")

        if s.defence is not None:
            case, participant = case_service.resolve_invite(db, invite_token)
            case_service.submit_defense(
                db, case=case, defendant=participant, nickname=s.defendant,
                body=s.defence,
            )

        for juror, vote in s.ballots:
            jury_service.cast_vote(
                db,
                case=case,
                voter_key=f"seed:{case.id}:{juror}",
                juror_name=juror,
                vote=vote,
            )

        if s.judge and verdicts is not None:
            print("    asking the judge to rule…", flush=True)
            verdicts.generate_for_case(db, case)
            ruled += 1

    return filed, ruled


def check_fixtures() -> None:
    """Refuse to seed material the court itself would refuse to try.

    The pre-screen holds back anything reading as a real dispute rather than a
    joke, and it is right to — but a seed that trips it fills the feed with
    refusal cards instead of verdicts. Cheap to catch here. ("Sue him." in a
    defence was enough to read as legal.)
    """
    for scenario in [*SCENARIOS, *(s for s, _ in AGAINST_ME)]:
        for label, text in (
            ("title", scenario.title),
            ("accusation", scenario.accusation),
            ("defence", scenario.defence or ""),
        ):
            screen = safety.screen_text(text)
            if screen.blocked:
                raise SystemExit(
                    f"fixture {scenario.title!r}: the {label} trips the "
                    f"pre-screen ({screen.category}). Reword it."
                )


def _cast_user(db, name: str) -> User:
    """A stand-in account for one of the regulars. Created once, reused after."""
    subject = f"seed|cast-{name.lower()}"
    user = db.execute(select(User).where(User.auth_subject == subject)).scalar_one_or_none()
    if user is None:
        user = User(id=uuid.uuid4(), auth_subject=subject, display_name=name)
        db.add(user)
        db.commit()
    return user


def seed_court(db, owner: User) -> str:
    """Put the regulars in a court with the account, so it is not a room of one."""
    court = next(
        (c for c in social_service.list_courts(db, owner) if c.name == COURT_NAME),
        None,
    )
    if court is None:
        court = social_service.create_court(db, owner, COURT_NAME)

    for name in COURT_CAST:
        member = _cast_user(db, name)
        social_service.add_court_member(db, court, owner, member.id)
    return f"{court.name} ({len(COURT_CAST) + 1} members)"


def _partner(db, exclude: User) -> User:
    """The friend on the other side. Reused across runs, created once."""
    subject, name, email = PARTNER
    user = db.execute(select(User).where(User.auth_subject == subject)).scalar_one_or_none()
    if user is None:
        user = User(id=uuid.uuid4(), auth_subject=subject, display_name=name, email=email)
        db.add(user)
        db.commit()
    if user.id == exclude.id:  # pragma: no cover - the seeder is not the friend
        raise SystemExit("the partner account cannot be the account being seeded")
    return user


def seed_summons(db, owner: User) -> int:
    """File two cases *at* the account: one to answer, one to judge."""
    partner = _partner(db, owner)
    profile = game_service.profile_for(db, partner)
    profile.coins += STARTING_COINS_TOPUP
    db.commit()

    seated = 0
    for scenario, role in AGAINST_ME:
        if db.execute(
            select(Case.id).where(
                Case.creator_id == partner.id,
                Case.title == scenario.title,
                Case.deleted_at.is_(None),
            )
        ).first():
            print(f"  already summoned: {scenario.title}")
            continue

        case, _invite, _jury = case_service.create_case(
            db,
            user=partner,
            title=scenario.title,
            category=scenario.category,
            accusation=scenario.accusation,
            defendant_nickname=scenario.defendant or owner.display_name,
        )
        social_service.seat_member(db, case, partner, owner.id, role)
        seated += 1
        print(f"  summoned as {role}: {scenario.title}")

        if scenario.defence is not None:
            defendant = case_service.participant(case, ParticipantRole.defendant)
            if defendant is not None:
                case_service.submit_defense(
                    db, case=case, defendant=defendant,
                    nickname=scenario.defendant, body=scenario.defence,
                )
    return seated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--email", action="append", default=[], required=True,
                        help="Account whose feed to fill. Repeatable.")
    parser.add_argument("--clear", action="store_true",
                        help="Delete the seeded cases instead.")
    parser.add_argument("--no-rule", action="store_true",
                        help="File and defend, but do not call the judge.")
    args = parser.parse_args()

    check_fixtures()

    with SessionLocal() as db:
        users = list(db.execute(select(User).where(User.email.in_(args.email))).scalars())
        missing = set(args.email) - {u.email for u in users}
        if missing:
            print(f"no such account: {', '.join(sorted(missing))}", file=sys.stderr)
            return 1

        for user in users:
            print(f"{user.email}:")
            if args.clear:
                print(f"  deleted {_clear(db, user)} cases")
                continue
            print(f"  court: {seed_court(db, user)}")
            filed, ruled = seed_feed(db, user, rule=not args.no_rule)
            seated = seed_summons(db, user)
            print(f"  {filed} filed, {ruled} ruled, {seated} filed against you")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
