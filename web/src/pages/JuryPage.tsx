import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { Courtroom } from "../components/Courtroom";
import { Parties } from "../components/Parties";
import { Chip, Disclaimer, ErrorBanner, LoadingCard, Notice, Shell } from "../components/Chrome";
import { TallyBar } from "../components/VerdictCard";
import { VerdictReveal } from "../components/VerdictReveal";
import {
  ApiError,
  api,
  type JuryRoom,
  type JuryVote,
  type PublicVerdict,
} from "../lib/api";
import { useCourtroom } from "../lib/courtroom";
import { session } from "../lib/session";
import { LIMITS } from "../lib/validation";

/** While the court is out, check back without making the juror refresh. */
const POLL_MS = 4000;

export default function JuryPage() {
  const { token = "" } = useParams();
  const [room, setRoom] = useState<JuryRoom | null>(null);
  const [verdict, setVerdict] = useState<PublicVerdict | null>(null);
  const [failure, setFailure] = useState<"invalid" | "offline" | null>(null);
  const [name, setName] = useState(() => session.jurorName ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The name the room knows you by. It changes when you vote, which reconnects
  // the socket once; history replays, so nothing is lost.
  const [chatName, setChatName] = useState(() => session.jurorName ?? "");
  const courtroom = useCourtroom(
    useMemo(
      () =>
        failure || !token
          ? null
          : {
              kind: "juror" as const,
              token,
              voter: session.jurorKey(),
              name: chatName || undefined,
            },
      [failure, token, chatName],
    ),
  );

  const load = useCallback(async () => {
    try {
      const fresh = await api.getJuryRoom(token);
      setRoom(fresh);
      if (fresh.verdict_ready && fresh.your_vote) {
        try {
          setVerdict(await api.getJuryVerdict(token));
        } catch {
          // Not yet readable — the poll below will come back for it.
        }
      }
      return fresh;
    } catch (err) {
      // A dead link and an unreachable courthouse are different problems, and
      // telling someone their link is invalid when their wifi dropped sends
      // them to argue with the person who sent it.
      setFailure(err instanceof ApiError && err.isInvalidLink ? "invalid" : "offline");
      return null;
    }
  }, [token]);

  useEffect(() => {
    void load();
  }, [load]);

  // The room tells us the moment the case moves; no need to wait for the poll.
  useEffect(() => {
    if (courtroom.caseStatus === "completed" || courtroom.caseStatus === "ready") void load();
  }, [courtroom.caseStatus, load]);

  // Poll only while this juror is waiting on a ruling they are entitled to.
  useEffect(() => {
    if (!room || verdict || !room.your_vote || room.status === "expired") return;
    const timer = window.setTimeout(() => void load(), POLL_MS);
    return () => window.clearTimeout(timer);
  }, [room, verdict, load]);

  async function vote(choice: JuryVote) {
    setBusy(true);
    setError(null);
    try {
      const trimmed = name.trim();
      await api.castVote(token, { vote: choice, juror_name: trimmed || undefined });
      if (trimmed) {
        session.setJurorName(trimmed);
        setChatName(trimmed);
      }
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Your vote did not reach the court.");
      // A 409 means the state moved on (already voted, or the verdict landed).
      if (err instanceof ApiError && err.status === 409) await load();
    } finally {
      setBusy(false);
    }
  }

  if (failure === "offline") {
    return (
      <Shell>
        <Notice emoji="📡" title="The courthouse is not answering">
          Your link looks fine — we just could not reach the court. Check your connection
          and try again.
        </Notice>
        <button
          className="btn"
          type="button"
          onClick={() => {
            setFailure(null);
            void load();
          }}
        >
          Try again
        </button>
        <Disclaimer />
      </Shell>
    );
  }

  if (failure === "invalid") {
    return (
      <Shell>
        <Notice emoji="🔒" title="This jury summons is not valid">
          The link may have expired or been revoked. Ask whoever filed the case for a fresh one.
        </Notice>
        <Link className="btn btn-secondary" to="/">
          What is Group Chat Court?
        </Link>
        <Disclaimer />
      </Shell>
    );
  }

  if (!room) {
    return (
      <Shell>
        <LoadingCard label="Entering the jury box" />
      </Shell>
    );
  }

  // --- the reveal, for a juror who voted ---
  if (verdict) {
    return (
      <Shell>
        <VerdictReveal verdict={verdict} yourVote={room.your_vote} />
        <Courtroom room={courtroom} title="Argue about it" />
        <Link className="btn btn-secondary" to="/file">
          File a case of your own
        </Link>
        <Disclaimer>{verdict.disclaimer}</Disclaimer>
      </Shell>
    );
  }

  // --- the jury has been dismissed, and this person never voted ---
  if (!room.jury_open && !room.your_vote) {
    return (
      <Shell>
        <Notice emoji="⚖️" title="This jury has been dismissed">
          {room.verdict_ready
            ? "The court has already ruled, and it does not seat jurors after the fact."
            : "Voting on this case is closed."}
        </Notice>
        <Link className="btn btn-secondary" to="/file">
          File a case of your own
        </Link>
        <Disclaimer />
      </Shell>
    );
  }

  const canVote = Boolean(room.defense);

  return (
    <Shell>
      <section className="card">
        <p className="card-label">
          {room.your_vote ? "You are seated" : "You have been called for jury duty"}
        </p>
        <h2 className="case-title">{room.case_title}</h2>
        <div className="row" style={{ marginTop: 12 }}>
          <Chip accent>
            {room.plaintiff_name} v. {room.defendant_name}
          </Chip>
          {!canVote && <Chip live>Awaiting the defense</Chip>}
          {room.your_vote && (
            <Chip verdict={room.your_vote}>
              You voted {room.your_vote === "guilty" ? "guilty" : "not guilty"}
            </Chip>
          )}
        </div>
      </section>

      <Parties
        plaintiff={room.plaintiff_name}
        defendant={room.defendant_name}
        defended={canVote}
      />

      <Courtroom room={courtroom} />

      {room.your_vote ? (
        <section className="card">
          <p className="card-label">Your vote is on the record</p>
          <p className="meta" style={{ marginTop: 0 }}>
            It cannot be changed, which is the point.{" "}
            {room.verdict_ready
              ? "The ruling is in. Fetching it…"
              : "Judge Byte rules once the plaintiff calls the court to order. Keep this page open — the verdict appears right here."}
          </p>
          {room.tally && (
            <div className="section">
              <h3>The jury so far</h3>
              <p className="meta" style={{ marginTop: 0 }}>
                {room.tally.summary}
              </p>
              <TallyBar tally={room.tally} />
            </div>
          )}
        </section>
      ) : (
        <section className="card">
          <p className="card-label">Your verdict</p>
          <p className="meta" style={{ marginTop: 0 }}>
            One vote per person, and you cannot change it. You will not see how anyone else voted
            until yours is in.
          </p>

          <label htmlFor="juror-name">Your name (optional)</label>
          <input
            id="juror-name"
            value={name}
            maxLength={LIMITS.nickname.max}
            placeholder="Juror #7"
            autoComplete="nickname"
            onChange={(e) => setName(e.target.value)}
          />

          <div className="ballot">
            <button
              className="ballot-btn"
              data-vote="guilty"
              type="button"
              disabled={busy || !canVote}
              onClick={() => vote("guilty")}
            >
              Guilty
              <small>They did it and they know it</small>
            </button>
            <button
              className="ballot-btn"
              data-vote="not_guilty"
              type="button"
              disabled={busy || !canVote}
              onClick={() => vote("not_guilty")}
            >
              Not guilty
              <small>This case should never have been filed</small>
            </button>
          </div>

          {error && <ErrorBanner>{error}</ErrorBanner>}
        </section>
      )}

      <details className="card card-flat">
        <summary style={{ cursor: "pointer", fontWeight: 600 }}>Read the case file</summary>
        <div className="section">
          <h3>The prosecution says</h3>
          <p className="quote">“{room.accusation}”</p>
        </div>
        <div className="section">
          <h3>The defense says</h3>
          {room.defense ? (
            <p className="quote quote-defense">“{room.defense}”</p>
          ) : (
            <p className="meta" style={{ marginTop: 0 }}>
              {room.defendant_name} has not answered the charge yet. Come back once they have —
              a juror who votes on half a case is just a hater.
            </p>
          )}
        </div>
      </details>

      <Disclaimer />
    </Shell>
  );
}
