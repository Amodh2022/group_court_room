import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { NotificationBell } from "../components/Notifications";
import CourtsPage from "../pages/CourtsPage";
import DashboardPage from "../pages/DashboardPage";
import FilePage from "../pages/FilePage";
import { session } from "../lib/session";

type Handler = (init?: RequestInit) => unknown;

function mockApi(routes: Record<string, Handler>) {
  const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
    const path = String(url).replace("http://localhost:8000", "");
    const key = Object.keys(routes).find((k) => {
      const [method, route] = k.split(" ");
      return (init?.method ?? "GET") === method && path.startsWith(route);
    });
    const body = key ? routes[key](init) : [];
    return { ok: true, status: 200, json: async () => body };
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

const COURT = {
  id: "c1",
  name: "Brunch Bunch",
  invite_code: "ABC123",
  owner_id: "u1",
  members: [{ user_id: "u1", handle: "alex", display_name: "Alex" }],
};

beforeEach(() => {
  window.localStorage.clear();
  session.signIn("tok", "Alex");
});
afterEach(() => vi.unstubAllGlobals());

describe("courts", () => {
  it("lists courts and adds a friend found by handle", async () => {
    const fetchMock = mockApi({
      "GET /api/v1/notifications": () => ({ unread: 0, items: [] }),
      "GET /api/v1/courts": () => [COURT],
      "GET /api/v1/users/search": () => [{ user_id: "u2", handle: "sam", display_name: "Sam" }],
      "POST /api/v1/courts/c1/members": () => COURT,
    });
    render(
      <MemoryRouter>
        <CourtsPage />
      </MemoryRouter>,
    );

    expect(await screen.findByText("Brunch Bunch")).toBeInTheDocument();
    expect(screen.getByText("@alex")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(/add a friend/i), { target: { value: "@sa" } });
    fireEvent.click(await screen.findByRole("button", { name: /Sam\s*@sam/ }));

    await waitFor(() => {
      const post = fetchMock.mock.calls.find(([url]) => String(url).endsWith("/courts/c1/members"));
      expect(post).toBeTruthy();
      expect(JSON.parse(String((post![1] as RequestInit).body))).toEqual({ user_id: "u2" });
    });
  });

  it("joins a court by invite code", async () => {
    const fetchMock = mockApi({
      "GET /api/v1/notifications": () => ({ unread: 0, items: [] }),
      "GET /api/v1/courts": () => [],
      "POST /api/v1/courts/join": () => COURT,
    });
    render(
      <MemoryRouter>
        <CourtsPage />
      </MemoryRouter>,
    );
    fireEvent.change(await screen.findByLabelText(/invite code/i), { target: { value: "ABC123" } });
    fireEvent.click(screen.getByRole("button", { name: /join court/i }));
    await waitFor(() =>
      expect(fetchMock.mock.calls.some(([url]) => String(url).endsWith("/courts/join"))).toBe(true),
    );
  });
});

describe("shared cases", () => {
  it("links a juror to the jury screen and the accused to the invite screen", async () => {
    mockApi({
      "GET /api/v1/notifications": () => ({ unread: 0, items: [] }),
      "GET /api/v1/cases/shared": () => [
        { case_id: "k1", title: "Pizza", category: "food", status: "ready", role: "juror", creator_name: "Sam", link_kind: "jury", token: "jry_1" },
        { case_id: "k2", title: "Parking", category: "food", status: "ready", role: "accused", creator_name: "Sam", link_kind: "invite", token: "inv_1" },
      ],
      "GET /api/v1/cases": () => [],
    });
    render(
      <MemoryRouter>
        <DashboardPage />
      </MemoryRouter>,
    );
    expect(await screen.findByText("Shared with me")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Pizza/ })).toHaveAttribute("href", "/jury/jry_1");
    expect(screen.getByRole("link", { name: /Parking/ })).toHaveAttribute("href", "/invite/inv_1");
  });
});

describe("notifications", () => {
  it("shows the unread count, lists items and marks them read on open", async () => {
    const fetchMock = mockApi({
      "GET /api/v1/notifications": () => ({
        unread: 2,
        items: [
          { id: "n1", kind: "summoned", text: "Sam summoned you", created_at: "2026-10-12T10:00:00Z", read: false, case_id: "k2", court_id: null, link_kind: "invite", token: "inv_1" },
        ],
      }),
      "POST /api/v1/notifications/read-all": () => undefined,
    });
    render(
      <MemoryRouter>
        <Routes>
          <Route path="/" element={<NotificationBell />} />
          <Route path="/invite/:token" element={<p>Invite screen</p>} />
        </Routes>
      </MemoryRouter>,
    );
    const bell = await screen.findByRole("button", { name: /2 unread/i });
    fireEvent.click(bell);
    fireEvent.click(await screen.findByText("Sam summoned you"));
    expect(await screen.findByText("Invite screen")).toBeInTheDocument();
    expect(
      fetchMock.mock.calls.some(([url]) => String(url).endsWith("/notifications/read-all")),
    ).toBe(true);
  });
});

describe("file a case with people", () => {
  it("sends the court and the accused user id", async () => {
    const fetchMock = mockApi({
      "GET /api/v1/notifications": () => ({ unread: 0, items: [] }),
      "GET /api/v1/courts": () => [
        { ...COURT, members: [...COURT.members, { user_id: "u2", handle: "sam", display_name: "Sam" }] },
      ],
      "POST /api/v1/cases": () => ({
        id: "k9", title: "T", invite_url: "x", jury_url: "y", invite_token: "a", jury_token: "b",
      }),
    });
    render(
      <MemoryRouter initialEntries={["/file"]}>
        <Routes>
          <Route path="/file" element={<FilePage />} />
          <Route path="/cases/:id" element={<p>Case file</p>} />
        </Routes>
      </MemoryRouter>,
    );
    fireEvent.change(await screen.findByLabelText(/case title/i), { target: { value: "The Last Pizza Slice" } });
    fireEvent.change(screen.getByLabelText(/the accusation/i), {
      target: { value: "They ate the last slice after saying they were full." },
    });
    fireEvent.change(await screen.findByLabelText(/court \(optional\)/i), { target: { value: "c1" } });
    fireEvent.click(await screen.findByRole("button", { name: "@sam" }));
    fireEvent.click(screen.getByRole("button", { name: /file the case/i }));

    expect(await screen.findByText("Case file")).toBeInTheDocument();
    const post = fetchMock.mock.calls.find(([, init]) => (init as RequestInit)?.method === "POST")!;
    expect(JSON.parse(String((post[1] as RequestInit).body))).toMatchObject({
      court_id: "c1",
      accused_user_id: "u2",
      defendant_nickname: "Sam",
    });
  });
});
