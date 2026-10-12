"""High-entropy capability tokens.

Only the SHA-256 hash is persisted. A database dump therefore does not hand an
attacker working invite or share links. Lookups are by hash, so they stay a
single indexed equality comparison.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets

from app.config import get_settings

_TOKEN_PREFIXES = {"invite": "inv", "share": "shr", "jury": "jry"}


def generate_token(kind: str) -> tuple[str, str]:
    """Return `(raw_token, token_hash)`. The raw token is never stored."""
    prefix = _TOKEN_PREFIXES[kind]
    raw = f"{prefix}_{secrets.token_urlsafe(get_settings().token_bytes)}"
    return raw, hash_token(raw)


def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def tokens_match(raw: str, stored_hash: str) -> bool:
    return hmac.compare_digest(hash_token(raw), stored_hash)
