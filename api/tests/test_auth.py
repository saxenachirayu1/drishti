"""
Token verification and roles (C-02).

Supabase signs user tokens with ES256, and the role must come from
`app_metadata` - a user can edit their own `user_metadata`, so trusting it
would be a privilege escalation.
"""

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from app import auth
from app.config import settings

HS_SECRET = "test-legacy-secret"


@pytest.fixture
def es256_key(monkeypatch):
    """An EC P-256 keypair, served to the app as if it were the project's JWKS."""
    key = ec.generate_private_key(ec.SECP256R1())
    pub = key.public_key()

    class FakeJWK:
        def __init__(self, k): self.key = k

    class FakeClient:
        def __init__(self, *a, **kw): pass
        def get_signing_key_from_jwt(self, token): return FakeJWK(pub)

    monkeypatch.setattr(auth, "_jwk_client", None)
    monkeypatch.setattr(auth.jwt, "PyJWKClient", FakeClient)
    monkeypatch.setattr(settings, "AUTH_BYPASS", False)
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://proj.supabase.co")
    yield key
    auth._jwk_client = None


def es_token(key, **claims):
    body = {"sub": "user-1", "aud": "authenticated", **claims}
    return jwt.encode(body, key, algorithm="ES256")


# --- the escalation this guards against ------------------------------------
def test_role_comes_from_app_metadata(es256_key):
    tok = es_token(es256_key, app_metadata={"role": "officer"})
    assert auth.current_user(authorization=f"Bearer {tok}").role == "officer"


def test_user_metadata_cannot_grant_a_role(es256_key):
    """A user can edit their own user_metadata, so it must be ignored."""
    tok = es_token(es256_key, user_metadata={"role": "admin"},
                   app_metadata={"role": "citizen"})
    assert auth.current_user(authorization=f"Bearer {tok}").role == "citizen"


def test_user_metadata_alone_gives_only_citizen(es256_key):
    tok = es_token(es256_key, user_metadata={"role": "admin"})
    user = auth.current_user(authorization=f"Bearer {tok}")
    assert user.role == "citizen", "self-set metadata must not become a real role"


def test_an_unknown_role_falls_back_to_citizen(es256_key):
    tok = es_token(es256_key, app_metadata={"role": "superuser"})
    assert auth.current_user(authorization=f"Bearer {tok}").role == "citizen"


def test_service_role_token_is_treated_as_admin(es256_key):
    tok = es_token(es256_key, role="service_role")
    assert auth.current_user(authorization=f"Bearer {tok}").role == "admin"


# --- verification ----------------------------------------------------------
def test_es256_token_is_accepted(es256_key):
    tok = es_token(es256_key, app_metadata={"role": "admin"})
    assert auth.current_user(authorization=f"Bearer {tok}").user_id == "user-1"


def test_a_token_signed_by_someone_else_is_rejected(es256_key):
    other = ec.generate_private_key(ec.SECP256R1())
    tok = jwt.encode({"sub": "mallory", "aud": "authenticated",
                      "app_metadata": {"role": "admin"}}, other, algorithm="ES256")
    with pytest.raises(Exception) as e:
        auth.current_user(authorization=f"Bearer {tok}")
    assert e.value.status_code == 401


def test_hs256_legacy_secret_still_verifies(monkeypatch):
    monkeypatch.setattr(settings, "AUTH_BYPASS", False)
    monkeypatch.setattr(settings, "SUPABASE_URL", "")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", HS_SECRET)
    monkeypatch.setattr(auth, "_jwk_client", None)
    tok = jwt.encode({"sub": "svc", "role": "service_role"}, HS_SECRET, algorithm="HS256")
    assert auth.current_user(authorization=f"Bearer {tok}").role == "admin"


def test_garbage_token_is_401(monkeypatch):
    monkeypatch.setattr(settings, "AUTH_BYPASS", False)
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", HS_SECRET)
    monkeypatch.setattr(settings, "SUPABASE_URL", "")
    with pytest.raises(Exception) as e:
        auth.current_user(authorization="Bearer not.a.token")
    assert e.value.status_code == 401


def test_missing_header_is_401(monkeypatch):
    monkeypatch.setattr(settings, "AUTH_BYPASS", False)
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://proj.supabase.co")
    with pytest.raises(Exception) as e:
        auth.current_user(authorization=None)
    assert e.value.status_code == 401


# --- the offline bypass stays available ------------------------------------
def test_dev_bypass_when_no_project_configured(monkeypatch):
    monkeypatch.setattr(settings, "SUPABASE_URL", "")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", "")
    monkeypatch.setattr(settings, "AUTH_BYPASS", False)
    monkeypatch.setattr(settings, "DEV_ROLE", "officer")
    assert settings.auth_enabled is False
    assert auth.current_user(authorization=None).role == "officer"


def test_auth_turns_on_once_a_project_is_configured(monkeypatch):
    monkeypatch.setattr(settings, "AUTH_BYPASS", False)
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://proj.supabase.co")
    assert settings.auth_enabled is True, "a configured project must enforce tokens"


def test_jwks_url_is_derived_from_the_project_url(monkeypatch):
    monkeypatch.setattr(settings, "SUPABASE_JWKS_URL", "")
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://proj.supabase.co")
    assert settings.jwks_url == "https://proj.supabase.co/auth/v1/.well-known/jwks.json"
