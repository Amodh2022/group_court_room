import { useEffect, useMemo, useState } from "react";

import { Gavel } from "./Icons";
import { VerdictCard } from "./VerdictCard";
import { VERDICT_LABELS, type JuryVote, type PublicVerdict } from "../lib/api";

interface Beat {
  line: string;
  sub?: string;
  gavel?: boolean;
  ms: number;
}

function prefersReducedMotion(): boolean {
  try {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

function buildBeats(verdict: PublicVerdict, yourVote: JuryVote | null): Beat[] {
  const beats: Beat[] = [
    { line: "All rise.", gavel: true, ms: 1500 },
    {
      line: "The court has reached a decision.",
      sub: verdict.case_title,
      ms: 2000,
    },
  ];

  if (yourVote) {
    beats.push({
      line: `You voted ${VERDICT_LABELS[yourVote].toLowerCase()}.`,
      sub: verdict.jury ? verdict.jury.summary : undefined,
      ms: 2000,
    });
  } else if (verdict.jury && verdict.jury.total > 0) {
    beats.push({ line: verdict.jury.summary, sub: "The judge is not bound by it.", ms: 2000 });
  }

  beats.push({
    line: "Judge Byte will now deliver the verdict.",
    sub: verdict.charge,
    ms: 1800,
  });
  return beats;
}

/** The verdict as theatre: a few beats of anticipation, then the stamp.
 *
 *  Same content as the card either way — the sequence only controls when it
 *  arrives. Skipping, or preferring reduced motion, goes straight to the card.
 */
export function VerdictReveal({
  verdict,
  yourVote = null,
}: {
  verdict: PublicVerdict;
  yourVote?: JuryVote | null;
}) {
  const beats = useMemo(() => buildBeats(verdict, yourVote), [verdict, yourVote]);
  const [index, setIndex] = useState(() => (prefersReducedMotion() ? beats.length : 0));

  useEffect(() => {
    if (index >= beats.length) return;
    const timer = window.setTimeout(() => setIndex((i) => i + 1), beats[index].ms);
    return () => window.clearTimeout(timer);
  }, [index, beats]);

  if (index >= beats.length) {
    return <VerdictCard verdict={verdict} animate />;
  }

  const beat = beats[index];
  return (
    <section className="reveal-stage" aria-live="polite" data-testid="verdict-reveal">
      <div>
        {beat.gavel ? (
          <span className="reveal-gavel" aria-hidden="true">
            <Gavel />
          </span>
        ) : (
          <div className="reveal-beat" aria-hidden="true">
            <span />
            <span />
            <span />
          </div>
        )}

        <p className="reveal-line" key={`line-${index}`}>
          {beat.line}
        </p>
        {beat.sub && (
          <p className="reveal-sub" key={`sub-${index}`}>
            {beat.sub}
          </p>
        )}

        <button
          className="btn btn-ghost"
          type="button"
          onClick={() => setIndex(beats.length)}
          style={{ marginTop: 30 }}
        >
          Skip to the verdict
        </button>
      </div>
    </section>
  );
}
