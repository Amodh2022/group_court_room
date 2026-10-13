import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { Disclaimer, Notice } from "../components/Chrome";
import { CourtStage } from "../components/stage/CourtStage";
import { SceneTitle } from "../components/stage/SceneParts";
import { VerdictReveal } from "../components/VerdictReveal";
import type { Scene } from "../lib/stage";
import { api, type PublicVerdict } from "../lib/api";

type Status = "loading" | "ready" | "invalid";

export default function VerdictPage() {
  const { token = "" } = useParams();
  const [status, setStatus] = useState<Status>("loading");
  const [verdict, setVerdict] = useState<PublicVerdict | null>(null);
  const [shareNote, setShareNote] = useState<string | null>(null);
  const [reported, setReported] = useState(false);
  const [revealed, setRevealed] = useState<"rise" | "verdict">("rise");

  const onStage = useCallback((next: "rise" | "verdict") => setRevealed(next), []);

  useEffect(() => {
    let cancelled = false;
    api
      .getPublicVerdict(token)
      .then((data) => {
        if (cancelled) return;
        setVerdict(data);
        setStatus("ready");
        document.title = `${data.case_title} — Sue Me`;
      })
      .catch(() => {
        if (!cancelled) setStatus("invalid");
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  async function handleShare() {
    if (!verdict) return;
    const url = window.location.href;
    const shareData = { title: "Sue Me", text: verdict.share_caption, url };

    if (navigator.share) {
      try {
        await navigator.share(shareData);
        return;
      } catch {
        // User dismissed the sheet, or it is unavailable — fall through to copy.
      }
    }
    try {
      await navigator.clipboard.writeText(`${verdict.share_caption} ${url}`);
      setShareNote("Link copied to your clipboard.");
    } catch {
      setShareNote("Copy this page's address to share it.");
    }
  }

  async function handleReport() {
    try {
      await api.report({ reason: "other", share_token: token });
    } finally {
      // Confirmed either way: a reporter must not learn whether the token resolved.
      setReported(true);
    }
  }

  if (status === "loading") {
    return (
      <CourtStage scene="arrival">
        <SceneTitle label="Approaching the bench">Fetching the verdict…</SceneTitle>
      </CourtStage>
    );
  }

  if (status === "invalid") {
    return (
      <CourtStage scene="record">
        <Notice emoji="🔒" title="This verdict is no longer public">
          The person who shared it may have revoked the link, or it may never have existed.
        </Notice>
        <Link className="btn scene-next" to="/file">
          Start your own case
        </Link>
        <Disclaimer />
      </CourtStage>
    );
  }

  // The camera is wherever the theatre is: pushed at the bench while the beats
  // play, then released the moment the card lands.
  const scene: Scene = revealed;

  return (
    <CourtStage
      scene={scene}
      hud={
        <Link className="chip" to="/">
          Sue&nbsp;Me
        </Link>
      }
    >
      <VerdictReveal verdict={verdict!} onStage={onStage} />

      {revealed === "verdict" && (
        <>
      <button className="btn scene-next" type="button" onClick={handleShare}>
        Share this verdict
      </button>
      {shareNote && (
        <p className="meta" role="status" style={{ textAlign: "center" }}>
          {shareNote}
        </p>
      )}

      <Link className="btn btn-secondary scene-next" to="/file">
        Take your own case to court
      </Link>

      <Disclaimer>{verdict!.disclaimer}</Disclaimer>

      {reported ? (
        <p className="footer-link" role="status">
          Thanks — this has been sent for review.
        </p>
      ) : (
        <button
          className="footer-link"
          type="button"
          onClick={handleReport}
          style={{ background: "none", border: 0, cursor: "pointer", width: "100%" }}
        >
          Report this verdict
        </button>
      )}
        </>
      )}
    </CourtStage>
  );
}
