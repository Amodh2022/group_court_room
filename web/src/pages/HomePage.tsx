import { Link } from "react-router-dom";

import { Gavel, IconArrow, IconGavel, IconLink, IconList, IconUsers } from "../components/Icons";

import { Chip, Disclaimer, Shell } from "../components/Chrome";
import { session } from "../lib/session";

const STEPS = [
  {
    Icon: IconList,
    tint: "var(--tint-1)",
    title: "File the case",
    text: "Describe the disagreement. The pettier, the better.",
  },
  {
    Icon: IconLink,
    tint: "var(--tint-2)",
    title: "Summon the accused",
    text: "Add them by handle, or send one link. They answer for themselves.",
  },
  {
    Icon: IconUsers,
    tint: "var(--tint-3)",
    title: "Seat the jury",
    text: "Pick a court and its members are the jury, or share a link. Everyone votes before anyone sees the ruling.",
  },
  {
    Icon: IconGavel,
    tint: "var(--tint-4)",
    title: "Hear the verdict",
    text: "Judge Byte rules, reads out the priors, and sometimes overrules the lot of you.",
  },
];

export default function HomePage() {
  const signedIn = session.isSignedIn;

  return (
    <Shell>
      <section className="hero hero-panel">
        <div className="hero-top">
          <span className="gavel" aria-hidden="true">
            <Gavel />
          </span>
        </div>
        <h1>
          Settle it
          <br />
          in <strong>court.</strong>
        </h1>
        <p className="lede">
          The group chat argument that will not die, decided by a judge who has no
          jurisdiction, no evidence, and no mercy — with your friends on the jury.
        </p>

        <div className="hero-actions">
          <Link className="hero-cta" to={signedIn ? "/cases" : "/file"}>
            <span>{signedIn ? "My cases" : "Get started"}</span>
            <span className="cta-circle" aria-hidden="true">
              <IconArrow />
            </span>
          </Link>
        </div>
      </section>

      <section className="card">
        <p className="card-label">How it works</p>
        <ol style={{ listStyle: "none", padding: 0, margin: 0 }}>
          {STEPS.map((step, index) => (
            <li key={step.title} className="section" style={{ display: "flex", gap: 14 }}>
              <span aria-hidden="true" className="step-badge" style={{ background: step.tint }}>
                <step.Icon />
              </span>
              <div>
                <h3>
                  Step {index + 1} — {step.title}
                </h3>
                <p>{step.text}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <section className="card">
        <p className="card-label">The court remembers</p>
        <h2 className="case-title" style={{ fontSize: 26 }}>
          Every verdict goes on a permanent record.
        </h2>
        <p className="meta">
          Convictions, acquittals, guilty streaks. The judge reads the priors aloud before
          sentencing, and your group gets a standings table of who keeps losing.
        </p>
        <div className="row" style={{ marginTop: 18 }}>
          <Chip verdict="guilty">4 convictions</Chip>
          <Chip accent>3-case guilty streak</Chip>
          <Chip>Habitual Offender</Chip>
        </div>
      </section>

      <Disclaimer />
    </Shell>
  );
}
