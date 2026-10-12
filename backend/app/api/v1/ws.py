"""The courtroom socket.

One endpoint. The first frame authenticates — tokens are never put in the URL,
where they would land in access logs — and from then on a connection does two
things at once: reads what its owner sends, and tails the room's log.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import uuid
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.concurrency import run_in_threadpool

from app.db.session import SessionLocal
from app.models import Case
from app.services import chat_service
from app.services.chat_hub import hub
from app.services.chat_service import ChatError, Seat

logger = logging.getLogger(__name__)

router = APIRouter(tags=["courtroom"])

AUTH_TIMEOUT = 10.0
TICK = 1.5
PING_EVERY = 25.0
MAX_FRAME = 2048

# WebSocket close codes in the application range.
CLOSE_BAD_REQUEST = 4400
CLOSE_UNAUTHORIZED = 4401


def _in_session(fn):
    """Run a sync service call on a worker thread with its own DB session."""

    async def call(*args: Any) -> Any:
        def run() -> Any:
            db = SessionLocal()
            try:
                return fn(db, *args)
            finally:
                db.close()

        return await run_in_threadpool(run)

    return call


_authenticate = _in_session(chat_service.authenticate)
_history = _in_session(chat_service.history)
_say = _in_session(chat_service.say)
_object = _in_session(chat_service.object_)
_hide = _in_session(chat_service.hide)


def _case_status(db, case_id: uuid.UUID) -> str | None:
    case = db.get(Case, case_id)
    return case.status if case else None


_status = _in_session(_case_status)


def _tail(db, case_id: uuid.UUID, last_n: int):
    return (
        chat_service.since(db, case_id, last_n),
        chat_service.hidden_since(db, case_id, last_n),
    )


_tail_room = _in_session(_tail)


def _roster(db, case_id: uuid.UUID, seats: list[dict]):
    return chat_service.roster(db, case_id, seats)


_roster_of = _in_session(_roster)


async def _send(ws: WebSocket, **frame: Any) -> None:
    await ws.send_json(frame)


async def _reader(ws: WebSocket, seat: Seat, conn) -> None:
    """Handle what this person sends. Refusals go back to them alone."""
    while True:
        raw = await ws.receive_text()
        if len(raw) > MAX_FRAME:
            await _send(ws, type="error", code="too_long", message="That is too much to say at once.")
            continue
        try:
            frame = json.loads(raw)
        except ValueError:
            frame = None
        if not isinstance(frame, dict):
            frame = {}
        kind = frame.get("type")

        try:
            if kind == "say":
                await _say(seat, frame.get("body"))
            elif kind == "object":
                await _object(seat)
            elif kind == "hide":
                await _hide(seat, frame.get("id"))
            elif kind == "ping":
                await _send(ws, type="pong")
                continue
            else:
                raise ChatError("invalid", "The court did not understand that.")
        except ChatError as err:
            await _send(ws, type="error", code=err.code, message=err.message)
            continue
        hub.wake(seat.case_id)


async def _tailer(ws: WebSocket, seat: Seat, conn, last_n: int) -> None:
    """Send whatever is new. Woken by the hub, and by a timer for other processes."""
    last_online = -1
    last_roster: list[dict] | None = None
    last_status: str | None = None
    since_ping = 0.0
    while True:
        woke = True
        try:
            await asyncio.wait_for(conn.event.wait(), TICK)
        except TimeoutError:
            woke = False
        conn.event.clear()

        fresh, hidden = await _tail_room(seat.case_id, last_n)
        for message in fresh:
            await _send(ws, type="message", message=message)
            last_n = message["n"]
        for message_id in hidden:
            await _send(ws, type="hidden", id=message_id)

        online = hub.online(seat.case_id)
        if online != last_online:
            last_online = online
            await _send(ws, type="presence", online=online)

        seats = await _roster_of(seat.case_id, hub.seats(seat.case_id))
        if seats != last_roster:
            last_roster = seats
            await _send(ws, type="roster", seats=seats)

        status = await _status(seat.case_id)
        if status != last_status:
            last_status = status
            await _send(ws, type="case", status=status)

        since_ping = 0.0 if (fresh or woke) else since_ping + TICK
        if since_ping >= PING_EVERY:
            since_ping = 0.0
            await _send(ws, type="ping")


@router.websocket("/ws/room")
async def room(ws: WebSocket) -> None:
    await ws.accept()

    try:
        first = await asyncio.wait_for(ws.receive_json(), AUTH_TIMEOUT)
        if not isinstance(first, dict) or first.get("type") != "auth":
            raise ValueError
    except (TimeoutError, ValueError, WebSocketDisconnect):
        with contextlib.suppress(Exception):
            await ws.close(code=CLOSE_BAD_REQUEST)
        return

    try:
        seat = await _authenticate(first)
    except ChatError as err:
        with contextlib.suppress(Exception):
            await _send(ws, type="error", code=err.code, message=err.message)
            await ws.close(code=CLOSE_UNAUTHORIZED)
        return

    conn = hub.join(
        seat.case_id,
        {"ref": seat.ref, "name": seat.name, "role": seat.role, "ballot_key": seat.ballot_key},
    )
    try:
        messages = await _history(seat.case_id)
        await _send(
            ws,
            type="welcome",
            seat={"role": seat.role, "name": seat.name, "ref": seat.ref},
            messages=messages,
        )
        last_n = messages[-1]["n"] if messages else 0

        reader = asyncio.create_task(_reader(ws, seat, conn))
        tailer = asyncio.create_task(_tailer(ws, seat, conn, last_n))
        done, pending = await asyncio.wait({reader, tailer}, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        for task in done:
            exc = task.exception()
            if exc and not isinstance(exc, WebSocketDisconnect):
                logger.warning("ws.closed_on_error", extra={"error": type(exc).__name__})
    except WebSocketDisconnect:
        pass
    finally:
        hub.leave(seat.case_id, conn)
