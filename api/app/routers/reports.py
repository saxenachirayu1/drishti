import uuid

from fastapi import APIRouter, Depends
from shapely.geometry import Point

from ..auth import current_user, require
from ..config import settings
from ..errors import api_error
from ..models import CitizenReport
from ..repo import get_repo

router = APIRouter()


@router.post("/reports")
def create_report(body: CitizenReport, user=Depends(current_user)):
    """C-13: a citizen files a report; it is matched straight away."""
    repo = get_repo()
    rid = uuid.uuid4().hex[:8]
    repo.create_report({
        "id": rid, "user_id": user.user_id,
        "location": Point(body.lon, body.lat),
        "photo_url": body.photo_url, "note": body.note,
        "linked_site_id": None, "status": "new",
    })
    return {"id": rid, **_match(rid)}


@router.get("/reports")
def list_reports(status: str = None, user=Depends(require("officer", "admin"))):
    rows = get_repo().list_reports(status=status)
    return [_report_public(r) for r in rows]


@router.post("/reports/{report_id}/match")
def match_report(report_id: str, user=Depends(require("officer", "admin"))):
    """
    C-13: link a citizen report to the nearest site within
    REPORT_MATCH_RADIUS_M (150 m by default), else flag it for admin review as
    a possible new site.
    """
    if not get_repo().get_report(report_id):
        raise api_error(404, "not_found", "No such report")
    return _match(report_id)


def _report_public(r: dict) -> dict:
    loc = r.get("location")
    return {"id": r["id"], "note": r.get("note"), "photo_url": r.get("photo_url"),
            "status": r.get("status"), "linked_site_id": r.get("linked_site_id"),
            "lon": getattr(loc, "x", None), "lat": getattr(loc, "y", None)}


def _match(report_id: str) -> dict:
    """Nearest-site match, shared by create and the explicit re-match."""
    repo = get_repo()
    report = repo.get_report(report_id)
    loc = report.get("location")
    best, best_d = None, float("inf")
    for s in repo.list_sites():
        pt = s.get("centroid")
        if loc is not None and pt is not None and hasattr(pt, "distance"):
            d = pt.distance(loc) * 111_000  # deg -> rough metres
            if d < best_d:
                best, best_d = s, d
    if best and best_d <= settings.REPORT_MATCH_RADIUS_M:
        repo.update_report(report_id, status="matched", linked_site_id=best["id"])
        return {"status": "matched", "site_id": best["id"], "distance_m": round(best_d)}
    repo.update_report(report_id, status="new")
    return {"status": "flagged_for_review",
            "nearest_site_id": best["id"] if best else None,
            "distance_m": round(best_d) if best else None}
