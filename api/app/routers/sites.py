from typing import Optional

from fastapi import APIRouter, Depends

from ..auth import current_user, require
from ..errors import api_error
from ..repo import get_repo
from ..serialize import site_public

router = APIRouter()


@router.get("/sites")
def list_sites(city_id: Optional[str] = None, near_water: Optional[bool] = None,
               status: Optional[str] = None, ward_id: Optional[str] = None,
               user=Depends(current_user)):
    rows = get_repo().list_sites(city_id=city_id, near_water=near_water,
                                 status=status, ward_id=ward_id)
    return [site_public(s) for s in rows]


@router.get("/sites/{site_id}")
def site_detail(site_id: str, user=Depends(current_user)):
    s = get_repo().get_site(site_id)
    if not s:
        raise api_error(404, "not_found", "No such site")
    return site_public(s)


@router.get("/sites/{site_id}/timeline")
def site_timeline(site_id: str, user=Depends(current_user)):
    """C: detections in date order for A's before/after slider."""
    repo = get_repo()
    if not repo.get_site(site_id):
        raise api_error(404, "not_found", "No such site")
    dets = sorted(repo.list_detections(site_id),
                  key=lambda d: str(d.get("detected_on", "")))
    return [{"detection_id": d["id"], "date": str(d.get("detected_on", "")),
             "area_m2": d["area_m2"], "confidence": d["confidence"],
             "thumb_url": d.get("thumb_url")} for d in dets]


@router.post("/sites/{site_id}/dismiss")
def dismiss_site(site_id: str, body: dict, user=Depends(require("officer", "admin"))):
    repo = get_repo()
    if not repo.get_site(site_id):
        raise api_error(404, "not_found", "No such site")
    repo.update_site(site_id, status="dismissed")
    repo.audit_add(user.user_id, "dismiss", "site", site_id,
                   {"reason": body.get("reason")})
    return {"id": site_id, "status": "dismissed"}
