import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

import { ErrorBanner, LoadingCard, PageHeading, Shell } from "../components/Chrome";
import { Avatar } from "../components/Avatar";
import { UserPicker } from "../components/UserPicker";
import { ApiError, api, type Court } from "../lib/api";
import { session } from "../lib/session";

export default function CourtsPage() {
  const navigate = useNavigate();
  const [courts, setCourts] = useState<Court[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    api
      .listCourts()
      .then(setCourts)
      .catch((err) => {
        if (err instanceof ApiError && err.isUnauthorized) {
          session.signOut();
          navigate("/file", { replace: true });
          return;
        }
        setError(err instanceof ApiError ? err.message : "Could not load your courts.");
      });
  }, [navigate]);

  useEffect(() => {
    if (!session.isSignedIn) {
      navigate("/file", { replace: true });
      return;
    }
    load();
  }, [load, navigate]);

  async function run(action: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await action();
      load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  }

  if (courts === null && !error) {
    return (
      <Shell>
        <LoadingCard label="Loading your courts" />
      </Shell>
    );
  }

  return (
    <Shell wide>
      <PageHeading label="Your people" title="Courts">
        <p className="meta">
          A court is a persistent friend group. File a case in one and everyone in it is the jury.
        </p>
      </PageHeading>

      {error && <ErrorBanner>{error}</ErrorBanner>}

      <div className="tile-grid">
        {(courts ?? []).map((court) => (
          <section className="card court-card" key={court.id} aria-label={court.name}>
            <div className="row row-between">
              <h3>{court.name}</h3>
              <span className="chip">Code {court.invite_code}</span>
            </div>
            <ul className="member-list">
              {court.members.map((member) => (
                <li key={member.user_id}>
                  <Avatar name={member.display_name} seed={member.user_id} />
                  <span>
                    <b>{member.display_name}</b>
                    <small>@{member.handle}</small>
                  </span>
                </li>
              ))}
            </ul>
            <label htmlFor={`add-${court.id}`}>Add a friend</label>
            <UserPicker
              id={`add-${court.id}`}
              exclude={court.members.map((m) => m.user_id)}
              onPick={(user) => run(() => api.addCourtMember(court.id, user.user_id))}
            />
          </section>
        ))}

        {creating ? (
          <form
            className="card"
            onSubmit={(event) => {
              event.preventDefault();
              if (!name.trim()) return;
              run(async () => {
                await api.createCourt(name.trim());
                setName("");
                setCreating(false);
              });
            }}
          >
            <p className="card-label">New court</p>
            <label htmlFor="court-name">Court name</label>
            <input
              id="court-name"
              value={name}
              maxLength={40}
              placeholder="The Brunch Bunch"
              onChange={(e) => setName(e.target.value)}
            />
            <button className="btn" type="submit" disabled={busy}>
              Create court
            </button>
          </form>
        ) : (
          <button className="add-tile" type="button" onClick={() => setCreating(true)}>
            <span className="round-icon">+</span>
            <span>New court</span>
          </button>
        )}
      </div>

      <form
        className="card"
        onSubmit={(event) => {
          event.preventDefault();
          if (!code.trim()) return;
          run(async () => {
            await api.joinCourt(code.trim());
            setCode("");
          });
        }}
      >
        <p className="card-label">Have an invite code?</p>
        <label htmlFor="join-code">Invite code</label>
        <input
          id="join-code"
          value={code}
          placeholder="Paste the code from a friend"
          onChange={(e) => setCode(e.target.value)}
        />
        <button className="btn btn-secondary" type="submit" disabled={busy}>
          Join court
        </button>
      </form>
    </Shell>
  );
}
