"""Model -> DTO mapping, in one place.

Public and private views are built explicitly from named fields. Adding a
private column to `Case` therefore cannot silently widen any response.
"""

from __future__ import annotations

from app.config import get_settings
from app.db.base import as_aware
from app.models import Case, CaseStatus, JuryVoteKind, Offender, ParticipantRole, Verdict
from app.schemas.case import (
    CaseDetail,
    CaseSummary,
    InvitePreview,
    ParticipantSummary,
    PublicVerdict,
)
from app.schemas.jury import JuryRoom, JuryTally, RapSheetEntry
from app.services import jury_service
from app.services.case_service import participant


def invite_url(raw_token: str) -> str:
    return f"{get_settings().web_base_url.rstrip('/')}/invite/{raw_token}"


def share_url(raw_token: str) -> str:
    return f"{get_settings().web_base_url.rstrip('/')}/verdict/{raw_token}"


def jury_url(raw_token: str) -> str:
    return f"{get_settings().web_base_url.rstrip('/')}/jury/{raw_token}"


def jury_tally(tally: jury_service.Tally) -> JuryTally:
    return JuryTally(
        guilty=tally.guilty,
        not_guilty=tally.not_guilty,
        total=tally.total,
        majority=tally.majority,
        summary=tally.summary(),
    )


def _defendant_fields(case: Case) -> tuple[str | None, bool]:
    defendant = participant(case, ParticipantRole.defendant)
    if defendant is None:
        return None, False
    return defendant.display_name, defendant.submission is not None


def case_summary(case: Case) -> CaseSummary:
    nickname, submitted = _defendant_fields(case)
    return CaseSummary(
        id=case.id,
        title=case.title,
        category=case.category,
        status=case.status,
        created_at=as_aware(case.created_at),
        expires_at=as_aware(case.expires_at),
        defendant_nickname=nickname,
        defense_submitted=submitted,
        verdict_ready=case.status == CaseStatus.completed,
        share_enabled=case.share_is_active,
        jury_count=len(case.jury_votes or []),
    )


def case_detail(
    case: Case,
    *,
    raw_invite_token: str | None = None,
    raw_jury_token: str | None = None,
) -> CaseDetail:
    base = case_summary(case).model_dump()
    return CaseDetail(
        **base,
        accusation=case.accusation,
        failure_reason=case.failure_reason,
        participants=[
            ParticipantSummary(
                role=p.role,
                display_name=p.display_name,
                has_submitted=p.submission is not None,
                joined_at=as_aware(p.joined_at),
            )
            for p in sorted(case.participants, key=lambda p: p.role)
        ],
        invite_url=invite_url(raw_invite_token) if raw_invite_token else None,
        jury_url=jury_url(raw_jury_token) if raw_jury_token else None,
        # The creator sees the running count at any time — they are not voting.
        jury_tally=jury_tally(jury_service.tally(case)),
    )


def invite_preview(case: Case) -> InvitePreview:
    """Safe preview for an unauthenticated visitor."""
    defendant = participant(case, ParticipantRole.defendant)
    creator = participant(case, ParticipantRole.creator)
    return InvitePreview(
        case_title=case.title,
        category=case.category,
        accusation=case.accusation,
        plaintiff_name=(creator.display_name if creator else None) or "The Plaintiff",
        defendant_nickname=defendant.display_name if defendant else None,
        expires_at=as_aware(defendant.invite_expires_at) if defendant else None,
        already_submitted=bool(defendant and defendant.submission),
        verdict_ready=case.status == CaseStatus.completed,
        # The defendant is told how many friends are already in the jury box.
        jury_count=len(case.jury_votes or []),
    )


_PUBLIC_FIELDS = (
    "case_title", "charge", "prosecution_summary", "defense_summary", "verdict",
    "reasoning", "sentence", "judge_roast", "closing_line", "share_caption",
    "jury_note",
)

_GUILTY_RESULTS = {"guilty", "both_guilty"}


def _overruled(verdict_kind: str, majority: str | None) -> bool:
    """Did the judge land opposite a jury that actually reached a majority?"""
    if majority is None or verdict_kind == "insufficient_evidence":
        return False
    judged_guilty = verdict_kind in _GUILTY_RESULTS
    return judged_guilty is not (majority == JuryVoteKind.guilty)


def public_verdict(verdict: Verdict, case: Case | None = None) -> PublicVerdict:
    """Field-by-field allowlist. The raw accusation and defence never appear.

    The jury appears only as counts. Who voted which way is never published,
    including to the creator: the group has to argue about that themselves.
    """
    result = verdict.result or {}
    tally = jury_service.tally(case) if case is not None else None
    kind = str(result.get("verdict", ""))
    return PublicVerdict(
        **{field: str(result.get(field, "")) for field in _PUBLIC_FIELDS},
        jury=jury_tally(tally) if tally and tally.total else None,
        jury_overruled=_overruled(kind, tally.majority) if tally else False,
        decided_at=as_aware(verdict.created_at),
    )


def jury_room(case: Case, *, your_vote: str | None) -> JuryRoom:
    """The juror's view. Both arguments, no account data, no running count."""
    defendant = participant(case, ParticipantRole.defendant)
    creator = participant(case, ParticipantRole.creator)
    submission = defendant.submission if defendant else None
    return JuryRoom(
        case_title=case.title,
        category=case.category,
        accusation=case.accusation,
        defense=submission.body if submission else None,
        plaintiff_name=(creator.display_name if creator else None) or "The Plaintiff",
        defendant_name=(defendant.display_name if defendant else None) or "The Defendant",
        status=case.status,
        jury_open=case.jury_is_open and not CaseStatus(case.status).is_terminal,
        verdict_ready=case.status == CaseStatus.completed,
        your_vote=your_vote,
        tally=jury_tally(jury_service.tally(case)) if your_vote else None,
    )


def _record_title(offender: Offender) -> str:
    """A label for the leaderboard. Earned, not assigned."""
    if offender.current_streak >= 3:
        return "On a Spree"
    if offender.convictions >= 5:
        return "Habitual Offender"
    if offender.convictions >= 3:
        return "Repeat Offender"
    if offender.convictions == 0 and offender.cases_total >= 3:
        return "Unbreakable Alibi"
    if offender.convictions == 0:
        return "Clean Record"
    return "Known to the Court"


def rap_sheet(offenders: list[Offender]) -> list[RapSheetEntry]:
    return [
        RapSheetEntry(
            id=o.id,
            display_name=o.display_name,
            rank=index,
            title=_record_title(o),
            cases_total=o.cases_total,
            convictions=o.convictions,
            acquittals=o.acquittals,
            mistrials=o.mistrials,
            current_streak=o.current_streak,
            longest_streak=o.longest_streak,
            conviction_rate=o.conviction_rate,
            last_verdict_at=as_aware(o.last_verdict_at),
        )
        for index, o in enumerate(offenders, start=1)
    ]
