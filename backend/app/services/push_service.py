"""Push delivery through Firebase Cloud Messaging (HTTP v1).

`social_service.notify` calls `queue()`; the push is sent only after the
surrounding transaction commits, on a background thread, so a slow or failing
FCM never delays or breaks a request. Authenticates with the service-account
key at FIREBASE_CREDENTIALS (no Firebase SDK: a signed JWT is exchanged for an
access token). With no key configured every call is a no-op, so local
development and tests need nothing. The in-app notification stays the source
of truth; pushes are best-effort.
"""

from __future__ import annotations

import json
import logging
import threading
import time
import uuid
from datetime import UTC, datetime, timedelta
from functools import lru_cache

import httpx
from jose import jwt
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import SessionLocal
from app.models import Notification
from app.models.device import DeviceToken

logger = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_token_cache: dict[str, tuple[str, float]] = {}
_PENDING = "pending_pushes"


@lru_cache
def _credentials(path: str) -> dict:
    with open(path) as fh:
        return json.load(fh)


def push_enabled() -> bool:
    return bool(get_settings().firebase_credentials)


def _access_token(creds: dict) -> str:
    cached = _token_cache.get(creds["client_email"])
    if cached and cached[1] > time.time() + 60:
        return cached[0]
    now = int(time.time())
    assertion = jwt.encode(
        {"iss": creds["client_email"], "scope": _SCOPE, "aud": creds["token_uri"],
         "iat": now, "exp": now + 3600},
        creds["private_key"],
        algorithm="RS256",
    )
    res = httpx.post(
        creds["token_uri"],
        data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        timeout=10,
    )
    res.raise_for_status()
    body = res.json()
    _token_cache[creds["client_email"]] = (body["access_token"], now + body["expires_in"])
    return body["access_token"]


def _send(creds: dict, token: str, title: str, body: str, data: dict[str, str]) -> bool:
    """Send one message. Returns False when the token is dead and should be dropped."""
    res = httpx.post(
        f"https://fcm.googleapis.com/v1/projects/{creds['project_id']}/messages:send",
        headers={"Authorization": f"Bearer {_access_token(creds)}"},
        json={"message": {"token": token, "notification": {"title": title, "body": body},
                          "data": data}},
        timeout=10,
    )
    if res.status_code in (404, 410):
        return False
    if res.status_code >= 400:
        logger.warning("push.failed", extra={"status": res.status_code})
    return True


def register_device(db: Session, user_id: uuid.UUID, token: str, platform: str) -> None:
    existing = db.execute(
        select(DeviceToken).where(DeviceToken.token == token)
    ).scalar_one_or_none()
    if existing is not None:
        existing.user_id = user_id  # the phone changed hands: follow the latest sign-in
        existing.platform = platform
        existing.last_seen_at = datetime.now(UTC)
    else:
        db.add(DeviceToken(id=uuid.uuid4(), user_id=user_id, token=token, platform=platform))
    db.commit()


def queue(
    db: Session, user_id: uuid.UUID, text: str, *, kind: str,
    case_id: uuid.UUID | None = None, court_id: uuid.UUID | None = None,
) -> None:
    """Remember a push to send once the current transaction commits."""
    if not push_enabled():
        return
    data = {"kind": kind}
    if case_id:
        data["case_id"] = str(case_id)
    if court_id:
        data["court_id"] = str(court_id)
    db.info.setdefault(_PENDING, []).append((user_id, text, data))


def deliver(items: list[tuple[uuid.UUID, str, dict[str, str]]], *, sender=_send) -> int:
    """Send queued pushes in a fresh session. Honors the per-user daily cap."""
    settings = get_settings()
    if not push_enabled():
        return 0
    creds = _credentials(settings.firebase_credentials)
    since = datetime.now(UTC) - timedelta(days=1)
    sent = 0
    with SessionLocal() as db:
        for user_id, text, data in items:
            recent = db.execute(
                select(func.count()).select_from(Notification).where(
                    Notification.user_id == user_id, Notification.created_at >= since
                )
            ).scalar_one()
            if recent > settings.push_daily_cap:
                continue
            for device in db.execute(
                select(DeviceToken).where(DeviceToken.user_id == user_id)
            ).scalars():
                try:
                    alive = sender(creds, device.token, "Sue Me", text, data)
                except Exception:
                    logger.exception("push.error")
                    continue
                if alive:
                    sent += 1
                else:
                    db.delete(device)
        db.commit()
    return sent


@event.listens_for(Session, "after_commit")
def _flush_pending(session: Session) -> None:
    items = session.info.pop(_PENDING, None)
    if items:
        threading.Thread(target=_safe_deliver, args=(items,), daemon=True).start()


@event.listens_for(Session, "after_rollback")
def _drop_pending(session: Session) -> None:
    session.info.pop(_PENDING, None)


def _safe_deliver(items) -> None:
    try:
        deliver(items)
    except Exception:
        logger.exception("push.deliver_failed")
