import { useEffect, useState } from "react";

import { api, type UserHit } from "../lib/api";

/** Search people by handle (or exact email) and pick one. */
export function UserPicker({
  id,
  onPick,
  exclude = [],
  placeholder = "Search by @handle or email",
}: {
  id: string;
  onPick: (user: UserHit) => void;
  exclude?: string[];
  placeholder?: string;
}) {
  const [term, setTerm] = useState("");
  const [hits, setHits] = useState<UserHit[]>([]);
  const [searched, setSearched] = useState(false);

  useEffect(() => {
    const trimmed = term.trim().replace(/^@/, "");
    if (trimmed.length < 2) {
      setHits([]);
      setSearched(false);
      return;
    }
    let cancelled = false;
    const timer = window.setTimeout(() => {
      api
        .searchUsers(trimmed)
        .then((rows) => {
          if (cancelled) return;
          setHits(rows);
          setSearched(true);
        })
        .catch(() => !cancelled && setSearched(true));
    }, 250);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [term]);

  const visible = hits.filter((hit) => !exclude.includes(hit.user_id));

  return (
    <div className="picker-search">
      <input
        id={id}
        value={term}
        placeholder={placeholder}
        autoComplete="off"
        onChange={(e) => setTerm(e.target.value)}
      />
      {visible.length > 0 && (
        <ul className="hit-list">
          {visible.map((hit) => (
            <li key={hit.user_id}>
              <button
                type="button"
                onClick={() => {
                  onPick(hit);
                  setTerm("");
                  setHits([]);
                }}
              >
                <b>{hit.display_name}</b>
                <small>@{hit.handle}</small>
              </button>
            </li>
          ))}
        </ul>
      )}
      {searched && visible.length === 0 && term.trim().length >= 2 && (
        <p className="hint">No one found. Try their exact email, or send them a link instead.</p>
      )}
    </div>
  );
}
