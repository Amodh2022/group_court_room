/* The stage machine.
 *
 * A case is not a stack of pages, it is one room the camera moves around in.
 * Nothing here renders: this module owns *where the camera is* and *how long
 * it takes to get there*, so the scene components can stay dumb.
 *
 * Scenes are named after what the room is doing, not after a route, because
 * two different links (a juror's and a defendant's) can put the camera in the
 * same place.
 */

export type Scene =
  | "arrival" // the courthouse, before the case is opened
  | "charge" // the plaintiff's accusation, read aloud
  | "defense" // the accused answers
  | "deliberation" // the floor is open: chat, objections, the jury box
  | "ballot" // the camera turns to face you: vote
  | "rise" // all rise — the push to the bench
  | "verdict" // the stamp
  | "record"; // the rap sheet, and the way out

export const SCENES: Scene[] = [
  "arrival",
  "charge",
  "defense",
  "deliberation",
  "ballot",
  "rise",
  "verdict",
  "record",
];

/** Where the camera sits, and what the room looks like from there.
 *
 *  `z` is a scale, not a translation: the stage is flat layers, so pushing in
 *  means growing the backdrop while the content holds still. `tilt` is degrees
 *  of X-rotation — small numbers only; past about 4deg the text edges crawl.
 */
export interface CameraShot {
  z: number;
  y: number;
  tilt: number;
  /** 0–1. Drives the backdrop's warmth: cold for procedure, hot for judgment. */
  heat: number;
  /** How far the gaze parallax is allowed to push, in px. */
  sway: number;
  /** Milliseconds for the move *into* this shot. */
  ms: number;
}

const SHOTS: Record<Scene, CameraShot> = {
  arrival: { z: 1.14, y: 10, tilt: 1.5, heat: 0.15, sway: 22, ms: 900 },
  charge: { z: 1.0, y: 0, tilt: 0, heat: 0.35, sway: 16, ms: 700 },
  defense: { z: 1.02, y: -6, tilt: -1, heat: 0.3, sway: 16, ms: 700 },
  deliberation: { z: 0.96, y: 0, tilt: 0, heat: 0.45, sway: 10, ms: 700 },
  ballot: { z: 1.08, y: 4, tilt: 0, heat: 0.55, sway: 8, ms: 600 },
  // The one shot that moves fast and hard. Everything else is a drift.
  rise: { z: 1.34, y: -34, tilt: 3, heat: 0.95, sway: 4, ms: 420 },
  verdict: { z: 1.0, y: 0, tilt: 0, heat: 0.8, sway: 14, ms: 900 },
  record: { z: 0.94, y: 0, tilt: 0, heat: 0.25, sway: 18, ms: 700 },
};

export function shotFor(scene: Scene): CameraShot {
  return SHOTS[scene] ?? SHOTS.charge;
}

export function prefersReducedMotion(): boolean {
  try {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

/** The CSS custom properties a shot becomes. Kept in one place so the stage
 *  and any test can agree on the contract without reading the stylesheet. */
export function shotVars(shot: CameraShot, reduced: boolean): Record<string, string> {
  return {
    "--cam-z": reduced ? "1" : String(shot.z),
    "--cam-y": reduced ? "0px" : `${shot.y}px`,
    "--cam-tilt": reduced ? "0deg" : `${shot.tilt}deg`,
    "--cam-heat": String(shot.heat),
    "--cam-sway": reduced ? "0px" : `${shot.sway}px`,
    "--cam-ms": reduced ? "0ms" : `${shot.ms}ms`,
  };
}
