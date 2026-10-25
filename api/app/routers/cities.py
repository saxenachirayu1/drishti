from datetime import date

from fastapi import APIRouter, Depends

from ..auth import current_user
from ..config import settings
from ..errors import api_error
from ..repo import get_repo
from ..services.scoring import compute_score

router = APIRouter()


def _median_days_to_clear(repo, city_id: str) -> float:
    """
    Median days from complaint sent to site cleared.

    Computed from real history when there is any, falling back to the
    configured default until complaints have been through a full cycle.
    """
    from statistics import median

    spans = []
    for c in repo.list_complaints(status="sent"):
        site = repo.get_site(c["site_id"])
        if not site or site.get("city_id") != city_id:
            continue
        sent_at, cleared_at = c.get("sent_at"), site.get("cleared_at")
        if sent_at and cleared_at:
            try:
                spans.append((date.fromisoformat(str(cleared_at)[:10]) -
                              date.fromisoformat(str(sent_at)[:10])).days)
            except ValueError:
                continue
    if spans:
        return float(median(spans))
    return settings.DEFAULT_MEDIAN_DAYS_TO_CLEAR


@router.get("/cities/{city_id}/score")
def city_score(city_id: str, user=Depends(current_user)):
    """C-14: monthly cleanliness score with its parts."""
    repo = get_repo()
    if not repo.get_city(city_id):
        raise api_error(404, "not_found", "No such city")
    sites = repo.list_sites(city_id=city_id)
    active = [s for s in sites if s["status"] == "active"]
    cleared = [s for s in sites if s["status"] == "cleared"]
    pct_cleared = (len(cleared) / len(sites)) if sites else 0.0

    # Burn events. Until B sends real fire history this is a proxy: sites
    # whose fire_risk is at or over the threshold. Swap for a count of B's
    # fire_events once they arrive (see INTEGRATION.md, "Member B").
    burns = sum(1 for s in sites
                if s.get("fire_risk", 0) >= settings.FIRE_RISK_THRESHOLD)

    result = compute_score(
        active_sites=len(active),
        city_area_km2=settings.CITY_AREA_KM2.get(
            city_id, settings.FALLBACK_CITY_AREA_KM2),
        burn_events=burns,
        median_days_to_clear=_median_days_to_clear(repo, city_id),
        pct_verified_cleared=pct_cleared,
    )
    period = date.today().strftime("%Y-%m")
    result["city_id"] = city_id
    result["period"] = period
    repo.upsert_score(result)
    return result
