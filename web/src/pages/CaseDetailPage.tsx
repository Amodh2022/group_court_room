import { useCallback, useEffect, useRef, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";

import {
  Chip,
  CopyLink,
  Disclaimer,
  ErrorBanner,
  LoadingCard,
  Notice,
  PageHeading,
  Shell,
} from "../components/Chrome";
import { Courtroom } from "../components/Courtroom";
import { Parties } from "../components/Parties";
import { TallyBar } from "../components/VerdictCard";
import { VerdictReveal } from "../components/VerdictReveal";
import {
  ApiError,
  STATUS_LABELS,
  api,
  type CaseDetail,
  type PublicVerdict,
  type VerdictResponse,
} from "../lib/api";
import { useCourtroom } from "../lib/courtroom";
import { session } from "../lib/session";

/** The generating status resolves in seconds; polling beats making them refresh. */
const POLL_MS = 2500;

function asPublicVerdict(response: VerdictResponse, detail: CaseDetail): PublicVerdict | null {
  if (!response.result) return null;
  const tally = detail.jury_tally && detail.jury_tally.total > 0 ? detail.jury_tally : null;
  const guiltyVerdict = response.result.verdict === "guilty" || response.result.verdict === "both_guilty";
  return {
    ...response.result,
    jury: tally,
    jury_overruled: Boolean(
      tally?.majority &&
        response.result.verdict !== "insufficient_evidence" &&
        guiltyVerdict !== (tally.majority === "guilty"),
    ),
    decided_at: response.created_at ?? new Date().toISOString(),
    disclaimer:
      "Group Chat Court is a comedy game. This verdict is entertainment, not a finding of fact.",
  };
}

export default function CaseDetailPage() {
  const { id = "" } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  // Handed over by the filing screen: the raw tokens exist only in that reply.
  const freshLinks = (location.state ?? {}) as { inviteUrl?: string; juryUrl?: string };

  const [detail, setDetail] = useState<CaseDetail | null>(null);
  const [verdict, setVerdict] = useState<PublicVerdict | null>(null);
  const [shareUrl, setShareUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [missing, setMissing] = useState(false);
  const pollRef = useRef<number | null>(null);

  const courtroom = useCourtroom(
    session.token ? { kind: "creator", case_id: id, token: session.token } : null,
  );

  const load = useCallback(async () => {
    try {
      const fresh = await api.getCase(id);
      setDetail(fresh);
      if (fresh.status === "completed") {
        const response = await api.getVerdict(id);
        setVerdict(asPublicVerdict(response, fresh));
      }
      return fresh;
    } catch (err) {
      if (err instanceof ApiError && err.isUnauthorized) {
        session.signOut();
        navigate("/file", { replace: true });
      } else if (err instanceof ApiError && err.isInvalidLink) {
        setMissing(true);
      } else {
        setError(err instanceof ApiError ? err.message : "Could not load this case.");
      }
      return null;
    }
  }, [id, navigate]);

  useEffect(() => {
    if (!session.isSignedIn) {
      navigate("/file", { replace: true });
      return;
    }
    void load();
  }, [load, navigate]);

  // The room hears about the defense, the votes and the verdict first; refresh
  // the case file the moment it says the status moved.
  useEffect(() => {
    if (courtroom.caseStatus && detail && courtroom.caseStatus !== detail.status) void load();
  }, [courtroom.caseStatus, detail, load]);

  // Poll only while the judge is actually out.
  useEffect(() => {
    if (detail?.status !== "generating") {
      if (pollRef.current) window.clearTimeout(pollRef.current);
      return;
    }
    pollRef.current = window.setTimeout(() => void load(), POLL_MS);
    return () => {
      if (pollRef.current) window.clearTimeout(pollRef.current);
    };
  }, [detail?.status, load]);

  async function requestVerdict() {
    setBusy(true);
    setError(null);
    try {
      await api.requestVerdict(id);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "The court could not be convened.");
    } finally {
      setBusy(false);
    }
  }

  async function share() {
    setBusy(true);
    try {
      const link = await api.enableShare(id);
      setShareUrl(link.share_url);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not publish the verdict.");
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!window.confirm("Delete this case? The links stop working immediately.")) return;
    try {
      await api.deleteCase(id);
      navigate("/cases", { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not delete this case.");
    }
  }

  if (missing) {
    return (
      <Shell>
        <Notice emoji="🗄️" title="No such case">
          It may have been deleted, or it was never yours to begin with.
        </Notice>
      </Shell>
    );
  }

  if (!detail) {
    return (
      <Shell>
        <LoadingCard label="Loading the case file" />
      </Shell>
    );
  }

  const inviteUrl = freshLinks.inviteUrl ?? detail.invite_url;
  const juryUrl = freshLinks.juryUrl ?? detail.jury_url;
  const tally = detail.jury_tally;

  return (
    <Shell>
      <PageHeading label="Case file" title={detail.title}>
        <div className="row" style={{ marginTop: 14 }}>
          <Chip live={detail.status === "generating"} accent={detail.status === "completed"}>
            {STATUS_LABELS[detail.status] ?? detail.status}
          </Chip>
          {detail.defendant_nickname && <Chip>v. {detail.defendant_nickname}</Chip>}
          {detail.jury_count > 0 && (
            <Chip>
              {detail.jury_count} juror{detail.jury_count === 1 ? "" : "s"} seated
            </Chip>
          )}
        </div>
      </PageHeading>

      {error && <ErrorBanner>{error}</ErrorBanner>}

      <Parties
        plaintiff={session.displayName ?? "You"}
        defendant={detail.defendant_nickname ?? "The accused"}
        defended={detail.defense_submitted}
      />

      {/* --- the verdict, once it exists --- */}
      {verdict ? (
        <>
          <VerdictReveal verdict={verdict} />
          <Courtroom room={courtroom} title="The courtroom" />
          {shareUrl ? (
            <div className="card card-flat">
              <CopyLink label="Public verdict link" url={shareUrl} />
            </div>
          ) : (
            <button className="btn" type="button" onClick={share} disabled={busy}>
              Publish a shareable link
            </button>
          )}
        </>
      ) : (
        <>
          <section className="card">
            <p className="card-label">The accusation</p>
            <p className="quote">“{detail.accusation}”</p>
          </section>

          {/* --- links to hand out --- */}
          <section className="card">
            <p className="card-label">Summonses</p>
            {inviteUrl ? (
              <>
                <CopyLink label="For the accused" url={inviteUrl} />
                <p className="hint">They write the defense. One person, one link.</p>
              </>
            ) : (
              <p className="meta">
                The defense link was shown once, when you filed. Your browser kept the copy you
                sent — the court does not store it.
              </p>
            )}

            {juryUrl ? (
              <div style={{ marginTop: 20 }}>
                <CopyLink label="For the group chat" url={juryUrl} />
                <p className="hint">
                  Everyone else votes here. Nobody sees the ruling until they have voted.
                </p>
              </div>
            ) : (
              <p className="meta" style={{ marginTop: 16 }}>
                The jury link was shown once, when you filed.
              </p>
            )}
          </section>

          <Courtroom room={courtroom} title="The courtroom" />

          {/* --- the jury so far --- */}
          {tally && tally.total > 0 && (
            <section className="card">
              <p className="card-label">The jury so far</p>
              <p className="meta" style={{ marginTop: 0 }}>
                {tally.summary}
              </p>
              <TallyBar tally={tally} />
            </section>
          )}

          {/* --- the action --- */}
          {detail.status === "ready" || detail.status === "failed" ? (
            <>
              <button className="btn" type="button" onClick={requestVerdict} disabled={busy}>
                {busy ? "Convening the court…" : "Call the court to order"}
              </button>
              {detail.failure_reason && (
                <p className="hint" style={{ textAlign: "center" }}>
                  Last attempt failed: {detail.failure_reason}
                </p>
              )}
            </>
          ) : detail.status === "generating" ? (
            <div className="card notice">
              <span className="emoji" aria-hidden="true">
                🔨
              </span>
              <h2>The judge is deliberating</h2>
              <p>This takes a few seconds. The page updates itself.</p>
            </div>
          ) : (
            <p className="hint" style={{ textAlign: "center", marginTop: 22 }}>
              {detail.status === "awaiting_defense"
                ? "Waiting on the defense. Seat the jury in the meantime — they can vote now."
                : `This case is ${STATUS_LABELS[detail.status]?.toLowerCase() ?? detail.status}.`}
            </p>
          )}
        </>
      )}

      <button className="footer-link" type="button" onClick={remove}
        style={{ background: "none", border: 0, cursor: "pointer", width: "100%" }}>
        Delete this case
      </button>

      <Disclaimer />
    </Shell>
  );
}
