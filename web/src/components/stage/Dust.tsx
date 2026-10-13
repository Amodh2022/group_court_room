import { useEffect, useRef } from "react";

import { prefersReducedMotion } from "../../lib/stage";

interface Speck {
  x: number; // 0..1 of width
  y: number; // 0..1 of height
  r: number; // radius in CSS px
  /** Upward drift, fractions of height per second. */
  rise: number;
  /** Horizontal sway, in CSS px either side of x. */
  sway: number;
  /** Radians. Where in its own sway this speck currently is. */
  phase: number;
  /** Radians per second. */
  speed: number;
  alpha: number;
}

const COUNT = 70;

/** The dust in the light. A canvas rather than DOM nodes: seventy elements
 *  each running their own CSS animation is seventy composited layers, and the
 *  whole point is that this never stops moving.
 *
 *  It runs on its own clock, independent of the pointer — sit perfectly still
 *  and the room is still alive, which is the difference between an animation
 *  and a hover effect.
 */
export function Dust({ heat }: { heat: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  // Read inside the loop rather than restarting it when the scene changes.
  const heatRef = useRef(heat);
  heatRef.current = heat;

  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;

    const reduced = prefersReducedMotion();
    const specks: Speck[] = Array.from({ length: COUNT }, () => ({
      x: Math.random(),
      y: Math.random(),
      r: 0.8 + Math.random() * 2.6,
      rise: 0.008 + Math.random() * 0.03,
      sway: 4 + Math.random() * 22,
      phase: Math.random() * Math.PI * 2,
      speed: 0.15 + Math.random() * 0.5,
      alpha: 0.18 + Math.random() * 0.5,
    }));

    let width = 0;
    let height = 0;
    const resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const rect = el.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      el.width = Math.round(width * dpr);
      el.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();

    const observer = new ResizeObserver(resize);
    observer.observe(el);

    let frame = 0;
    let last = performance.now();

    const draw = (now: number) => {
      // Clamped: a tab restored after a minute must not teleport the field.
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      ctx.clearRect(0, 0, width, height);

      const warm = heatRef.current;
      for (const s of specks) {
        if (!reduced) {
          s.y -= s.rise * dt;
          s.phase += s.speed * dt;
          if (s.y < -0.02) {
            // Re-enter from the bottom at a fresh column, so the field never
            // settles into visible columns of repeating dust.
            s.y = 1.02;
            s.x = Math.random();
          }
        }

        const px = s.x * width + Math.sin(s.phase) * s.sway;
        const py = s.y * height;

        // The hotter the room, the more of the dust catches the bench light.
        const ember = s.r > 2.4 && warm > 0.5;
        ctx.fillStyle = ember
          ? `rgba(255, 196, 120, ${s.alpha * warm})`
          : `rgba(255, 255, 255, ${s.alpha})`;
        ctx.beginPath();
        ctx.arc(px, py, s.r, 0, Math.PI * 2);
        ctx.fill();
      }

      frame = window.requestAnimationFrame(draw);
    };

    frame = window.requestAnimationFrame(draw);

    // A background tab should not be burning a rAF loop.
    const onVisibility = () => {
      if (document.hidden) {
        window.cancelAnimationFrame(frame);
        frame = 0;
      } else if (!frame) {
        last = performance.now();
        frame = window.requestAnimationFrame(draw);
      }
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      document.removeEventListener("visibilitychange", onVisibility);
      observer.disconnect();
    };
  }, []);

  return <canvas className="stage-dust" ref={canvas} aria-hidden="true" />;
}
