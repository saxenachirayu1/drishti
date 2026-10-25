"""
Auth (C-02): verify the Supabase user token and enforce the role per endpoint.

Supabase signs user tokens with an ECC P-256 key, so they are verified against
the project's published JWKS with ES256. The legacy HS256 secret only covers
the old anon/service_role keys, so it is tried second, as a fallback.

The role is read from `app_metadata`, never `user_metadata`: a user can edit
their own `user_metadata` through the Supabase client, so trusting it would let
anyone make themselves an admin. The database writes the real role into
`app_metadata`.

With no Supabase project configured, auth is bypassed and every request is
treated as settings.DEV_ROLE so the API can be run offline.
"""
import logging
from typing import Optional

import jwt
from fastapi import Depends, Header

from .config import settings
from .errors import api_error

log = logging.getLogger("drishti.auth")

ROLES = {"citizen", "officer", "board", "admin"}

_jwk_client = None


class User:
    def __init__(self, user_id, role):
        self.user_id = user_id
        self.role = role


def _jwks():
    """Cached JWKS client for the project's public signing keys."""
    global _jwk_client
    if _jwk_client is None and settings.jwks_url:
        _jwk_client = jwt.PyJWKClient(settings.jwks_url, cache_keys=True)
    return _jwk_client


def _decode(token: str) -> dict:
    """Verify a token, ES256 (user tokens) first, then the legacy HS256 secret."""
    errors = []

    client = _jwks()
    if client is not None:
        try:
            key = client.get_signing_key_from_jwt(token).key
            return jwt.decode(token, key, algorithms=["ES256"],
                              audience="authenticated")
        except Exception as e:
            errors.append(f"ES256: {e}")

    if settings.SUPABASE_JWT_SECRET:
        try:
            return jwt.decode(token, settings.SUPABASE_JWT_SECRET,
                              algorithms=["HS256"], audience="authenticated")
        except Exception as e:
            errors.append(f"HS256: {e}")
        try:
            # service_role / anon keys carry no "authenticated" audience
            return jwt.decode(token, settings.SUPABASE_JWT_SECRET,
                              algorithms=["HS256"], options={"verify_aud": False})
        except Exception as e:
            errors.append(f"HS256(no-aud): {e}")

    log.info("token rejected: %s", "; ".join(errors) or "no verifier configured")
    raise api_error(401, "bad_token", "Invalid or expired token")


def _role_of(payload: dict) -> str:
    """The caller's role. Only app_metadata is trusted (see module docstring)."""
    if payload.get("role") == "service_role":
        # Holding the service key is already full access to the database.
        return "admin"
    role = (payload.get("app_metadata") or {}).get("role")
    return role if role in ROLES else "citizen"


def current_user(authorization: Optional[str] = Header(default=None)) -> User:
    if not settings.auth_enabled:
        return User(user_id="dev-user", role=settings.DEV_ROLE)

    if not authorization or not authorization.lower().startswith("bearer "):
        raise api_error(401, "no_token", "Missing bearer token")

    payload = _decode(authorization.split(" ", 1)[1])
    return User(user_id=payload.get("sub", "unknown"), role=_role_of(payload))


def require(*allowed):
    """Dependency factory: require("officer", "admin")."""
    allowed_set = set(allowed)

    def _guard(user: User = Depends(current_user)) -> User:
        if user.role not in allowed_set:
            raise api_error(403, "forbidden", f"Needs role in {sorted(allowed_set)}")
        return user

    return _guard
