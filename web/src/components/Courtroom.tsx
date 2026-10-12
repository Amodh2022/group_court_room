import { useEffect, useMemo, useRef, useState } from "react";

import { Avatar } from "./Avatar";
import type { ChatMessage, Courtroom as Room } from "../lib/courtroom";

const MAX_BODY = 280;
const MUTE_KEY = "gcc.muted";

function loadMuted(): string[] {
  try {
    const raw = window.localStorage.getItem(MUTE_KEY);
    return raw ? (JSON.parse(raw) as string[]) : [];
  } catch {
    return [];
  }
}

function saveMuted(refs: string[]): void {
  try {
    window.localStorage.setItem(MUTE_KEY, JSON.stringify(refs));
  } catch {
    /* storage blocked: muting still works for this visit */
  }
}

function clock(at: string | null): string {
  if (!at) return "";
  try {
    return new Date(at).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  } catch {
    return "";
  }
}

function Bubble({
  message,
  mine,
  canClear,
  onClear,
  onMute,
}: {
  message: ChatMessage;
  mine: boolean;
  canClear: boolean;
  onClear: () => void;
  onMute: () => void;
}) {
  const { kind, meta } = message;

  if (kind === "system") {
    return (
      <li className="chat-system" data-kind="system">
        {message.body}
      </li>
    );
  }

  if (kind === "judge") {
    const ruling = meta.ruling as string | undefined;
    return (
      <li className="chat-judge" data-kind="judge" data-ruling={ruling}>
        <Avatar name="Judge Byte" judge />
        <div>
          <p className="chat-author">
            Judge Byte
            {ruling && <span className={`chat-ruling ${ruling}`}>{ruling}</span>}
          </p>
          <p className="chat-text">{message.body}</p>
        </div>
      </li>
    );
  }

  if (meta.objection) {
    return (
      <li className="chat-objection" data-kind="objection">
        <span className="chat-objection-stamp">OBJECTION!</span>
        <span className="chat-objection-by">{mine ? "You" : message.author}</span>
      </li>
    );
  }

  const statement = meta.statement as string | undefined;
  if (statement) {
    return (
      <li className="chat-statement" data-kind={kind} data-statement={statement}>
        <p className="card-label">
          {statement === "opening" ? `Opening statement · ${message.author}` : `The defense · ${message.author}`}
        </p>
        <p className={statement === "opening" ? "quote" : "quote quote-defense"}>“{message.body}”</p>
      </li>
    );
  }

  return (
    <li className={`chat-row${mine ? " mine" : ""}`} data-kind={kind}>
      {!mine && <Avatar name={message.author} />}
      <div className="chat-bubble-wrap">
        {!mine && (
          <p className="chat-author">
            {message.author}
            {kind !== "juror" && <span className="chat-role">{kind}</span>}
          </p>
        )}
        <p className="chat-bubble">{message.body}</p>
        <p className="chat-meta">
          {clock(message.at)}
          {!mine && (
            <button type="button" className="chat-link" onClick={onMute}>
              mute
            </button>
          )}
          {canClear && (
            <button type="button" className="chat-link" onClick={onClear}>
              clear
            </button>
          )}
        </p>
      </div>
    </li>
  );
}

/** The jury box: everyone in the room, numbered, with a presence dot. */
function JuryBox({ room }: { room: Room }) {
  const seats = room.roster;
  if (seats.length === 0) return null;
  const roleLabel = (role: string, voted: boolean) =>
    role === "plaintiff" ? "Plaintiff" : role === "defendant" ? "Defense" : voted ? "Voted" : "Juror";

  return (
    <aside className="courtroom-box" aria-label="Jury box">
      <h4>Jury box</h4>
      <ol className="jurybox">
        {seats.map((seat, index) => (
          <li key={seat.ref} data-role={seat.role}>
            <span className="seatno">{index + 1}</span>
            <Avatar name={seat.name} presence={seat.role !== "juror" || seat.voted ? "on" : "away"} />
            <span className="who">
              <b>{seat.name}</b>
              <small>{roleLabel(seat.role, seat.voted)}</small>
            </span>
          </li>
        ))}
      </ol>
    </aside>
  );
}

/** The trial, as a group chat. Presentation only: everything it shows comes from
 *  the room hook, and everything it does goes back through it. */
export function Courtroom({ room, title = "The courtroom" }: { room: Room; title?: string }) {
  const [draft, setDraft] = useState("");
  const [muted, setMuted] = useState<string[]>(loadMuted);
  const logRef = useRef<HTMLUListElement>(null);
  const stuckToBottom = useRef(true);

  const visible = useMemo(
    () => room.messages.filter((m) => !muted.includes(m.ref) || m.kind === "judge" || m.kind === "system"),
    [room.messages, muted],
  );

  // Follow the conversation, but never yank someone who has scrolled up to read.
  // Pinned again after the next frame and once web fonts settle: text reflows
  // when the webfont swaps in, which makes the log taller than it was a moment
  // ago and would otherwise leave the newest line half cut off.
  useEffect(() => {
    const pin = () => {
      const log = logRef.current;
      if (log && stuckToBottom.current) log.scrollTop = log.scrollHeight;
    };
    pin();
    const frame = window.requestAnimationFrame(pin);
    void document.fonts?.ready.then(pin);
    return () => window.cancelAnimationFrame(frame);
  }, [visible.length]);

  function onScroll() {
    const log = logRef.current;
    if (!log) return;
    stuckToBottom.current = log.scrollHeight - log.scrollTop - log.clientHeight < 80;
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    const text = draft.trim();
    if (!text) return;
    if (room.say(text)) {
      setDraft("");
      stuckToBottom.current = true;
    }
  }

  function mute(ref: string) {
    const next = [...new Set([...muted, ref])];
    setMuted(next);
    saveMuted(next);
  }

  const live = room.state === "live";

  return (
    <section className="courtroom" aria-label={title}>
      <header className="courtroom-head">
        <p className="card-label" style={{ margin: 0 }}>
          <span className="window-dots" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          {title}
        </p>
        <span className={`chip${live ? " chip-live" : ""}`} data-testid="room-state">
          {room.state === "live"
            ? `${room.online} here now`
            : room.state === "refused"
              ? "Closed"
              : room.state === "reconnecting"
                ? "Reconnecting…"
                : "Connecting…"}
        </span>
      </header>

      {room.state === "refused" ? (
        <p className="empty" style={{ margin: 16 }}>
          This courtroom is closed to you. The link may have expired.
        </p>
      ) : (
        <div className={`courtroom-body${room.roster.length ? " with-box" : ""}`}>
          <ul className="chat-log" role="log" aria-live="polite" ref={logRef} onScroll={onScroll}>
            {visible.length === 0 && (
              <li className="chat-system">{live ? "The room is quiet." : "Entering the courtroom…"}</li>
            )}
            {visible.map((message) => (
              <Bubble
                key={message.id}
                message={message}
                mine={room.seat?.ref === message.ref}
                canClear={
                  room.seat?.role === "plaintiff" &&
                  (message.kind === "juror" || message.kind === "defendant") &&
                  !message.meta.statement &&
                  !message.meta.objection
                }
                onClear={() => room.hide(message.id)}
                onMute={() => mute(message.ref)}
              />
            ))}
          </ul>
          <JuryBox room={room} />
        </div>
      )}

      <form className="chat-composer" onSubmit={submit}>
        <button
          type="button"
          className="chat-object"
          disabled={!live || room.caseStatus === "completed"}
          onClick={() => room.object()}
          title="Object! The judge will rule on it."
        >
          Objection!
        </button>
        <input
          aria-label="Message the courtroom"
          value={draft}
          maxLength={MAX_BODY}
          placeholder={live ? "Say something to the court…" : "Connecting…"}
          disabled={!live}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button className="btn btn-inline" type="submit" disabled={!live || !draft.trim()}>
          Send
        </button>
      </form>
      <p className="chat-notice" role="status">
        {room.notice ?? ""}
      </p>
    </section>
  );
}
