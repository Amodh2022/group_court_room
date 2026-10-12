from __future__ import annotations

from fastapi import HTTPException, status


def http_error(code: int, error: str, message: str) -> HTTPException:
    return HTTPException(status_code=code, detail={"error": error, "message": message})


def not_found(resource: str = "Case") -> HTTPException:
    return http_error(status.HTTP_404_NOT_FOUND, "not_found", f"{resource} not found.")


def invalid_link() -> HTTPException:
    """Deliberately generic.

    A revoked link, an expired link, a deleted case and a token that never
    existed must all look identical, or the response becomes an oracle for
    probing which tokens are real.
    """
    return http_error(
        status.HTTP_404_NOT_FOUND,
        "invalid_link",
        "This link is invalid or has expired.",
    )


def conflict(message: str) -> HTTPException:
    return http_error(status.HTTP_409_CONFLICT, "conflict", message)


def forbidden(message: str = "You do not have access to this case.") -> HTTPException:
    return http_error(status.HTTP_403_FORBIDDEN, "forbidden", message)


def unauthorized(message: str = "Missing or invalid credentials.") -> HTTPException:
    return http_error(401, "unauthorized", message)
