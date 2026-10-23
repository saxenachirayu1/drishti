"""
Auth (C-02): verify the Supabase JWT and enforce the role per endpoint.

If SUPABASE_JWT_SECRET is not set (offline dev), auth is bypassed and every
request is treated as settings.DEV_ROLE so you can test without real logins.
"""
from typing import Optional

import jwt
from fastapi import Depends, Header

from .config import settings
from .errors import api_error

ROLES = {"citizen", "officer", "board", "admin"}


class User:
    def __init__(self, user_id, role):
        self.user_id = user_id
        self.role = role


def current_user(authorization: Optional[str] = Header(default=None)) -> User:
    # Dev bypass
    if not settings.SUPABASE_JWT_SECRET:
        return User(user_id="dev-user", role=settings.DEV_ROLE)

    if not authorization or not authorization.lower().startswith("bearer "):
        raise api_error(401, "no_token", "Missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        payload = jwt.decode(
            token, settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"], audience="authenticated",
        )
    except Exception:
        raise api_error(401, "bad_token", "Invalid or expired token")
    role = payload.get("user_metadata", {}).get("role") or payload.get("role", "citizen")
    return User(user_id=payload.get("sub", "unknown"), role=role)


def require(*allowed):
    """Dependency factory: require(['officer','admin'])."""
    allowed_set = set(allowed)

    def _guard(user: User = Depends(current_user)) -> User:
        if user.role not in allowed_set:
            raise api_error(403, "forbidden", f"Needs role in {sorted(allowed_set)}")
        return user

    return _guard
