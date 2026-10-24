"""Small geometry helpers: metric projections, distances, IoU. Everything is stored in EPSG:4326;
areas and distances are computed in the city's UTM zone."""

from __future__ import annotations

from functools import lru_cache

import numpy as np
import shapely
from pyproj import Transformer
from shapely.geometry.base import BaseGeometry


def utm_epsg_for(lon: float, lat: float) -> int:
    zone = int((lon + 180) // 6) + 1
    return (32600 if lat >= 0 else 32700) + zone


@lru_cache(maxsize=16)
def _to_metric(epsg: int) -> Transformer:
    return Transformer.from_crs(4326, epsg, always_xy=True)


@lru_cache(maxsize=16)
def _to_wgs84(epsg: int) -> Transformer:
    return Transformer.from_crs(epsg, 4326, always_xy=True)


def _apply(t: Transformer, geom: BaseGeometry) -> BaseGeometry:
    return shapely.transform(geom, lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1])))


def to_metric(geom: BaseGeometry, epsg: int) -> BaseGeometry:
    return _apply(_to_metric(epsg), geom)


def to_wgs84(geom: BaseGeometry, epsg: int) -> BaseGeometry:
    return _apply(_to_wgs84(epsg), geom)


def area_m2(geom: BaseGeometry, epsg: int) -> float:
    return to_metric(geom, epsg).area


def distance_m(a: BaseGeometry, b: BaseGeometry, epsg: int) -> float:
    return to_metric(a, epsg).distance(to_metric(b, epsg))


def iou(a: BaseGeometry, b: BaseGeometry) -> float:
    """Intersection over union. Works in any CRS, as long as both share it."""
    if a.is_empty or b.is_empty:
        return 0.0
    inter = a.intersection(b).area
    if inter == 0:
        return 0.0
    return inter / a.union(b).area
