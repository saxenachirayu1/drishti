"""B-14, B-15: keep one site id per dump across scenes, and flag sites that disappeared.

The pipeline never changes a site's `status` (that is Member C's verification job).
It only maintains geometry, last_seen, confidence, missed_scenes and cleared_candidate.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

import numpy as np
from affine import Affine
from rasterio.features import rasterize
from shapely.geometry.base import BaseGeometry
from shapely.ops import unary_union

from . import config
from .geo import iou, to_metric, to_wgs84
from .polygonize import Detection


@dataclass
class Site:
    id: str
    geom: BaseGeometry            # EPSG:4326
    first_seen: datetime
    last_seen: datetime
    status: str = "active"
    confidence: float = 0.0
    missed_scenes: int = 0
    cleared_candidate: bool = False


@dataclass
class SiteUpdate:
    site_id: str | None            # None = create a new site
    detection: Detection           # union of every detection that matched this site in the scene
    fields: dict = field(default_factory=dict)


def _best_site(det: Detection, sites: list[Site], metric: dict[str, BaseGeometry],
               iou_min: float, dist_max: float) -> str | None:
    best, best_key = None, None
    for s in sites:
        g = metric[s.id]
        score = iou(det.geom_metric, g)
        dist = det.geom_metric.centroid.distance(g.centroid)
        if score > iou_min or dist < dist_max:
            key = (score, -dist)
            if best_key is None or key > best_key:
                best, best_key = s.id, key
    return best


def match_detections(detections: list[Detection], sites: list[Site], epsg: int,
                     iou_min: float = config.MATCH_IOU,
                     dist_max: float = config.MATCH_CENTROID_M) -> list[SiteUpdate]:
    """Each detection joins the existing site it overlaps best (IoU > 0.3 or centroids within 50 m),
    or starts a new site. Several detections on one site are merged, so one dump keeps one id."""
    metric = {s.id: to_metric(s.geom, epsg) for s in sites}
    grouped: dict[str | None, list[Detection]] = {}
    new_sites: list[Detection] = []
    for det in detections:
        sid = _best_site(det, sites, metric, iou_min, dist_max)
        if sid is None:
            new_sites.append(det)
        else:
            grouped.setdefault(sid, []).append(det)

    updates: list[SiteUpdate] = []
    for sid, dets in grouped.items():
        if len(dets) == 1:
            merged = dets[0]
        else:
            gm = unary_union([d.geom_metric for d in dets])
            conf = sum(d.confidence * d.area_m2 for d in dets) / sum(d.area_m2 for d in dets)
            merged = Detection(to_wgs84(gm, epsg), gm, gm.area, round(conf, 4))
        updates.append(SiteUpdate(sid, merged))
    updates.extend(SiteUpdate(None, d) for d in new_sites)
    return updates


def covered_fraction(site_metric: BaseGeometry, coverage: np.ndarray, transform: Affine) -> float:
    """Share of the site's pixels the model saw clearly in this scene."""
    inside = rasterize([(site_metric, 1)], out_shape=coverage.shape, transform=transform, fill=0,
                       dtype="uint8", all_touched=True).astype(bool)
    return float(coverage[inside].mean()) if inside.any() else 0.0


def scene_updates(sites: list[Site], detections: list[Detection], coverage: np.ndarray,
                  transform: Affine, epsg: int, scene_time: datetime,
                  min_coverage: float = 0.7) -> list[SiteUpdate]:
    """Everything one processed scene changes about sites:
    matched sites get the new geometry, last_seen and a reset miss counter;
    unmatched sites the scene saw clearly get one more miss, and become cleared candidates after 2."""
    updates = match_detections(detections, sites, epsg)
    matched = {u.site_id for u in updates if u.site_id}
    for u in updates:
        u.fields = {"last_seen": scene_time, "confidence": u.detection.confidence,
                    "missed_scenes": 0, "cleared_candidate": False}
        if u.site_id is None:
            u.fields["first_seen"] = scene_time

    for s in sites:
        if s.id in matched or s.status == "dismissed":
            continue
        if covered_fraction(to_metric(s.geom, epsg), coverage, transform) < min_coverage:
            continue  # clouds over the site: no evidence either way
        misses = s.missed_scenes + 1
        updates.append(SiteUpdate(s.id, detection=None,  # type: ignore[arg-type]
                                  fields={"missed_scenes": misses,
                                          "cleared_candidate": misses >= config.CLEARED_AFTER_MISSES}))
    return updates
