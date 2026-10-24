"""Everything the pipeline reads from and writes to Supabase, behind one interface.

`SupabaseStore` talks to the real database with the service role key.
`MemoryStore` keeps the same data in dicts, for tests and dry runs.
Both make re-runs safe (B-18, N-14): scenes are unique per (city, STAC id), detections per
(site, scene) and fire events per (lat, lon, time, source).
"""

from __future__ import annotations

import uuid
from dataclasses import asdict
from datetime import datetime, timezone
from typing import Any, Protocol

from shapely import wkb
from shapely.geometry import shape
from shapely.geometry.base import BaseGeometry

from .firms import FireEvent
from .polygonize import Detection
from .stac import SceneRef
from .tracking import Site


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def ewkt(geom: BaseGeometry) -> str:
    return f"SRID=4326;{geom.wkt}"


def parse_geom(value: Any) -> BaseGeometry:
    """PostgREST returns PostGIS geometry as GeoJSON (or hex WKB on older setups)."""
    if isinstance(value, dict):
        return shape(value)
    if isinstance(value, str):
        return wkb.loads(value, hex=True)
    raise ValueError(f"cannot read geometry from {type(value)}")


def _iso(v: Any) -> Any:
    return v.isoformat() if isinstance(v, datetime) else v


class Store(Protocol):
    def scene_ids(self, city_id: str, statuses: tuple[str, ...] = ("processed",)) -> set[str]: ...
    def upsert_scene(self, city_id: str, scene: SceneRef) -> str: ...
    def set_scene_status(self, scene_id: str, status: str) -> None: ...
    def load_sites(self, city_id: str) -> list[Site]: ...
    def create_site(self, city_id: str, det: Detection, fields: dict) -> str: ...
    def update_site(self, site_id: str, fields: dict, geom: BaseGeometry | None = None) -> None: ...
    def upsert_detection(self, site_id: str, scene_id: str, det: Detection, thumb_url: str | None) -> None: ...
    def upload_thumbnail(self, path: str, png: bytes) -> str: ...
    def upsert_fire_events(self, events: list[FireEvent]) -> int: ...
    def fire_times_by_site(self, city_id: str, since: datetime) -> dict[str, list[datetime]]: ...
    def start_run(self, city_id: str | None, kind: str, params: dict) -> str: ...
    def mark_running(self, run_id: str) -> None: ...
    def finish_run(self, run_id: str, stats: dict, error: str | None = None) -> None: ...
    def claim_next_run(self) -> dict | None: ...


# ---------------------------------------------------------------------------
class MemoryStore:
    def __init__(self) -> None:
        self.scenes: dict[str, dict] = {}
        self.sites: dict[str, dict] = {}
        self.detections: dict[tuple[str, str], dict] = {}
        self.fires: dict[tuple, FireEvent] = {}
        self.files: dict[str, bytes] = {}
        self.runs: dict[str, dict] = {}

    def scene_ids(self, city_id, statuses=("processed",)):
        return {s["stac_item_id"] for s in self.scenes.values() if s["city_id"] == city_id and s["status"] in statuses}

    def upsert_scene(self, city_id, scene):
        for sid, s in self.scenes.items():
            if s["city_id"] == city_id and s["stac_item_id"] == scene.stac_item_id:
                return sid
        sid = str(uuid.uuid4())
        self.scenes[sid] = {"city_id": city_id, "stac_item_id": scene.stac_item_id,
                            "acquired_at": scene.acquired_at, "cloud_cover": scene.cloud_cover, "status": "new"}
        return sid

    def set_scene_status(self, scene_id, status):
        self.scenes[scene_id]["status"] = status

    def load_sites(self, city_id):
        return [Site(id=k, geom=v["geom"], first_seen=v["first_seen"], last_seen=v["last_seen"],
                     status=v["status"], confidence=v["confidence"], missed_scenes=v["missed_scenes"],
                     cleared_candidate=v["cleared_candidate"])
                for k, v in self.sites.items() if v["city_id"] == city_id]

    def create_site(self, city_id, det, fields):
        sid = str(uuid.uuid4())
        self.sites[sid] = {"city_id": city_id, "geom": det.geom, "status": "active", "near_water": False,
                           "fire_risk": 0, "missed_scenes": 0, "cleared_candidate": False,
                           "confidence": det.confidence, **fields}
        return sid

    def update_site(self, site_id, fields, geom=None):
        self.sites[site_id].update(fields)
        if geom is not None:
            self.sites[site_id]["geom"] = geom

    def upsert_detection(self, site_id, scene_id, det, thumb_url):
        self.detections[(site_id, scene_id)] = {"geom": det.geom, "confidence": det.confidence,
                                                "area_m2": det.area_m2, "thumb_url": thumb_url}

    def upload_thumbnail(self, path, png):
        self.files[path] = png
        return f"memory://thumbnails/{path}"

    def upsert_fire_events(self, events):
        new = 0
        for e in events:
            key = (e.lat, e.lon, e.detected_at, e.source)
            if key not in self.fires:
                new += 1
            self.fires[key] = e
        return new

    def fire_times_by_site(self, city_id, since):
        out: dict[str, list[datetime]] = {}
        for e in self.fires.values():
            if e.city_id == city_id and e.site_id and e.detected_at >= since:
                out.setdefault(e.site_id, []).append(e.detected_at)
        return out

    def start_run(self, city_id, kind, params):
        rid = str(uuid.uuid4())
        self.runs[rid] = {"city_id": city_id, "kind": kind, "params": params, "status": "running",
                          "started_at": now_utc()}
        return rid

    def mark_running(self, run_id):
        self.runs[run_id].update(status="running", started_at=now_utc())

    def finish_run(self, run_id, stats, error=None):
        self.runs[run_id].update(stats, status="failed" if error else "done", error=error, finished_at=now_utc())

    def queue_run(self, city_id, kind, params=None):
        rid = str(uuid.uuid4())
        self.runs[rid] = {"city_id": city_id, "kind": kind, "params": params or {}, "status": "queued"}
        return rid

    def claim_next_run(self):
        for rid, r in self.runs.items():
            if r["status"] == "queued":
                r["status"] = "running"
                return {"id": rid, **r}
        return None


# ---------------------------------------------------------------------------
class SupabaseStore:
    """Needs the `db` extra. Uses the service role key: never ship it to the app (N-08)."""

    def __init__(self, url: str, key: str):
        from supabase import create_client

        if not url or not key:
            raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        self.db = create_client(url, key)

    def _t(self, name: str):
        return self.db.table(name)

    def scene_ids(self, city_id, statuses=("processed",)):
        rows = self._t("scenes").select("stac_item_id").eq("city_id", city_id).in_("status", list(statuses)).execute()
        return {r["stac_item_id"] for r in rows.data}

    def upsert_scene(self, city_id, scene):
        row = {"city_id": city_id, "stac_item_id": scene.stac_item_id,
               "acquired_at": scene.acquired_at.isoformat(), "cloud_cover": scene.cloud_cover}
        res = self._t("scenes").upsert(row, on_conflict="city_id,stac_item_id").execute()
        return res.data[0]["id"]

    def set_scene_status(self, scene_id, status):
        self._t("scenes").update({"status": status}).eq("id", scene_id).execute()

    def load_sites(self, city_id):
        rows = self._t("sites").select(
            "id, geom, first_seen, last_seen, status, confidence, missed_scenes, cleared_candidate"
        ).eq("city_id", city_id).execute().data
        return [Site(id=r["id"], geom=parse_geom(r["geom"]),
                     first_seen=datetime.fromisoformat(r["first_seen"]),
                     last_seen=datetime.fromisoformat(r["last_seen"]),
                     status=r["status"], confidence=r.get("confidence") or 0.0,
                     missed_scenes=r.get("missed_scenes") or 0,
                     cleared_candidate=bool(r.get("cleared_candidate"))) for r in rows]

    def create_site(self, city_id, det, fields):
        row = {"city_id": city_id, "geom": ewkt(det.geom), **{k: _iso(v) for k, v in fields.items()}}
        return self._t("sites").insert(row).execute().data[0]["id"]

    def update_site(self, site_id, fields, geom=None):
        row = {k: _iso(v) for k, v in fields.items()}
        if geom is not None:
            row["geom"] = ewkt(geom)
        self._t("sites").update(row).eq("id", site_id).execute()

    def upsert_detection(self, site_id, scene_id, det, thumb_url):
        row = {"site_id": site_id, "scene_id": scene_id, "geom": ewkt(det.geom),
               "confidence": det.confidence, "thumb_url": thumb_url}
        self._t("detections").upsert(row, on_conflict="site_id,scene_id").execute()

    def upload_thumbnail(self, path, png):
        bucket = self.db.storage.from_("thumbnails")
        bucket.upload(path, png, {"content-type": "image/png", "upsert": "true"})
        return bucket.get_public_url(path)

    def upsert_fire_events(self, events):
        if not events:
            return 0
        rows = []
        for e in events:
            d = asdict(e)
            d["detected_at"] = e.detected_at.isoformat()
            rows.append(d)
        res = self._t("fire_events").upsert(rows, on_conflict="lat,lon,detected_at,source",
                                            ignore_duplicates=True).execute()
        return len(res.data or [])

    def fire_times_by_site(self, city_id, since):
        rows = self._t("fire_events").select("site_id, detected_at").eq("city_id", city_id) \
            .gte("detected_at", since.isoformat()).not_.is_("site_id", "null").execute().data
        out: dict[str, list[datetime]] = {}
        for r in rows:
            out.setdefault(r["site_id"], []).append(datetime.fromisoformat(r["detected_at"]))
        return out

    def start_run(self, city_id, kind, params):
        row = {"city_id": city_id, "kind": kind, "params": params, "status": "running",
               "started_at": now_utc().isoformat()}
        return self._t("pipeline_runs").insert(row).execute().data[0]["id"]

    def mark_running(self, run_id):
        self._t("pipeline_runs").update({"status": "running", "started_at": now_utc().isoformat()}) \
            .eq("id", run_id).execute()

    def finish_run(self, run_id, stats, error=None):
        row = {**stats, "status": "failed" if error else "done", "error": error,
               "finished_at": now_utc().isoformat()}
        self._t("pipeline_runs").update(row).eq("id", run_id).execute()

    def claim_next_run(self):
        rows = self._t("pipeline_runs").select("*").eq("status", "queued").order("queued_at").limit(1).execute().data
        if not rows:
            return None
        claimed = self._t("pipeline_runs").update({"status": "running", "started_at": now_utc().isoformat()}) \
            .eq("id", rows[0]["id"]).eq("status", "queued").execute().data
        return claimed[0] if claimed else None

