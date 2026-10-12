import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import InvitePage from "../pages/InvitePage";

const PREVIEW = {
  case_title: "The Last Pizza Slice",
  category: "food",
  accusation: "My friend ate the last pizza slice after saying they were full.",
  plaintiff_name: "Alex",
  defendant_nickname: "SliceBandit",
  expires_at: "2030-01-01T00:00:00Z",
  already_submitted: false,
  verdict_ready: false,
};

function renderPage(token = "inv_token") {
  return render(
    <MemoryRouter initialEntries={[`/invite/${token}`]}>
      <Routes>
        <Route path="/invite/:token" element={<InvitePage />} />
      </Routes>
    </MemoryRouter>,
  );
}

function mockFetch(responses: Array<{ status: number; body: unknown }>) {
  const fetchMock = vi.fn();
  responses.forEach(({ status, body }) => {
    fetchMock.mockResolvedValueOnce({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    });
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

beforeEach(() => vi.resetAllMocks());
afterEach(() => vi.unstubAllGlobals());

describe("invitation page", () => {
  it("shows a loading state before the summons arrives", () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => {})));
    renderPage();
    expect(screen.getByText("Loading the summons")).toBeInTheDocument();
  });

  it("renders the accusation and the defense form", async () => {
    mockFetch([{ status: 200, body: PREVIEW }]);
    renderPage();

    expect(await screen.findByText("The Last Pizza Slice")).toBeInTheDocument();
    expect(screen.getByText(/ate the last pizza slice/)).toBeInTheDocument();
    expect(screen.getByText(/Filed by Alex/)).toBeInTheDocument();
    // The nickname the creator suggested is pre-filled.
    expect(screen.getByLabelText(/call you/i)).toHaveValue("SliceBandit");
    expect(screen.getByRole("button", { name: /file my defense/i })).toBeEnabled();
  });

  it("treats an invalid or expired link as a dead link, without detail", async () => {
    mockFetch([
      { status: 404, body: { error: "invalid_link", message: "This link is invalid or has expired." } },
    ]);
    renderPage("inv_dead");

    expect(await screen.findByText(/no longer valid/i)).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  });

  it("blocks submission and explains why when the defense is too short", async () => {
    const fetchMock = mockFetch([{ status: 200, body: PREVIEW }]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    const user = userEvent.setup();
    await user.type(screen.getByLabelText(/state your case/i), "nope");
    await user.click(screen.getByRole("button", { name: /file my defense/i }));

    expect(await screen.findByText(/too short to be a defense/i)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(1); // nothing was posted
  });

  it("requires a nickname", async () => {
    mockFetch([{ status: 200, body: { ...PREVIEW, defendant_nickname: null } }]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    const user = userEvent.setup();
    await user.type(
      screen.getByLabelText(/state your case/i),
      "Nobody claimed it so I assumed it was abandoned.",
    );
    await user.click(screen.getByRole("button", { name: /file my defense/i }));

    expect(await screen.findByText(/needs a name to address you by/i)).toBeInTheDocument();
  });

  it("shows a confirmation page after a successful submission", async () => {
    mockFetch([
      { status: 200, body: PREVIEW },
      { status: 201, body: { case_title: "The Last Pizza Slice", nickname: "Sam", message: "ok" } },
    ]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    const user = userEvent.setup();
    await user.type(
      screen.getByLabelText(/state your case/i),
      "Nobody claimed it, so I assumed it was abandoned property.",
    );
    await user.click(screen.getByRole("button", { name: /file my defense/i }));

    expect(await screen.findByText(/on the record/i)).toBeInTheDocument();
  });

  it("explains a duplicate submission instead of showing a raw error", async () => {
    mockFetch([
      { status: 200, body: PREVIEW },
      { status: 409, body: { error: "conflict", message: "A defense has already been submitted." } },
    ]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    const user = userEvent.setup();
    await user.type(
      screen.getByLabelText(/state your case/i),
      "Letting the record show I have a very good explanation.",
    );
    await user.click(screen.getByRole("button", { name: /file my defense/i }));

    expect(await screen.findByText(/already filed/i)).toBeInTheDocument();
  });

  it("surfaces a network failure without losing what was typed", async () => {
    const fetchMock = vi.fn();
    fetchMock.mockResolvedValueOnce({ ok: true, status: 200, json: async () => PREVIEW });
    fetchMock.mockRejectedValueOnce(new TypeError("network down"));
    vi.stubGlobal("fetch", fetchMock);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    const user = userEvent.setup();
    const textarea = screen.getByLabelText(/state your case/i);
    await user.type(textarea, "I have a perfectly reasonable explanation for all of this.");
    await user.click(screen.getByRole("button", { name: /file my defense/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent(/could not reach the courthouse/i);
    expect(textarea).toHaveValue("I have a perfectly reasonable explanation for all of this.");
  });

  it("shows the already-defended state when the case is closed", async () => {
    mockFetch([{ status: 200, body: { ...PREVIEW, already_submitted: true } }]);
    renderPage();
    expect(await screen.findByText(/already filed/i)).toBeInTheDocument();
  });

  it("counts down the remaining characters", async () => {
    mockFetch([{ status: 200, body: PREVIEW }]);
    renderPage();
    await screen.findByText("The Last Pizza Slice");

    const user = userEvent.setup();
    await user.type(screen.getByLabelText(/state your case/i), "12345");
    await waitFor(() => expect(screen.getByText("995 characters left")).toBeInTheDocument());
  });
});
