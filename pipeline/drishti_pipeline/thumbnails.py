"""B-16: an RGB thumbnail of each detection, with the site outline, for the before-and-after slider."""

from __future__ import annotations

import io

import numpy as np
from affine import Affine
from PIL import Image, ImageDraw
from shapely.geometry.base import BaseGeometry

THUMB_SIZE = 256
PAD_M = 150.0  # context around the site, in metres


def stretch(rgb: np.ndarray, low: float = 2, high: float = 98) -> np.ndarray:
    """(H, W, 3) reflectance -> uint8 with a percentile stretch. NaN becomes black."""
    finite = rgb[np.isfinite(rgb)]
    if finite.size == 0:
        return np.zeros(rgb.shape, "uint8")
    lo, hi = np.percentile(finite, [low, high])
    scaled = (rgb - lo) / max(hi - lo, 1e-6)
    return (np.nan_to_num(np.clip(scaled, 0, 1), nan=0) * 255).astype("uint8")


def render(rgb: np.ndarray, transform: Affine, site_metric: BaseGeometry,
           size: int = THUMB_SIZE, pad_m: float = PAD_M) -> bytes:
    """Crop a square around the site (metric CRS of `transform`), draw its outline, return PNG bytes."""
    minx, miny, maxx, maxy = site_metric.buffer(pad_m).bounds
    inv = ~transform
    c0, r0 = inv @ (minx, maxy)
    c1, r1 = inv @ (maxx, miny)
    h, w = rgb.shape[:2]
    r0, c0 = max(int(np.floor(min(r0, r1))), 0), max(int(np.floor(min(c0, c1))), 0)
    r1, c1 = min(int(np.ceil(max(r0, r1))) + 1, h), min(int(np.ceil(max(c0, c1))) + 1, w)
    crop = stretch(rgb[r0:r1, c0:c1])
    if crop.size == 0:
        crop = np.zeros((1, 1, 3), "uint8")
    img = Image.fromarray(crop).resize((size, size), Image.NEAREST)

    sx, sy = size / max(crop.shape[1], 1), size / max(crop.shape[0], 1)
    draw = ImageDraw.Draw(img)
    polys = getattr(site_metric, "geoms", [site_metric])
    for p in polys:
        pts = []
        for x, y in p.exterior.coords:
            col, row = inv @ (x, y)
            pts.append(((col - c0) * sx, (row - r0) * sy))
        draw.line(pts, fill=(255, 64, 64), width=2)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def storage_path(site_id: str, scene_id: str) -> str:
    return f"{site_id}/{scene_id}.png"
