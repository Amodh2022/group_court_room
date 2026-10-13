import { useEffect, useRef, type ReactNode } from "react";

import { Dust } from "./Dust";
import {
  prefersReducedMotion,
  shotFor,
  shotVars,
  type Scene,
} from "../../lib/stage";

/** How far each depth layer moves against the gaze, as a fraction of --cam-sway.
 *  Negative means it moves *with* the pointer, which is what sells the
 *  foreground sitting in front of your face. */
const DEPTHS = [0.9, 0.55, 0.3, -0.25];

/** The room. One element, mounted once per case, never unmounted between
 *  scenes — that persistence is the whole point. The backdrop, the motes and
 *  the bench survive every transition; only the content pane swaps.
 *
 *  The gaze is written straight to the DOM as custom properties rather than
 *  through state: pointermove fires far faster than React should re-render,
 *  and the layers are pure CSS transforms off those two numbers.
 */
export function CourtStage({
  scene,
  children,
  hud,
}: {
  scene: Scene;
  children: ReactNode;
  hud?: ReactNode;
}) {
  const root = useRef<HTMLDivElement>(null);
  const pane = useRef<HTMLDivElement>(null);

  // Camera. Written as vars so a scene change is one CSS transition, not a
  // re-mount — React only ever changes the data-scene attribute.
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const vars = shotVars(shotFor(scene), prefersReducedMotion());
    for (const [key, value] of Object.entries(vars))
      el.style.setProperty(key, value);
  }, [scene]);

  // The entrance. Deliberately NOT a `key={scene}` on the pane: a scene's
  // content can be the thing that *decides* the scene — the verdict reveal
  // moves the camera as its beats play — and remounting it would reset that
  // state and loop forever. So the animation is restarted by hand instead,
  // and the children are left alone.
  useEffect(() => {
    const el = pane.current;
    if (!el || prefersReducedMotion()) return;
    el.style.animation = "none";
    void el.offsetWidth; // reflow: without it the re-assignment is coalesced
    el.style.animation = "";
  }, [scene]);

  // Gaze. Pointer on desktop, device tilt on a phone that will give it to us
  // without a permission prompt. Both are decoration: if neither arrives the
  // room simply sits still.
  useEffect(() => {
    if (prefersReducedMotion()) return;
    const el = root.current;
    if (!el) return;

    let x = 0;
    let y = 0;
    let frame = 0;
    const paint = () => {
      frame = 0;
      el.style.setProperty("--gaze-x", x.toFixed(4));
      el.style.setProperty("--gaze-y", y.toFixed(4));
    };
    const schedule = () => {
      if (!frame) frame = window.requestAnimationFrame(paint);
    };

    const onPointer = (event: PointerEvent) => {
      // -1..1 from the centre of the viewport.
      x = (event.clientX / window.innerWidth) * 2 - 1;
      y = (event.clientY / window.innerHeight) * 2 - 1;
      schedule();
    };
    const onTilt = (event: DeviceOrientationEvent) => {
      if (event.gamma == null || event.beta == null) return;
      x = Math.max(-1, Math.min(1, event.gamma / 35));
      y = Math.max(-1, Math.min(1, (event.beta - 45) / 35));
      schedule();
    };

    window.addEventListener("pointermove", onPointer, { passive: true });
    window.addEventListener("deviceorientation", onTilt, { passive: true });
    return () => {
      window.removeEventListener("pointermove", onPointer);
      window.removeEventListener("deviceorientation", onTilt);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <div className="stage" data-scene={scene} ref={root}>
      <div className="stage-camera">
        <div className="stage-breath">
          <div
            className="stage-layer stage-sky"
            style={depth(0)}
            aria-hidden="true"
          />
          <div
            className="stage-layer stage-motes"
            style={depth(1)}
            aria-hidden="true"
          >
            <Dust heat={shotFor(scene).heat} />
          </div>
          <div
            className="stage-layer stage-bench"
            style={depth(2)}
            aria-hidden="true"
          >
            <span className="bench-glow" />
            <span className="bench-arch" />
            <span className="bench-top" />
            <span className="bench-seal">§</span>
          </div>
          <div
            className="stage-layer stage-haze"
            style={depth(3)}
            aria-hidden="true"
          />
        </div>
      </div>

      {hud && <div className="stage-hud">{hud}</div>}

      {/* The pane scrolls; the inner rail is what centres. Centring the
          scroller itself (align-content: center) clips whatever overflows the
          top and puts it out of reach of the scrollbar — a long verdict loses
          its own stamp. An auto-margined flex child centres when it fits and
          simply starts at the top when it does not. */}
      <div className="stage-content" ref={pane}>
        <div className="stage-rail">{children}</div>
      </div>
    </div>
  );
}

function depth(index: number): React.CSSProperties {
  return { "--depth": String(DEPTHS[index] ?? 0) } as React.CSSProperties;
}
