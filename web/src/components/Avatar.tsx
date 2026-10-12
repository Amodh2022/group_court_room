import { Gavel } from "./Icons";

const TINTS = ["", "c1", "c2", "c3", "c4"] as const;

/** A stable tint per person, so a face keeps its colour from message to message. */
export function tintFor(key: string): string {
  let hash = 0;
  for (let i = 0; i < key.length; i += 1) hash = (hash * 31 + key.charCodeAt(i)) >>> 0;
  return TINTS[hash % TINTS.length];
}

export type Presence = "on" | "away" | "off";

/** The reference's squircle participant tile, with an optional presence dot. */
export function Avatar({
  name,
  seed,
  judge = false,
  large = false,
  presence,
}: {
  name: string;
  seed?: string;
  judge?: boolean;
  large?: boolean;
  presence?: Presence;
}) {
  const classes = ["avatar", large ? "lg" : "", judge ? "judge" : tintFor(seed ?? name)]
    .filter(Boolean)
    .join(" ");
  return (
    <span className={classes} aria-hidden="true">
      {judge ? <Gavel /> : (name.trim().slice(0, 1).toUpperCase() || "?")}
      {presence && <span className={`presence${presence === "on" ? "" : ` ${presence}`}`} />}
    </span>
  );
}
