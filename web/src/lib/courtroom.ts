import { useCallback, useEffect, useRef, useState } from "react";

import { API_BASE_URL, type CaseStatus } from "./api";

/** The three ways into a courtroom, matching the three capabilities. */
export type RoomAuth =
  | { kind: "juror"; token: string; voter: string; name?: string }
  | { kind: "defendant"; token: string }
  | { kind: "creator"; case_id: string; token: string };

export type ChatKind = "plaintiff" | "defendant" | "juror" | "judge" | "system";

export interface ChatMessage {
  id: string;
  n: number;
  kind: ChatKind;
  author: string;
  ref: string;
  body: string;
  meta: Record<string, unknown>;
  at: string | null;
}

export interface Seat {
  role: "plaintiff" | "defendant" | "juror";
  name: string;
  ref: string;
}

/** One seat in the jury box. `voted` says a ballot exists, never which way. */
export interface RosterSeat {
  ref: string;
  name: string;
  role: "plaintiff" | "defendant" | "juror";
  voted: boolean;
}

export type ConnState = "connecting" | "live" | "reconnecting" | "refused";

const RECONNECT_MS = [1000, 2000, 4000, 8000];
const ERROR_VISIBLE_MS = 5000;

export function roomUrl(): string {
  return `${API_BASE_URL.replace(/^http/, "ws")}/api/v1/ws/room`;
}

/** Messages by position, one per id. A reconnect replays history, so merging
 *  must be idempotent or every drop of wifi would double the transcript. */
export function mergeMessages(current: ChatMessage[], incoming: ChatMessage[]): ChatMessage[] {
  const byId = new Map(current.map((m) => [m.id, m]));
  for (const message of incoming) byId.set(message.id, message);
  return [...byId.values()].sort((a, b) => a.n - b.n);
}

export interface Courtroom {
  state: ConnState;
  seat: Seat | null;
  messages: ChatMessage[];
  online: number;
  roster: RosterSeat[];
  caseStatus: CaseStatus | null;
  /** The last refusal, shown briefly under the composer. */
  notice: string | null;
  say: (body: string) => boolean;
  object: () => boolean;
  hide: (id: string) => boolean;
}

/** Connect to a case's courtroom and keep it connected.
 *
 *  Authenticates with its first frame, so no token ever appears in the URL. A
 *  refusal (dead link) is final and is not retried; a dropped connection is, with
 *  backoff, and resumes from the server's history rather than from memory.
 */
export function useCourtroom(auth: RoomAuth | null): Courtroom {
  const [state, setState] = useState<ConnState>("connecting");
  const [seat, setSeat] = useState<Seat | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [online, setOnline] = useState(0);
  const [roster, setRoster] = useState<RosterSeat[]>([]);
  const [caseStatus, setCaseStatus] = useState<CaseStatus | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const socketRef = useRef<WebSocket | null>(null);

  // Depend on the credential's content, not its identity: a parent that rebuilds
  // the object every render must not tear the socket down every render.
  const authKey = auth ? JSON.stringify(auth) : null;

  useEffect(() => {
    if (!authKey) return;
    const credential = JSON.parse(authKey) as RoomAuth;
    let closed = false;
    let attempt = 0;
    let retry: number | undefined;
    let noticeTimer: number | undefined;

    const flash = (text: string) => {
      setNotice(text);
      window.clearTimeout(noticeTimer);
      noticeTimer = window.setTimeout(() => setNotice(null), ERROR_VISIBLE_MS);
    };

    const connect = () => {
      if (closed) return;
      setState(attempt === 0 ? "connecting" : "reconnecting");
      const socket = new WebSocket(roomUrl());
      socketRef.current = socket;
      let refused = false;

      socket.onopen = () => socket.send(JSON.stringify({ type: "auth", ...credential }));

      socket.onmessage = (event) => {
        let frame: Record<string, unknown>;
        try {
          frame = JSON.parse(String(event.data));
        } catch {
          return;
        }
        switch (frame.type) {
          case "welcome":
            attempt = 0;
            setState("live");
            setSeat(frame.seat as Seat);
            setMessages((current) => mergeMessages(current, frame.messages as ChatMessage[]));
            break;
          case "message":
            setMessages((current) => mergeMessages(current, [frame.message as ChatMessage]));
            break;
          case "hidden":
            setMessages((current) => current.filter((m) => m.id !== frame.id));
            break;
          case "presence":
            setOnline(Number(frame.online) || 0);
            break;
          case "roster":
            setRoster(frame.seats as RosterSeat[]);
            break;
          case "case":
            setCaseStatus(frame.status as CaseStatus);
            break;
          case "error":
            if (frame.code === "invalid_link") {
              refused = true;
              setState("refused");
            } else {
              flash(String(frame.message ?? "The court did not like that."));
            }
            break;
          default:
            break; // ping / pong
        }
      };

      socket.onclose = () => {
        if (closed || refused) return;
        const wait = RECONNECT_MS[Math.min(attempt, RECONNECT_MS.length - 1)];
        attempt += 1;
        setState("reconnecting");
        retry = window.setTimeout(connect, wait);
      };
    };

    connect();
    return () => {
      closed = true;
      window.clearTimeout(retry);
      window.clearTimeout(noticeTimer);
      socketRef.current?.close();
      socketRef.current = null;
    };
  }, [authKey]);

  const send = useCallback((frame: Record<string, unknown>): boolean => {
    const socket = socketRef.current;
    if (!socket || socket.readyState !== WebSocket.OPEN) return false;
    socket.send(JSON.stringify(frame));
    return true;
  }, []);

  return {
    state,
    seat,
    messages,
    online,
    roster,
    caseStatus,
    notice,
    say: (body) => send({ type: "say", body }),
    object: () => send({ type: "object" }),
    hide: (id) => send({ type: "hide", id }),
  };
}
