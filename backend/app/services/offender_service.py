"""Criminal records: the memory that makes case #5 funnier than case #1.

A record belongs to one court (the creator's) and one nickname. It is updated
exactly once per case, when the verdict is stored, and it is read back into the
judge's prompt as priors.
"""

from __future__ import annotations

import logging
import re
import unicodedata
import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.base import utcnow
from app.models import Case, Offender, User

logger = logging.getLogger(__name__)

_SLUG_STRIP = re.compile(r"[^a-z0-9]+")

# Convictions that land on the defendant, and on the plaintiff respectively.
_DEFENDANT_GUILTY = {"guilty", "both_guilty"}
_PLAINTIFF_GUILTY = {"not_guilty", "both_guilty"}


def slugify(name: str) -> str:
    """Fold a nickname to its record key. Empty input has no record."""
    folded = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return _SLUG_STRIP.sub("-", folded.lower()).strip("-")[:60]


def get_or_create(db: Session, *, owner: User, display_name: str | None) -> Offender | None:
    """Find this court's record for a nickname, opening one if it is new."""
    if not display_name or not (slug := slugify(display_name)):
        return None

    existing = db.execute(
        select(Offender).where(Offender.owner_id == owner.id, Offender.slug == slug)
    ).scalar_one_or_none()
    if existing is not None:
        # Keep the most recent spelling: people recapitalise, records persist.
        existing.display_name = display_name[:40]
        return existing

    offender = Offender(
        id=uuid.uuid4(), owner_id=owner.id, slug=slug, display_name=display_name[:40]
    )
    db.add(offender)
    try:
        db.flush()
    except IntegrityError:
        # Two cases filed against the same person at once; the other won.
        db.rollback()
        return db.execute(
            select(Offender).where(Offender.owner_id == owner.id, Offender.slug == slug)
        ).scalar_one_or_none()
    return offender


def _apply(offender: Offender, *, convicted: bool, mistrial: bool) -> None:
    offender.cases_total += 1
    offender.last_verdict_at = utcnow()
    if mistrial:
        offender.mistrials += 1
        return
    if convicted:
        offender.convictions += 1
        offender.current_streak += 1
        offender.longest_streak = max(offender.longest_streak, offender.current_streak)
    else:
        offender.acquittals += 1
        offender.current_streak = 0


def record_verdict(db: Session, case: Case, verdict_kind: str) -> None:
    """Write this case into both parties' records. Called once, after storing.

    `both_guilty` convicts both sides; `insufficient_evidence` is a mistrial
    and marks neither, but still counts as an appearance before this court.
    """
    mistrial = verdict_kind == "insufficient_evidence"
    pairs = (
        (case.defendant_offender_id, verdict_kind in _DEFENDANT_GUILTY),
        (case.plaintiff_offender_id, verdict_kind in _PLAINTIFF_GUILTY),
    )
    for offender_id, convicted in pairs:
        if offender_id is None:
            continue
        offender = db.get(Offender, offender_id)
        if offender is not None:
            _apply(offender, convicted=convicted, mistrial=mistrial)

    db.commit()
    logger.info(
        "record.updated", extra={"case_id": str(case.id), "verdict": verdict_kind}
    )


def priors_line(offender: Offender | None) -> str:
    """One sentence of record, written for the judge to read aloud."""
    if offender is None or offender.cases_total == 0:
        return "First appearance before this court. No prior record."

    parts = [
        f"{offender.cases_total} prior appearance{'s' if offender.cases_total != 1 else ''}",
        f"{offender.convictions} conviction{'s' if offender.convictions != 1 else ''}",
        f"{offender.acquittals} acquittal{'s' if offender.acquittals != 1 else ''}",
    ]
    if offender.mistrials:
        parts.append(f"{offender.mistrials} mistrial{'s' if offender.mistrials != 1 else ''}")
    line = ", ".join(parts) + "."
    if offender.current_streak >= 2:
        line += f" Currently on a {offender.current_streak}-case guilty streak."
    if offender.is_repeat_offender:
        line += " The court considers this a repeat offender."
    return line


def leaderboard(db: Session, user: User, limit: int = 50) -> list[Offender]:
    """This court's standings. Most convicted first, then most tried."""
    return list(
        db.execute(
            select(Offender)
            .where(Offender.owner_id == user.id, Offender.cases_total > 0)
            .order_by(
                Offender.convictions.desc(),
                Offender.cases_total.desc(),
                Offender.display_name.asc(),
            )
            .limit(min(limit, 100))
        ).scalars()
    )
