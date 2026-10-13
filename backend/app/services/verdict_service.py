"""Turns a claimed job into a stored verdict.

The LLM never touches database state: it returns a validated value object, and
this module decides what happens to the case.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.base import utcnow
from app.llm.base import (
    LLMError,
    LLMProvider,
    LLMRefusalError,
    VerdictGeneration,
    VerdictRequest,
)
from app.models import Case, CaseStatus, Offender, ParticipantRole, Verdict
from app.prompts.verdict_prompt import PROMPT_VERSION
from app.services import chat_service, jury_service, offender_service, safety, social_service
from app.services.case_service import participant

logger = logging.getLogger(__name__)


class VerdictService:
    def __init__(self, provider: LLMProvider) -> None:
        self._provider = provider

    # -- public API --------------------------------------------------------

    def generate_for_case(self, db: Session, case: Case) -> Verdict:
        """Generate, validate and persist. Idempotent on an existing verdict."""
        existing = db.execute(
            select(Verdict).where(Verdict.case_id == case.id)
        ).scalar_one_or_none()
        if existing is not None:
            self._mark_completed(db, case)
            return existing

        request = self._build_request(db, case)

        screen = safety.screen_text(case.title, request.accusation, request.defense)
        if screen.blocked:
            # Serious material is answered, not silently dropped — but it is
            # answered by us, never by the comedy model.
            logger.warning(
                "verdict.prescreen_blocked",
                extra={"case_id": str(case.id), "category": screen.category},
            )
            # A refusal is not a trial: nobody's record is touched by it.
            return self._store(
                db, case,
                result=safety.jurisdiction_refusal(case.title),
                model_version="safety-prescreen",
                prompt_version=PROMPT_VERSION,
                record=False,
            )

        generation = self._generate_with_retries(request, case_id=case.id)

        result = generation.output.model_dump()
        review = safety.review_output(
            result, request.accusation, request.defense
        )
        if review.blocked:
            logger.warning(
                "verdict.output_blocked",
                extra={"case_id": str(case.id), "category": review.category},
            )
            return self._store(
                db, case,
                result=safety.jurisdiction_refusal(case.title),
                model_version=f"{generation.model_version}+safety-blocked",
                prompt_version=generation.prompt_version,
                record=False,
            )

        return self._store(
            db, case,
            result=result,
            model_version=generation.model_version,
            prompt_version=generation.prompt_version,
        )

    def mark_failed(self, db: Session, case: Case, reason: str) -> None:
        db.execute(
            update(Case)
            .where(Case.id == case.id, Case.status == CaseStatus.generating)
            .values(status=CaseStatus.failed, failure_reason=reason[:120])
        )
        db.commit()
        logger.error("verdict.failed", extra={"case_id": str(case.id), "reason": reason})

    # -- internals ---------------------------------------------------------

    def _build_request(self, db: Session, case: Case) -> VerdictRequest:
        defendant = participant(case, ParticipantRole.defendant)
        creator = participant(case, ParticipantRole.creator)
        if defendant is None or defendant.submission is None:
            raise RuntimeError(f"case {case.id} reached generation without a defense")
        return VerdictRequest(
            title=case.title,
            category=case.category,
            accusation=case.accusation,
            defense=defendant.submission.body,
            plaintiff_name=(creator.display_name if creator else None) or "The Plaintiff",
            defendant_name=defendant.display_name or "The Defendant",
            plaintiff_record=offender_service.priors_line(
                db.get(Offender, case.plaintiff_offender_id)
                if case.plaintiff_offender_id else None
            ),
            defendant_record=offender_service.priors_line(
                db.get(Offender, case.defendant_offender_id)
                if case.defendant_offender_id else None
            ),
            jury_summary=jury_service.tally_for(db, case).summary(),
        )

    def _generate_with_retries(
        self, request: VerdictRequest, *, case_id: uuid.UUID
    ) -> VerdictGeneration:
        settings = get_settings()
        last: Exception | None = None
        for attempt in range(1, settings.llm_max_attempts + 1):
            try:
                return self._provider.generate_verdict(request)
            except LLMRefusalError:
                # The provider's own safety system declined. Retrying the same
                # input would only spend money to be declined again.
                raise
            except LLMError as exc:
                last = exc
                logger.warning(
                    "verdict.attempt_failed",
                    extra={"case_id": str(case_id), "attempt": attempt,
                           "error": type(exc).__name__},
                )
                if not exc.retryable or attempt == settings.llm_max_attempts:
                    raise
        raise last or RuntimeError("generation failed")

    def _store(
        self,
        db: Session,
        case: Case,
        *,
        result: dict,
        model_version: str,
        prompt_version: str,
        record: bool = True,
    ) -> Verdict:
        verdict = Verdict(
            id=uuid.uuid4(),
            case_id=case.id,
            result=result,
            model_version=model_version[:64],
            prompt_version=prompt_version[:32],
        )
        db.add(verdict)
        try:
            db.flush()
        except IntegrityError:
            # A concurrent worker stored one first; theirs wins.
            db.rollback()
            self._mark_completed(db, case)
            return db.execute(
                select(Verdict).where(Verdict.case_id == case.id)
            ).scalar_one()

        db.execute(
            update(Case)
            .where(Case.id == case.id)
            .values(status=CaseStatus.completed, failure_reason=None, updated_at=utcnow())
        )
        # Nobody is excluded: the judge caused this, not a player, so everyone
        # following the case wants to hear it.
        social_service.notify_case(
            db,
            case,
            "verdict_ready",
            f"Judge Byte has ruled on “{case.title}”.",
        )
        db.commit()
        db.refresh(verdict)

        if record:
            # After the commit, and never inside it: a bookkeeping failure must
            # not cost the user the verdict they already waited for.
            try:
                offender_service.record_verdict(db, case, str(result.get("verdict", "")))
            # Records are not worth a lost verdict.
            except Exception:
                logger.exception("record.update_failed", extra={"case_id": str(case.id)})

        chat_service.verdict_in(db, case)

        logger.info(
            "verdict.stored",
            extra={"case_id": str(case.id), "model": model_version,
                   "prompt_version": prompt_version},
        )
        return verdict

    def _mark_completed(self, db: Session, case: Case) -> None:
        db.execute(
            update(Case)
            .where(Case.id == case.id, Case.status != CaseStatus.completed)
            .values(status=CaseStatus.completed)
        )
        db.commit()
