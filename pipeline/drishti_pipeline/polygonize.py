"""B-13: probability map -> clean site polygons with area and mean confidence."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from affine import Affine
from rasterio.features import rasterize, shapes
from shapely.geometry import shape
from shapely.geometry.base import BaseGeometry

from . import config
from .geo import to_wgs84


@dataclass(frozen=True)
class Detection:
    geom: BaseGeometry          # EPSG:4326, what gets stored
    geom_metric: BaseGeometry   # in the scene's UTM CRS, for matching and areas
    area_m2: float
    confidence: float           # mean probability inside the polygon


def polygonize(prob: np.ndarray, transform: Affine, epsg: int,
               threshold: float = config.PROB_THRESHOLD,
               min_area_m2: float = config.MIN_SITE_AREA_M2,
               simplify_m: float = config.SIMPLIFY_TOLERANCE_M) -> list[Detection]:
    """`transform` maps pixels to metres in UTM zone `epsg` (the scene's grid)."""
    mask = (prob >= threshold).astype("uint8")
    out: list[Detection] = []
    for geojson, value in shapes(mask, mask=mask.astype(bool), transform=transform, connectivity=8):
        if value != 1:
            continue
        poly = shape(geojson)
        if poly.area < min_area_m2:
            continue
        simple = poly.simplify(simplify_m, preserve_topology=True)
        if simple.is_empty or not simple.is_valid:
            simple = poly
        inside = rasterize([(poly, 1)], out_shape=prob.shape, transform=transform, fill=0, dtype="uint8").astype(bool)
        confidence = float(prob[inside].mean()) if inside.any() else float(threshold)
        out.append(Detection(to_wgs84(simple, epsg), simple, float(poly.area), round(confidence, 4)))
    return sorted(out, key=lambda d: d.area_m2, reverse=True)
