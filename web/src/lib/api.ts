import { session } from "./session";

export const API_BASE_URL: string =
  (import.meta.env?.VITE_API_BASE_URL as string | undefined) ?? "http://localhost:8000";

export type VerdictKind =
  | "guilty"
  | "not_guilty"
  | "both_guilty"
  | "insufficient_evidence";

export type JuryVote = "guilty" | "not_guilty";

export type CaseStatus =
  | "draft"
  | "awaiting_defense"
  | "ready"
  | "generating"
  | "completed"
  | "failed"
  | "expired";

export interface JuryTally {
  guilty: number;
  not_guilty: number;
  total: number;
  majority: JuryVote | null;
  summary: string;
}

export interface InvitePreview {
  case_title: string;
  category: string;
  accusation: string;
  plaintiff_name: string;
  defendant_nickname: string | null;
  expires_at: string | null;
  already_submitted: boolean;
  verdict_ready: boolean;
  jury_count: number;
}

export interface JuryRoom {
  case_title: string;
  category: string;
  accusation: string;
  defense: string | null;
  plaintiff_name: string;
  defendant_name: string;
  status: CaseStatus;
  jury_open: boolean;
  verdict_ready: boolean;
  your_vote: JuryVote | null;
  tally: JuryTally | null;
}

export interface PublicVerdict {
  case_title: string;
  charge: string;
  prosecution_summary: string;
  defense_summary: string;
  verdict: VerdictKind;
  reasoning: string;
  sentence: string;
  judge_roast: string;
  closing_line: string;
  share_caption: string;
  jury_note: string;
  jury: JuryTally | null;
  jury_overruled: boolean;
  decided_at: string;
  disclaimer: string;
}

export interface CaseSummary {
  id: string;
  title: string;
  category: string;
  status: CaseStatus;
  created_at: string;
  expires_at: string | null;
  defendant_nickname: string | null;
  defense_submitted: boolean;
  verdict_ready: boolean;
  share_enabled: boolean;
  jury_count: number;
}

export interface CaseDetail extends CaseSummary {
  accusation: string;
  participants: {
    role: string;
    display_name: string | null;
    has_submitted: boolean;
    joined_at: string | null;
  }[];
  invite_url: string | null;
  jury_url: string | null;
  share_url: string | null;
  failure_reason: string | null;
  jury_tally: JuryTally | null;
}

export interface CaseCreated extends CaseDetail {
  invite_token: string;
  invite_url: string;
  jury_token: string;
  jury_url: string;
}

export interface VerdictResponse {
  case_id: string;
  status: CaseStatus;
  result: Omit<PublicVerdict, "decided_at" | "disclaimer" | "jury" | "jury_overruled"> | null;
  model_version: string | null;
  prompt_version: string | null;
  created_at: string | null;
}

export interface RapSheetEntry {
  id: string;
  display_name: string;
  rank: number;
  title: string;
  cases_total: number;
  convictions: number;
  acquittals: number;
  mistrials: number;
  current_streak: number;
  longest_streak: number;
  conviction_rate: number;
  last_verdict_at: string | null;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly fields?: { field: string; message: string }[],
  ) {
    super(message);
  }

  /** A dead link: wrong, revoked, expired or deleted. Deliberately not distinguished. */
  get isInvalidLink(): boolean {
    return this.status === 404;
  }

  get isRateLimited(): boolean {
    return this.status === 429;
  }

  get isUnauthorized(): boolean {
    return this.status === 401;
  }
}

interface RequestOptions extends RequestInit {
  /** Attach the signed-in user's bearer token. */
  auth?: boolean;
}

async function request<T>(path: string, init?: RequestOptions): Promise<T> {
  const { auth, ...rest } = init ?? {};
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((rest.headers as Record<string, string>) ?? {}),
  };
  if (auth && session.token) headers.Authorization = `Bearer ${session.token}`;

  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, { ...rest, headers });
  } catch {
    throw new ApiError(0, "network_error", "Could not reach the courthouse. Check your connection.");
  }

  if (response.status === 204) return undefined as T;

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    // The API nests its error shape under `detail` for raised HTTPExceptions.
    const detail = body?.detail ?? body;
    throw new ApiError(
      response.status,
      detail?.error ?? "http_error",
      detail?.message ?? "Something went wrong.",
      detail?.fields,
    );
  }
  return body as T;
}

const q = encodeURIComponent;

interface AuthResult {
  access_token: string;
  display_name: string;
  user_id: string;
  email: string | null;
  handle?: string;
}

export interface UserHit {
  user_id: string;
  handle: string;
  display_name: string;
}

export interface Court {
  id: string;
  name: string;
  invite_code: string;
  owner_id: string;
  members: UserHit[];
}

export interface SharedCase {
  case_id: string;
  title: string;
  category: string;
  status: CaseStatus;
  role: "accused" | "juror";
  creator_name: string;
  link_kind: "invite" | "jury";
  token: string;
}

export interface AppNotification {
  id: string;
  kind: "added_to_court" | "summoned" | "jury_duty";
  text: string;
  created_at: string;
  read: boolean;
  case_id: string | null;
  court_id: string | null;
  link_kind: "invite" | "jury" | null;
  token: string | null;
}

export interface NotificationFeed {
  unread: number;
  items: AppNotification[];
}

export const api = {
  // --- accounts ------------------------------------------------------------
  login: (email: string, password: string) =>
    request<AuthResult>("/api/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    }),

  register: (email: string, password: string, displayName: string) =>
    request<AuthResult>("/api/v1/auth/register", {
      method: "POST",
      body: JSON.stringify({ email, password, display_name: displayName }),
    }),

  me: () => request<{ user_id: string; display_name: string }>("/api/v1/auth/me", { auth: true }),

  // --- the creator's court -------------------------------------------------
  createCase: (payload: {
    title: string;
    category: string;
    accusation: string;
    defendant_nickname?: string;
    court_id?: string;
    accused_user_id?: string;
  }) =>
    request<CaseCreated>("/api/v1/cases", {
      method: "POST",
      body: JSON.stringify(payload),
      auth: true,
    }),

  sharedCases: () => request<SharedCase[]>("/api/v1/cases/shared", { auth: true }),

  addCaseMember: (id: string, userId: string, role: "accused" | "juror") =>
    request<void>(`/api/v1/cases/${q(id)}/members`, {
      method: "POST",
      body: JSON.stringify({ user_id: userId, role }),
      auth: true,
    }),

  // --- people, courts, notifications ----------------------------------------
  searchUsers: (term: string) =>
    request<UserHit[]>(`/api/v1/users/search?q=${q(term)}`, { auth: true }),

  listCourts: () => request<Court[]>("/api/v1/courts", { auth: true }),

  createCourt: (name: string) =>
    request<Court>("/api/v1/courts", {
      method: "POST",
      body: JSON.stringify({ name }),
      auth: true,
    }),

  addCourtMember: (courtId: string, userId: string) =>
    request<Court>(`/api/v1/courts/${q(courtId)}/members`, {
      method: "POST",
      body: JSON.stringify({ user_id: userId }),
      auth: true,
    }),

  joinCourt: (inviteCode: string) =>
    request<Court>("/api/v1/courts/join", {
      method: "POST",
      body: JSON.stringify({ invite_code: inviteCode }),
      auth: true,
    }),

  leaveCourt: (courtId: string, userId: string) =>
    request<void>(`/api/v1/courts/${q(courtId)}/members/${q(userId)}`, {
      method: "DELETE",
      auth: true,
    }),

  notifications: () => request<NotificationFeed>("/api/v1/notifications", { auth: true }),

  readAllNotifications: () =>
    request<void>("/api/v1/notifications/read-all", { method: "POST", auth: true }),

  listCases: () => request<CaseSummary[]>("/api/v1/cases", { auth: true }),

  getCase: (id: string) => request<CaseDetail>(`/api/v1/cases/${q(id)}`, { auth: true }),

  deleteCase: (id: string) =>
    request<void>(`/api/v1/cases/${q(id)}`, { method: "DELETE", auth: true }),

  requestVerdict: (id: string) =>
    request<VerdictResponse>(`/api/v1/cases/${q(id)}/verdict`, { method: "POST", auth: true }),

  getVerdict: (id: string) =>
    request<VerdictResponse>(`/api/v1/cases/${q(id)}/verdict`, { auth: true }),

  enableShare: (id: string) =>
    request<{ share_token: string; share_url: string }>(`/api/v1/cases/${q(id)}/share`, {
      method: "POST",
      auth: true,
    }),

  rapSheet: () => request<RapSheetEntry[]>("/api/v1/cases/rap-sheet", { auth: true }),

  // --- the defendant -------------------------------------------------------
  getInvite: (token: string) => request<InvitePreview>(`/api/v1/invites/${q(token)}`),

  submitDefense: (token: string, payload: { nickname: string; body: string }) =>
    request<{ case_title: string; nickname: string; message: string }>(
      `/api/v1/invites/${q(token)}/defense`,
      { method: "POST", body: JSON.stringify(payload) },
    ),

  // --- the jury ------------------------------------------------------------
  getJuryRoom: (token: string) =>
    request<JuryRoom>(`/api/v1/jury/${q(token)}?voter=${q(session.jurorKey())}`),

  castVote: (token: string, payload: { vote: JuryVote; juror_name?: string }) =>
    request<{ your_vote: JuryVote; tally: JuryTally; message: string }>(
      `/api/v1/jury/${q(token)}/vote`,
      {
        method: "POST",
        body: JSON.stringify({ ...payload, voter_key: session.jurorKey() }),
      },
    ),

  getJuryVerdict: (token: string) =>
    request<PublicVerdict>(`/api/v1/jury/${q(token)}/verdict?voter=${q(session.jurorKey())}`),

  // --- everyone ------------------------------------------------------------
  getPublicVerdict: (token: string) => request<PublicVerdict>(`/api/v1/public/verdicts/${q(token)}`),

  report: (payload: { reason: string; share_token?: string; details?: string }) =>
    request<{ ok: boolean }>(`/api/v1/reports`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
};

export const VERDICT_LABELS: Record<VerdictKind, string> = {
  guilty: "Guilty",
  not_guilty: "Not Guilty",
  both_guilty: "Both Guilty",
  insufficient_evidence: "Insufficient Evidence",
};

export const CATEGORIES: { value: string; label: string; emoji: string }[] = [
  { value: "food", label: "Food", emoji: "🍕" },
  { value: "roommates", label: "Roommates", emoji: "🏠" },
  { value: "group_chat", label: "Group chat", emoji: "💬" },
  { value: "travel", label: "Travel", emoji: "✈️" },
  { value: "money", label: "Money", emoji: "💸" },
  { value: "pets", label: "Pets", emoji: "🐕" },
  { value: "gaming", label: "Gaming", emoji: "🎮" },
  { value: "other", label: "Other", emoji: "⚖️" },
];

export const STATUS_LABELS: Record<CaseStatus, string> = {
  draft: "Draft",
  awaiting_defense: "Awaiting defense",
  ready: "Ready to rule",
  generating: "Deliberating",
  completed: "Verdict in",
  failed: "Needs a retry",
  expired: "Expired",
};
