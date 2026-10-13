"""Share-card rendering from a reusable template.

Deliberately SVG built from one template rather than per-case image generation:
every card is the same vector document with text substituted, so rendering costs
nothing per case, needs no headless browser in the request path, and cannot
drift between cases. See README "Share cards" for the optional PNG path.
"""

from __future__ import annotations

from html import escape

_STAMP = {
    "guilty": ("GUILTY", "#E5484D"),
    "not_guilty": ("NOT GUILTY", "#30A46C"),
    "both_guilty": ("BOTH GUILTY", "#F76808"),
    "insufficient_evidence": ("INSUFFICIENT EVIDENCE", "#8E8C99"),
}

WIDTH, HEIGHT = 1200, 630


def _wrap(text: str, width: int, max_lines: int) -> list[str]:
    words, lines, current = text.split(), [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) <= width:
            current = candidate
            continue
        lines.append(current)
        current = word
        if len(lines) == max_lines:
            break
    if current and len(lines) < max_lines:
        lines.append(current)
    if len(lines) == max_lines and len(" ".join(lines)) < len(text):
        lines[-1] = lines[-1][: width - 1].rstrip() + "…"
    return lines


def render_share_card(result: dict) -> str:
    verdict = str(result.get("verdict", "insufficient_evidence"))
    label, colour = _STAMP.get(verdict, _STAMP["insufficient_evidence"])
    title = escape(str(result.get("case_title", "Sue Me")))
    caption_lines = [escape(line) for line in
                     _wrap(str(result.get("share_caption", "")), 46, 2)]
    sentence_lines = [escape(line) for line in
                      _wrap(str(result.get("sentence", "")), 58, 2)]

    caption = "".join(
        f'<tspan x="80" dy="{0 if i == 0 else 56}">{line}</tspan>'
        for i, line in enumerate(caption_lines)
    )
    sentence = "".join(
        f'<tspan x="80" dy="{0 if i == 0 else 34}">{line}</tspan>'
        for i, line in enumerate(sentence_lines)
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" \
viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-label="Verdict: {label}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#1A1523"/>
      <stop offset="100%" stop-color="#2B2438"/>
    </linearGradient>
  </defs>
  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#bg)"/>
  <rect x="24" y="24" width="{WIDTH - 48}" height="{HEIGHT - 48}" rx="24"
        fill="none" stroke="#4B3F63" stroke-width="2"/>

  <text x="80" y="110" font-family="Georgia, 'Times New Roman', serif" font-size="30"
        fill="#C9A227" letter-spacing="6">GROUP CHAT COURT</text>

  <text x="80" y="188" font-family="Georgia, serif" font-size="44" fill="#F5F2FA">{title}</text>

  <g transform="translate(80 250)">
    <rect width="{min(len(label) * 26 + 56, 1040)}" height="92" rx="10"
          fill="none" stroke="{colour}" stroke-width="6" transform="rotate(-3)"/>
    <text x="28" y="62" transform="rotate(-3)" font-family="Georgia, serif"
          font-size="52" font-weight="bold" fill="{colour}" letter-spacing="3">{label}</text>
  </g>

  <text x="80" y="432" font-family="Georgia, serif" font-size="38"
        fill="#E8E2F4">{caption}</text>

  <text x="80" y="536" font-family="Helvetica, Arial, sans-serif" font-size="24"
        fill="#A79EBD">{sentence}</text>

  <text x="80" y="{HEIGHT - 42}" font-family="Helvetica, Arial, sans-serif" font-size="20"
        fill="#6E6383">A comedy game. Not legal advice, not a finding of fact.</text>
</svg>"""


def render_og_page(*, result: dict, canonical_url: str, card_url: str) -> str:
    """Minimal HTML shell carrying Open Graph tags for social crawlers.

    The SPA cannot provide these: crawlers do not execute JavaScript, so the
    preview would be blank. A human hitting this URL is redirected into the app.
    """
    title = escape(f"{result.get('case_title', 'Verdict')} — Sue Me")
    description = escape(str(result.get("share_caption", "The court has ruled.")))[:200]
    canonical = escape(canonical_url, quote=True)
    card = escape(card_url, quote=True)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>{title}</title>
<meta name="description" content="{description}">
<meta property="og:type" content="website">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:image" content="{card}">
<meta property="og:url" content="{canonical}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{title}">
<meta name="twitter:description" content="{description}">
<meta name="twitter:image" content="{card}">
<meta http-equiv="refresh" content="0;url={canonical}">
</head><body><p>Opening the verdict… <a href="{canonical}">Continue</a>.</p></body></html>"""
