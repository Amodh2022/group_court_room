"""Run one real verdict through whichever LLM provider is configured.

    cd backend
    set -a && . ../.env && set +a
    .venv/bin/python scripts/try_provider.py

Prints which provider answered, how long it took, and the verdict. Never prints
a key. Use it after changing LLM_PROVIDER or a key to find out whether the
setup works before anyone files a case.
"""

from __future__ import annotations

import sys
import time

from app.config import get_settings
from app.llm.base import LLMError, LLMRefusalError, VerdictRequest
from app.llm.factory import get_llm_provider

REQUEST = VerdictRequest(
    title="The Aisle Seat Incident",
    category="travel",
    accusation="They booked the aisle seat on a nine hour flight after I said I get motion sick.",
    defense="You said 'whatever you want'. That is agreement in every language.",
    plaintiff_name="Alex",
    defendant_name="Priya",
    plaintiff_record="First appearance before this court. No prior record.",
    defendant_record="3 prior appearances, 2 convictions. Currently on a 2-case guilty streak.",
    jury_summary="The jury voted 3-1 for guilty.",
)


def main() -> int:
    settings = get_settings()
    try:
        provider = get_llm_provider()
    except RuntimeError as exc:
        print(f"setup problem: {exc}")
        return 2

    print(f"provider: {settings.llm_provider} ({provider.name})")
    for attempt in (1, 2):
        started = time.time()
        try:
            result = provider.generate_verdict(REQUEST)
        except LLMRefusalError as exc:
            print(f"refused by the provider's safety system: {exc}")
            return 1
        except LLMError as exc:
            print(f"failed ({type(exc).__name__}, retryable={exc.retryable}): {exc}")
            return 1
        elapsed = time.time() - started
        label = "first call" if attempt == 1 else "second call"
        print(f"{label}: {elapsed:.1f}s -> {result.output.verdict}")
        if attempt == 2:
            out = result.output
            print(f"  charge:    {out.charge}")
            print(f"  sentence:  {out.sentence}")
            print(f"  roast:     {out.judge_roast}")
            if out.jury_note:
                print(f"  jury note: {out.jury_note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
