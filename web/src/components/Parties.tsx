import { Avatar } from "./Avatar";

/** The reference's Plaintiff / Defense trays: a large tile for each side, under a
 *  folder tab. Shown wherever the two sides of a case are introduced. */
export function Parties({
  plaintiff,
  defendant,
  defended = false,
}: {
  plaintiff: string;
  defendant: string;
  /** Whether the accused has answered the charge yet. */
  defended?: boolean;
}) {
  return (
    <div className="parties" data-testid="parties">
      <div className="tray party">
        <span className="tab">Plaintiff</span>
        <Avatar name={plaintiff} large presence="on" />
        <b>{plaintiff}</b>
        <small>Brings the charge</small>
      </div>
      <div className="tray party">
        <span className="tab">Defense</span>
        <Avatar name={defendant} large presence={defended ? "on" : "away"} />
        <b>{defendant}</b>
        <small>{defended ? "Has answered" : "Awaiting a defense"}</small>
      </div>
    </div>
  );
}
