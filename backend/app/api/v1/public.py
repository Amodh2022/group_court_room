from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Path, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import get_db
from app.models import Case, CaseStatus, Verdict
from app.schemas.case import PublicVerdict
from app.security.rate_limit import RateLimit
from app.security.tokens import hash_token
from app.services import errors, serializers
from app.templates.share_card import render_og_page, render_share_card

router = APIRouter(prefix="/public", tags=["public"])

DbDep = Annotated[Session, Depends(get_db)]


@router.get(
    "/verdicts/{token}",
    response_model=PublicVerdict,
    dependencies=[Depends(RateLimit("public_reads"))],
)
def public_verdict(
    token: Annotated[str, Path(min_length=8, max_length=128)], db: DbDep
) -> PublicVerdict:
    """The only endpoint reachable without a credential or an invite.

    Returns a hand-built DTO containing the generated verdict and nothing else:
    no accusation, no defence body, no participant records, no account data.
    """
    case, verdict = _load_shared_verdict(db, token)
    return serializers.public_verdict(verdict, case)


def _load_shared_verdict(db: Session, token: str) -> tuple[Case, Verdict]:
    case = db.execute(
        select(Case).where(
            Case.share_token_hash == hash_token(token),
            Case.deleted_at.is_(None),
            Case.share_revoked_at.is_(None),
            Case.status == CaseStatus.completed,
        )
    ).scalar_one_or_none()
    if case is None:
        raise errors.invalid_link()
    verdict = db.execute(select(Verdict).where(Verdict.case_id == case.id)).scalar_one_or_none()
    if verdict is None:
        raise errors.invalid_link()
    return case, verdict


@router.get(
    "/verdicts/{token}/card.svg",
    response_class=Response,
    dependencies=[Depends(RateLimit("public_reads"))],
    include_in_schema=False,
)
def verdict_card(
    token: Annotated[str, Path(min_length=8, max_length=128)], db: DbDep
) -> Response:
    """Share image, rendered from one reusable template per verdict."""
    _, verdict = _load_shared_verdict(db, token)
    return Response(
        content=render_share_card(verdict.result or {}),
        media_type="image/svg+xml",
        headers={"Cache-Control": "public, max-age=3600"},
    )


@router.get(
    "/verdicts/{token}/preview",
    response_class=Response,
    dependencies=[Depends(RateLimit("public_reads"))],
    include_in_schema=False,
)
def verdict_og_preview(
    token: Annotated[str, Path(min_length=8, max_length=128)], db: DbDep
) -> Response:
    """Crawler-facing HTML with Open Graph tags; humans are bounced to the SPA."""
    _, verdict = _load_shared_verdict(db, token)
    settings = get_settings()
    web = settings.web_base_url.rstrip("/")
    html = render_og_page(
        result=verdict.result or {},
        canonical_url=f"{web}/verdict/{token}",
        card_url=f"{settings.api_base_url.rstrip('/')}/api/v1/public/verdicts/{token}/card.svg",
    )
    return Response(content=html, media_type="text/html")
