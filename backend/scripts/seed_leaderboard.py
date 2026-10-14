"""Fill one court's rap sheet with a dummy cast, so the leaderboard has shape.

This writes *fabricated* records. Nothing in the app invents a number, so an
empty court is genuinely empty — which makes the standings impossible to look
at while building them. This script is the only place allowed to make records
up, it is explicit about it, and `--clear` takes every one of them back out.

    python -m scripts.seed_leaderboard --email you@example.com
    python -m scripts.seed_leaderboard --email you@example.com --clear

Omit --email and it seeds every account that has one. The owner's own name is
seeded too, so the "where you stand" band on the rap sheet has a row to point
at.
"""

from __future__ import annotations

import argparse
import sys
import uuid
from datetime import timedelta

from sqlalchemy import select

from app.db.base import utcnow
from app.db.session import SessionLocal
from app.models import Offender, User
from app.services.offender_service import slugify

# name, cases, convictions, acquittals, mistrials, current streak, longest,
# days since the last verdict. Totals add up; streaks never exceed convictions.
CAST: list[tuple[str, int, int, int, int, int, int, int]] = [
    ("Dev", 14, 11, 2, 1, 4, 5, 1),
    ("Maya", 12, 8, 3, 1, 0, 3, 2),
    ("Priya", 11, 7, 4, 0, 2, 2, 3),
    ("Arjun", 9, 5, 3, 1, 1, 2, 5),
    ("Sam", 8, 4, 4, 0, 0, 2, 6),
    ("Rhea", 7, 3, 3, 1, 3, 3, 8),
    ("Kabir", 6, 2, 4, 0, 0, 1, 11),
    ("Nikhil", 5, 1, 4, 0, 0, 1, 14),
    ("Tara", 4, 0, 4, 0, 0, 0, 19),
]

# Where the account holder lands in their own court: mid-table, with someone
# in reach. Convictions sit just under Arjun's, so the band reads "1 more".
OWNER_RECORD = (10, 4, 5, 1, 1, 3)


# Fabricated or not, a record still has to be arithmetically possible: the
# three outcomes add up to the total, and no streak outruns the convictions.
for _name, _total, _guilty, _acq, _mis, _streak, _longest, _days in [
    ("", *OWNER_RECORD, 0),
    *CAST,
]:
    assert _guilty + _acq + _mis == _total, _name
    assert _streak <= _longest <= _guilty, _name


def seed_court(db, owner: User, *, clear: bool) -> int:
    # The owner goes in first and keeps their slot: an account called "Dev"
    # must not collide with the Dev in the cast — one court, one record per
    # name.
    rows: dict[str, tuple] = {}
    for row in [(owner.display_name or "You", *OWNER_RECORD, 4), *CAST]:
        if slug := slugify(row[0]):
            rows.setdefault(slug, row)

    touched = 0
    for slug, (name, total, guilty, acquitted, mistrials, streak, longest, days) in (
        rows.items()
    ):
        offender = db.execute(
            select(Offender).where(Offender.owner_id == owner.id, Offender.slug == slug)
        ).scalar_one_or_none()

        if clear:
            if offender is not None:
                db.delete(offender)
                touched += 1
            continue

        if offender is None:
            offender = Offender(
                id=uuid.uuid4(), owner_id=owner.id, slug=slug, display_name=name[:40]
            )
            db.add(offender)
        offender.display_name = name[:40]
        offender.cases_total = total
        offender.convictions = guilty
        offender.acquittals = acquitted
        offender.mistrials = mistrials
        offender.current_streak = streak
        offender.longest_streak = longest
        offender.last_verdict_at = utcnow() - timedelta(days=days)
        touched += 1

    return touched


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--email",
        action="append",
        default=[],
        help="Account whose court to seed. Repeatable. Default: every account with an email.",
    )
    parser.add_argument(
        "--clear", action="store_true", help="Remove the seeded records instead."
    )
    args = parser.parse_args()

    with SessionLocal() as db:
        if args.email:
            users = list(
                db.execute(select(User).where(User.email.in_(args.email))).scalars()
            )
            missing = set(args.email) - {u.email for u in users}
            if missing:
                print(f"no such account: {', '.join(sorted(missing))}", file=sys.stderr)
                return 1
        else:
            users = list(
                db.execute(select(User).where(User.email.is_not(None))).scalars()
            )

        if not users:
            print("no accounts to seed", file=sys.stderr)
            return 1

        for user in users:
            count = seed_court(db, user, clear=args.clear)
            verb = "cleared" if args.clear else "seeded"
            print(f"{verb} {count:2d} records in {user.email}'s court")
        db.commit()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
