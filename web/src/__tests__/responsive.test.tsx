/** Mobile-first layout guarantees that are cheap to regress and painful to notice. */

import { describe, expect, it } from "vitest";

// Vite's ?raw import gives the stylesheet as a string without touching node:fs,
// which jsdom does not provide here.
import css from "../styles.css?raw";

describe("mobile-first styling", () => {
  it("constrains the column rather than fixing a desktop width", () => {
    expect(css).toMatch(/\.shell\s*{[^}]*max-width:\s*680px/);
    // A bare `width: NNNpx` (as opposed to max-width) would break small screens.
    expect(css).not.toMatch(/(?<![-a-z])width:\s*\d{3,}px/);
  });

  it("uses 16px inputs so iOS Safari does not zoom on focus", () => {
    expect(css).toMatch(/input,\s*textarea[^{]*{[^}]*font-size:\s*16px/);
  });

  it("keeps buttons at a comfortable touch target", () => {
    expect(css).toMatch(/\.btn\s*{[^}]*min-height:\s*48px/);
  });

  it("scales headings fluidly instead of at fixed breakpoints", () => {
    expect(css).toMatch(/font-size:\s*clamp\(/);
  });

  it("is light by default and ships a dark variant", () => {
    // The reference theme is a bright courtroom; dark is an override, not the base.
    expect(css).toMatch(/:root\s*{[^}]*color-scheme:\s*light/);
    expect(css).toMatch(/@media\s*\(prefers-color-scheme:\s*dark\)/);
  });

  it("respects reduced-motion preferences", () => {
    expect(css).toMatch(/@media\s*\(prefers-reduced-motion:\s*reduce\)/);
  });

  it("keeps a visible focus ring for keyboard users", () => {
    expect(css).toMatch(/:focus-visible/);
  });
});
