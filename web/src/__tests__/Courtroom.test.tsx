import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Courtroom } from "../components/Courtroom";
import { Parties } from "../components/Parties";
import { mergeMessages, useCourtroom, type ChatMessage, type RoomAuth } from "../lib/courtroom";
import { FakeSocket } from "../test-socket";

const JUROR: RoomAuth = { kind: "juror", token: "jry_secret_token", voter: "juror-device-1", name: "Priya" };
const CREATOR: RoomAuth = { kind: "creator", case_id: "case-1", token: "jwt-secret" };

function msg(n: number, over: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: `m${n}`,
    n,
    kind: "juror",
    author: "Sam",
    ref: "ref-sam",
    body: `message ${n}`,
    meta: {},
    at: "2026-10-12T12:00:00Z",
    ...over,
  };
}

function Harness({ auth }: { auth: RoomAuth | null }) {
  return <Courtroom room={useCourtroom(auth)} />;
}

/** Open the socket and let the server welcome us in. */
function joinAs(role: "juror" | "plaintiff", messages: ChatMessage[] = []) {
  const socket = FakeSocket.latest;
  act(() => socket.open());
  act(() =>
    socket.push({ type: "welcome", seat: { role, name: "Priya", ref: "ref-me" }, messages }),
  );
  return socket;
}

beforeEach(() => {
  window.localStorage.clear(); // mutes persist on purpose; tests must not share them
  vi.useFakeTimers({ shouldAdvanceTime: true });
});
afterEach(() => vi.useRealTimers());

describe("connecting", () => {
  it("authenticates in its first frame, so no token ever sits in the URL", () => {
    render(<Harness auth={JUROR} />);
    const socket = FakeSocket.latest;
    act(() => socket.open());

    expect(socket.sent[0]).toEqual({ type: "auth", ...JUROR });
    expect(socket.url).toMatch(/^wss?:\/\/.+\/api\/v1\/ws\/room$/);
    expect(socket.url).not.toContain("jry_secret_token");
    expect(socket.url).not.toContain("juror-device-1");
  });

  it("shows the history it is welcomed with", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [msg(1), msg(2, { body: "the pizza was abandoned" })]);

    expect(screen.getByText("message 1")).toBeInTheDocument();
    expect(screen.getByText("the pizza was abandoned")).toBeInTheDocument();
    expect(screen.getByTestId("room-state")).toHaveTextContent(/here now|Connecting/);
  });

  it("does not open a second socket when the parent re-renders with an equal credential", () => {
    const { rerender } = render(<Harness auth={{ ...JUROR }} />);
    rerender(<Harness auth={{ ...JUROR }} />);
    rerender(<Harness auth={{ ...JUROR }} />);
    expect(FakeSocket.instances).toHaveLength(1);
  });

  it("opens nothing without a credential", () => {
    render(<Harness auth={null} />);
    expect(FakeSocket.instances).toHaveLength(0);
  });
});

describe("a dead link", () => {
  it("is final: it says so and does not keep retrying", () => {
    render(<Harness auth={JUROR} />);
    const socket = FakeSocket.latest;
    act(() => socket.open());
    act(() => socket.push({ type: "error", code: "invalid_link", message: "invalid" }));
    act(() => socket.drop());
    act(() => {
      vi.advanceTimersByTime(30_000);
    });

    expect(screen.getByText(/closed to you/i)).toBeInTheDocument();
    expect(FakeSocket.instances).toHaveLength(1);
  });
});

describe("a dropped connection", () => {
  it("reconnects, and replayed history does not double the transcript", () => {
    render(<Harness auth={JUROR} />);
    const first = joinAs("juror", [msg(1), msg(2)]);

    act(() => first.drop());
    expect(screen.getByTestId("room-state")).toHaveTextContent(/Reconnecting/);
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    expect(FakeSocket.instances).toHaveLength(2);

    const second = FakeSocket.latest;
    act(() => second.open());
    act(() =>
      second.push({
        type: "welcome",
        seat: { role: "juror", name: "Priya", ref: "ref-me" },
        messages: [msg(1), msg(2), msg(3)],
      }),
    );

    expect(screen.getAllByText(/^message \d$/)).toHaveLength(3);
    expect(screen.getByTestId("room-state")).toHaveTextContent(/here now/);
  });

  it("backs off further each time it fails", () => {
    render(<Harness auth={JUROR} />);
    act(() => FakeSocket.latest.drop());
    act(() => {
      vi.advanceTimersByTime(999);
    });
    expect(FakeSocket.instances).toHaveLength(1);
    act(() => {
      vi.advanceTimersByTime(1);
    });
    expect(FakeSocket.instances).toHaveLength(2);

    act(() => FakeSocket.latest.drop());
    act(() => {
      vi.advanceTimersByTime(1999);
    });
    expect(FakeSocket.instances).toHaveLength(2);
    act(() => {
      vi.advanceTimersByTime(1);
    });
    expect(FakeSocket.instances).toHaveLength(3);
  });
});

describe("speaking", () => {
  it("cannot send until the court has let you in", () => {
    render(<Harness auth={JUROR} />);
    expect(screen.getByLabelText(/message the courtroom/i)).toBeDisabled();
    expect(screen.getByRole("button", { name: /objection/i })).toBeDisabled();
  });

  it("sends what you type and clears the box", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");

    fireEvent.change(screen.getByLabelText(/message the courtroom/i), {
      target: { value: "  the aisle seat is a war crime  " },
    });
    fireEvent.click(screen.getByRole("button", { name: /^send$/i }));

    expect(socket.sent.at(-1)).toEqual({ type: "say", body: "the aisle seat is a war crime" });
    expect(screen.getByLabelText(/message the courtroom/i)).toHaveValue("");
  });

  it("does not send an empty line", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror");
    expect(screen.getByRole("button", { name: /^send$/i })).toBeDisabled();
  });

  it("sends an objection", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");
    fireEvent.click(screen.getByRole("button", { name: /objection/i }));
    expect(socket.sent.at(-1)).toEqual({ type: "object" });
  });

  it("shows a refusal briefly, then lets it go", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");

    act(() => socket.push({ type: "error", code: "blocked", message: "Judge Byte will not entertain that." }));
    expect(screen.getByRole("status")).toHaveTextContent(/will not entertain/);

    act(() => {
      vi.advanceTimersByTime(5100);
    });
    expect(screen.getByRole("status")).toBeEmptyDOMElement();
  });
});

describe("what arrives", () => {
  it("puts a new message at the end, in order", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror", [msg(1)]);

    act(() => socket.push({ type: "message", message: msg(3, { body: "third" }) }));
    act(() => socket.push({ type: "message", message: msg(2, { body: "second" }) }));

    const order = screen.getAllByText(/^(message 1|second|third)$/).map((e) => e.textContent);
    expect(order).toEqual(["message 1", "second", "third"]);
  });

  it("styles the judge as the court speaking", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [
      msg(1, { kind: "judge", author: "Judge Byte", ref: "judge", body: "Court is in session." }),
    ]);
    const row = screen.getByText("Court is in session.").closest("li");
    expect(row).toHaveAttribute("data-kind", "judge");
    expect(screen.getByText("Judge Byte")).toBeInTheDocument();
  });

  it("stamps an objection and shows how the judge ruled", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [
      msg(1, { body: "OBJECTION!", meta: { objection: true } }),
      msg(2, {
        kind: "judge", author: "Judge Byte", ref: "judge",
        body: "Overruled. Sit down.", meta: { ruling: "overruled", on: "m1" },
      }),
    ]);
    expect(screen.getByText("OBJECTION!")).toBeInTheDocument();
    expect(screen.getByText("overruled", { selector: ".chat-ruling" })).toBeInTheDocument();
  });

  it("shows the opening statement and the defense as statements, not chatter", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [
      msg(1, { kind: "plaintiff", author: "Alex", body: "They ate it.", meta: { statement: "opening" } }),
      msg(2, { kind: "defendant", author: "Sam", body: "It was abandoned.", meta: { statement: "defense" } }),
    ]);
    expect(screen.getByText(/Opening statement · Alex/)).toBeInTheDocument();
    expect(screen.getByText(/The defense · Sam/)).toBeInTheDocument();
    expect(screen.getByText(/“It was abandoned.”/)).toBeInTheDocument();
  });

  it("removes a message the plaintiff cleared", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror", [msg(1, { body: "something unhelpful" })]);
    expect(screen.getByText("something unhelpful")).toBeInTheDocument();

    act(() => socket.push({ type: "hidden", id: "m1" }));
    expect(screen.queryByText("something unhelpful")).not.toBeInTheDocument();
  });

  it("shows who is here and when the case moves on", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");
    act(() => socket.push({ type: "presence", online: 4 }));
    expect(screen.getByTestId("room-state")).toHaveTextContent("4 here now");

    act(() => socket.push({ type: "case", status: "completed" }));
    expect(screen.getByRole("button", { name: /objection/i })).toBeDisabled();
  });
});

describe("keeping order", () => {
  it("lets the plaintiff clear a juror's line, and sends the right id", () => {
    render(<Harness auth={CREATOR} />);
    const socket = joinAs("plaintiff", [msg(1, { body: "rude" })]);

    fireEvent.click(screen.getByRole("button", { name: /clear/i }));
    expect(socket.sent.at(-1)).toEqual({ type: "hide", id: "m1" });
  });

  it("never offers clear to a juror, nor on the judge or a statement", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [msg(1)]);
    expect(screen.queryByRole("button", { name: /clear/i })).not.toBeInTheDocument();
  });

  it("does not offer clear on the plaintiff's own opening statement", () => {
    render(<Harness auth={CREATOR} />);
    joinAs("plaintiff", [
      msg(1, { kind: "plaintiff", author: "Alex", meta: { statement: "opening" } }),
      msg(2, { kind: "judge", author: "Judge Byte", ref: "judge" }),
    ]);
    expect(screen.queryByRole("button", { name: /clear/i })).not.toBeInTheDocument();
  });

  it("lets anyone mute a person, but never the judge", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [
      msg(1, { body: "annoying thing" }),
      msg(2, { kind: "judge", author: "Judge Byte", ref: "judge", body: "Order." }),
    ]);

    fireEvent.click(screen.getByRole("button", { name: /mute/i }));
    expect(screen.queryByText("annoying thing")).not.toBeInTheDocument();
    expect(screen.getByText("Order.")).toBeInTheDocument();
  });

  it("marks your own messages as yours", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror", [msg(1, { ref: "ref-me", author: "Priya", body: "mine" }), msg(2)]);
    expect(screen.getByText("mine").closest("li")).toHaveClass("mine");
    expect(screen.getByText("message 2").closest("li")).not.toHaveClass("mine");
  });
});

describe("mergeMessages", () => {
  it("is idempotent and keeps position order", () => {
    const merged = mergeMessages([msg(2), msg(1)], [msg(1), msg(3)]);
    expect(merged.map((m) => m.n)).toEqual([1, 2, 3]);
    expect(mergeMessages(merged, merged)).toEqual(merged);
  });

  it("lets a later copy of a message replace an earlier one", () => {
    const merged = mergeMessages([msg(1, { body: "old" })], [msg(1, { body: "new" })]);
    expect(merged).toHaveLength(1);
    expect(merged[0].body).toBe("new");
  });
});

describe("the jury box", () => {
  const seats = [
    { ref: "r1", name: "Alex", role: "plaintiff", voted: false },
    { ref: "r2", name: "Priya", role: "defendant", voted: false },
    { ref: "r3", name: "Dev", role: "juror", voted: true },
    { ref: "r4", name: "Mia", role: "juror", voted: false },
  ];

  it("lists everyone in the room, numbered, with their role", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");
    act(() => socket.push({ type: "roster", seats }));

    const box = screen.getByRole("complementary", { name: /jury box/i });
    expect(box).toHaveTextContent("Alex");
    expect(box).toHaveTextContent("Plaintiff");
    expect(box).toHaveTextContent("Defense");
    expect(box.querySelectorAll("li")).toHaveLength(4);
    expect(box.querySelectorAll(".seatno")[3]).toHaveTextContent("4");
  });

  it("marks who has voted, and nothing about which way", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");
    act(() => socket.push({ type: "roster", seats }));

    const box = screen.getByRole("complementary", { name: /jury box/i });
    expect(box).toHaveTextContent("Voted");
    expect(box.textContent?.toLowerCase()).not.toContain("guilty");
  });

  it("is absent until the room has told us who is here", () => {
    render(<Harness auth={JUROR} />);
    joinAs("juror");
    expect(screen.queryByRole("complementary", { name: /jury box/i })).not.toBeInTheDocument();
  });

  it("follows people in and out", () => {
    render(<Harness auth={JUROR} />);
    const socket = joinAs("juror");
    act(() => socket.push({ type: "roster", seats }));
    act(() => socket.push({ type: "roster", seats: seats.slice(0, 2) }));

    const box = screen.getByRole("complementary", { name: /jury box/i });
    expect(box.querySelectorAll("li")).toHaveLength(2);
    expect(box).not.toHaveTextContent("Mia");
  });
});

describe("the parties", () => {
  it("introduces both sides, and says whether the accused has answered", () => {
    const { rerender } = render(<Parties plaintiff="Alex" defendant="Priya" />);
    expect(screen.getByText("Alex")).toBeInTheDocument();
    expect(screen.getByText("Priya")).toBeInTheDocument();
    expect(screen.getByText(/awaiting a defense/i)).toBeInTheDocument();

    rerender(<Parties plaintiff="Alex" defendant="Priya" defended />);
    expect(screen.getByText(/has answered/i)).toBeInTheDocument();
  });
});
