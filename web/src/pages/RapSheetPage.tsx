import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { Chip, LoadingCard, PageHeading, Shell } from "../components/Chrome";
import { ApiError, api, type RapSheetEntry } from "../lib/api";
import { session } from "../lib/session";

export default function RapSheetPage() {
  const navigate = useNavigate();
  const [rows, setRows] = useState<RapSheetEntry[] | null>(null);

  useEffect(() => {
    if (!session.isSignedIn) {
      navigate("/file", { replace: true });
      return;
    }
    let cancelled = false;
    api
      .rapSheet()
      .then((entries) => !cancelled && setRows(entries))
      .catch((err) => {
        if (cancelled) return;
        if (err instanceof ApiError && err.isUnauthorized) {
          session.signOut();
          navigate("/file", { replace: true });
          return;
        }
        setRows([]);
      });
    return () => {
      cancelled = true;
    };
  }, [navigate]);

  if (rows === null) {
    return (
      <Shell>
        <LoadingCard label="Pulling the records" />
      </Shell>
    );
  }

  return (
    <Shell wide>
      <PageHeading label="Standings" title="The rap sheet">
        <p className="meta">
          Every verdict this court has handed down, by the person who earned it. The judge reads
          these out before sentencing.
        </p>
      </PageHeading>

      {rows.length === 0 ? (
        <div className="empty" style={{ marginTop: 24 }}>
          <span className="emoji" aria-hidden="true">
            📂
          </span>
          <p>No convictions yet. Suspiciously clean, this group.</p>
          <Link className="btn" to="/file" style={{ maxWidth: "20rem", margin: "18px auto 0" }}>
            File a case
          </Link>
        </div>
      ) : (
        <div style={{ marginTop: 22 }}>
          {rows.map((row) => (
            <article className="rap-row" key={row.id}>
              <span className="rap-rank" aria-label={`Rank ${row.rank}`}>
                {row.rank}
              </span>
              <div>
                <p className="rap-name">{row.display_name}</p>
                <p className="rap-title">{row.title}</p>
                <div className="row" style={{ marginTop: 8 }}>
                  <Chip>{row.cases_total} tried</Chip>
                  <Chip verdict="not_guilty">{row.acquittals} acquitted</Chip>
                  {row.current_streak >= 2 && (
                    <Chip accent>{row.current_streak}-case streak</Chip>
                  )}
                </div>
              </div>
              <div className="rap-score">
                <b>{row.convictions}</b>
                <small>guilty</small>
              </div>
            </article>
          ))}
        </div>
      )}
    </Shell>
  );
}
