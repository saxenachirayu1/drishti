"""Jobs the worker and CLI run: detection over new scenes, and the daily fire layer.
Every external dependency is passed in, so the whole flow is testable offline."""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone

from . import firms, risk, thumbnails, weather
from .bands import SceneStack, load_stack, rgb
from .config import City
from .inference import Predictor, predict_scene
from .polygonize import polygonize
from .stac import SceneRef, search_scenes, select_new_scenes
from .store import Store
from .tracking import scene_updates
from .util import retry
from .water import WaterIndex

log = logging.getLogger("drishti")


@dataclass
class RunStats:
    scenes_processed: int = 0
    sites_new: int = 0
    sites_updated: int = 0
    errors: list[str] = field(default_factory=list)

    def db_fields(self) -> dict:
        return {"scenes_processed": self.scenes_processed, "sites_new": self.sites_new,
                "sites_updated": self.sites_updated}


def process_scene(city: City, scene: SceneRef, scene_id: str, stack: SceneStack, store: Store,
                  predictor: Predictor, water: WaterIndex | None, stats: RunStats) -> None:
    epsg = stack.crs.to_epsg() if hasattr(stack.crs, "to_epsg") else int(str(stack.crs).split(":")[-1])
    result = predict_scene(stack.reflectance, stack.scl, predictor)
    detections = polygonize(result.probability, stack.transform, epsg)
    sites = store.load_sites(city.id)
    image = rgb(stack.reflectance)

    for u in scene_updates(sites, detections, result.coverage, stack.transform, epsg, scene.acquired_at):
        if u.detection is None:                       # a miss: only counters change
            store.update_site(u.site_id, u.fields)    # type: ignore[arg-type]
            continue
        if u.site_id is None:
            fields = dict(u.fields)
            if water is not None:
                fields["near_water"] = water.near(u.detection.geom)
            site_id = store.create_site(city.id, u.detection, fields)
            stats.sites_new += 1
        else:
            site_id = u.site_id
            store.update_site(site_id, u.fields, geom=u.detection.geom)
            stats.sites_updated += 1
        png = thumbnails.render(image, stack.transform, u.detection.geom_metric)
        url = store.upload_thumbnail(thumbnails.storage_path(site_id, scene_id), png)
        store.upsert_detection(site_id, scene_id, u.detection, url)


def run_detect(city: City, start: date, end: date, store: Store, predictor: Predictor, *,
               search: Callable[..., list[SceneRef]] = search_scenes,
               load: Callable[[SceneRef, tuple], SceneStack] = load_stack,
               water: WaterIndex | None = None, run_id: str | None = None) -> RunStats:
    """B-12 to B-18 for one city and date range. Already-processed scenes are skipped, failed ones retried."""
    stats = RunStats()
    run_id = run_id or store.start_run(city.id, "detect", {"start": start.isoformat(), "end": end.isoformat()})
    try:
        done = store.scene_ids(city.id, ("processed",))
        scenes = select_new_scenes(retry(lambda: search(city, start, end)), done)
        log.info("%s: %d new scenes", city.name, len(scenes))
        for scene in scenes:
            scene_id = store.upsert_scene(city.id, scene)
            try:
                stack = retry(lambda s=scene: load(s, city.bbox))
                process_scene(city, scene, scene_id, stack, store, predictor, water, stats)
                store.set_scene_status(scene_id, "processed")
                stats.scenes_processed += 1
            except Exception as exc:  # noqa: BLE001 - one bad scene must not stop the run
                log.exception("scene %s failed", scene.stac_item_id)
                store.set_scene_status(scene_id, "failed")
                stats.errors.append(f"{scene.stac_item_id}: {exc}")
    except Exception as exc:  # noqa: BLE001
        stats.errors.append(str(exc))
    store.finish_run(run_id, stats.db_fields(), "; ".join(stats.errors)[:2000] or None)
    return stats


def city_centre(city: City) -> tuple[float, float]:
    w, s, e, n = city.bbox
    return (s + n) / 2, (w + e) / 2


def run_fires(city: City, store: Store, *, start: date, end: date, map_key: str,
              fetch_fires: Callable[..., list[firms.FireEvent]] = firms.fetch,
              fetch_weather: Callable[..., weather.Weather] = weather.fetch,
              now: datetime | None = None, run_id: str | None = None,
              update_risk: bool = True) -> dict:
    """B-19 to B-22: pull fire points for [start, end], link them to sites, refresh fire-risk scores."""
    now = now or datetime.now(timezone.utc)
    run_id = run_id or store.start_run(city.id, "fires", {"start": start.isoformat(), "end": end.isoformat()})
    result = {"events": 0, "new_events": 0, "linked": 0, "risk_updated": 0}
    error = None
    try:
        sites = store.load_sites(city.id)
        for first_day, days in firms.date_windows(start, end):
            events = fetch_fires(map_key, city.bbox, city.id, first_day, days, now.date())
            events = firms.match_to_sites(events, sites, city.utm_epsg)
            result["events"] += len(events)
            result["linked"] += sum(1 for e in events if e.site_id)
            result["new_events"] += store.upsert_fire_events(events)

        if update_risk and sites:
            lat, lon = city_centre(city)
            w = fetch_weather(lat, lon, now.date())
            fires = store.fire_times_by_site(city.id, now - timedelta(days=30))
            for s in sites:
                if s.status == "dismissed":
                    continue
                store.update_site(s.id, {"fire_risk": risk.fire_risk(fires.get(s.id, []), w, now)})
                result["risk_updated"] += 1
    except Exception as exc:  # noqa: BLE001
        log.exception("fire run failed for %s", city.name)
        error = str(exc)[:2000]
    store.finish_run(run_id, {}, error)
    result["error"] = error
    return result


def run_backfill(city: City, store: Store, *, months: int = 12, map_key: str, today: date | None = None,
                 **kwargs) -> dict:
    """B-22: twelve months of fire history, without touching today's risk scores."""
    today = today or date.today()
    return run_fires(city, store, start=today - timedelta(days=30 * months), end=today, map_key=map_key,
                     update_risk=False, **kwargs)
