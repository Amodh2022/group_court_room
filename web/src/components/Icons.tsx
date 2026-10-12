import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement>;

/** The courthouse from the reference's "Court Trial" cards: pediment, columns, steps. */
export function Courthouse(props: IconProps) {
  return (
    <svg viewBox="0 0 48 48" fill="currentColor" aria-hidden="true" {...props}>
      <path d="M24 3 3 14v4h42v-4L24 3Zm0 5.2L36.6 14H11.4L24 8.2Z" />
      <path d="M8 21h6v15H8V21Zm13 0h6v15h-6V21Zm13 0h6v15h-6V21Z" />
      <path d="M4 38h40v4H4v-4Zm-1 5h42v3H3v-3Z" />
    </svg>
  );
}

/** A gavel on its block. */
export function Gavel(props: IconProps) {
  return (
    <svg viewBox="0 0 48 48" fill="currentColor" aria-hidden="true" {...props}>
      <path d="m27.6 4.2 11.2 11.2-5.3 5.3-2-2-7.6 7.6 2 2-5.3 5.3L8.4 22.4l5.3-5.3 2 2 7.6-7.6-2-2 5.3-5.3Z" />
      <path d="m16.3 27.4 4.3 4.3L9.1 43.2a3.05 3.05 0 0 1-4.3-4.3l11.5-11.5Z" />
      <path d="M26 41h18v4H26v-4Z" />
    </svg>
  );
}

/** Raised hand: a juror waiting in the venire. */
export function Hand(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...props}>
      <path d="M8.5 3a1.5 1.5 0 0 1 1.5 1.5V10h1V3.5a1.5 1.5 0 0 1 3 0V10h1V5.5a1.5 1.5 0 0 1 3 0V14c0 4.4-2.7 8-7 8-3 0-4.6-1.7-6-4.2l-2.2-3.9a1.4 1.4 0 0 1 2.4-1.4L7 14V4.5A1.5 1.5 0 0 1 8.5 3Z" />
    </svg>
  );
}

/** Stroked UI icons (24px grid) for nav and round action buttons. */
function Stroke(props: IconProps & { d: string }) {
  const { d, ...rest } = props;
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...rest}
    >
      <path d={d} />
    </svg>
  );
}

export const IconHome = (p: IconProps) => <Stroke d="M4 11.5 12 4l8 7.5V20h-5.5v-5.5h-5V20H4v-8.5Z" {...p} />;
export const IconPlus = (p: IconProps) => <Stroke d="M12 5v14M5 12h14" {...p} />;
export const IconBell = (p: IconProps) => (
  <Stroke d="M6 16.5V11a6 6 0 1 1 12 0v5.5l1.5 1.5h-15L6 16.5ZM10 20.5h4" {...p} />
);
export const IconUsers = (p: IconProps) => (
  <Stroke
    d="M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM2.5 20c.4-3.3 3-5.5 6.5-5.5s6.1 2.2 6.5 5.5M16.5 4.3a3.5 3.5 0 0 1 0 6.4M18 14.8c1.9.6 3.2 2.3 3.5 5.2"
    {...p}
  />
);
export const IconList = (p: IconProps) => <Stroke d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01" {...p} />;
export const IconArrow = (p: IconProps) => <Stroke d="M5 12h14M13 6l6 6-6 6" {...p} />;
export const IconSearch = (p: IconProps) => <Stroke d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14ZM20 20l-4-4" {...p} />;
export const IconLink = (p: IconProps) => (
  <Stroke d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3A4 4 0 0 0 11 18.7l1-1" {...p} />
);
export const IconGavel = (p: IconProps) => (
  <Stroke d="m14 5 5 5-3 3-5-5 3-3ZM11 8 4.5 14.5l3 3L14 11M4 20h9" {...p} />
);
