import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";

import { api, type AppNotification } from "../lib/api";
import { IconBell } from "./Icons";

export function destinationOf(n: AppNotification): string | null {
  if (n.link_kind === "invite" && n.token) return `/invite/${n.token}`;
  if (n.link_kind === "jury" && n.token) return `/jury/${n.token}`;
  if (n.court_id) return "/courts";
  return null;
}

/** Bell with an unread badge; opens a list of in-app notifications. */
export function NotificationBell() {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [unread, setUnread] = useState(0);
  const [items, setItems] = useState<AppNotification[]>([]);
  const [failed, setFailed] = useState(false);
  const box = useRef<HTMLDivElement>(null);

  const load = useCallback(() => {
    api
      .notifications()
      .then((feed) => {
        setUnread(feed.unread);
        setItems(feed.items);
        setFailed(false);
      })
      .catch(() => setFailed(true));
  }, []);

  useEffect(() => {
    load();
    const timer = window.setInterval(load, 60_000);
    return () => window.clearInterval(timer);
  }, [load]);

  useEffect(() => {
    if (!open) return;
    const close = (event: MouseEvent) => {
      if (box.current && !box.current.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);

  async function toggle() {
    const next = !open;
    setOpen(next);
    if (next) {
      load();
      if (unread > 0) {
        try {
          await api.readAllNotifications();
        } catch {
          /* the list still shows; the badge clears on the next successful read */
        }
      }
    } else {
      setUnread(0);
    }
  }

  return (
    <div className="bell" ref={box}>
      <button
        type="button"
        className="icon-btn"
        aria-label={unread > 0 ? `Notifications, ${unread} unread` : "Notifications"}
        aria-expanded={open}
        onClick={toggle}
      >
        <IconBell />
        {unread > 0 && <span className="badge">{unread > 9 ? "9+" : unread}</span>}
      </button>
      {open && (
        <div className="popover" role="dialog" aria-label="Notifications">
          <p className="card-label">Notifications</p>
          {failed && <p className="meta">Could not load notifications.</p>}
          {!failed && items.length === 0 && <p className="meta">Nothing yet. The court is quiet.</p>}
          <ul className="notif-list">
            {items.map((n) => {
              const to = destinationOf(n);
              return (
                <li key={n.id} data-read={n.read}>
                  <button
                    type="button"
                    disabled={!to}
                    onClick={() => {
                      setOpen(false);
                      if (to) navigate(to);
                    }}
                  >
                    <span>{n.text}</span>
                    <small>{new Date(n.created_at).toLocaleString()}</small>
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </div>
  );
}
