import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";

import { Chip, ErrorBanner, LoadingCard, Notice, Shell, Disclaimer } from "../components/Chrome";
import { Courtroom } from "../components/Courtroom";
import { ApiError, api, type InvitePreview } from "../lib/api";
import { useCourtroom } from "../lib/courtroom";
import { LIMITS, hasErrors, validateDefense, type DefenseErrors } from "../lib/validation";

type Status = "loading" | "ready" | "invalid" | "submitted" | "closed";

export default function InvitePage() {
  const { token = "" } = useParams();
  const [status, setStatus] = useState<Status>("loading");
  const [preview, setPreview] = useState<InvitePreview | null>(null);

  const [nickname, setNickname] = useState("");
  const [body, setBody] = useState("");
  const [errors, setErrors] = useState<DefenseErrors>({});
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  // The accused is seated in the courtroom once they have answered the charge —
  // before that they are writing, not listening.
  const inCourt = status === "submitted" || status === "closed";
  const courtroom = useCourtroom(inCourt ? { kind: "defendant", token } : null);

  useEffect(() => {
    let cancelled = false;
    api
      .getInvite(token)
      .then((data) => {
        if (cancelled) return;
        setPreview(data);
        setNickname(data.defendant_nickname ?? "");
        setStatus(data.already_submitted ? "closed" : "ready");
      })
      .catch(() => {
        // Every failure reason looks the same here, exactly as the API intends.
        if (!cancelled) setStatus("invalid");
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitError(null);

    const found = validateDefense(nickname, body);
    setErrors(found);
    if (hasErrors(found)) return;

    setSubmitting(true);
    try {
      await api.submitDefense(token, { nickname: nickname.trim(), body: body.trim() });
      setStatus("submitted");
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) {
        setStatus("closed");
      } else if (error instanceof ApiError && error.isInvalidLink) {
        setStatus("invalid");
      } else {
        setSubmitError(
          error instanceof ApiError ? error.message : "Something went wrong. Try again.",
        );
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (status === "loading") {
    return (
      <Shell>
        <LoadingCard label="Loading the summons" />
      </Shell>
    );
  }

  if (status === "invalid") {
    return (
      <Shell>
        <Notice emoji="🔒" title="This summons is no longer valid">
          The link may have expired, been revoked, or never existed. Ask your friend to send
          you a fresh one.
        </Notice>
        <Disclaimer />
      </Shell>
    );
  }

  if (status === "submitted") {
    return (
      <Shell>
        <Notice emoji="📜" title="Your defense is on the record">
          The jury is reading it now. Watch them react below — and object if they get ahead of
          themselves.
        </Notice>
        <Courtroom room={courtroom} title="Your trial" />
        <a className="btn btn-secondary" href="/file" style={{ textDecoration: "none" }}>
          File a case of your own
        </a>
        <Disclaimer />
      </Shell>
    );
  }

  if (status === "closed") {
    return (
      <Shell>
        <Notice emoji="⚖️" title="A defense was already filed">
          This court accepts one defense per case, and it has already been entered.
        </Notice>
        <Courtroom room={courtroom} title="The trial" />
        <Disclaimer />
      </Shell>
    );
  }

  const remaining = LIMITS.defense.max - body.trim().length;

  return (
    <Shell>
      <section className="card">
        <p className="card-label">You have been summoned</p>
        <h2 className="case-title">{preview!.case_title}</h2>
        <p className="meta">
          Filed by {preview!.plaintiff_name}
          {preview!.expires_at
            ? ` · closes ${new Date(preview!.expires_at).toLocaleDateString(undefined, {
                month: "short",
                day: "numeric",
              })}`
            : ""}
        </p>
        <p className="quote" style={{ marginTop: 16 }}>
          “{preview!.accusation}”
        </p>
        {preview!.jury_count > 0 && (
          <div className="row" style={{ marginTop: 16 }}>
            <Chip live>
              {preview!.jury_count} juror{preview!.jury_count === 1 ? "" : "s"} already voting
            </Chip>
          </div>
        )}
      </section>

      <form className="card" onSubmit={handleSubmit} noValidate>
        <p className="card-label">Your defense</p>

        <label htmlFor="nickname">What should the court call you?</label>
        <input
          id="nickname"
          name="nickname"
          value={nickname}
          maxLength={LIMITS.nickname.max + 10}
          autoComplete="nickname"
          aria-invalid={Boolean(errors.nickname)}
          aria-describedby={errors.nickname ? "nickname-error" : undefined}
          onChange={(e) => setNickname(e.target.value)}
        />
        {errors.nickname && (
          <p className="field-error" id="nickname-error">
            {errors.nickname}
          </p>
        )}

        <label htmlFor="defense">State your case</label>
        <textarea
          id="defense"
          name="defense"
          value={body}
          placeholder="Explain yourself. The judge has heard it all before."
          aria-invalid={Boolean(errors.body)}
          aria-describedby={errors.body ? "defense-error" : "defense-counter"}
          onChange={(e) => setBody(e.target.value)}
        />
        <p className="counter" id="defense-counter" data-over={remaining < 0}>
          {remaining} characters left
        </p>
        {errors.body && (
          <p className="field-error" id="defense-error">
            {errors.body}
          </p>
        )}

        {submitError && <ErrorBanner>{submitError}</ErrorBanner>}

        <button className="btn" type="submit" disabled={submitting}>
          {submitting ? "Filing…" : "File my defense"}
        </button>
      </form>

      <Disclaimer>
        Your defense is shown to the judge and summarised in the verdict. Don't put anything
        private in it.
      </Disclaimer>
    </Shell>
  );
}
