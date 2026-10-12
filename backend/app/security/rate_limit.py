"""Fixed-window, in-memory rate limiter.

Adequate for a single-process private beta. For multi-instance deployment swap
`_Counter` for Redis — the dependency surface (`RateLimit(...)`) stays the same.
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict

from fastapi import HTTPException, Request, status

from app.config import get_settings


class _Counter:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._buckets: dict[tuple[str, str], tuple[int, float]] = defaultdict(lambda: (0, 0.0))

    def hit(self, key: tuple[str, str], limit: int, window: float) -> tuple[bool, float]:
        now = time.monotonic()
        with self._lock:
            count, window_start = self._buckets[key]
            if now - window_start >= window:
                count, window_start = 0, now
            count += 1
            self._buckets[key] = (count, window_start)
            retry_after = window - (now - window_start)
        return count <= limit, max(retry_after, 0.0)

    def reset(self) -> None:
        with self._lock:
            self._buckets.clear()


counter = _Counter()


def client_key(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


class RateLimit:
    """Dependency factory: `Depends(RateLimit("public_writes"))`."""

    def __init__(self, bucket: str) -> None:
        self.bucket = bucket

    def __call__(self, request: Request) -> None:
        settings = get_settings()
        if not settings.rate_limit_enabled:
            return
        limit = getattr(settings, f"rate_limit_{self.bucket}")
        allowed, retry_after = counter.hit(
            (self.bucket, client_key(request)), limit, settings.rate_limit_window_seconds
        )
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "error": "rate_limited",
                    "message": "Too many requests. The court needs a recess.",
                },
                headers={"Retry-After": str(int(retry_after) + 1)},
            )
