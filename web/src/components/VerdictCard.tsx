import { VERDICT_LABELS, type JuryTally, type PublicVerdict } from "../lib/api";

export function VerdictStamp({
  verdict,
  animate = false,
}: {
  verdict: PublicVerdict["verdict"];
  animate?: boolean;
}) {
  return (
    <div className="stamp-wrap">
      <span
        className={`stamp${animate ? " stamp-animate" : ""}`}
        data-verdict={verdict}
        data-testid="verdict-stamp"
      >
        {VERDICT_LABELS[verdict] ?? "Verdict"}
      </span>
    </div>
  );
}

/** How the room voted, as a bar. Counts only — never who voted which way. */
export function TallyBar({ tally }: { tally: JuryTally }) {
  const total = Math.max(tally.total, 1);
  const guiltyShare = (tally.guilty / total) * 100;
  return (
    <div className="tally" data-testid="jury-tally">
      <div
        className="tally-bar"
        role="img"
        aria-label={`Jury: ${tally.guilty} guilty, ${tally.not_guilty} not guilty`}
      >
        <i className="is-guilty" style={{ flexBasis: `${guiltyShare}%` }} />
        <i className="is-not-guilty" style={{ flexBasis: `${100 - guiltyShare}%` }} />
      </div>
      <div className="tally-legend">
        <span className="is-guilty">{tally.guilty} guilty</span>
        <span className="is-not-guilty">{tally.not_guilty} not guilty</span>
      </div>
    </div>
  );
}

export function VerdictCard({
  verdict,
  animate = false,
}: {
  verdict: PublicVerdict;
  animate?: boolean;
}) {
  return (
    <article className="card" aria-labelledby="verdict-case-title">
      <p className="card-label">In the matter of</p>
      <h2 className="case-title" id="verdict-case-title">
        {verdict.case_title}
      </h2>
      <p className="meta">{verdict.charge}</p>

      <VerdictStamp verdict={verdict.verdict} animate={animate} />

      {verdict.jury && (
        <div className="section">
          <h3>The jury</h3>
          <p className="meta" style={{ marginTop: 0 }}>
            {verdict.jury.summary}
          </p>
          <TallyBar tally={verdict.jury} />
          {verdict.jury_overruled && (
            <div className="overruled" data-testid="overruled">
              <strong>The jury has been overruled.</strong>
              <span className="meta">
                {verdict.jury_note || "The court thanks the jury for its time, and disagrees."}
              </span>
            </div>
          )}
        </div>
      )}

      <div className="section">
        <h3>Prosecution</h3>
        <p>{verdict.prosecution_summary}</p>
      </div>

      <div className="section">
        <h3>Defense</h3>
        <p>{verdict.defense_summary}</p>
      </div>

      <div className="section">
        <h3>Reasoning</h3>
        <p>{verdict.reasoning}</p>
      </div>

      <div className="section">
        <h3>Sentence</h3>
        <p className="sentence">{verdict.sentence}</p>
      </div>

      <div className="section">
        <h3>The judge adds</h3>
        <p className="roast">“{verdict.judge_roast}”</p>
      </div>

      <p className="closing">{verdict.closing_line}</p>
    </article>
  );
}
