from fastapi import APIRouter

from ..config import settings

router = APIRouter()


@router.get("/health")
def health():
    """C-03: version + status of DB, watsonx and scheduler, plus the tunables.

    The `config` block reports the values actually in force, so a teammate can
    confirm an .env change took effect without reading the logs.
    """
    return {
        "status": "ok",
        "version": "1.0",
        "db": "supabase" if not settings.offline else "in-memory (offline)",
        "repo_backend": settings.REPO_BACKEND,
        "granite": "on" if settings.granite_on else "template-fallback",
        "email": "resend" if settings.RESEND_API_KEY else "console",
        "auth": "jwt" if settings.SUPABASE_JWT_SECRET else f"dev-bypass ({settings.DEV_ROLE})",
        "pipeline": "webhook" if settings.PIPELINE_WEBHOOK_URL else "not wired",
        "config": {
            "score_weights": settings.SCORE_WEIGHTS,
            "score_caps": settings.SCORE_CAPS,
            "fire_risk_threshold": settings.FIRE_RISK_THRESHOLD,
            "verify_clear_scenes": settings.VERIFY_CLEAR_SCENES,
            "verify_shrink_ratio": settings.VERIFY_SHRINK_RATIO,
            "report_match_radius_m": settings.REPORT_MATCH_RADIUS_M,
            "default_median_days_to_clear": settings.DEFAULT_MEDIAN_DAYS_TO_CLEAR,
            "city_area_km2": settings.CITY_AREA_KM2,
        },
        "config_problems": settings.check(),
    }
