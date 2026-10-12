"""The courtroom socket: who gets in, what gets said, and what never does."""

from __future__ import annotations

import contextlib
import json
import queue
import threading
import uuid
from datetime import timedelta

import pytest

from app.db.session import SessionLocal
from app.services import chat_service

JUROR_KEY = "juror-device-key-0001"


class Room:
    """A connected client. Frames are read on a thread so a test can never hang."""

    def __init__(self, client, auth: dict):
        self._cm = client.websocket_connect("/api/v1/ws/room")
        self.ws = self._cm.__enter__()
        self.ws.send_json({"type": "auth", **auth})
        self._frames: queue.Queue = queue.Queue()
        self.seen: list[dict] = []
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        try:
            while True:
                self._frames.put(self.ws.receive_json())
        except Exception:  # noqa: BLE001 - any failure just means the socket is done
            self._frames.put(None)

    def expect(self, predicate, timeout: float = 8.0) -> dict:
        for frame in self.seen:
            if predicate(frame):
                self.seen.remove(frame)
                return frame
        while True:
            try:
                frame = self._frames.get(timeout=timeout)
            except queue.Empty:
                raise AssertionError(f"timed out; saw {self.seen}") from None
            if frame is None:
                raise AssertionError(f"socket closed; saw {self.seen}")
            if predicate(frame):
                return frame
            self.seen.append(frame)

    def message(self, contains: str | None = None, **match) -> dict:
        def ok(f):
            m = f.get("message") or {}
            return (
                f.get("type") == "message"
                and (contains is None or contains in m.get("body", ""))
                and all(m.get(k) == v for k, v in match.items())
            )

        return self.expect(ok)["message"]

    def error(self) -> dict:
        return self.expect(lambda f: f.get("type") == "error")

    def say(self, body: str) -> None:
        self.ws.send_json({"type": "say", "body": body})

    def silent(self, predicate, wait: float = 2.5) -> bool:
        """True if nothing matching arrives within `wait` seconds."""
        try:
            self.expect(predicate, timeout=wait)
        except AssertionError:
            return True
        return False

    def close(self):
        with contextlib.suppress(Exception):  # closing a dead socket is fine
            self._cm.__exit__(None, None, None)


@pytest.fixture(autouse=True)
def _no_pacing(monkeypatch):
    monkeypatch.setattr(chat_service, "MIN_INTERVAL", timedelta(0))


@pytest.fixture
def rooms(client):
    opened: list[Room] = []

    def join(**auth):
        room = Room(client, auth)
        opened.append(room)
        return room

    yield join
    for room in opened:
        room.close()


@pytest.fixture
def trial(defended_case):
    """A defended case with all three ways in."""
    case, headers = defended_case()
    return {
        "case": case,
        "headers": headers,
        "juror": {"kind": "juror", "token": case["jury_token"], "voter": JUROR_KEY,
                  "name": "Priya"},
        "defendant": {"kind": "defendant", "token": case["invite_token"]},
        "creator": {"kind": "creator", "case_id": case["id"],
                    "token": headers["Authorization"].split(" ", 1)[1]},
    }


# --- getting in ------------------------------------------------------------


def test_a_juror_joins_and_hears_the_whole_trial_so_far(rooms, trial):
    room = rooms(**trial["juror"])
    welcome = room.expect(lambda f: f["type"] == "welcome")

    assert welcome["seat"]["role"] == "juror"
    assert welcome["seat"]["name"] == "Priya"
    kinds = [m["kind"] for m in welcome["messages"]]
    # Court opens, the plaintiff states the charge, the defense answers, the
    # judge reads the priors and tells the jury to vote.
    assert kinds[:3] == ["system", "plaintiff", "defendant"]
    bodies = " ".join(m["body"] for m in welcome["messages"])
    assert "last pizza slice" in bodies
    assert "No prior record" in bodies
    assert "cast your votes" in bodies


def test_the_plaintiff_and_the_accused_can_join_too(rooms, trial):
    assert rooms(**trial["creator"]).expect(lambda f: f["type"] == "welcome")["seat"]["role"] == "plaintiff"
    assert rooms(**trial["defendant"]).expect(lambda f: f["type"] == "welcome")["seat"]["role"] == "defendant"


@pytest.mark.parametrize(
    "auth",
    [
        {"kind": "juror", "token": "jry_not-a-real-token-at-all", "voter": JUROR_KEY},
        {"kind": "defendant", "token": "inv_not-a-real-token-at-all"},
        {"kind": "creator", "case_id": str(uuid.uuid4()), "token": "garbage"},
        {"kind": "nonsense"},
        {},
    ],
)
def test_a_bad_credential_is_refused_with_the_same_generic_error(client, auth):
    with client.websocket_connect("/api/v1/ws/room") as ws:
        ws.send_json({"type": "auth", **auth})
        frame = ws.receive_json()
    assert frame["type"] == "error"
    assert frame["code"] == "invalid_link"


def test_a_juror_key_that_is_too_short_to_be_a_device_is_refused(client, trial):
    with client.websocket_connect("/api/v1/ws/room") as ws:
        ws.send_json({"type": "auth", "kind": "juror", "token": trial["case"]["jury_token"],
                      "voter": "x"})
        assert ws.receive_json()["code"] == "invalid_link"


def test_the_first_frame_must_be_auth(client):
    from starlette.websockets import WebSocketDisconnect

    with client.websocket_connect("/api/v1/ws/room") as ws:
        ws.send_json({"type": "say", "body": "hello"})
        with pytest.raises(WebSocketDisconnect) as closed:
            ws.receive_json()
    assert closed.value.code == 4400


def test_a_deleted_case_has_no_courtroom(client, rooms, trial):
    client.delete(f"/api/v1/cases/{trial['case']['id']}", headers=trial["headers"])
    with client.websocket_connect("/api/v1/ws/room") as ws:
        ws.send_json({"type": "auth", **trial["juror"]})
        assert ws.receive_json()["code"] == "invalid_link"


# --- speaking --------------------------------------------------------------


def test_what_a_juror_says_reaches_everyone_in_the_room(rooms, trial):
    juror = rooms(**trial["juror"])
    plaintiff = rooms(**trial["creator"])
    juror.expect(lambda f: f["type"] == "welcome")
    plaintiff.expect(lambda f: f["type"] == "welcome")

    juror.say("honestly the aisle seat is a war crime")

    heard = plaintiff.message("aisle seat")
    assert heard["kind"] == "juror"
    assert heard["author"] == "Priya"
    # The speaker hears it back through the same path, so order is one truth.
    assert juror.message("aisle seat")["id"] == heard["id"]


def test_messages_do_not_leak_between_cases(rooms, trial, make_case):
    other, _ = make_case(title="A Different Dispute")
    mine = rooms(**trial["juror"])
    theirs = rooms(kind="juror", token=other["jury_token"], voter="some-other-device-key")
    mine.expect(lambda f: f["type"] == "welcome")
    theirs.expect(lambda f: f["type"] == "welcome")

    mine.say("this is about pizza")
    mine.message("this is about pizza")

    assert theirs.silent(lambda f: f.get("type") == "message" and "pizza" in f["message"]["body"]
                         and f["message"]["kind"] == "juror")


def test_a_late_joiner_sees_history_in_order(rooms, trial):
    first = rooms(**trial["juror"])
    first.expect(lambda f: f["type"] == "welcome")
    for line in ("one", "two", "three"):
        first.say(line)
        first.message(line)

    late = rooms(kind="juror", token=trial["case"]["jury_token"], voter="a-second-device-key")
    bodies = [m["body"] for m in late.expect(lambda f: f["type"] == "welcome")["messages"]]
    assert bodies[-3:] == ["one", "two", "three"]


# --- what is refused -------------------------------------------------------


@pytest.mark.parametrize(
    ("body", "code"),
    [
        ("", "invalid"),
        ("   ", "invalid"),
        ("x" * 281, "too_long"),
        ("I am going to sue you for this", "blocked"),
        ("you should kill yourself", "blocked"),
        ("OBJECTION! fake one", "invalid"),
    ],
)
def test_refusals_go_back_to_the_speaker_alone(rooms, trial, body, code):
    speaker = rooms(**trial["juror"])
    watcher = rooms(**trial["creator"])
    speaker.expect(lambda f: f["type"] == "welcome")
    watcher.expect(lambda f: f["type"] == "welcome")

    speaker.say(body)

    assert speaker.error()["code"] == code
    # Nothing was stored or broadcast.
    assert watcher.silent(lambda f: f.get("type") == "message" and f["message"]["kind"] == "juror")


def test_a_refused_line_is_never_stored(rooms, trial):
    speaker = rooms(**trial["juror"])
    speaker.expect(lambda f: f["type"] == "welcome")
    speaker.say("I will sue every one of you")
    speaker.error()

    db = SessionLocal()
    try:
        bodies = [m["body"] for m in chat_service.history(db, uuid.UUID(trial["case"]["id"]))]
    finally:
        db.close()
    assert not any("sue every one" in b for b in bodies)


def test_pacing_slows_a_flood(rooms, trial, monkeypatch):
    monkeypatch.setattr(chat_service, "MIN_INTERVAL", timedelta(seconds=30))
    speaker = rooms(**trial["juror"])
    speaker.expect(lambda f: f["type"] == "welcome")

    speaker.say("first")
    speaker.message("first")
    speaker.say("second, immediately")

    assert speaker.error()["code"] == "slow_down"


def test_a_juror_has_a_per_minute_ceiling(rooms, trial, monkeypatch):
    monkeypatch.setattr(chat_service, "PER_MINUTE", 3)
    speaker = rooms(**trial["juror"])
    speaker.expect(lambda f: f["type"] == "welcome")

    for i in range(3):
        speaker.say(f"line {i}")
        speaker.message(f"line {i}")
    speaker.say("one too many")

    assert speaker.error()["code"] == "slow_down"


def test_a_juror_has_a_ceiling_per_case(rooms, trial, monkeypatch):
    monkeypatch.setattr(chat_service, "CASE_CAP_JUROR", 2)
    speaker = rooms(**trial["juror"])
    speaker.expect(lambda f: f["type"] == "welcome")

    for i in range(2):
        speaker.say(f"line {i}")
        speaker.message(f"line {i}")
    speaker.say("a third")

    assert speaker.error()["code"] == "capped"


# --- objections ------------------------------------------------------------


def test_an_objection_gets_an_immediate_ruling_from_the_judge(rooms, trial):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")

    juror.ws.send_json({"type": "object"})

    objection = juror.message("OBJECTION!")
    ruling = juror.message(kind="judge")
    assert objection["meta"] == {"objection": True}
    assert ruling["meta"]["ruling"] in {"sustained", "overruled"}
    assert ruling["meta"]["on"] == objection["id"]
    assert ruling["body"].split(".")[0] in {"Sustained", "Overruled"}


def test_each_juror_has_two_objections(rooms, trial):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")

    for _ in range(2):
        juror.ws.send_json({"type": "object"})
        juror.message("OBJECTION!")
    juror.ws.send_json({"type": "object"})

    assert juror.error()["code"] == "capped"


def test_it_is_too_late_to_object_once_the_court_has_ruled(client, rooms, trial, drain):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")
    client.post(f"/api/v1/cases/{trial['case']['id']}/verdict", headers=trial["headers"])
    drain()

    juror.ws.send_json({"type": "object"})
    assert juror.error()["code"] == "closed"


# --- keeping order ---------------------------------------------------------


def test_the_plaintiff_can_clear_a_message_from_the_record(rooms, trial):
    plaintiff = rooms(**trial["creator"])
    juror = rooms(**trial["juror"])
    plaintiff.expect(lambda f: f["type"] == "welcome")
    juror.expect(lambda f: f["type"] == "welcome")

    juror.say("something unhelpful")
    target = plaintiff.message("something unhelpful")
    plaintiff.ws.send_json({"type": "hide", "id": target["id"]})

    assert juror.expect(lambda f: f["type"] == "hidden")["id"] == target["id"]
    # A later joiner never sees it at all.
    late = rooms(kind="juror", token=trial["case"]["jury_token"], voter="a-third-device-key-x")
    bodies = [m["body"] for m in late.expect(lambda f: f["type"] == "welcome")["messages"]]
    assert "something unhelpful" not in bodies


def test_a_juror_cannot_clear_anything(rooms, trial):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")
    juror.say("mine")
    mine = juror.message("mine")

    juror.ws.send_json({"type": "hide", "id": mine["id"]})
    assert juror.error()["code"] == "forbidden"


def test_the_judges_words_cannot_be_cleared(rooms, trial):
    plaintiff = rooms(**trial["creator"])
    welcome = plaintiff.expect(lambda f: f["type"] == "welcome")
    judge_line = next(m for m in welcome["messages"] if m["kind"] == "judge")

    plaintiff.ws.send_json({"type": "hide", "id": judge_line["id"]})
    assert plaintiff.error()["code"] == "forbidden"


# --- the game, narrated ----------------------------------------------------


def test_a_vote_is_announced_but_never_which_way(client, rooms, trial):
    watcher = rooms(**trial["creator"])
    watcher.expect(lambda f: f["type"] == "welcome")

    client.post(
        f"/api/v1/jury/{trial['case']['jury_token']}/vote",
        json={"voter_key": JUROR_KEY, "juror_name": "Priya", "vote": "guilty"},
    )

    note = watcher.message("has cast a vote")
    assert note["kind"] == "system"
    assert note["meta"] == {"voted": 1}
    assert "Priya" in note["body"]
    assert "guilty" not in note["body"].lower()


def test_the_room_hears_that_a_verdict_exists_but_never_what_it_is(client, rooms, trial, drain):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")

    client.post(f"/api/v1/cases/{trial['case']['id']}/verdict", headers=trial["headers"])
    juror.message("retires to chambers")
    drain()

    decision = juror.message("reached a decision")
    assert decision["kind"] == "judge"
    assert decision["meta"] == {"verdict_ready": True}
    for word in ("guilty", "not guilty", "insufficient", "sentence"):
        assert word not in decision["body"].lower()


def test_the_room_learns_when_the_case_changes_state(client, rooms, trial, drain):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")
    assert juror.expect(lambda f: f["type"] == "case")["status"] == "ready"

    client.post(f"/api/v1/cases/{trial['case']['id']}/verdict", headers=trial["headers"])
    drain()

    assert juror.expect(lambda f: f["type"] == "case" and f["status"] == "completed")


def test_presence_counts_people_in_the_room(rooms, trial):
    first = rooms(**trial["juror"])
    first.expect(lambda f: f["type"] == "welcome")
    assert first.expect(lambda f: f["type"] == "presence")["online"] >= 1

    rooms(**trial["creator"])
    assert first.expect(lambda f: f["type"] == "presence" and f["online"] == 2)


# --- the jury box -----------------------------------------------------------


def seats_of(frame: dict) -> dict[str, dict]:
    return {seat["name"]: seat for seat in frame["seats"]}


def test_the_jury_box_lists_who_is_here_in_order(rooms, trial):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")
    rooms(**trial["defendant"])
    rooms(**trial["creator"])

    box = juror.expect(lambda f: f["type"] == "roster" and len(f["seats"]) == 3)
    # Plaintiff, then the accused, then jurors, however they arrived.
    assert [seat["role"] for seat in box["seats"]] == ["plaintiff", "defendant", "juror"]
    assert box["seats"][2]["name"] == "Priya"


def test_the_jury_box_never_exposes_the_ballot_key_or_a_direction(rooms, trial, client):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")
    client.post(
        f"/api/v1/jury/{trial['case']['jury_token']}/vote",
        json={"voter_key": JUROR_KEY, "juror_name": "Priya", "vote": "guilty"},
    )

    box = juror.expect(lambda f: f["type"] == "roster" and f["seats"][0].get("voted"))
    assert set(box["seats"][0]) == {"ref", "name", "role", "voted"}
    assert "guilty" not in json.dumps(box).lower()


def test_a_juror_shows_as_not_voted_until_they_do(rooms, trial, client):
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")
    first = juror.expect(lambda f: f["type"] == "roster")
    assert first["seats"][0]["voted"] is False

    client.post(
        f"/api/v1/jury/{trial['case']['jury_token']}/vote",
        json={"voter_key": JUROR_KEY, "vote": "not_guilty"},
    )
    assert juror.expect(lambda f: f["type"] == "roster" and f["seats"][0]["voted"])


def test_the_same_person_in_two_tabs_holds_one_seat(rooms, trial):
    first = rooms(**trial["juror"])
    first.expect(lambda f: f["type"] == "welcome")
    rooms(**trial["juror"])  # the same device key, a second tab

    assert first.silent(lambda f: f.get("type") == "roster" and len(f["seats"]) > 1)


def test_a_seat_empties_when_someone_leaves(rooms, trial):
    stayer = rooms(**trial["juror"])
    stayer.expect(lambda f: f["type"] == "welcome")
    leaver = rooms(**trial["creator"])
    stayer.expect(lambda f: f["type"] == "roster" and len(f["seats"]) == 2)

    leaver.close()
    assert stayer.expect(lambda f: f["type"] == "roster" and len(f["seats"]) == 1)


# --- another process --------------------------------------------------------


def test_a_message_written_by_another_process_still_arrives(rooms, trial):
    """The verdict worker is a separate process with no access to the hub.

    It writes a row and nothing else. The room must still hear it, which is the
    whole reason messages live in the database and connections only tail it.
    """
    juror = rooms(**trial["juror"])
    juror.expect(lambda f: f["type"] == "welcome")

    db = SessionLocal()
    try:
        chat_service.announce(db, uuid.UUID(trial["case"]["id"]), "Written from far away.")
    finally:
        db.close()

    assert juror.message("Written from far away.")["kind"] == "judge"


# --- ordering ---------------------------------------------------------------


def test_simultaneous_writers_never_share_a_position(trial):
    case_id = uuid.UUID(trial["case"]["id"])

    def burst():
        db = SessionLocal()
        try:
            for i in range(5):
                chat_service.announce(db, case_id, f"burst {i}")
        finally:
            db.close()

    threads = [threading.Thread(target=burst) for _ in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    db = SessionLocal()
    try:
        positions = [m["n"] for m in chat_service.history(db, case_id, limit=500)]
    finally:
        db.close()
    assert len(positions) == len(set(positions))
    assert positions == sorted(positions)
