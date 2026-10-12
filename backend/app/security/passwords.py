"""Password hashing with stdlib scrypt (no extra dependency)."""

from __future__ import annotations

import base64
import hashlib
import hmac
import os

_N, _R, _P = 2**14, 8, 1


def _derive(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    return f"scrypt${base64.b64encode(salt).decode()}${base64.b64encode(_derive(password, salt)).decode()}"


def verify_password(password: str, stored: str | None) -> bool:
    """Constant-time check. Always does the work, even for unknown users."""
    try:
        _, salt_b64, hash_b64 = (stored or _DUMMY).split("$")
        salt, expected = base64.b64decode(salt_b64), base64.b64decode(hash_b64)
    except ValueError:
        return False
    ok = hmac.compare_digest(_derive(password, salt), expected)
    return ok and stored is not None


_DUMMY = hash_password("dummy-password-for-timing")
