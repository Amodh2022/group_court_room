import type { ReactNode } from "react";
import { NavLink, Link } from "react-router-dom";

import { session } from "../lib/session";
import { Courthouse, IconHome, IconList, IconPlus, IconUsers } from "./Icons";
import { NotificationBell } from "./Notifications";

const NAV = [
  { to: "/cases", label: "Home", Icon: IconHome },
  { to: "/courts", label: "Courts", Icon: IconUsers },
  { to: "/file", label: "File", Icon: IconPlus },
  { to: "/rap-sheet", label: "Record", Icon: IconList },
];

/** Top bar everywhere; inline nav on tablet, side nav on desktop, bottom nav on phones. */
export function AppBar() {
  const signedIn = session.isSignedIn;
  return (
    <header className="appbar">
      <Link className="appbar-brand" to="/">
        <span className="seal" aria-hidden="true">
          <Courthouse />
        </span>
        <span>Sue Me</span>
      </Link>

      {signedIn ? (
        <>
          <nav className="appnav" aria-label="Main">
            {NAV.map(({ to, label, Icon }) => (
              <NavLink key={to} className="navitem" to={to}>
                <Icon />
                <span>{label}</span>
              </NavLink>
            ))}
          </nav>
          <NotificationBell />
        </>
      ) : (
        <NavLink className="navlink" to="/file">
          Sign in
        </NavLink>
      )}
    </header>
  );
}

export function Shell({ children, wide = false }: { children: ReactNode; wide?: boolean }) {
  const signedIn = session.isSignedIn;
  return (
    <div className={signedIn ? "frame frame-nav" : "frame"}>
      <AppBar />
      <div className={wide ? "shell shell-wide" : "shell"}>
        <main>{children}</main>
      </div>
    </div>
  );
}

/** A round icon button with a small label beneath, like the reference's Send / Receive row. */
export function RoundAction({
  to,
  label,
  children,
  onClick,
  dashed = false,
}: {
  to?: string;
  label: string;
  children: ReactNode;
  onClick?: () => void;
  dashed?: boolean;
}) {
  const cls = dashed ? "round-action dashed" : "round-action";
  const body = (
    <>
      <span className="round-icon">{children}</span>
      <span className="round-label">{label}</span>
    </>
  );
  return to ? (
    <Link className={cls} to={to}>
      {body}
    </Link>
  ) : (
    <button className={cls} type="button" onClick={onClick}>
      {body}
    </button>
  );
}

export function PageHeading({
  label,
  title,
  children,
}: {
  label: string;
  title: string;
  children?: ReactNode;
}) {
  return (
    <div style={{ paddingTop: 34 }}>
      <p className="card-label">{label}</p>
      <h2 className="case-title">{title}</h2>
      {children}
    </div>
  );
}

export function Notice({
  emoji,
  title,
  children,
  action,
}: {
  emoji: string;
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="card notice">
      <span className="emoji" aria-hidden="true">
        {emoji}
      </span>
      <h2>{title}</h2>
      <p>{children}</p>
      {action}
    </div>
  );
}

export function LoadingCard({ label }: { label: string }) {
  return (
    <div className="card" aria-busy="true" aria-live="polite">
      <span className="visually-hidden">{label}</span>
      <div className="skeleton" style={{ height: 16, width: "40%" }} />
      <div className="skeleton" style={{ height: 34, width: "85%", marginTop: 14 }} />
      <div className="skeleton" style={{ height: 96, width: "100%", marginTop: 18 }} />
      <div className="skeleton" style={{ height: 16, width: "60%", marginTop: 16 }} />
    </div>
  );
}

export function ErrorBanner({ children }: { children: ReactNode }) {
  return (
    <p className="error-banner" role="alert">
      {children}
    </p>
  );
}

export function Disclaimer({ children }: { children?: ReactNode }) {
  return (
    <p className="disclaimer">
      {children ??
        "Sue Me is a comedy game. Verdicts are entertainment — not a finding of fact, and not legal advice."}
    </p>
  );
}

export function Chip({
  children,
  accent = false,
  live = false,
  verdict,
}: {
  children: ReactNode;
  accent?: boolean;
  live?: boolean;
  verdict?: string;
}) {
  const classes = ["chip", accent ? "chip-accent" : "", live ? "chip-live" : ""]
    .filter(Boolean)
    .join(" ");
  return (
    <span className={classes} data-verdict={verdict}>
      {children}
    </span>
  );
}

/** A link the user is meant to send to someone, with one-tap copying. */
export function CopyLink({ label, url }: { label: string; url: string }) {
  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
    } catch {
      // Clipboard is unavailable (insecure origin, denied permission). The URL
      // is on screen and selectable, which is the fallback.
    }
  }
  return (
    <div>
      <p className="card-label" style={{ marginBottom: 4 }}>
        {label}
      </p>
      <div className="linkbox">
        <code>{url}</code>
        <button className="btn btn-secondary btn-inline" type="button" onClick={copy}>
          Copy
        </button>
      </div>
    </div>
  );
}
