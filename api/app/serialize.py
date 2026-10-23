"""Turn internal site records (shapely geoms, date objects) into JSON-safe
dicts for API responses, and into the flat 'facts' dict Granite needs."""
from .repo import get_repo


def _iso(d):
    return d.isoformat() if hasattr(d, "isoformat") else d


def site_public(site: dict) -> dict:
    pt = site.get("centroid")
    lon = lat = None
    if pt is not None and hasattr(pt, "x"):
        lon, lat = pt.x, pt.y
    return {
        "id": site["id"], "city_id": site["city_id"], "ward_id": site.get("ward_id"),
        "area_m2": site.get("area_m2", 0), "first_seen": _iso(site.get("first_seen")),
        "last_seen": _iso(site.get("last_seen")), "near_water": site.get("near_water", False),
        "status": site.get("status", "active"), "fire_risk": site.get("fire_risk", 0),
        "centroid_lon": lon, "centroid_lat": lat,
    }


def confidence_pct(site_id: str) -> int:
    dets = get_repo().list_detections(site_id)
    if not dets:
        return 80
    return int(round(max(d["confidence"] for d in dets) * 100))


def site_facts(site: dict) -> dict:
    repo = get_repo()
    city = repo.get_city(site["city_id"]) or {}
    ward = None
    if site.get("ward_id"):
        wards = [w for w in repo.list_wards() if w["id"] == site["ward_id"]]
        ward = wards[0] if wards else None
    return {
        "city": city.get("name", site["city_id"]),
        "ward_no": ward["ward_no"] if ward else "-",
        "ward_name": ward["name"] if ward else "unassigned",
        "area_m2": int(site.get("area_m2", 0)),
        "first_seen": _iso(site.get("first_seen")),
        "last_seen": _iso(site.get("last_seen")),
        "growth": site.get("growth", "unknown"),
        "near_water": site.get("near_water", False),
        "fire_risk": site.get("fire_risk", 0),
        "confidence_pct": confidence_pct(site["id"]),
    }
