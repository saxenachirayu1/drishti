"""Command line and worker.

  drishti-pipeline detect --city <id> [--start 2026-10-01 --end 2026-10-20]
  drishti-pipeline fires --city <id> [--days 2]
  drishti-pipeline backfill-fires --city <id> [--months 12]
  drishti-pipeline worker [--once]          # runs jobs Member C's API queues in pipeline_runs
  drishti-pipeline labels-check labels/pune.geojson
  drishti-pipeline build-dataset --city <id> --start ... --end ... [--scenes 3]
  drishti-pipeline evaluate --pred pred.geojson --truth labels/pune.geojson
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from . import run
from .config import City, Settings, load_cities

log = logging.getLogger("drishti")


def make_predictor(checkpoint: str | None):
    from .inference import BaselinePredictor, PrithviPredictor

    if checkpoint:
        return PrithviPredictor(checkpoint)
    log.warning("no checkpoint given: using the spectral baseline (B-10), not Prithvi")
    return BaselinePredictor()


def make_store(settings: Settings):
    from .store import SupabaseStore

    return SupabaseStore(settings.supabase_url, settings.supabase_key)


def _city(cities: dict[str, City], key: str) -> City:
    if key in cities:
        return cities[key]
    for c in cities.values():
        if c.name.lower() == key.lower():
            return c
    raise SystemExit(f"unknown city {key!r}; known: {', '.join(c.name for c in cities.values())}")


def _date(s: str | None, default: date) -> date:
    return date.fromisoformat(s) if s else default


def dispatch(job: dict, cities: dict[str, City], store, settings: Settings, predictor_factory=make_predictor,
             water_factory=None) -> dict:
    """Run one queued pipeline_runs row. Unknown kinds fail the run instead of crashing the worker."""
    today = datetime.now(timezone.utc).date()
    params = job.get("params") or {}
    city = cities.get(job.get("city_id") or "")
    if city is None:
        store.finish_run(job["id"], {}, f"unknown city {job.get('city_id')}")
        return {"error": "unknown city"}
    if job["kind"] == "detect":
        stats = run.run_detect(city, _date(params.get("start"), today - timedelta(days=10)),
                               _date(params.get("end"), today), store, predictor_factory(settings.checkpoint),
                               water=water_factory(city) if water_factory else None, run_id=job["id"])
        return stats.db_fields() | {"errors": stats.errors}
    if job["kind"] == "fires":
        return run.run_fires(city, store, start=_date(params.get("start"), today - timedelta(days=1)),
                             end=_date(params.get("end"), today), map_key=settings.firms_map_key, run_id=job["id"])
    store.finish_run(job["id"], {}, f"pipeline does not handle kind {job['kind']!r}")
    return {"error": "unsupported kind"}


def water_for(city: City):
    from .util import retry
    from .water import WaterIndex, fetch_water

    try:
        return WaterIndex(retry(lambda: fetch_water(city.bbox)), city.utm_epsg)
    except Exception as exc:  # noqa: BLE001 - near_water is a Should; never block detection on it
        log.warning("water features unavailable for %s: %s", city.name, exc)
        return None


def main(argv: list[str] | None = None, store=None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(prog="drishti-pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("detect")
    d.add_argument("--city", required=True)
    d.add_argument("--start")
    d.add_argument("--end")
    d.add_argument("--checkpoint", help="fine-tuned Prithvi .ckpt; omit to use the spectral baseline")
    d.add_argument("--no-water", action="store_true")

    f = sub.add_parser("fires")
    f.add_argument("--city", required=True)
    f.add_argument("--days", type=int, default=2)

    b = sub.add_parser("backfill-fires")
    b.add_argument("--city", required=True)
    b.add_argument("--months", type=int, default=12)

    w = sub.add_parser("worker")
    w.add_argument("--once", action="store_true")
    w.add_argument("--poll", type=int, default=30)

    lc = sub.add_parser("labels-check")
    lc.add_argument("path")

    bd = sub.add_parser("build-dataset")
    bd.add_argument("--city", required=True)
    bd.add_argument("--start", required=True)
    bd.add_argument("--end", required=True)
    bd.add_argument("--scenes", type=int, default=3, help="use the N clearest scenes")
    bd.add_argument("--out", default="data/dataset")

    ev = sub.add_parser("evaluate")
    ev.add_argument("--pred", required=True)
    ev.add_argument("--truth", required=True)

    args = p.parse_args(argv)
    settings = Settings()

    if args.cmd == "labels-check":
        from .labels import TARGET_POSITIVES_PER_CITY, label_stats, load_labels, meets_target

        lbls = load_labels(args.path)
        print(json.dumps(label_stats(lbls), indent=2))
        ok = meets_target(lbls)
        print(f"waste target ({TARGET_POSITIVES_PER_CITY}+): {'met' if ok else 'NOT met'}")
        return 0 if ok else 1

    if args.cmd == "evaluate":
        from .evaluation import site_scores
        from .labels import WASTE, load_labels

        pred = [lbl.geom for lbl in load_labels(args.pred) if lbl.label == WASTE]
        truth = [lbl.geom for lbl in load_labels(args.truth) if lbl.label == WASTE]
        s = site_scores(pred, truth)
        print(f"precision {s.precision:.3f}  recall {s.recall:.3f}  f1 {s.f1:.3f}  "
              f"({s.true_positives} matched / {s.predicted} predicted / {s.actual} actual)")
        return 0

    cities = load_cities(settings.cities_file)
    today = datetime.now(timezone.utc).date()

    if args.cmd == "build-dataset":
        from .bands import load_stack
        from .dataset import build_dataset
        from .labels import load_labels
        from .stac import search_scenes, select_new_scenes

        city = _city(cities, args.city)
        if not city.labels:
            raise SystemExit(f"{city.name} has no labels file in cities.yaml")
        lbls = load_labels(Path(settings.cities_file).parent.parent / city.labels)
        scenes = select_new_scenes(search_scenes(city, date.fromisoformat(args.start), date.fromisoformat(args.end)),
                                   set())
        scenes = sorted(scenes, key=lambda s: s.cloud_cover)[: args.scenes]
        for sc in scenes:
            prefix = f"{city.name.lower()}_{sc.stac_item_id}"
            counts = build_dataset(load_stack(sc, city.bbox), lbls, Path(args.out), prefix)
            print(sc.stac_item_id, counts)
        return 0

    store = store or make_store(settings)

    if args.cmd == "detect":
        city = _city(cities, args.city)
        stats = run.run_detect(city, _date(args.start, today - timedelta(days=10)), _date(args.end, today), store,
                               make_predictor(args.checkpoint or settings.checkpoint),
                               water=None if args.no_water else water_for(city))
        print(json.dumps(stats.db_fields() | {"errors": stats.errors}, indent=2))
        return 1 if stats.errors else 0

    if args.cmd == "fires":
        city = _city(cities, args.city)
        res = run.run_fires(city, store, start=today - timedelta(days=args.days - 1), end=today,
                            map_key=settings.firms_map_key)
        print(json.dumps(res, indent=2, default=str))
        return 1 if res.get("error") else 0

    if args.cmd == "backfill-fires":
        city = _city(cities, args.city)
        res = run.run_backfill(city, store, months=args.months, map_key=settings.firms_map_key)
        print(json.dumps(res, indent=2, default=str))
        return 1 if res.get("error") else 0

    if args.cmd == "worker":
        while True:
            job = store.claim_next_run()
            if job:
                log.info("running %s for %s", job["kind"], job.get("city_id"))
                dispatch(job, cities, store, settings, water_factory=water_for)
            elif args.once:
                return 0       # queue drained
            else:
                time.sleep(args.poll)
    return 0


if __name__ == "__main__":
    sys.exit(main())

