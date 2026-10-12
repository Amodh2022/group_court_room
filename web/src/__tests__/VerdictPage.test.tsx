import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import VerdictPage from "../pages/VerdictPage";

const VERDICT = {
  case_title: "The Last Pizza Slice",
  charge: "Alleged food misconduct",
  prosecution_summary: "Alex brings a food complaint and asks the court to take it seriously.",
  defense_summary: "Sam disputes the framing and submits that the slice was abandoned.",
  verdict: "both_guilty" as const,
  reasoning: "Neither party produced receipts, which is on brand.",
  sentence: "Establish a formal last-slice policy before your next order.",
  judge_roast: "You had a whole defense ready, which is rarely the mark of innocence.",
  closing_line: "This court is adjourned. Go outside.",
  share_caption: "The court has ruled: both guilty.",
  jury_note: "",
  jury: null,
  jury_overruled: false,
  decided_at: "2026-10-09T12:00:00Z",
  disclaimer: "Group Chat Court is a comedy game. Not legal advice.",
};

function renderPage(token = "shr_token") {
  return render(
    <MemoryRouter initialEntries={[`/verdict/${token}`]}>
      <Routes>
        <Route path="/verdict/:token" element={<VerdictPage />} />
        <Route path="/" element={<p>Home page</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

/** Walk past the reveal sequence to the card underneath.
 *  The sequence is covered on its own in VerdictReveal.test.tsx. */
async function skipReveal() {
  const skip = await screen.findByRole("button", { name: /skip to the verdict/i });
  fireEvent.click(skip);
}

function mockFetchOnce(status: number, body: unknown) {
  const fetchMock = vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

beforeEach(() => vi.resetAllMocks());
afterEach(() => vi.unstubAllGlobals());

describe("public verdict page", () => {
  it("renders every part of the verdict card", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();
    await skipReveal();

    expect(await screen.findByText("The Last Pizza Slice")).toBeInTheDocument();
    expect(screen.getByText(VERDICT.charge)).toBeInTheDocument();
    expect(screen.getByTestId("verdict-stamp")).toHaveTextContent("Both Guilty");
    expect(screen.getByText(VERDICT.prosecution_summary)).toBeInTheDocument();
    expect(screen.getByText(VERDICT.defense_summary)).toBeInTheDocument();
    expect(screen.getByText(VERDICT.reasoning)).toBeInTheDocument();
    expect(screen.getByText(VERDICT.sentence)).toBeInTheDocument();
    expect(screen.getByText(`“${VERDICT.judge_roast}”`)).toBeInTheDocument();
    expect(screen.getByText(VERDICT.closing_line)).toBeInTheDocument();
  });

  it("colour-codes the stamp by verdict", async () => {
    mockFetchOnce(200, { ...VERDICT, verdict: "not_guilty" });
    renderPage();
    await skipReveal();
    const stamp = await screen.findByTestId("verdict-stamp");
    expect(stamp).toHaveAttribute("data-verdict", "not_guilty");
    expect(stamp).toHaveTextContent("Not Guilty");
  });

  it("offers a clear call to action to start a new case", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();
    expect(
      await screen.findByRole("link", { name: /take your own case to court/i }),
    ).toHaveAttribute("href", "/file");
  });

  it("shows a revoked link as simply unavailable", async () => {
    mockFetchOnce(404, { error: "invalid_link", message: "This link is invalid or has expired." });
    renderPage("shr_revoked");

    expect(await screen.findByText(/no longer public/i)).toBeInTheDocument();
    expect(screen.queryByTestId("verdict-stamp")).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: /start your own case/i })).toHaveAttribute(
      "href",
      "/file",
    );
  });

  it("falls back to the clipboard when the share sheet is unavailable", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();
    await skipReveal();
    await screen.findByText("The Last Pizza Slice");

    // No navigator.share in this browser. Stub after render so user-event's own
    // clipboard setup cannot overwrite the spy.
    const writeText = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("navigator", { clipboard: { writeText } });

    fireEvent.click(screen.getByRole("button", { name: /share this verdict/i }));
    await waitFor(() => expect(writeText).toHaveBeenCalledOnce());
    expect(await screen.findByRole("status")).toHaveTextContent(/copied/i);
  });

  it("uses the native share sheet when the browser has one", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();
    await skipReveal();
    await screen.findByText("The Last Pizza Slice");

    const share = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("navigator", { share });

    fireEvent.click(screen.getByRole("button", { name: /share this verdict/i }));
    await waitFor(() => expect(share).toHaveBeenCalledOnce());
    expect(share).toHaveBeenCalledWith(
      expect.objectContaining({ text: VERDICT.share_caption }),
    );
  });

  it("confirms a report without revealing whether the link resolved", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();
    await skipReveal();
    await screen.findByText("The Last Pizza Slice");

    await userEvent.setup().click(screen.getByRole("button", { name: /report this verdict/i }));
    expect(await screen.findByText(/sent for review/i)).toBeInTheDocument();
  });

  it("shows the legal disclaimer the API supplied", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();
    await skipReveal();
    expect(await screen.findByText(VERDICT.disclaimer)).toBeInTheDocument();
  });

  it("opens on the reveal rather than the ruling", async () => {
    mockFetchOnce(200, VERDICT);
    renderPage();

    expect(await screen.findByTestId("verdict-reveal")).toBeInTheDocument();
    // The answer is not on screen until the sequence reaches it.
    expect(screen.queryByTestId("verdict-stamp")).not.toBeInTheDocument();
  });

  it("publishes the jury's split alongside the ruling", async () => {
    mockFetchOnce(200, {
      ...VERDICT,
      verdict: "not_guilty",
      jury: {
        guilty: 4,
        not_guilty: 1,
        total: 5,
        majority: "guilty",
        summary: "The jury voted 4–1 for guilty.",
      },
      jury_overruled: true,
      jury_note: "The court has read the room and ignored it.",
    });
    renderPage();
    await skipReveal();

    expect(await screen.findByTestId("jury-tally")).toBeInTheDocument();
    expect(screen.getByText("The jury voted 4–1 for guilty.")).toBeInTheDocument();
    expect(screen.getByTestId("overruled")).toHaveTextContent(/overruled/i);
  });
});
