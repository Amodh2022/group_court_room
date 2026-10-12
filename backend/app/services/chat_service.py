"""The courtroom: who may speak, how fast, and what the judge says back.

Everything here is synchronous and database-backed, so the websocket layer can
run it in a worker thread and so a different process (the verdict worker) can
speak in the same room without any shared memory.
"""

from __future__ import annotations

import hashlib
import logging
import uuid
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from fastapi import HTTPException
from jose import JWTError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.base import as_aware, utcnow
from app.models import Case, CaseStatus, ChatMessage, JuryVote, ParticipantRole
from app.security.auth import user_from_token
from app.services import case_service, jury_service, safety

logger = logging.getLogger(__name__)

MAX_BODY = 280
MIN_INTERVAL = timedelta(milliseconds=900)
PER_MINUTE = 15
CASE_CAP_JUROR = 80
CASE_CAP_PARTY = 200
OBJECTIONS_PER_JUROR = 2
HISTORY = 100

OBJECTION_PREFIX = "OBJECTION!"

_SUSTAINED = (
    "Sustained. The court finds that objection annoyingly correct.",
    "Sustained. I do not know on what grounds, but I am not about to argue.",
    "Sustained. The witness will rephrase, and then go outside.",
)
_OVERRULED = (
    "Overruled. The court has heard worse from a group chat at 2am.",
    "Overruled. Sit down, you are not even a real lawyer.",
    "Overruled. Nice energy, wrong objection.",
)


class ChatError(Exception):
    """A refusal the speaker should be told about. Never stored, never sent on."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class Seat:
    """Who is in the room. Resolved once, at connection."""

    case_id: uuid.UUID
    role: str  # plaintiff | defendant | juror
    name: str
    ref: str
    # Hash of the juror's device key as stored on their ballot. Lets the room say
    # "has voted" without ever being able to say which way. Never sent to clients.
    ballot_key: str | None = None

    @property
    def is_creator(self) -> bool:
        return self.role == "plaintiff"


# --- identity --------------------------------------------------------------


def _ref(case_id: uuid.UUID, key: str) -> str:
    return hashlib.sha256(f"{case_id}:{key}".encode()).hexdigest()[:12]


def _clean_name(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    name = " ".join(value.split())[:40]
    return name or None


def authenticate(db: Session, payload: dict[str, Any]) -> Seat:
    """Turn a connection's first message into a seat, or refuse it.

    Three ways in, matching the three capabilities: an account for the plaintiff,
    the invite link for the accused, the jury link for everyone else. Every
    failure is the same error so a probe learns nothing about which tokens exist.
    """
    kind = payload.get("kind")
    try:
        if kind == "creator":
            user = user_from_token(db, str(payload.get("token", "")))
            case_id = uuid.UUID(str(payload.get("case_id", "")))
            case = case_service.get_owned_case(db, case_id, user)
            return Seat(case.id, "plaintiff", user.display_name, _ref(case.id, f"user:{user.id}"))

        if kind == "defendant":
            case, defendant = case_service.resolve_invite(db, str(payload.get("token", "")))
            if defendant.role != ParticipantRole.defendant:
                raise ChatError("invalid_link", "This link is invalid or has expired.")
            name = defendant.display_name or "The Defendant"
            return Seat(case.id, "defendant", name, _ref(case.id, "defendant"))

        if kind == "juror":
            case = jury_service.resolve_jury_token(db, str(payload.get("token", "")))
            voter = str(payload.get("voter", ""))
            if len(voter) < 8:
                raise ChatError("invalid_link", "This link is invalid or has expired.")
            ref = _ref(case.id, f"juror:{voter}")
            name = _clean_name(payload.get("name"))
            if name is None:
                ballot = jury_service.find_vote(db, case, voter)
                name = (ballot.juror_name if ballot else None) or f"Juror {ref[:4].upper()}"
            return Seat(case.id, "juror", name, ref, ballot_key=jury_service.voter_hash(voter))
    except ChatError:
        raise
    except (HTTPException, JWTError, ValueError):
        pass
    raise ChatError("invalid_link", "This link is invalid or has expired.")


def _live_case(db: Session, case_id: uuid.UUID) -> Case:
    case = db.get(Case, case_id)
    if case is None or case.deleted_at is not None or case.status == CaseStatus.expired:
        raise ChatError("closed", "This courtroom is closed.")
    return case


# --- reading ---------------------------------------------------------------


def serialize(message: ChatMessage) -> dict[str, Any]:
    return {
        "id": str(message.id),
        "n": message.n,
        "kind": message.kind,
        "author": message.author_name,
        "ref": message.author_ref,
        "body": message.body,
        "meta": message.meta or {},
        "at": as_aware(message.created_at).isoformat() if message.created_at else None,
    }


def history(db: Session, case_id: uuid.UUID, limit: int = HISTORY) -> list[dict[str, Any]]:
    rows = db.execute(
        select(ChatMessage)
        .where(ChatMessage.case_id == case_id, ChatMessage.hidden_at.is_(None))
        .order_by(ChatMessage.n.desc())
        .limit(limit)
    ).scalars().all()
    return [serialize(m) for m in reversed(rows)]


def since(db: Session, case_id: uuid.UUID, last_n: int) -> list[dict[str, Any]]:
    rows = db.execute(
        select(ChatMessage)
        .where(
            ChatMessage.case_id == case_id,
            ChatMessage.n > last_n,
            ChatMessage.hidden_at.is_(None),
        )
        .order_by(ChatMessage.n)
        .limit(200)
    ).scalars().all()
    return [serialize(m) for m in rows]


def hidden_since(db: Session, case_id: uuid.UUID, last_n: int) -> list[str]:
    """Ids at or before `last_n` that have since been hidden.

    A connection has already shown these, so it needs telling to take them
    down — including when the hide happened in a different process.
    """
    rows = db.execute(
        select(ChatMessage.id).where(
            ChatMessage.case_id == case_id,
            ChatMessage.n <= last_n,
            ChatMessage.hidden_at.is_not(None),
            ChatMessage.hidden_at > utcnow() - timedelta(seconds=30),
        )
    ).scalars().all()
    return [str(i) for i in rows]


def voted_keys(db: Session, case_id: uuid.UUID) -> set[str]:
    """Which ballots exist for this case: who voted, never how."""
    return set(
        db.execute(select(JuryVote.voter_key).where(JuryVote.case_id == case_id)).scalars()
    )


def roster(db: Session, case_id: uuid.UUID, seats: list[dict]) -> list[dict[str, Any]]:
    """The jury box: the plaintiff, the accused, then jurors in order, each marked
    with whether they have voted. Built from who is connected right now."""
    voted = voted_keys(db, case_id)
    rank = {"plaintiff": 0, "defendant": 1, "juror": 2}
    ordered = sorted(seats, key=lambda seat: rank.get(seat.get("role", "juror"), 2))
    return [
        {
            "ref": seat["ref"],
            "name": seat["name"],
            "role": seat["role"],
            "voted": bool(seat.get("ballot_key") and seat["ballot_key"] in voted),
        }
        for seat in ordered
    ]


def latest_n(db: Session, case_id: uuid.UUID) -> int:
    return db.execute(
        select(func.coalesce(func.max(ChatMessage.n), 0)).where(ChatMessage.case_id == case_id)
    ).scalar_one()


# --- writing ---------------------------------------------------------------


def _append(
    db: Session,
    *,
    case_id: uuid.UUID,
    kind: str,
    author: str,
    ref: str,
    body: str,
    meta: dict[str, Any] | None = None,
) -> ChatMessage:
    """Add a message at the next position, retrying if another writer won it."""
    for _ in range(6):
        message = ChatMessage(
            id=uuid.uuid4(),
            case_id=case_id,
            n=latest_n(db, case_id) + 1,
            kind=kind,
            author_name=author,
            author_ref=ref,
            body=body,
            meta=meta,
        )
        db.add(message)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            continue
        db.refresh(message)
        return message
    raise ChatError("busy", "The courtroom is packed. Try again in a second.")


def _check_pace(db: Session, seat: Seat) -> None:
    now = utcnow()
    recent = db.execute(
        select(ChatMessage.created_at)
        .where(
            ChatMessage.case_id == seat.case_id,
            ChatMessage.author_ref == seat.ref,
            ChatMessage.created_at > now - timedelta(minutes=1),
        )
        .order_by(ChatMessage.created_at.desc())
    ).scalars().all()
    if recent and now - as_aware(recent[0]) < MIN_INTERVAL:
        raise ChatError("slow_down", "Slow down. The stenographer is only one person.")
    if len(recent) >= PER_MINUTE:
        raise ChatError("slow_down", "Order! That is a lot of messages. Give it a minute.")

    total = db.execute(
        select(func.count()).where(
            ChatMessage.case_id == seat.case_id, ChatMessage.author_ref == seat.ref
        )
    ).scalar_one()
    cap = CASE_CAP_JUROR if seat.role == "juror" else CASE_CAP_PARTY
    if total >= cap:
        raise ChatError("capped", "You have said plenty. The court is moving on.")


def say(db: Session, seat: Seat, body: Any) -> ChatMessage:
    _live_case(db, seat.case_id)
    if not isinstance(body, str):
        raise ChatError("invalid", "Say something.")
    text = " ".join(body.split())
    if not text:
        raise ChatError("invalid", "Say something.")
    if len(text) > MAX_BODY:
        raise ChatError("too_long", f"Keep it under {MAX_BODY} characters.")
    if text.upper().startswith(OBJECTION_PREFIX):
        # Objections have their own button, their own limit and their own ruling.
        raise ChatError("invalid", "Use the objection button. The court keeps count.")

    screen = safety.screen_chat(text)
    if screen.blocked:
        logger.warning(
            "chat.blocked", extra={"case_id": str(seat.case_id), "category": screen.category}
        )
        raise ChatError(
            "blocked",
            "Judge Byte will not entertain that here. Keep it light, or take it elsewhere.",
        )

    _check_pace(db, seat)
    return _append(
        db, case_id=seat.case_id, kind=seat.role, author=seat.name, ref=seat.ref, body=text
    )


def object_(db: Session, seat: Seat) -> list[ChatMessage]:
    """A juror (or either party) objects. The judge rules, instantly and arbitrarily."""
    case = _live_case(db, seat.case_id)
    if case.status == CaseStatus.completed:
        raise ChatError("closed", "The court has ruled. It is too late to object.")

    used = db.execute(
        select(func.count()).where(
            ChatMessage.case_id == seat.case_id,
            ChatMessage.author_ref == seat.ref,
            ChatMessage.body.like(f"{OBJECTION_PREFIX}%"),
        )
    ).scalar_one()
    if used >= OBJECTIONS_PER_JUROR:
        raise ChatError("capped", "You are out of objections. The court admires the stamina.")
    _check_pace(db, seat)

    objection = _append(
        db, case_id=seat.case_id, kind=seat.role, author=seat.name, ref=seat.ref,
        body=OBJECTION_PREFIX, meta={"objection": True},
    )
    # Deterministic from the message id, so a replay or a retry never flips it.
    roll = int(objection.id.hex[:8], 16)
    sustained = roll % 2 == 0
    pool = _SUSTAINED if sustained else _OVERRULED
    ruling = _append(
        db, case_id=seat.case_id, kind="judge", author="Judge Byte", ref="judge",
        body=pool[(roll >> 4) % len(pool)],
        meta={"ruling": "sustained" if sustained else "overruled", "on": str(objection.id)},
    )
    return [objection, ruling]


def hide(db: Session, seat: Seat, message_id: Any) -> uuid.UUID:
    """Only the plaintiff keeps order in the room."""
    if not seat.is_creator:
        raise ChatError("forbidden", "Only the plaintiff can clear the record.")
    try:
        target = db.get(ChatMessage, uuid.UUID(str(message_id)))
    except ValueError:
        target = None
    if target is None or target.case_id != seat.case_id:
        raise ChatError("invalid", "No such message.")
    if target.kind in {"judge", "system"}:
        raise ChatError("forbidden", "The judge's words stay on the record.")
    target.hidden_at = utcnow()
    db.commit()
    return target.id


# --- the judge -------------------------------------------------------------


def announce(
    db: Session,
    case_id: uuid.UUID,
    body: str,
    *,
    kind: str = "judge",
    meta: dict[str, Any] | None = None,
) -> ChatMessage | None:
    """Speak as the court. Never raises: a missed announcement must not break a
    defence submission, a vote or a verdict, which are the things that matter."""
    try:
        return _append(
            db, case_id=case_id, kind=kind,
            author="Judge Byte" if kind == "judge" else "The Court",
            ref=kind, body=body, meta=meta,
        )
    except Exception:
        db.rollback()
        logger.exception("chat.announce_failed", extra={"case_id": str(case_id)})
        return None


def _wake(case_id: uuid.UUID) -> None:
    from app.services.chat_hub import hub  # local: the hub is an async-side object

    hub.wake_threadsafe(case_id)


def open_courtroom(db: Session, case: Case, plaintiff_name: str, plaintiff_ref_key: str) -> None:
    """Court is in session, and the plaintiff has the floor."""
    announce(db, case.id, f"Court is now in session: {case.title}.", kind="system")
    try:
        _append(
            db, case_id=case.id, kind="plaintiff", author=plaintiff_name,
            ref=_ref(case.id, plaintiff_ref_key), body=case.accusation,
            meta={"statement": "opening"},
        )
    except Exception:
        db.rollback()
        logger.exception("chat.opening_failed", extra={"case_id": str(case.id)})
    _wake(case.id)


def defense_entered(db: Session, case: Case, name: str, defense: str, priors: str) -> None:
    """The accused answers the charge, and the judge reads their record aloud."""
    try:
        _append(
            db, case_id=case.id, kind="defendant", author=name,
            ref=_ref(case.id, "defendant"), body=defense, meta={"statement": "defense"},
        )
    except Exception:
        db.rollback()
        logger.exception("chat.defense_failed", extra={"case_id": str(case.id)})
    announce(db, case.id, f"For the record, {name}: {priors}")
    announce(
        db, case.id,
        "Both sides have been heard. Jurors, cast your votes. You will not see the ruling "
        "until you have.",
    )
    _wake(case.id)


def juror_voted(db: Session, case: Case, name: str, total: int) -> None:
    announce(
        db, case.id,
        f"{name} has cast a vote. {total} juror{'s' if total != 1 else ''} on the record.",
        kind="system", meta={"voted": total},
    )
    _wake(case.id)


def court_retires(db: Session, case: Case) -> None:
    announce(db, case.id, "The judge retires to chambers. Nobody touch anything.")
    _wake(case.id)


def verdict_in(db: Session, case: Case) -> None:
    """The ruling exists. The room hears that, never what it is."""
    announce(
        db, case.id,
        "The court has reached a decision. Jurors who have voted may now hear it.",
        meta={"verdict_ready": True},
    )
    _wake(case.id)
