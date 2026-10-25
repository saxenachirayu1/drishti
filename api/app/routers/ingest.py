"""
Ingest (Member B -> this API).

B's pipeline runs as a separate service, so it needs a way to hand over what it
found without touching the database directly. That keeps ward assignment, the
audit log and validation in one place, and means B's schema questions surface
as a 422 naming the field instead of as bad rows in Supabase.

Auth: an officer/admin token, or the shared secret in INGEST_API_KEY presented
as `X-Ingest-Key` (easier for a cron job or a notebook).
"""
import logging

from fastapi import APIRouter, Depends, Header
from shapely.geometry import Point

from ..auth import User, current_user
from ..config import settings
from ..errors import api_error
from ..models import IngestBatch
from ..repo import get_repo
from ..serialize import site_public
from ..services.ward_mapping import assign_site_to_ward

router = APIRouter()
log = logging.getLogger("drishti.ingest")


def ingest_auth(x_ingest_key: str = Header(default=None),
                authorization: str = Header(default=None)) -> str:
    """Accept the shared ingest key, else fall back to normal role auth."""
    if settings.INGEST_API_KEY and x_ingest_key == settings.INGEST_API_KEY:
        return "pipeline"
    try:
        user: User = current_user(authorization=authorization)
    except Exception:
        raise api_error(401, "no_token", "Send X-Ingest-Key or a bearer token")
    if user.role not in ("officer", "admin"):
        raise api_error(403, "forbidden", "Needs the ingest key or an officer/admin token")
    return user.user_id


@router.post("/ingest")
def ingest(batch: IngestBatch, actor: str = Depends(ingest_auth)):
    """
    Take a batch of B's output. Idempotent: posting the same ids again updates
    those rows rather than duplicating them, so B can safely retry.

    Sites are assigned to a ward on the way in (C-05/06), so B never has to
    know about wards.
    """
    repo = get_repo()
    wrote = {"sites": 0, "detections": 0, "fire_events": 0, "wards_assigned": 0}
    unknown_sites = []

    for site_in in batch.sites:
        site = {
            "id": site_in.id,
            "city_id": site_in.city_id,
            "centroid": Point(site_in.centroid_lon, site_in.centroid_lat),
            "area_m2": site_in.area_m2,
            "first_seen": site_in.first_seen,
            "last_seen": site_in.last_seen,
            "near_water": site_in.near_water,
            "fire_risk": site_in.fire_risk,
            "growth": site_in.growth or "unknown",
        }
        # Never let B's status overwrite one the officers have moved on
        # (complaint_sent, cleared, dismissed); only set it for a new site.
        existing = repo.get_site(site_in.id)
        if existing is None:
            site["status"] = site_in.status or "active"
            site["ward_id"] = None
        saved = repo.upsert_site(site)
        wrote["sites"] += 1

        if not saved.get("ward_id"):
            assigned = assign_site_to_ward(saved)
            if assigned:
                repo.update_site(saved["id"], ward_id=assigned["ward_id"])
                wrote["wards_assigned"] += 1

    for det in batch.detections:
        if repo.get_site(det.site_id) is None:
            unknown_sites.append(det.site_id)
            continue
        repo.upsert_detection(det.model_dump(mode="json"))
        wrote["detections"] += 1

    for ev in batch.fire_events:
        if repo.get_site(ev.site_id) is None:
            unknown_sites.append(ev.site_id)
            continue
        payload = ev.model_dump(mode="json")
        repo.upsert_fire_event(payload)
        wrote["fire_events"] += 1

    repo.audit_add(actor, "ingest", "pipeline_run", batch.run_id or "-", wrote)
    if unknown_sites:
        log.warning("ingest referenced unknown sites: %s", sorted(set(unknown_sites)))

    return {"written": wrote,
            "skipped_unknown_site_ids": sorted(set(unknown_sites))}


@router.get("/ingest/example")
def ingest_example(user=Depends(current_user)):
    """A batch in the exact shape /ingest expects, for B to copy."""
    return {
        "run_id": "run-123",
        "sites": [{
            "id": "site-42", "city_id": "indore",
            "centroid_lon": 75.81, "centroid_lat": 22.66,
            "area_m2": 2400, "first_seen": "2026-10-01", "last_seen": "2026-10-20",
            "near_water": False, "fire_risk": 35,
            "growth": "grew ~400 m2 since first seen",
        }],
        "detections": [{
            "id": "det-42-1", "site_id": "site-42", "scene_id": "sc-9",
            "confidence": 0.88, "area_m2": 2400, "detected_on": "2026-10-20",
        }],
        "fire_events": [{
            "id": "fe-42-1", "site_id": "site-42",
            "detected_at": "2026-10-19T06:00:00Z", "frp": 8.2,
            "confidence": 0.7, "source": "VIIRS",
        }],
    }


@router.get("/ingest/sites/{site_id}")
def ingested_site(site_id: str, user=Depends(current_user)):
    """Read back what the API stored, so B can check a round trip."""
    site = get_repo().get_site(site_id)
    if not site:
        raise api_error(404, "not_found", "No such site")
    return site_public(site)
