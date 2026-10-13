import type { ReactNode } from "react";

/** A scene's title block. Deliberately not a <h1>-per-scene: the case keeps one
 *  heading for the whole visit, so a screen reader is not told the page
 *  changed every time the camera moves. */
export function SceneTitle({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="scene-title">
      <p className="card-label">{label}</p>
      <p className="scene-line">{children}</p>
    </div>
  );
}

/** A panel on the stage. Same ink-and-offset look as `.card`, but transparent
 *  enough that the room reads through it. */
export function ScenePanel({
  children,
  tone,
}: {
  children: ReactNode;
  tone?: "plaintiff" | "defense" | "bench";
}) {
  return (
    <section className="scene-panel" data-tone={tone}>
      {children}
    </section>
  );
}

/** The way forward. One per scene, always in the same place, so the journey has
 *  a rhythm you can learn in two taps. */
export function SceneNext({
  children,
  onClick,
  disabled = false,
}: {
  children: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button className="btn scene-next" type="button" onClick={onClick} disabled={disabled}>
      {children}
    </button>
  );
}

/** How far the *case* has got — not how far the reader has clicked. Purely a
 *  readout: there is nothing to press, because a juror does not advance a case,
 *  the parties do. */
export function SceneProgress({
  step,
  of,
  labels,
}: {
  step: number;
  of: number;
  labels?: readonly string[];
}) {
  const here = labels?.[Math.max(0, Math.min(step, of) - 1)];
  return (
    <div className="scene-progress-wrap">
      <ol className="scene-progress" aria-hidden="true">
        {Array.from({ length: of }, (_, i) => (
          <li key={i} data-state={i < step - 1 ? "done" : i === step - 1 ? "now" : "todo"} />
        ))}
      </ol>
      <p className="scene-progress-label" role="status">
        {here ? `${here} · step ${step} of ${of}` : `Step ${step} of ${of}`}
      </p>
    </div>
  );
}
