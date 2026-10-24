"""B-19, B-20, B-22: NASA FIRMS active-fire points, matched to sites."""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass, replace
from datetime import date, datetime, timedelta, timezone

from shapely.geometry import Point
from shapely.strtree import STRtree

from . import config
from .geo import to_metric
from .tracking import Site


@dataclass(frozen=True)
class FireEvent:
    city_id: str
    detected_at: datetime
    lat: float
    lon: float
    frp: float | None
    confidence: str | None
    source: str = "VIIRS"
    site_id: str | None = None


def area_url(map_key: str, source: str, bbox: tuple[float, float, float, float],
             day_range: int, start: date | None = None) -> str:
    """FIRMS area API: /api/area/csv/{key}/{source}/{west,south,east,north}/{days}[/{YYYY-MM-DD}]."""
    if not 1 <= day_range <= config.FIRMS_MAX_DAY_RANGE:
        raise ValueError("FIRMS returns 1 to 10 days per request")
    coords = ",".join(f"{v:g}" for v in bbox)
    url = f"{config.FIRMS_URL}/{map_key}/{source}/{coords}/{day_range}"
    return f"{url}/{start.isoformat()}" if start else url


def source_for(start: date, today: date) -> str:
    """Recent days come from the near-real-time feed; older days from the standard archive."""
    return config.FIRMS_NRT_SOURCE if (today - start).days <= config.FIRMS_NRT_MAX_AGE_DAYS \
        else config.FIRMS_ARCHIVE_SOURCE


def parse_csv(text: str, city_id: str) -> list[FireEvent]:
    events = []
    for row in csv.DictReader(io.StringIO(text)):
        if not row.get("latitude"):
            continue
        t = (row.get("acq_time") or "0").zfill(4)
        when = datetime.strptime(f"{row['acq_date']} {t}", "%Y-%m-%d %H%M").replace(tzinfo=timezone.utc)
        frp = row.get("frp")
        events.append(FireEvent(
            city_id=city_id, detected_at=when,
            lat=round(float(row["latitude"]), 5), lon=round(float(row["longitude"]), 5),
            frp=float(frp) if frp not in (None, "") else None,
            confidence=row.get("confidence") or None,
            source="VIIRS",
        ))
    return events


def date_windows(start: date, end: date, max_days: int = config.FIRMS_MAX_DAY_RANGE) -> list[tuple[date, int]]:
    """Split [start, end] into requests of at most 10 days: (first day, number of days)."""
    out, d = [], start
    while d <= end:
        n = min(max_days, (end - d).days + 1)
        out.append((d, n))
        d += timedelta(days=n)
    return out


def fetch(map_key: str, bbox, city_id: str, start: date, days: int, today: date) -> list[FireEvent]:
    import httpx

    from .util import retry

    if not map_key:
        raise RuntimeError("FIRMS_MAP_KEY is not set")
    url = area_url(map_key, source_for(start, today), bbox, days, start)

    def call():
        r = httpx.get(url, timeout=60)
        r.raise_for_status()
        return r.text

    return parse_csv(retry(call), city_id)


def match_to_sites(events: list[FireEvent], sites: list[Site], epsg: int,
                   max_m: float = config.FIRE_MATCH_M) -> list[FireEvent]:
    """Attach each fire point to the nearest site polygon within 500 m (VIIRS pixels are ~375 m)."""
    live = [s for s in sites if s.status != "dismissed"]
    if not live:
        return list(events)
    geoms = [to_metric(s.geom, epsg) for s in live]
    tree = STRtree(geoms)
    out = []
    for ev in events:
        p = to_metric(Point(ev.lon, ev.lat), epsg)
        best, best_d = None, max_m
        for i in tree.query(p.buffer(max_m)):
            d = geoms[int(i)].distance(p)
            if d <= best_d:
                best, best_d = live[int(i)].id, d
        out.append(replace(ev, site_id=best))
    return out
