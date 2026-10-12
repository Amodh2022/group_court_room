import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import FilePage from "../pages/FilePage";
import { session } from "../lib/session";

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/file"]}>
      <Routes>
        <Route path="/file" element={<FilePage />} />
        <Route path="/cases/:id" element={<p>Case file</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

function mockFetchSequence(responses: { status: number; body: unknown }[]) {
  let call = 0;
  const fetchMock = vi.fn().mockImplementation(async (url: string) => {
    // Court lookups are incidental to these tests and must not consume the sequence.
    if (String(url).includes("/api/v1/courts")) {
      return { ok: true, status: 200, json: async () => [] };
    }
    if (String(url).includes("/api/v1/notifications")) {
      return { ok: true, status: 200, json: async () => ({ unread: 0, items: [] }) };
    }
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

function caseCalls(fetchMock: ReturnType<typeof vi.fn>) {
  return fetchMock.mock.calls.filter(([url]) => !/\/api\/v1\/(courts|notifications)/.test(String(url)));
}

const CREATED = {
  id: "11111111-1111-1111-1111-111111111111",
  title: "The Last Pizza Slice",
  invite_url: "http://web.test/invite/inv_abc",
  jury_url: "http://web.test/jury/jry_abc",
  invite_token: "inv_abc",
  jury_token: "jry_abc",
};

beforeEach(() => {
  vi.resetAllMocks();
  window.localStorage.clear();
});
afterEach(() => vi.unstubAllGlobals());

describe("filing a case from the browser", () => {
  it("asks for an account before it will take a filing", async () => {
    renderPage();
    expect(await screen.findByText(/what should the court call you/i)).toBeInTheDocument();
    expect(screen.queryByLabelText(/case title/i)).not.toBeInTheDocument();
  });

  it("swears the user in and then shows the filing form", async () => {
    mockFetchSequence([
      { status: 200, body: { access_token: "tok", display_name: "Alex", user_id: "u1" } },
    ]);
    renderPage();

    fireEvent.change(screen.getByLabelText(/email/i), { target: { value: "alex@example.com" } });
    fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "correct-horse" } });
    fireEvent.click(screen.getByRole("button", { name: /^sign in$/i }));

    expect(await screen.findByLabelText(/case title/i)).toBeInTheDocument();
    expect(session.isSignedIn).toBe(true);
  });

  it("refuses a case the court would reject anyway", async () => {
    session.signIn("tok", "Alex");
    const fetchMock = mockFetchSequence([{ status: 201, body: CREATED }]);
    renderPage();

    fireEvent.change(await screen.findByLabelText(/case title/i), { target: { value: "Hi" } });
    fireEvent.click(screen.getByRole("button", { name: /file the case/i }));

    expect(await screen.findByText(/at least 3 characters/i)).toBeInTheDocument();
    expect(caseCalls(fetchMock)).toHaveLength(0);
  });

  it("files the case and hands the court the chosen category", async () => {
    session.signIn("tok", "Alex");
    const fetchMock = mockFetchSequence([{ status: 201, body: CREATED }]);
    renderPage();

    fireEvent.change(await screen.findByLabelText(/case title/i), {
      target: { value: "The Last Pizza Slice" },
    });
    fireEvent.change(screen.getByLabelText(/the accusation/i), {
      target: { value: "They ate the last slice after saying they were full." },
    });
    fireEvent.change(screen.getByLabelText(/who is on trial/i), { target: { value: "Sam" } });
    fireEvent.click(screen.getByRole("button", { name: "Food" }));
    fireEvent.click(screen.getByRole("button", { name: /file the case/i }));

    expect(await screen.findByText("Case file")).toBeInTheDocument();
    const [, init] = caseCalls(fetchMock)[0];
    expect(JSON.parse(String((init as RequestInit).body))).toMatchObject({
      title: "The Last Pizza Slice",
      category: "food",
      defendant_nickname: "Sam",
    });
    // The filing is authenticated; the invite and jury links are not.
    expect((init as RequestInit).headers).toMatchObject({ Authorization: "Bearer tok" });
  });
});
