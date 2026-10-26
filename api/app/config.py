"""
Central configuration, read from environment / .env.

Everything that a teammate might reasonably want to change without editing
Python lives here: which data backend to use, the score weights and caps, the
report-match radius, the verification thresholds. All of it is overridable by
an environment variable, so tuning against A's and B's real data is an `.env`
edit and a restart, not a code change. See INTEGRATION.md.
"""
import json
import os

from dotenv import load_dotenv

load_dotenv()


def _float(name, default):
    try:
        return float(os.getenv(name, "") or default)
    except ValueError:
        return float(default)


def _int(name, default):
    try:
        return int(os.getenv(name, "") or default)
    except ValueError:
        return int(default)


def _first(names, default=""):
    """First of these env vars that is set.

    The team's root .env.example and this service grew different spellings for
    the same secret (WATSONX_API_KEY vs WATSONX_APIKEY). Accepting both means
    filling in either file works, instead of failing silently with the model
    switched off. The team's documented name is listed first.
    """
    for name in names:
        value = os.getenv(name, "")
        if value:
            return value
    return default


def _json(name, default):
    raw = os.getenv(name, "")
    if not raw:
        return default
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        print(f"[config] {name} is not valid JSON; using the default")
        return default


class Settings:
    """
    Every value is read in __init__, not in the class body, so `Settings()`
    picks up the current environment. That lets a test build a fresh Settings
    with patched env instead of reloading this module - a reload would swap the
    object that every router already holds a reference to.
    """

    def __init__(self):
        # --- Supabase (from Member A) --------------------------------------
        # If SUPABASE_URL is blank, the app runs in OFFLINE mode with an
        # in-memory database so you can build without A.
        self.SUPABASE_URL = os.getenv("SUPABASE_URL", "")
        # Root .env.example calls it SUPABASE_SERVICE_ROLE_KEY; accept both.
        self.SUPABASE_SERVICE_KEY = _first(
            ["SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SERVICE_KEY"])
        self.SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET", "")
        # Where the project publishes its ES256 public keys. Derived from
        # SUPABASE_URL unless overridden.
        self.SUPABASE_JWKS_URL = os.getenv("SUPABASE_JWKS_URL", "")
        # Escape hatch: force the dev bypass on even with a project configured.
        self.AUTH_BYPASS = os.getenv("AUTH_BYPASS", "") in ("1", "true", "yes")

        # Force a backend regardless of the keys: "auto"|"memory"|"supabase".
        # Use "memory" to demo with keys present; "supabase" to make a missing
        # key a loud failure instead of a silent fallback to in-memory data.
        self.REPO_BACKEND = os.getenv("REPO_BACKEND", "auto").strip().lower()

        # --- watsonx.ai Granite --------------------------------------------
        # If blank, complaint/assistant use a template.
        # Root .env.example calls it WATSONX_API_KEY; accept both.
        self.WATSONX_APIKEY = _first(["WATSONX_API_KEY", "WATSONX_APIKEY"])
        self.WATSONX_PROJECT_ID = os.getenv("WATSONX_PROJECT_ID", "")
        self.WATSONX_URL = os.getenv("WATSONX_URL",
                                     "https://us-south.ml.cloud.ibm.com")
        self.GRANITE_MODEL_ID = os.getenv("GRANITE_MODEL_ID",
                                          "ibm/granite-3-8b-instruct")

        # --- Email -----------------------------------------------------------
        # If RESEND_API_KEY is blank, "sending" is logged to the console.
        self.RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
        self.EMAIL_FROM = os.getenv("EMAIL_FROM", "drishti@example.com")

        # --- Member B's pipeline (section 6) ---------------------------------
        # Where POST /pipeline/run forwards to. Blank = record the run only.
        self.PIPELINE_WEBHOOK_URL = os.getenv("PIPELINE_WEBHOOK_URL", "")
        self.PIPELINE_WEBHOOK_TOKEN = os.getenv("PIPELINE_WEBHOOK_TOKEN", "")
        # Shared secret B presents to POST /ingest. Blank = normal role auth.
        self.INGEST_API_KEY = os.getenv("INGEST_API_KEY", "")

        # --- Tunables (C-14 score, C-12 verification, C-13 matching) ---------
        # A fire_risk at or above this counts as a burn site.
        self.FIRE_RISK_THRESHOLD = _int("FIRE_RISK_THRESHOLD", 60)

        # Score weights; must add up to 100 (reported by check()).
        self.SCORE_WEIGHTS = _json("SCORE_WEIGHTS", {
            "active": 40, "burn": 25, "clear_time": 20, "verified": 15,
        })
        # The value at which each part scores zero.
        self.SCORE_CAPS = _json("SCORE_CAPS", {
            "active_per_km2": 5.0,   # active-site density
            "burn_events": 20,       # burns per month
            "median_days": 60.0,     # days to clear
        })
        # Until complaints have been through a full cycle there is no real
        # clearance history; this stands in for it.
        self.DEFAULT_MEDIAN_DAYS_TO_CLEAR = _float(
            "DEFAULT_MEDIAN_DAYS_TO_CLEAR", 30.0)
        # City areas (km2) for the density part. Extend as cities are added.
        self.CITY_AREA_KM2 = _json("CITY_AREA_KM2",
                                   {"indore": 530.0, "bhopal": 463.0})
        self.FALLBACK_CITY_AREA_KM2 = _float("FALLBACK_CITY_AREA_KM2", 400.0)

        # Verification (C-12)
        self.VERIFY_CLEAR_SCENES = _int("VERIFY_CLEAR_SCENES", 2)
        self.VERIFY_SHRINK_RATIO = _float("VERIFY_SHRINK_RATIO", 0.8)

        # Citizen-report matching (C-13)
        self.REPORT_MATCH_RADIUS_M = _float("REPORT_MATCH_RADIUS_M", 150.0)

        # Browser origins allowed to call this API. "*" is right for local
        # development; set it to the dashboard's origin before the service is
        # public, so a hostile page cannot drive it with a user's token.
        self.ALLOWED_ORIGINS = [
            o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()
        ]

        # --- Dev convenience -------------------------------------------------
        # Dev auth bypass: when there is no JWT secret, treat every request as
        # this role so you can test without real Supabase logins.
        self.DEV_ROLE = os.getenv("DEV_ROLE", "officer")

    @property
    def offline(self) -> bool:
        if self.REPO_BACKEND == "memory":
            return True
        if self.REPO_BACKEND == "supabase":
            return False
        return not self.SUPABASE_URL or not self.SUPABASE_SERVICE_KEY

    @property
    def jwks_url(self) -> str:
        if self.SUPABASE_JWKS_URL:
            return self.SUPABASE_JWKS_URL
        if self.SUPABASE_URL:
            return f"{self.SUPABASE_URL.rstrip('/')}/auth/v1/.well-known/jwks.json"
        return ""

    @property
    def auth_enabled(self) -> bool:
        """Real token checks once a project is configured; bypass otherwise."""
        if self.AUTH_BYPASS:
            return False
        return bool(self.SUPABASE_URL or self.SUPABASE_JWT_SECRET)

    @property
    def granite_on(self) -> bool:
        return bool(self.WATSONX_APIKEY and self.WATSONX_PROJECT_ID)

    def check(self) -> list[str]:
        """Config problems worth warning about at startup. Never raises."""
        problems = []
        total = sum(self.SCORE_WEIGHTS.values())
        if round(total) != 100:
            problems.append(f"SCORE_WEIGHTS sum to {total}, not 100")
        missing = {"active", "burn", "clear_time", "verified"} - set(self.SCORE_WEIGHTS)
        if missing:
            problems.append(f"SCORE_WEIGHTS is missing {sorted(missing)}")
        missing_caps = {"active_per_km2", "burn_events", "median_days"} - set(self.SCORE_CAPS)
        if missing_caps:
            problems.append(f"SCORE_CAPS is missing {sorted(missing_caps)}")
        if self.REPO_BACKEND not in ("auto", "memory", "supabase"):
            problems.append(f"REPO_BACKEND={self.REPO_BACKEND!r} (auto|memory|supabase)")
        if self.REPO_BACKEND == "supabase" and not self.SUPABASE_URL:
            problems.append("REPO_BACKEND=supabase but SUPABASE_URL is blank")
        if not 0 < self.VERIFY_SHRINK_RATIO < 1:
            problems.append("VERIFY_SHRINK_RATIO must be between 0 and 1")
        if "*" in self.ALLOWED_ORIGINS and not self.offline:
            problems.append("ALLOWED_ORIGINS is '*' while pointed at a real "
                            "project; set it to the dashboard's origin")
        return problems


settings = Settings()
