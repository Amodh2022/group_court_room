import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { Courtroom } from "../components/Courtroom";
import { Chip, Disclaimer, ErrorBanner, Notice } from "../components/Chrome";
import { CourtStage } from "../components/stage/CourtStage";
import { ScenePanel, SceneNext, SceneProgress, SceneTitle } from "../components/stage/SceneParts";
import { TallyBar } from "../components/VerdictCard";
import { VerdictReveal } from "../components/VerdictReveal";
import type { Scene } from "../lib/stage";
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

/** The stages of a case, for the progress rail. The reveal is not on it: you
 *  do not get to see how far away the verdict is. */
const STAGES = ["Charge", "Defense", "Your vote", "The bench"] as const;

export default function JuryPage() {
  const { token = "" } = useParams();
  const [room, setRoom] = useState<JuryRoom | null>(null);
  const [verdict, setVerdict] = useState<PublicVerdict | null>(null);
  const [failure, setFailure] = useState<"invalid" | "offline" | null>(null);
  const [name, setName] = useState(() => session.jurorName ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [revealed, setRevealed] = useState<"rise" | "verdict">("rise");

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

  // --- where the camera is ---------------------------------------------------
  //
  // The camera follows the *case*, never a click. A juror is never made to
  // page through the charge to reach the ballot: both sides, the chat and the
  // ballot are one scene, and the room moves when the case does — the defense
  // lands, the vote goes in, the judge rises. That is the difference between a
  // room you are standing in and a slideshow.
  const scene: Scene = !room
    ? "arrival"
    : verdict
      ? revealed
      : room.your_vote
        ? "deliberation"
        : room.defense
          ? "ballot"
          : "charge";

  const stage = !room ? 0 : room.your_vote ? 3 : room.defense ? 2 : 1;

  const onStage = useCallback((next: "rise" | "verdict") => setRevealed(next), []);

  const hud = (
    <>
      <Link className="chip" to="/">
        Sue&nbsp;Me
      </Link>
      {room && !verdict && (
        <Chip live={!room.your_vote}>
          {room.your_vote ? "Your vote is in" : courtroom.state === "live" ? `${courtroom.online} here` : "Jury duty"}
        </Chip>
      )}
    </>
  );

  return (
    <CourtStage scene={scene} hud={hud}>
      {renderScene()}
    </CourtStage>
  );

  function renderScene() {
    if (failure === "offline") {
      return (
        <>
          <Notice emoji="📡" title="The courthouse is not answering">
            Your link looks fine — we just could not reach the court. Check your connection and
            try again.
          </Notice>
          <SceneNext
            onClick={() => {
              setFailure(null);
              void load();
            }}
          >
            Try again
          </SceneNext>
          <Disclaimer />
        </>
      );
    }

    if (failure === "invalid") {
      return (
        <>
          <Notice emoji="🔒" title="This jury summons is not valid">
            The link may have expired or been revoked. Ask whoever filed the case for a fresh one.
          </Notice>
          <Link className="btn btn-secondary scene-next" to="/">
            What is Sue Me?
          </Link>
          <Disclaimer />
        </>
      );
    }

    if (!room) {
      return (
        <SceneTitle label="Approaching the bench">Entering the courtroom…</SceneTitle>
      );
    }

    // --- the reveal, for a juror who voted ---
    if (verdict) {
      return (
        <>
          <VerdictReveal verdict={verdict} yourVote={room.your_vote} onStage={onStage} />
          {revealed === "verdict" && (
            <>
              <Courtroom room={courtroom} title="Argue about it" />
              <Link className="btn btn-secondary scene-next" to="/file">
                File a case of your own
              </Link>
              <Disclaimer>{verdict.disclaimer}</Disclaimer>
            </>
          )}
        </>
      );
    }

    // --- the jury has been dismissed, and this person never voted ---
    if (!room.jury_open && !room.your_vote) {
      return (
        <>
          <Notice emoji="⚖️" title="This jury has been dismissed">
            {room.verdict_ready
              ? "The court has already ruled, and it does not seat jurors after the fact."
              : "Voting on this case is closed."}
          </Notice>
          <Link className="btn btn-secondary scene-next" to="/file">
            File a case of your own
          </Link>
          <Disclaimer />
        </>
      );
    }

    const canVote = Boolean(room.defense);

    // One scene, whatever the camera is doing. Everything a juror needs to
    // judge the case is on screen at once: the charge, the answer, the room,
    // and the ballot. The camera is the only thing that moves.
    const voted = Boolean(room.your_vote);

    return (
      <>
        <SceneProgress step={stage} of={STAGES.length} labels={STAGES} />

        <SceneTitle label={`${room.plaintiff_name} v. ${room.defendant_name}`}>
          {room.case_title}
        </SceneTitle>

        <div className="row" style={{ justifyContent: "center" }}>
          {!canVote && <Chip live>Awaiting the defense</Chip>}
          {voted && (
            <Chip verdict={room.your_vote!}>
              You voted {room.your_vote === "guilty" ? "guilty" : "not guilty"}
            </Chip>
          )}
        </div>

        <ScenePanel tone="plaintiff">
          <p className="card-label">The prosecution says</p>
          <p className="quote">“{room.accusation}”</p>
        </ScenePanel>

        <ScenePanel tone="defense">
          <p className="card-label">The defense says</p>
          {canVote ? (
            <p className="quote quote-defense">“{room.defense}”</p>
          ) : (
            <p className="meta" style={{ marginTop: 0 }}>
              {room.defendant_name} has not answered the charge yet. Come back once they have —
              a juror who votes on half a case is just a hater.
            </p>
          )}
        </ScenePanel>

        {/* The chat opens alongside the ballot, never instead of it. */}
        <Courtroom room={courtroom} />

        {voted ? (
          <ScenePanel tone="bench">
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
          </ScenePanel>
        ) : (
          <ScenePanel tone="bench">
            <p className="card-label">Your verdict</p>
            <p className="meta" style={{ marginTop: 0 }}>
              One vote per person, and you cannot change it. You will not see how anyone else
              voted until yours is in.
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
          </ScenePanel>
        )}

        <Disclaimer />
      </>
    );
  }
}
