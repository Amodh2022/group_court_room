import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { Chip, LoadingCard, PageHeading, RoundAction, Shell } from "../components/Chrome";
import { Courthouse, IconList, IconPlus, IconUsers } from "../components/Icons";
import { ApiError, STATUS_LABELS, api, type CaseSummary, type SharedCase } from "../lib/api";
import { session } from "../lib/session";

function statusChip(summary: CaseSummary) {
  if (summary.status === "generating") {
    return <Chip live>Deliberating</Chip>;
  }
  if (summary.status === "completed") {
    return <Chip accent>Verdict in</Chip>;
  }
  return <Chip>{STATUS_LABELS[summary.status] ?? summary.status}</Chip>;
}

export default function DashboardPage() {
  const navigate = useNavigate();
  const [cases, setCases] = useState<CaseSummary[] | null>(null);
  const [shared, setShared] = useState<SharedCase[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!session.isSignedIn) {
      navigate("/file", { replace: true });
      return;
    }
    let cancelled = false;
    api
      .listCases()
      .then((rows) => !cancelled && setCases(rows))
      .catch((err) => {
        if (cancelled) return;
        if (err instanceof ApiError && err.isUnauthorized) {
          session.signOut();
          navigate("/file", { replace: true });
          return;
        }
        setError(err instanceof ApiError ? err.message : "Could not load your cases.");
      });
    // Shared cases are a bonus; the docket still renders if this fails.
    api
      .sharedCases()
      .then((rows) => !cancelled && setShared(rows))
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [navigate]);

  if (error) {
    return (
      <Shell>
        <PageHeading label="Your docket" title="The clerk lost your file" />
        <p className="meta">{error}</p>
      </Shell>
    );
  }

  if (cases === null) {
    return (
      <Shell>
        <LoadingCard label="Loading your cases" />
      </Shell>
    );
  }

  const verdicts = cases.filter((row) => row.status === "completed").length;
  const open = cases.length - verdicts;

  return (
    <Shell wide>
      <PageHeading label="Your docket" title={`Hello, ${session.displayName ?? "counsel"}`}>
        <p className="meta">
          {cases.length === 0
            ? "Nothing on the docket."
            : `${cases.length} case${cases.length === 1 ? "" : "s"} on record.`}
        </p>
      </PageHeading>

      <section className="card balance-card" aria-label="Summary">
        <div className="balance-top">
          <div>
            <p className="card-label">Cases on record</p>
            <p className="balance-figure">{cases.length}</p>
          </div>
          <div className="balance-delta">
            <span>{open} open</span>
            <span>{verdicts} decided</span>
          </div>
        </div>
        <div className="action-row">
          <RoundAction to="/file" label="File">
            <IconPlus />
          </RoundAction>
          <RoundAction to="/courts" label="Courts">
            <IconUsers />
          </RoundAction>
          <RoundAction to="/rap-sheet" label="Record">
            <IconList />
          </RoundAction>
        </div>
      </section>

      {shared.length > 0 && (
        <>
          <div className="section-head">
            <h2>Shared with me</h2>
          </div>
          <div className="tile-grid">
            {shared.map((row) => (
              <Link
                className="trial"
                key={`${row.case_id}-${row.role}`}
                to={row.link_kind === "invite" ? `/invite/${row.token}` : `/jury/${row.token}`}
              >
                <Courthouse className="trial-icon" />
                <div>
                  <h3>{row.title}</h3>
                  <small>
                    From {row.creator_name} · you are {row.role === "accused" ? "the accused" : "a juror"}
                  </small>
                </div>
                <span className="btn btn-inline" aria-hidden="true">
                  {row.role === "accused" ? "Defend" : "Vote"}
                </span>
              </Link>
            ))}
          </div>
        </>
      )}

      <div className="section-head">
        <h2>My cases</h2>
      </div>

      {cases.length === 0 ? (
        <div className="empty">
          <span className="emoji" aria-hidden="true">
            🪑
          </span>
          <p>An empty courtroom is a wasted courtroom.</p>
          <Link className="btn" to="/file" style={{ maxWidth: "20rem", margin: "18px auto 0" }}>
            File your first case
          </Link>
        </div>
      ) : (
        <div className="tile-grid">
          {cases.map((row) => (
            <Link className="trial" key={row.id} to={`/cases/${row.id}`}>
              <Courthouse className="trial-icon" />
              <div>
                <h3>{row.title}</h3>
                <small>
                  Court Trial · {row.id.slice(0, 5).toUpperCase()}
                  {row.defendant_nickname ? ` · v. ${row.defendant_nickname}` : ""}
                </small>
                <div className="row">
                  {statusChip(row)}
                  {row.jury_count > 0 && (
                    <Chip>
                      {row.jury_count} juror{row.jury_count === 1 ? "" : "s"}
                    </Chip>
                  )}
                  {row.defense_submitted && row.status !== "completed" && <Chip>Defense filed</Chip>}
                </div>
              </div>
              <span className="btn btn-inline" aria-hidden="true">
                {row.status === "completed" ? "Verdict" : "Open"}
              </span>
            </Link>
          ))}
          <Link className="add-tile" to="/file">
            <span className="round-icon">+</span>
            <span>File a case</span>
          </Link>
        </div>
      )}
    </Shell>
  );
}
