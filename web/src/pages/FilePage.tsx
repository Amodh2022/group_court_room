import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

import { Disclaimer, ErrorBanner, Shell } from "../components/Chrome";
import { UserPicker } from "../components/UserPicker";
import { ApiError, CATEGORIES, api, type Court, type UserHit } from "../lib/api";
import { session } from "../lib/session";
import { LIMITS, hasErrors, validateCase, type CaseErrors } from "../lib/validation";

/** Email and password sign-in / sign-up.
 *
 *  Filing needs an account, because a court has to know whose record it is
 *  keeping. The account follows you across devices.
 */
function SwearIn({ onSignedIn }: { onSignedIn: () => void }) {
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (creating && !name.trim()) {
      setError("The court needs a name to address you by.");
      return;
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) {
      setError("Enter a valid email.");
      return;
    }
    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const result = creating
        ? await api.register(email.trim(), password, name.trim())
        : await api.login(email.trim(), password);
      session.signIn(result.access_token, result.display_name);
      onSignedIn();
    } catch (err) {
      setError(
        err instanceof ApiError ? err.message : "Could not reach the courthouse. Try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <Shell>
      <form className="card" onSubmit={handleSubmit} noValidate style={{ marginTop: 46 }}>
        <p className="card-label">Before you file</p>
        <h2 className="case-title">What should the court call you?</h2>
        <p className="meta">
          This is the name on your filings, and the name on your own record when the judge
          decides you were the problem all along.
        </p>

        {creating && (
          <>
            <label htmlFor="plaintiff-name">Your name</label>
            <input
              id="plaintiff-name"
              value={name}
              maxLength={LIMITS.nickname.max}
              autoComplete="nickname"
              placeholder="Alex"
              onChange={(e) => setName(e.target.value)}
            />
          </>
        )}

        <label htmlFor="account-email">Email</label>
        <input
          id="account-email"
          type="email"
          value={email}
          autoComplete="email"
          onChange={(e) => setEmail(e.target.value)}
        />

        <label htmlFor="account-password">Password</label>
        <input
          id="account-password"
          type="password"
          value={password}
          autoComplete={creating ? "new-password" : "current-password"}
          onChange={(e) => setPassword(e.target.value)}
        />

        {error && <ErrorBanner>{error}</ErrorBanner>}

        <button className="btn" type="submit" disabled={busy}>
          {busy ? "Swearing you in…" : creating ? "Create account" : "Sign in"}
        </button>
        <button
          className="btn btn-ghost"
          type="button"
          onClick={() => {
            setCreating(!creating);
            setError(null);
          }}
        >
          {creating ? "Already have an account? Sign in" : "New here? Create an account"}
        </button>
      </form>
      <Disclaimer />
    </Shell>
  );
}

export default function FilePage() {
  const navigate = useNavigate();
  const [signedIn, setSignedIn] = useState(session.isSignedIn);

  const [title, setTitle] = useState("");
  const [category, setCategory] = useState("group_chat");
  const [accusation, setAccusation] = useState("");
  const [defendant, setDefendant] = useState("");
  const [courts, setCourts] = useState<Court[]>([]);
  const [courtId, setCourtId] = useState("");
  const [accused, setAccused] = useState<UserHit | null>(null);
  const [errors, setErrors] = useState<CaseErrors>({});
  const [busy, setBusy] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  useEffect(() => {
    if (!signedIn) return;
    // Courts are optional; filing works without them.
    api
      .listCourts()
      .then((rows) => setCourts(Array.isArray(rows) ? rows : []))
      .catch(() => undefined);
  }, [signedIn]);

  const court = courts.find((c) => c.id === courtId);

  if (!signedIn) return <SwearIn onSignedIn={() => setSignedIn(true)} />;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitError(null);

    const defendantName = accused ? accused.display_name : defendant;
    const found = validateCase(title, accusation, defendantName);
    setErrors(found);
    if (hasErrors(found)) return;

    setBusy(true);
    try {
      const created = await api.createCase({
        title: title.trim(),
        category,
        accusation: accusation.trim(),
        defendant_nickname: defendantName.trim() || undefined,
        court_id: courtId || undefined,
        accused_user_id: accused?.user_id,
      });
      // The invite and jury tokens are returned exactly once, so the next
      // screen is handed them directly rather than re-fetching the case.
      navigate(`/cases/${created.id}`, {
        state: { inviteUrl: created.invite_url, juryUrl: created.jury_url },
      });
    } catch (err) {
      if (err instanceof ApiError && err.isUnauthorized) {
        session.signOut();
        setSignedIn(false);
        return;
      }
      setSubmitError(err instanceof ApiError ? err.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  }

  const remaining = LIMITS.accusation.max - accusation.trim().length;

  return (
    <Shell>
      <form className="card" onSubmit={handleSubmit} noValidate style={{ marginTop: 34 }}>
        <p className="card-label">New filing</p>
        <h2 className="case-title">What are we arguing about?</h2>

        <label htmlFor="case-title">Case title</label>
        <input
          id="case-title"
          value={title}
          maxLength={LIMITS.title.max}
          placeholder="The Last Pizza Slice"
          aria-invalid={Boolean(errors.title)}
          aria-describedby={errors.title ? "title-error" : undefined}
          onChange={(e) => setTitle(e.target.value)}
        />
        {errors.title && (
          <p className="field-error" id="title-error">
            {errors.title}
          </p>
        )}

        <label htmlFor="category-picker">Category</label>
        <div className="picker" id="category-picker" role="group" aria-label="Category">
          {CATEGORIES.map((option) => (
            <button
              key={option.value}
              type="button"
              aria-pressed={category === option.value}
              onClick={() => setCategory(option.value)}
            >
              <span aria-hidden="true">{option.emoji}</span> {option.label}
            </button>
          ))}
        </div>

        <label htmlFor="accusation">The accusation</label>
        <textarea
          id="accusation"
          value={accusation}
          placeholder="State what they did. The court responds well to specifics and badly to adjectives."
          aria-invalid={Boolean(errors.accusation)}
          aria-describedby={errors.accusation ? "accusation-error" : "accusation-counter"}
          onChange={(e) => setAccusation(e.target.value)}
        />
        <p className="counter" id="accusation-counter" data-over={remaining < 0}>
          {remaining} characters left
        </p>
        {errors.accusation && (
          <p className="field-error" id="accusation-error">
            {errors.accusation}
          </p>
        )}

        {courts.length > 0 && (
          <>
            <label htmlFor="court-select">Court (optional)</label>
            <select
              id="court-select"
              value={courtId}
              onChange={(e) => {
                setCourtId(e.target.value);
                setAccused(null);
              }}
            >
              <option value="">No court. Share links instead</option>
              {courts.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} ({c.members.length})
                </option>
              ))}
            </select>
            <p className="hint">Everyone in the court is seated on the jury automatically.</p>
          </>
        )}

        <label htmlFor="defendant">Who is on trial?</label>
        {accused ? (
          <div className="chosen">
            <b>{accused.display_name}</b>
            <small>@{accused.handle}</small>
            <button type="button" className="chip-x" onClick={() => setAccused(null)}>
              Remove
            </button>
          </div>
        ) : (
          <>
            {court && (
              <div className="picker" role="group" aria-label="Court members">
                {court.members.map((m) => (
                  <button key={m.user_id} type="button" aria-pressed={false} onClick={() => setAccused(m)}>
                    @{m.handle}
                  </button>
                ))}
              </div>
            )}
            <input
              id="defendant"
              value={defendant}
              maxLength={LIMITS.nickname.max}
              placeholder="Their name or nickname"
              aria-invalid={Boolean(errors.defendant)}
              aria-describedby="defendant-hint"
              onChange={(e) => setDefendant(e.target.value)}
            />
            <label htmlFor="accused-search">Or add them by handle</label>
            <UserPicker id="accused-search" onPick={setAccused} />
          </>
        )}
        <p className="hint" id="defendant-hint">
          Use the same name every time and their record follows them from case to case.
        </p>
        {errors.defendant && <p className="field-error">{errors.defendant}</p>}

        {submitError && <ErrorBanner>{submitError}</ErrorBanner>}

        <button className="btn" type="submit" disabled={busy}>
          {busy ? "Filing…" : "File the case"}
        </button>
      </form>

      <Disclaimer>
        Keep it harmless. Anything serious belongs in a real conversation, not a comedy game —
        the court will refuse it.
      </Disclaimer>
    </Shell>
  );
}
