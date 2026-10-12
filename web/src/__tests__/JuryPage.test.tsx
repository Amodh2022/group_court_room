import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { FakeSocket } from "../test-socket";
import JuryPage from "../pages/JuryPage";

const ROOM = {
  case_title: "The Last Pizza Slice",
  category: "food",
  accusation: "They ate the last slice right after saying they were full.",
  defense: "Nobody claimed it, so I assumed it was abandoned.",
  plaintiff_name: "Alex",
  defendant_name: "Sam",
  status: "ready" as const,
  jury_open: true,
  verdict_ready: false,
  your_vote: null,
  tally: null,
};

const TALLY = {
  guilty: 3,
  not_guilty: 1,
  total: 4,
  majority: "guilty" as const,
  summary: "The jury voted 3–1 for guilty.",
};

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/jury/jry_token"]}>
      <Routes>
        <Route path="/jury/:token" element={<JuryPage />} />
        <Route path="/file" element={<p>Filing page</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

/** Respond to each call in order; the last response repeats. */
function mockFetchSequence(responses: { status: number; body: unknown }[]) {
  let call = 0;
  const fetchMock = vi.fn().mockImplementation(async () => {
    const next = responses[Math.min(call, responses.length - 1)];
    call += 1;
    return {
      ok: next.status >= 200 && next.status < 300,
      status: next.status,
      json: async () => next.body,
    };
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

beforeEach(() => vi.resetAllMocks());
afterEach(() => vi.unstubAllGlobals());

describe("the jury box", () => {
  it("shows both sides before asking for a vote", async () => {
    mockFetchSequence([{ status: 200, body: ROOM }]);
    renderPage();

    expect(await screen.findByText(`“${ROOM.accusation}”`)).toBeInTheDocument();
    expect(screen.getByText(`“${ROOM.defense}”`)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^guilty/i })).toBeEnabled();
  });

  it("hides the running tally from a juror who has not voted", async () => {
    mockFetchSequence([{ status: 200, body: ROOM }]);
    renderPage();

    await screen.findByText(`“${ROOM.accusation}”`);
    expect(screen.queryByTestId("jury-tally")).not.toBeInTheDocument();
  });

  it("will not take a vote before the defense is in", async () => {
    mockFetchSequence([
      { status: 200, body: { ...ROOM, defense: null, status: "awaiting_defense" } },
    ]);
    renderPage();

    expect(await screen.findByText(/has not answered the charge yet/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^guilty/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /^not guilty/i })).toBeDisabled();
  });

  it("records a vote and then reveals the split", async () => {
    const fetchMock = mockFetchSequence([
      { status: 200, body: ROOM },
      { status: 201, body: { your_vote: "guilty", tally: TALLY, message: "Seated." } },
      { status: 200, body: { ...ROOM, your_vote: "guilty", tally: TALLY } },
    ]);
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: /^guilty/i }));

    expect(await screen.findByTestId("jury-tally")).toBeInTheDocument();
    expect(screen.getByText(TALLY.summary)).toBeInTheDocument();
    // The ballot carries the device's juror key, not an account credential.
    const voteCall = fetchMock.mock.calls.find(([url]) => String(url).endsWith("/vote"));
    expect(JSON.parse(String((voteCall?.[1] as RequestInit)?.body))).toMatchObject({
      vote: "guilty",
      voter_key: expect.stringContaining("juror-"),
    });
  });

  it("tells a juror their vote is final", async () => {
    mockFetchSequence([{ status: 200, body: { ...ROOM, your_vote: "not_guilty", tally: TALLY } }]);
    renderPage();

    expect(await screen.findByText(/cannot be changed/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^guilty/i })).not.toBeInTheDocument();
  });

  it("turns away a juror who arrived after the ruling", async () => {
    mockFetchSequence([
      {
        status: 200,
        body: { ...ROOM, jury_open: false, verdict_ready: true, status: "completed" },
      },
    ]);
    renderPage();

    expect(await screen.findByText(/jury has been dismissed/i)).toBeInTheDocument();
  });

  it("treats a dead jury link like any other dead link", async () => {
    mockFetchSequence([
      { status: 404, body: { error: "invalid_link", message: "This link is invalid." } },
    ]);
    renderPage();

    expect(await screen.findByText(/not valid/i)).toBeInTheDocument();
  });

  it("does not blame the link when the courthouse is unreachable", async () => {
    // A juror whose wifi dropped must not be told their invitation is dead —
    // they would go and argue with whoever sent it.
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
    renderPage();

    expect(await screen.findByText(/courthouse is not answering/i)).toBeInTheDocument();
    expect(screen.queryByText(/not valid/i)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: /try again/i })).toBeInTheDocument();
  });

  it("resolves a refused second ballot into the vote already on record", async () => {
    mockFetchSequence([
      { status: 200, body: ROOM },
      { status: 409, body: { error: "conflict", message: "You have already voted on this case." } },
      { status: 200, body: { ...ROOM, your_vote: "guilty", tally: TALLY } },
    ]);
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: /^guilty/i }));

    // Voting from a second tab is not an error worth showing: the juror is
    // simply shown the ballot the court already holds.
    expect(await screen.findByText(/your vote is on the record/i)).toBeInTheDocument();
    expect(await screen.findByTestId("jury-tally")).toBeInTheDocument();
  });

  it("seats the juror in the courtroom by device key, not by account", async () => {
    mockFetchSequence([{ status: 200, body: ROOM }]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    act(() => FakeSocket.latest.open());

    expect(FakeSocket.latest.sent[0]).toMatchObject({
      type: "auth",
      kind: "juror",
      token: "jry_token",
      voter: expect.stringContaining("juror-"),
    });
    // The chat opens alongside the ballot, not instead of it.
    expect(screen.getByRole("log")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^guilty/i })).toBeInTheDocument();
  });

  it("looks again the moment the room says the case has moved on", async () => {
    const fetchMock = mockFetchSequence([{ status: 200, body: ROOM }]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");
    const before = fetchMock.mock.calls.length;

    const socket = FakeSocket.latest;
    act(() => socket.open());
    act(() =>
      socket.push({
        type: "welcome",
        seat: { role: "juror", name: "Priya", ref: "r" },
        messages: [],
      }),
    );
    act(() => socket.push({ type: "case", status: "completed" }));

    await waitFor(() => expect(fetchMock.mock.calls.length).toBeGreaterThan(before));
  });
});
