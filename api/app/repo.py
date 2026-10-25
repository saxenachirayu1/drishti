"""
Data layer with two backends:
  - InMemoryRepo : the default. Works with no database so you can build and
                   demo offline. Seeded with 2 cities, wards (real polygons)
                   and sites, so ward-mapping / scoring / verification run for real.
  - SupabaseRepo : used automatically when SUPABASE_URL + SERVICE_KEY are set.
                   Same methods, backed by A's real tables.

Routers only ever call get_repo(); they never know which backend is live.
"""
from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timezone

from shapely.geometry import Point, Polygon, shape

from .config import settings


def _id(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


# ---------------------------------------------------------------------------
# In-memory backend (offline default)
# ---------------------------------------------------------------------------
def _square(cx, cy, half):
    return Polygon([(cx - half, cy - half), (cx + half, cy - half),
                    (cx + half, cy + half), (cx - half, cy + half)])


class InMemoryRepo:
    def __init__(self):
        self.cities = {
            "indore": {"id": "indore", "name": "Indore", "state": "MP", "is_pilot": True},
            "bhopal": {"id": "bhopal", "name": "Bhopal", "state": "MP", "is_pilot": True},
        }
        # wards with real polygons so point-in-polygon works
        self.wards = {
            "w-ind-12": {"id": "w-ind-12", "city_id": "indore", "ward_no": 12,
                         "name": "Rau", "officer_email": "ward12.indore@example.com",
                         "geom": _square(75.80, 22.65, 0.05)},
            "w-ind-5": {"id": "w-ind-5", "city_id": "indore", "ward_no": 5,
                        "name": "Sudama Nagar", "officer_email": "ward5.indore@example.com",
                        "geom": _square(75.85, 22.72, 0.05)},
            "w-bho-8": {"id": "w-bho-8", "city_id": "bhopal", "ward_no": 8,
                        "name": "Kolar", "officer_email": "ward8.bhopal@example.com",
                        "geom": _square(77.40, 23.20, 0.05)},
        }
        self.sites = {
            "site-1": {"id": "site-1", "city_id": "indore", "ward_id": None,
                       "centroid": Point(75.80, 22.65), "area_m2": 3200,
                       "first_seen": date(2026, 8, 14), "last_seen": date(2026, 10, 18),
                       "near_water": True, "status": "active", "fire_risk": 72,
                       "growth": "grew ~900 m2 since first seen"},
            "site-2": {"id": "site-2", "city_id": "indore", "ward_id": None,
                       "centroid": Point(75.85, 22.72), "area_m2": 1100,
                       "first_seen": date(2026, 9, 30), "last_seen": date(2026, 10, 17),
                       "near_water": False, "status": "active", "fire_risk": 40,
                       "growth": "stable"},
            "site-3": {"id": "site-3", "city_id": "bhopal", "ward_id": None,
                       "centroid": Point(77.40, 23.20), "area_m2": 4700,
                       "first_seen": date(2026, 7, 2), "last_seen": date(2026, 10, 19),
                       "near_water": True, "status": "active", "fire_risk": 61,
                       "growth": "grew ~1500 m2 since first seen"},
        }
        self.detections = {
            "det-1": {"id": "det-1", "site_id": "site-1", "scene_id": "sc-1",
                      "confidence": 0.86, "area_m2": 3200, "thumb_url": None,
                      "detected_on": date(2026, 10, 18)},
            "det-3": {"id": "det-3", "site_id": "site-3", "scene_id": "sc-1",
                      "confidence": 0.90, "area_m2": 4700, "thumb_url": None,
                      "detected_on": date(2026, 10, 19)},
        }
        self.fire_events = {
            "fe-1": {"id": "fe-1", "site_id": "site-1",
                     "detected_at": "2026-10-16T06:00:00Z", "frp": 12.5,
                     "confidence": 0.8, "source": "VIIRS"},
        }
        self.complaints = {}
        self.verifications = {}
        # one seeded report ~60 m from site-1, so C-13 matching is demoable
        self.citizen_reports = {
            "rep-1": {"id": "rep-1", "user_id": "citizen-demo",
                      "location": Point(75.8005, 22.6503),
                      "photo_url": None, "note": "Garbage being dumped near the canal",
                      "linked_site_id": None, "status": "new"},
        }
        self.city_scores = {}
        self.pipeline_runs = {}
        self.audit = []

    # --- cities / wards ---
    def list_cities(self):
        return list(self.cities.values())

    def get_city(self, cid):
        return self.cities.get(cid)

    def list_wards(self, city_id=None):
        return [w for w in self.wards.values() if city_id is None or w["city_id"] == city_id]

    def upsert_ward(self, ward):
        self.wards[ward["id"]] = ward

    def ward_containing(self, point: Point, city_id=None):
        """Return the ward whose polygon contains the point (largest overlap fallback)."""
        best = None
        for w in self.wards.values():
            if city_id and w["city_id"] != city_id:
                continue
            g = w.get("geom")
            if g is not None and g.contains(point):
                return w
            if best is None and g is not None:
                best = w  # fallback: first in city
        return best

    # --- sites ---
    def list_sites(self, city_id=None, near_water=None, status=None, ward_id=None):
        rows = list(self.sites.values())
        if city_id:
            rows = [s for s in rows if s["city_id"] == city_id]
        if near_water is not None:
            rows = [s for s in rows if s["near_water"] == near_water]
        if status:
            rows = [s for s in rows if s["status"] == status]
        if ward_id:
            rows = [s for s in rows if s.get("ward_id") == ward_id]
        return rows

    def get_site(self, sid):
        return self.sites.get(sid)

    def update_site(self, sid, **fields):
        self.sites[sid].update(fields)
        return self.sites[sid]

    def upsert_site(self, site):
        """Insert or merge a site. Used by B's ingest."""
        existing = self.sites.get(site["id"])
        if existing:
            existing.update(site)
            return existing
        self.sites[site["id"]] = site
        return site

    # --- detections / fires ---
    def list_detections(self, site_id):
        return [d for d in self.detections.values() if d["site_id"] == site_id]

    def upsert_detection(self, det):
        existing = self.detections.get(det["id"])
        if existing:
            existing.update(det)
            return existing
        self.detections[det["id"]] = det
        return det

    def list_fire_events(self, site_id):
        return [f for f in self.fire_events.values() if f["site_id"] == site_id]

    def upsert_fire_event(self, ev):
        existing = self.fire_events.get(ev["id"])
        if existing:
            existing.update(ev)
            return existing
        self.fire_events[ev["id"]] = ev
        return ev

    # --- complaints ---
    def create_complaint(self, c):
        self.complaints[c["id"]] = c
        return c

    def get_complaint(self, cid):
        return self.complaints.get(cid)

    def update_complaint(self, cid, **fields):
        self.complaints[cid].update(fields)
        return self.complaints[cid]

    def list_complaints(self, ward_id=None, status=None):
        rows = list(self.complaints.values())
        if ward_id:
            rows = [c for c in rows if c.get("ward_id") == ward_id]
        if status:
            rows = [c for c in rows if c["status"] == status]
        return rows

    # --- verifications ---
    def add_verification(self, v):
        self.verifications[v["id"]] = v
        return v

    # --- citizen reports ---
    def create_report(self, r):
        self.citizen_reports[r["id"]] = r
        return r

    def list_reports(self, status=None):
        rows = list(self.citizen_reports.values())
        if status:
            rows = [r for r in rows if r["status"] == status]
        return rows

    def get_report(self, rid):
        return self.citizen_reports.get(rid)

    def update_report(self, rid, **fields):
        self.citizen_reports[rid].update(fields)
        return self.citizen_reports[rid]

    # --- scores ---
    def upsert_score(self, s):
        self.city_scores[(s["city_id"], s["period"])] = s
        return s

    def get_score(self, city_id, period):
        return self.city_scores.get((city_id, period))

    # --- pipeline runs ---
    def create_run(self, r):
        self.pipeline_runs[r["id"]] = r
        return r

    def get_run(self, rid):
        return self.pipeline_runs.get(rid)

    def list_runs(self, status=None, limit=50):
        rows = list(self.pipeline_runs.values())
        if status:
            rows = [r for r in rows if r.get("status") == status]
        return sorted(rows, key=lambda r: str(r.get("queued_at", "")),
                      reverse=True)[:limit]

    def update_run(self, rid, **fields):
        self.pipeline_runs[rid].update(fields)
        return self.pipeline_runs[rid]

    # --- audit ---
    def audit_add(self, actor, action, entity, entity_id, details=None):
        self.audit.append({"actor": actor, "action": action, "entity": entity,
                           "entity_id": entity_id, "at": datetime.now(timezone.utc).isoformat(),
                           "details": details or {}})


# ---------------------------------------------------------------------------
# Supabase backend (used when keys are present). Methods mirror InMemoryRepo.
# Not live-tested here (needs A's real project) — wired against supabase-py.
# ---------------------------------------------------------------------------
class SupabaseRepo:
    def __init__(self):
        from supabase import create_client
        self.sb = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)

    def _t(self, name):
        return self.sb.table(name)

    @staticmethod
    def _hydrate(row):
        """Turn PostGIS GeoJSON columns into shapely geometries.

        The rest of the app (ward mapping, serialize, report matching) works on
        shapely objects, so both backends must hand back the same shapes.
        """
        if not row:
            return row
        for key in ("centroid", "location"):
            val = row.get(key)
            if isinstance(val, (str, dict)):
                try:
                    row[key] = shape(json.loads(val) if isinstance(val, str) else val)
                except Exception:
                    row[key] = None
        return row

    def _hydrate_all(self, rows):
        return [self._hydrate(r) for r in (rows or [])]

    @staticmethod
    def _dehydrate(row):
        """Make a row safe to send to PostgREST.

        Two conversions, done here so every writer gets them rather than each
        caller remembering:
          * shapely geometry -> the EWKT PostGIS accepts
          * date/datetime    -> ISO strings (the JSON encoder cannot take them)
        """
        out = dict(row)
        for key, val in list(out.items()):
            if val is None:
                continue
            if hasattr(val, "wkt"):                      # shapely geometry
                out[key] = f"SRID=4326;{val.wkt}"
            elif isinstance(val, (date, datetime)):      # date before datetime
                out[key] = val.isoformat()
        return out

    def list_cities(self):
        return self._t("cities").select("*").execute().data

    def get_city(self, cid):
        r = self._t("cities").select("*").eq("id", cid).execute().data
        return r[0] if r else None

    def list_wards(self, city_id=None):
        q = self._t("wards").select("*")
        if city_id:
            q = q.eq("city_id", city_id)
        return q.execute().data

    def upsert_ward(self, ward):
        self._t("wards").upsert(ward).execute()

    def ward_containing(self, point, city_id=None):
        """Same signature as InMemoryRepo: takes a shapely Point.

        Uses the PostGIS `ward_for_point` function in supabase/001_schema.sql.
        """
        rows = self.sb.rpc("ward_for_point", {
            "lon": point.x, "lat": point.y, "p_city_id": city_id,
        }).execute().data
        if not rows:
            return None
        return rows[0] if isinstance(rows, list) else rows

    def list_sites(self, city_id=None, near_water=None, status=None, ward_id=None):
        q = self._t("sites").select("*")
        if city_id:
            q = q.eq("city_id", city_id)
        if near_water is not None:
            q = q.eq("near_water", near_water)
        if status:
            q = q.eq("status", status)
        if ward_id:
            q = q.eq("ward_id", ward_id)
        return self._hydrate_all(q.execute().data)

    def get_site(self, sid):
        r = self._t("sites").select("*").eq("id", sid).execute().data
        return self._hydrate(r[0]) if r else None

    def update_site(self, sid, **fields):
        self._t("sites").update(self._dehydrate(fields)).eq("id", sid).execute()
        return self.get_site(sid)

    def upsert_site(self, site):
        self._t("sites").upsert(self._dehydrate(site)).execute()
        return self.get_site(site["id"])

    def list_detections(self, site_id):
        return self._t("detections").select("*").eq("site_id", site_id).execute().data

    def upsert_detection(self, det):
        self._t("detections").upsert(self._dehydrate(det)).execute()
        return det

    def list_fire_events(self, site_id):
        return self._t("fire_events").select("*").eq("site_id", site_id).execute().data

    def upsert_fire_event(self, ev):
        self._t("fire_events").upsert(self._dehydrate(ev)).execute()
        return ev

    def create_complaint(self, c):
        self._t("complaints").insert(self._dehydrate(c)).execute()
        return c

    def get_complaint(self, cid):
        r = self._t("complaints").select("*").eq("id", cid).execute().data
        return r[0] if r else None

    def update_complaint(self, cid, **fields):
        self._t("complaints").update(self._dehydrate(fields)).eq("id", cid).execute()
        return self.get_complaint(cid)

    def list_complaints(self, ward_id=None, status=None):
        q = self._t("complaints").select("*")
        if ward_id:
            q = q.eq("ward_id", ward_id)
        if status:
            q = q.eq("status", status)
        return q.execute().data

    def add_verification(self, v):
        self._t("verifications").insert(self._dehydrate(v)).execute()
        return v

    def create_report(self, r):
        self._t("citizen_reports").insert(self._dehydrate(r)).execute()
        return r

    def list_reports(self, status=None):
        q = self._t("citizen_reports").select("*")
        if status:
            q = q.eq("status", status)
        return self._hydrate_all(q.execute().data)

    def get_report(self, rid):
        r = self._t("citizen_reports").select("*").eq("id", rid).execute().data
        return self._hydrate(r[0]) if r else None

    def update_report(self, rid, **fields):
        self._t("citizen_reports").update(self._dehydrate(fields)).eq("id", rid).execute()
        return self.get_report(rid)

    def upsert_score(self, s):
        self._t("city_scores").upsert(self._dehydrate(s)).execute()
        return s

    def get_score(self, city_id, period):
        r = (self._t("city_scores").select("*")
             .eq("city_id", city_id).eq("period", period).execute().data)
        return r[0] if r else None

    def create_run(self, r):
        self._t("pipeline_runs").insert(self._dehydrate(r)).execute()
        return r

    def get_run(self, rid):
        r = self._t("pipeline_runs").select("*").eq("id", rid).execute().data
        return r[0] if r else None

    def list_runs(self, status=None, limit=50):
        q = self._t("pipeline_runs").select("*")
        if status:
            q = q.eq("status", status)
        return q.order("queued_at", desc=True).limit(limit).execute().data

    def update_run(self, rid, **fields):
        self._t("pipeline_runs").update(self._dehydrate(fields)).eq("id", rid).execute()
        return self.get_run(rid)

    def audit_add(self, actor, action, entity, entity_id, details=None):
        self._t("audit_log").insert({"actor": actor, "action": action, "entity": entity,
                                     "entity_id": entity_id, "details": details or {}}).execute()


# ---------------------------------------------------------------------------
# Choosing / swapping the backend
# ---------------------------------------------------------------------------
# Every method a backend must provide. `tests/test_repo_contract.py` checks
# both backends against this list, so adding a method here makes the contract
# test fail until each backend implements it. That is deliberate: it is how a
# new backend (or A's real Supabase project) finds out what it still owes.
REPO_METHODS = (
    "list_cities", "get_city",
    "list_wards", "upsert_ward", "ward_containing",
    "list_sites", "get_site", "update_site", "upsert_site",
    "list_detections", "upsert_detection",
    "list_fire_events", "upsert_fire_event",
    "create_complaint", "get_complaint", "update_complaint", "list_complaints",
    "add_verification",
    "create_report", "list_reports", "get_report", "update_report",
    "upsert_score", "get_score",
    "create_run", "get_run", "update_run", "list_runs",
    "audit_add",
)

_repo = None


def build_repo():
    """Make the backend the settings ask for, without caching it."""
    return InMemoryRepo() if settings.offline else SupabaseRepo()


def get_repo():
    """The process-wide repo. Built on first use."""
    global _repo
    if _repo is None:
        _repo = build_repo()
    return _repo


def set_repo(repo):
    """
    Swap the backend at runtime. Returns the one replaced, so a caller can put
    it back.

    This is the seam for A's integration and for tests: point the whole app at
    a real Supabase project, a fixture full of B's sample detections, or a fake
    that records calls, without any router knowing.
    """
    global _repo
    previous, _repo = _repo, repo
    return previous


def reset_repo():
    """Drop the cached repo so the next get_repo() rebuilds from settings."""
    global _repo
    previous, _repo = _repo, None
    return previous
