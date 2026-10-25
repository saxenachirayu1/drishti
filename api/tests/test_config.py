"""
The tuning seam: every threshold must actually be honoured, and bad config must
be reported rather than silently ignored.
"""
import pytest

from app.config import Settings, settings
from app.services.scoring import compute_score
from app.services.verification import decide_result


@pytest.fixture
def reload_config(monkeypatch):
    """Build a Settings with these env vars, as a restart would.

    No module reload: that would replace the `settings` object the routers
    already hold, and they would stop seeing the test's patches.
    """
    def _build(**env):
        for k, v in env.items():
            monkeypatch.setenv(k, v)
        return Settings()

    return _build


# --- env overrides reach the logic ----------------------------------------
def test_score_weights_can_be_retuned_without_code(monkeypatch):
    monkeypatch.setattr(settings, "SCORE_WEIGHTS",
                        {"active": 100, "burn": 0, "clear_time": 0, "verified": 0})
    clean = compute_score(active_sites=0, city_area_km2=500, burn_events=99,
                          median_days_to_clear=999, pct_verified_cleared=0)
    assert clean["score"] == 100, "burn/clear_time should carry no weight now"


def test_weights_argument_beats_the_configured_ones():
    a = compute_score(1, 500, 0, 5, 1.0)
    b = compute_score(1, 500, 0, 5, 1.0,
                      weights={"active": 100, "burn": 0, "clear_time": 0, "verified": 0})
    assert a["score"] != b["score"]
    assert b["weights"]["active"] == 100


def test_score_reports_its_parts():
    out = compute_score(1, 500, 0, 5, 1.0)
    assert set(out["parts"]) == {"active", "burn", "clear_time", "verified"}
    assert all(0 <= v <= 1 for v in out["parts"].values())


def test_verification_thresholds_are_configurable(monkeypatch):
    # three empty scenes needed before "cleared" instead of two
    monkeypatch.setattr(settings, "VERIFY_CLEAR_SCENES", 3)
    assert decide_result([3000, 0, 0]) != "cleared"
    assert decide_result([3000, 0, 0, 0]) == "cleared"


def test_shrink_ratio_is_configurable(monkeypatch):
    monkeypatch.setattr(settings, "VERIFY_SHRINK_RATIO", 0.99)
    assert decide_result([3000, 2900]) == "shrinking"
    monkeypatch.setattr(settings, "VERIFY_SHRINK_RATIO", 0.5)
    assert decide_result([3000, 2900]) == "still_present"


def test_report_radius_is_configurable(client, monkeypatch):
    far = {"lon": 75.81, "lat": 22.66}          # ~1.5 km from site-1
    monkeypatch.setattr(settings, "REPORT_MATCH_RADIUS_M", 150.0)
    assert client.post("/reports", json=far).json()["status"] == "flagged_for_review"
    monkeypatch.setattr(settings, "REPORT_MATCH_RADIUS_M", 5000.0)
    assert client.post("/reports", json=far).json()["status"] == "matched"


def test_fire_threshold_is_configurable(client, monkeypatch):
    """site-2 has fire_risk 40, below the default 60."""
    monkeypatch.setattr(settings, "FIRE_RISK_THRESHOLD", 30)
    d = client.post("/assistant/chat",
                    json={"message": "which sites are at risk of burning?",
                          "city_id": "indore"}).json()
    assert "site-2" in d["site_ids"]


# --- parsing and validation ------------------------------------------------
def test_json_env_vars_are_parsed(reload_config):
    s = reload_config(CITY_AREA_KM2='{"indore": 999.0}')
    assert s.CITY_AREA_KM2 == {"indore": 999.0}


def test_malformed_json_falls_back_to_the_default(reload_config):
    s = reload_config(CITY_AREA_KM2="not json{")
    assert s.CITY_AREA_KM2 == {"indore": 530.0, "bhopal": 463.0}


def test_malformed_number_falls_back_to_the_default(reload_config):
    s = reload_config(FIRE_RISK_THRESHOLD="sixty")
    assert s.FIRE_RISK_THRESHOLD == 60


def test_check_flags_weights_that_do_not_sum_to_100(monkeypatch):
    monkeypatch.setattr(settings, "SCORE_WEIGHTS", {"active": 10, "burn": 10,
                                                    "clear_time": 10, "verified": 10})
    assert any("sum to 40" in p for p in settings.check())


def test_check_flags_a_bad_backend_name(monkeypatch):
    monkeypatch.setattr(settings, "REPO_BACKEND", "postgres")
    assert any("REPO_BACKEND" in p for p in settings.check())


def test_check_flags_supabase_without_a_url(monkeypatch):
    monkeypatch.setattr(settings, "REPO_BACKEND", "supabase")
    monkeypatch.setattr(settings, "SUPABASE_URL", "")
    assert any("SUPABASE_URL is blank" in p for p in settings.check())


def test_check_is_quiet_when_config_is_fine():
    assert settings.check() == []


def test_forced_backend_overrides_the_keys(monkeypatch):
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://x.supabase.co")
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", "k")
    monkeypatch.setattr(settings, "REPO_BACKEND", "memory")
    assert settings.offline is True
    monkeypatch.setattr(settings, "REPO_BACKEND", "supabase")
    monkeypatch.setattr(settings, "SUPABASE_URL", "")
    assert settings.offline is False, "supabase forced: must not fall back silently"


# --- health surfaces it ----------------------------------------------------
def test_health_reports_the_config_in_force(client):
    h = client.get("/health").json()
    assert h["config"]["fire_risk_threshold"] == settings.FIRE_RISK_THRESHOLD
    assert h["config"]["score_weights"] == settings.SCORE_WEIGHTS
    assert h["config_problems"] == []
    assert h["repo_backend"] == settings.REPO_BACKEND


# --- the team's shared .env.example uses different spellings ---------------
def test_team_spelling_of_the_watsonx_key_is_accepted(reload_config):
    """Root .env.example says WATSONX_API_KEY; this service grew WATSONX_APIKEY."""
    s = reload_config(WATSONX_API_KEY="k", WATSONX_PROJECT_ID="p")
    assert s.WATSONX_APIKEY == "k"
    assert s.granite_on is True


def test_local_spelling_of_the_watsonx_key_still_works(reload_config):
    s = reload_config(WATSONX_APIKEY="k2", WATSONX_PROJECT_ID="p")
    assert s.WATSONX_APIKEY == "k2"


def test_team_spelling_of_the_supabase_service_key_is_accepted(reload_config):
    s = reload_config(SUPABASE_SERVICE_ROLE_KEY="svc",
                      SUPABASE_URL="https://x.supabase.co",
                      REPO_BACKEND="auto")   # conftest pins this to "memory"
    assert s.SUPABASE_SERVICE_KEY == "svc"
    assert s.offline is False, "real keys present: must not sit in offline mode"


def test_local_spelling_of_the_supabase_service_key_still_works(reload_config):
    s = reload_config(SUPABASE_SERVICE_KEY="svc2",
                      SUPABASE_URL="https://x.supabase.co",
                      REPO_BACKEND="auto")
    assert s.SUPABASE_SERVICE_KEY == "svc2"
