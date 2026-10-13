"""Handles, courts, direct case members and in-app notifications."""

from __future__ import annotations

import re
import secrets
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db.base import utcnow
from app.models import (
    Case,
    CaseMember,
    Court,
    CourtMember,
    Notification,
    Participant,
    ParticipantRole,
    User,
)
from app.security.tokens import generate_token
from app.services import errors, push_service

# --- handles ---------------------------------------------------------------


def _slug(base: str) -> str:
    slug = re.sub(r"[^a-z0-9_]", "", base.lower())[:14]
    return slug if len(slug) >= 3 else (slug + "user")[:14]


def ensure_handle(db: Session, user: User, seed: str | None = None) -> str:
    if user.handle:
        return user.handle
    base = _slug(seed or (user.email or "").split("@")[0] or user.display_name)
    candidate = base
    n = 1
    while db.execute(select(User.id).where(User.handle == candidate)).first() is not None:
        n += 1
        candidate = f"{base[: 20 - len(str(n))]}{n}"
    user.handle = candidate
    db.commit()
    return candidate


def search_users(db: Session, me: User, q: str) -> list[User]:
    q = q.strip().lower().lstrip("@")
    if len(q) < 2:
        return []
    rows = db.execute(
        select(User)
        .where(
            User.id != me.id,
            or_(User.handle.like(q.replace("%", "").replace("_", r"\_") + "%", escape="\\"),
                func.lower(User.email) == q),
        )
        .order_by(User.handle)
        .limit(10)
    ).scalars().all()
    for u in rows:
        ensure_handle(db, u)
    return list(rows)


# --- notifications ---------------------------------------------------------


def notify(
    db: Session, user_id: uuid.UUID, kind: str, text: str,
    *, case_id: uuid.UUID | None = None, court_id: uuid.UUID | None = None,
) -> None:
    db.add(Notification(
        id=uuid.uuid4(), user_id=user_id, kind=kind, text=text,
        case_id=case_id, court_id=court_id,
    ))
    # Delivered after the surrounding transaction commits (see push_service).
    push_service.queue(db, user_id, text, kind=kind, case_id=case_id, court_id=court_id)


def notify_case(
    db: Session, case: Case, kind: str, text: str, *, exclude: uuid.UUID | None = None,
) -> None:
    """Tell everyone following a case that something happened to it.

    That is the creator plus anyone seated through a direct case member row —
    the accused and the jurors who have accounts. Jurors who joined by link
    alone have no user to notify; the courtroom tells them instead.

    [exclude] is for the person who caused the event: being told you filed your
    own defense is noise, and noise spends the daily push cap.

    Rows are added to the caller's session and go out when it commits, so the
    notification and the thing it announces land together or not at all.
    """
    seen: set[uuid.UUID] = set()
    for user_id in (
        case.creator_id,
        *db.execute(
            select(CaseMember.user_id).where(CaseMember.case_id == case.id)
        ).scalars(),
    ):
        if user_id is None or user_id == exclude or user_id in seen:
            continue
        seen.add(user_id)
        notify(db, user_id, kind, text, case_id=case.id)


# --- courts ----------------------------------------------------------------

# No 0/O/1/I/L: invite codes get read aloud and retyped from screenshots.
_INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_LOOKALIKES = str.maketrans("01IL", "OOOO")


def create_court(db: Session, user: User, name: str) -> Court:
    court = Court(
        id=uuid.uuid4(), name=name.strip(), owner_id=user.id,
        invite_code="".join(secrets.choice(_INVITE_ALPHABET) for _ in range(8)),
    )
    db.add(court)
    db.flush()
    db.add(CourtMember(id=uuid.uuid4(), court_id=court.id, user_id=user.id))
    db.commit()
    db.refresh(court)
    return court


def list_courts(db: Session, user: User) -> list[Court]:
    return list(db.execute(
        select(Court)
        .join(CourtMember, CourtMember.court_id == Court.id)
        .where(CourtMember.user_id == user.id)
        .order_by(Court.created_at.desc())
    ).scalars().all())


def is_member(court: Court, user_id: uuid.UUID) -> bool:
    return any(m.user_id == user_id for m in court.members)


def get_court_for_member(db: Session, court_id: uuid.UUID, user: User) -> Court:
    court = db.get(Court, court_id)
    if court is None or not is_member(court, user.id):
        raise errors.not_found("Court")
    return court


def add_court_member(db: Session, court: Court, actor: User, user_id: uuid.UUID) -> Court:
    target = db.get(User, user_id)
    if target is None:
        raise errors.not_found("User")
    if not is_member(court, user_id):
        db.add(CourtMember(id=uuid.uuid4(), court_id=court.id, user_id=user_id))
        notify(
            db, user_id, "added_to_court",
            f"{actor.display_name} added you to the court “{court.name}”.",
            court_id=court.id,
        )
        db.commit()
        db.refresh(court)
    return court


def join_court(db: Session, user: User, code: str) -> Court:
    # Older codes can contain look-alike characters; match with those folded.
    wanted = code.strip().upper().translate(_LOOKALIKES)
    folded = Court.invite_code
    for ch in "01IL":
        folded = func.replace(folded, ch, "O")
    court = db.execute(select(Court).where(folded == wanted)).scalars().first()
    if court is None:
        raise errors.not_found("Court")
    if not is_member(court, user.id):
        db.add(CourtMember(id=uuid.uuid4(), court_id=court.id, user_id=user.id))
        db.commit()
        db.refresh(court)
    return court


def remove_court_member(db: Session, court: Court, actor: User, user_id: uuid.UUID) -> None:
    if user_id != actor.id and court.owner_id != actor.id:
        raise errors.forbidden("Only the owner can remove other members.")
    member = next((m for m in court.members if m.user_id == user_id), None)
    if member is None:
        raise errors.not_found("Member")
    if user_id == court.owner_id:
        raise errors.conflict("The owner cannot leave their own court.")
    db.delete(member)
    db.commit()


# --- case members ----------------------------------------------------------


def seat_member(
    db: Session, case: Case, actor: User, user_id: uuid.UUID, role: str,
    *, notify_user: bool = True,
) -> CaseMember:
    """Seat a user on a case as `accused` or `juror` (idempotent per user)."""
    target = db.get(User, user_id)
    if target is None:
        raise errors.not_found("User")
    if target.id == case.creator_id:
        raise errors.conflict("The plaintiff cannot also be seated as the accused or a juror.")
    existing = db.execute(
        select(CaseMember).where(CaseMember.case_id == case.id, CaseMember.user_id == user_id)
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    if role == "accused":
        taken = db.execute(
            select(CaseMember.id).where(CaseMember.case_id == case.id, CaseMember.role == "accused")
        ).first()
        if taken is not None:
            raise errors.conflict("This case already has an accused.")
        defendant = next(
            (p for p in case.participants if p.role == ParticipantRole.defendant), None
        )
        if defendant is not None and not defendant.display_name:
            defendant.display_name = target.display_name
    raw, token_hash = generate_token("jury" if role == "juror" else "invite")
    member = CaseMember(
        id=uuid.uuid4(), case_id=case.id, user_id=user_id, role=role,
        access_token=raw, token_hash=token_hash,
    )
    db.add(member)
    if notify_user:
        if role == "accused":
            text = f"{actor.display_name} has summoned you: “{case.title}”."
            kind = "summoned"
        else:
            text = f"{actor.display_name} seated you on the jury: “{case.title}”."
            kind = "jury_duty"
        notify(db, user_id, kind, text, case_id=case.id)
    db.commit()
    return member


def shared_cases(db: Session, user: User) -> list[dict]:
    rows = db.execute(
        select(CaseMember, Case)
        .join(Case, Case.id == CaseMember.case_id)
        .where(
            CaseMember.user_id == user.id,
            Case.creator_id != user.id,
            Case.deleted_at.is_(None),
        )
        .order_by(CaseMember.created_at.desc())
    ).all()
    out = []
    for member, case in rows:
        creator = db.get(User, case.creator_id)
        out.append({
            "case_id": case.id,
            "title": case.title,
            "category": case.category,
            "status": case.status,
            "role": member.role,
            "creator_name": creator.display_name if creator else "Someone",
            "link_kind": "invite" if member.role == "accused" else "jury",
            "token": member.access_token,
        })
    return out


def resolve_member_token(db: Session, token_hash: str, role: str) -> CaseMember | None:
    return db.execute(
        select(CaseMember).where(CaseMember.token_hash == token_hash, CaseMember.role == role)
    ).scalar_one_or_none()


def defendant_participant(case: Case) -> Participant | None:
    return next((p for p in case.participants if p.role == ParticipantRole.defendant), None)


def notifications_for(db: Session, user: User) -> tuple[int, list[tuple[Notification, dict]]]:
    rows = db.execute(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
    ).scalars().all()
    unread = db.execute(
        select(func.count()).select_from(Notification)
        .where(Notification.user_id == user.id, Notification.read.is_(False))
    ).scalar_one()
    links: dict[uuid.UUID, tuple[str, str]] = {}
    case_ids = [n.case_id for n in rows if n.case_id]
    if case_ids:
        for m in db.execute(
            select(CaseMember).where(CaseMember.user_id == user.id, CaseMember.case_id.in_(case_ids))
        ).scalars():
            links[m.case_id] = ("invite" if m.role == "accused" else "jury", m.access_token)
    return unread, [
        (n, {"link_kind": links.get(n.case_id, (None, None))[0],
             "token": links.get(n.case_id, (None, None))[1]}) if n.case_id
        else (n, {"link_kind": None, "token": None})
        for n in rows
    ]


def mark_all_read(db: Session, user: User) -> None:
    now = utcnow()
    for n in db.execute(
        select(Notification).where(Notification.user_id == user.id, Notification.read.is_(False))
    ).scalars():
        n.read = True
        n.read_at = now
    db.commit()
