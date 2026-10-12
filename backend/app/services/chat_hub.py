"""Who is connected to which room, and a nudge to wake them.

The hub holds no messages. Messages live in the database; this only tracks
connections (for the "here now" count) and lets a writer say "something new in
case X" so readers look immediately instead of at their next tick. Writers in
another process cannot reach it, which is fine: every connection also looks on
a short timer, so those messages arrive a beat later rather than never.
"""

from __future__ import annotations

import asyncio
import uuid
from collections import defaultdict


class _Conn:
    __slots__ = ("event", "seat")

    def __init__(self, seat: dict | None = None) -> None:
        self.event = asyncio.Event()
        # What the room is told about this connection: ref, name, role.
        self.seat = seat or {}


class ChatHub:
    def __init__(self) -> None:
        # A list, not a set: the jury box is numbered in the order people sat down.
        self._rooms: dict[uuid.UUID, list[_Conn]] = defaultdict(list)
        self._loop: asyncio.AbstractEventLoop | None = None

    def join(self, case_id: uuid.UUID, seat: dict | None = None) -> _Conn:
        self._loop = asyncio.get_running_loop()
        conn = _Conn(seat)
        self._rooms[case_id].append(conn)
        self.wake(case_id)  # everyone's "here now" count just changed
        return conn

    def leave(self, case_id: uuid.UUID, conn: _Conn) -> None:
        room = self._rooms.get(case_id)
        if room is None:
            return
        if conn in room:
            room.remove(conn)
        if not room:
            del self._rooms[case_id]
        else:
            self.wake(case_id)

    def online(self, case_id: uuid.UUID) -> int:
        return len(self._rooms.get(case_id, ()))

    def seats(self, case_id: uuid.UUID) -> list[dict]:
        """Who is here, one entry per person, in the order they sat down.

        The same person in two tabs is one seat: a jury box with a juror twice
        in it would read as ballot stuffing even though it is not.
        """
        seen: set[str] = set()
        out: list[dict] = []
        for conn in self._rooms.get(case_id, ()):
            ref = conn.seat.get("ref")
            if ref and ref not in seen:
                seen.add(ref)
                out.append(dict(conn.seat))
        return out

    def wake(self, case_id: uuid.UUID) -> None:
        for conn in list(self._rooms.get(case_id, ())):
            conn.event.set()

    def wake_threadsafe(self, case_id: uuid.UUID) -> None:
        """For callers on a worker thread, such as the sync REST handlers."""
        loop = self._loop
        if loop is not None and loop.is_running():
            loop.call_soon_threadsafe(self.wake, case_id)


hub = ChatHub()
