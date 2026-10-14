"""Every number the game pays out, in one file.

Rules live here as data, not scattered through the services that trigger them,
so the balance of the game can be read — and changed — without reading the code
that runs it. `game_service` is the engine; this is the rulebook.
"""

from __future__ import annotations

from dataclasses import dataclass

# --- filing ---------------------------------------------------------------

#: Coins taken when a case is filed. The filing screen quotes this.
CASE_FILING_COST = 10

#: How petty the plaintiff declared the case. The multiplier is applied to the
#: XP the case pays out, so claiming a bin-day dispute is world-ending is a bet.
PETTY_LEVELS: dict[int, str] = {1: "Mildly annoyed", 2: "Genuinely upset", 3: "This is war"}
PETTY_MIN, PETTY_MAX = 1, 3


def petty_multiplier(level: int) -> int:
    return max(PETTY_MIN, min(PETTY_MAX, level))


# --- the verdict ----------------------------------------------------------

#: Base XP to the side the judge found for, before the petty multiplier.
CASE_WIN_XP = 100

#: Base XP to the side the judge found against. Losing is still playing.
CASE_LOSS_XP = 20

#: A mistrial pays both sides this, flat, with no multiplier.
CASE_MISTRIAL_XP = 30

# --- the jury -------------------------------------------------------------

#: What a juror stakes on their own call, paid only if the judge agrees.
JURY_CORRECT_XP = 25

#: The first juror to commit doubles their stake. Voting early is the whole
#: risk: you call it before anyone has shown you which way the room is going.
JURY_FIRST_VOTE_MULTIPLIER = 2

#: Coins for calling it right, regardless of how early.
JURY_CORRECT_COINS = 5

# --- badges ---------------------------------------------------------------

#: Coins paid the first time a badge is earned.
BADGE_COINS = 15


@dataclass(frozen=True)
class BadgeSpec:
    code: str
    name: str
    #: One or two characters for the hexagon on the player card.
    glyph: str
    #: Shown under the badge once earned, or as the way to earn it.
    hint: str


#: Twelve, deliberately: the player card reads "n/12".
BADGES: tuple[BadgeSpec, ...] = (
    BadgeSpec("first_blood", "First blood", "1", "File your first case"),
    BadgeSpec("first_win", "First win", "W", "Win a case"),
    BadgeSpec("hung_jury", "Hung jury", "?", "Have a jury deadlock on your case"),
    BadgeSpec("clean_sweep", "Clean sweep", "3", "Win three cases in a row"),
    BadgeSpec("kingpin", "Kingpin", "K", "Top your court's rap sheet"),
    BadgeSpec("overruled", "Overruled", "!", "Have the judge overrule the jury"),
    BadgeSpec("jury_duty", "Jury duty", "J", "Vote on ten cases"),
    BadgeSpec("oracle", "Oracle", "O", "Call it like the judge five times"),
    BadgeSpec("quick_draw", "Quick draw", "Q", "Be the first juror to vote five times"),
    BadgeSpec("serial_filer", "Serial filer", "S", "File ten cases"),
    BadgeSpec("week_streak", "Regular", "7", "Open the app seven days running"),
    BadgeSpec("defender", "Defender", "D", "Win a case somebody filed against you"),
)

BADGES_BY_CODE: dict[str, BadgeSpec] = {b.code: b for b in BADGES}
BADGE_TOTAL = len(BADGES)


# --- daily quests ---------------------------------------------------------


@dataclass(frozen=True)
class QuestSpec:
    code: str
    text: str
    target: int
    xp: int


#: The three slots the dashboard draws. Seeded per player per day.
DAILY_QUESTS: tuple[QuestSpec, ...] = (
    QuestSpec("vote_jury", "Vote on 2 jury cases", 2, 30),
    QuestSpec("file_case", "File a new case", 1, 50),
    QuestSpec("show_up", "Open the app 1 day in a row", 1, 10),
)

QUESTS_BY_CODE: dict[str, QuestSpec] = {q.code: q for q in DAILY_QUESTS}
