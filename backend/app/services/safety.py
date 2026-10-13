"""Safety checks that do not depend on the system prompt.

Two gates:
  * `screen_text` runs BEFORE generation. Serious material never reaches the
    model as a comedy request.
  * `review_output` runs AFTER generation. Even a well-behaved model is not
    trusted to self-police, and a prompt-injected one certainly is not.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# Phrases that mark material a comedy game must not adjudicate. Deliberately
# phrase-level rather than single words: "kill" alone would flag "my roommate
# kills me at Mario Kart".
_SERIOUS_PATTERNS: tuple[tuple[str, str], ...] = (
    (r"\b(kill|hurt|beat|stab|shoot)\s+(him|her|them|you|me|myself|my)\b", "violence"),
    (r"\b(punch|assault|assaulted|abuse|abused|abusive|domestic violence)\b", "violence"),
    (r"\b(rape|raped|molest|molested|sexual assault|groped)\b", "sexual_misconduct"),
    (r"\b(suicide|suicidal|kill myself|end my life|self[- ]harm|cutting myself)\b", "self_harm"),
    (r"\b(stalk|stalking|stalker|harass|harassing|harassment|threaten|threatened|threatening)\b",
     "harassment"),
    (r"\b(overdose|overdosed)\b", "self_harm"),
    (
        (
            r"\b(lawsuit|sue(d|ing)?|court order|restraining order|police report|"
            r"filed charges|lawyer|attorney|custody|divorce|eviction|evicted)\b"
        ),
        "legal",
    ),
    (r"\b(stole|stolen|theft|fraud|scam|scammed|embezzl\w*|blackmail|extort\w*)\b", "crime"),
    (r"\b(racist|racial slur|homophobic|transphobic|antisemit\w*|nazi|slur)\b", "hate"),
    (r"\b(overdosing|cancer|terminal illness|died|dying|funeral|miscarriage)\b", "medical_grief"),
    (r"\b(minor|underage|child)\b.{0,30}\b(sex|nude|naked)\b", "csae"),
)

_COMPILED = tuple((re.compile(pattern, re.IGNORECASE), label) for pattern, label in
                  _SERIOUS_PATTERNS)

# Banned in generated output regardless of what the model thought it was doing.
_OUTPUT_BANNED = re.compile(
    r"\b(kill yourself|kys|you deserve|retard\w*|f[a4]gg\w*|n[i1]gg\w*|"
    r"slut|whore|rape|rapist)\b",
    re.IGNORECASE,
)

# A refusal verdict must stay non-comedic; these would mean the model roasted
# material it was told to decline.
_ROAST_MARKERS = re.compile(r"\b(lol|lmao|guilty as charged|roast|clown|loser)\b", re.IGNORECASE)


JURISDICTION_CHARGE = "Outside this court's jurisdiction"


@dataclass(frozen=True)
class SafetyVerdict:
    allowed: bool
    category: str | None = None

    @property
    def blocked(self) -> bool:
        return not self.allowed


def screen_text(*parts: str) -> SafetyVerdict:
    """Pre-generation gate over accusation + defense + title."""
    haystack = "\n".join(p for p in parts if p)
    for pattern, label in _COMPILED:
        if pattern.search(haystack):
            return SafetyVerdict(allowed=False, category=label)
    return SafetyVerdict(allowed=True)


def screen_chat(text: str) -> SafetyVerdict:
    """Gate for a single chat line.

    Stricter in one way than `screen_text`: it also refuses slurs and
    "you deserve it"-style pile-ons, because chat is the one place a stranger
    holding a link can address a named person directly. Rejected lines are
    never stored or broadcast.
    """
    verdict = screen_text(text)
    if verdict.blocked:
        return verdict
    if _OUTPUT_BANNED.search(text):
        return SafetyVerdict(allowed=False, category="abusive_language")
    return SafetyVerdict(allowed=True)


# Fields that end up on the public share card.
_PUBLISHED_FIELDS = (
    "case_title", "charge", "prosecution_summary", "defense_summary",
    "reasoning", "sentence", "judge_roast", "closing_line", "share_caption",
)

# A span this long is a deliberate quote, not incidental overlap. Short overlaps
# are unavoidable and fine — the judge naturally reuses nouns from the dispute.
VERBATIM_SPAN_WORDS = 6

_WORD = re.compile(r"[a-z0-9']+")


def _shingles(text: str, size: int) -> set[tuple[str, ...]]:
    words = _WORD.findall(text.lower())
    if len(words) < size:
        return set()
    return {tuple(words[i:i + size]) for i in range(len(words) - size + 1)}


def republishes_submission(result: dict, *submissions: str) -> bool:
    """True if published text carries a verbatim span from a private submission.

    The public card shows the judge's write-up. A model that has been
    prompt-injected — or that simply decides to quote — could otherwise dump
    what someone typed in private onto a shareable page.
    """
    published = " ".join(str(result.get(f, "")) for f in _PUBLISHED_FIELDS)
    published_spans = _shingles(published, VERBATIM_SPAN_WORDS)
    if not published_spans:
        return False
    return any(
        published_spans & _shingles(submission, VERBATIM_SPAN_WORDS)
        for submission in submissions
        if submission
    )


def review_output(result: dict, *submissions: str) -> SafetyVerdict:
    """Post-generation gate. Rejects output the model should not have produced."""
    text = "\n".join(str(v) for v in result.values())
    if _OUTPUT_BANNED.search(text):
        return SafetyVerdict(allowed=False, category="unsafe_output")
    if result.get("charge") == JURISDICTION_CHARGE and _ROAST_MARKERS.search(text):
        return SafetyVerdict(allowed=False, category="roasted_serious_case")
    if republishes_submission(result, *submissions):
        return SafetyVerdict(allowed=False, category="republished_submission")
    return SafetyVerdict(allowed=True)



def jurisdiction_refusal(case_title: str) -> dict:
    """The verdict served when pre-screening blocks a case.

    Stored like any other verdict so the creator gets a real, explained answer
    instead of a case stuck in `failed` with no explanation.
    """
    return {
        "case_title": case_title[:100],
        "charge": JURISDICTION_CHARGE,
        "prosecution_summary": "This filing was not read as a comedy submission.",
        "defense_summary": "No defence was argued, because no joke was made.",
        "verdict": "insufficient_evidence",
        "reasoning": (
            "This case raises something more serious than a group-chat squabble. "
            "Sue Me is a comedy game and will not turn it into a punchline."
        ),
        "sentence": "No sentence. Please talk this through properly, or with someone you trust.",
        "judge_roast": "The court has nothing funny to say here, and that is deliberate.",
        "closing_line": "Case dismissed, with respect.",
        "share_caption": "Some cases aren't for the courtroom.",
    }
