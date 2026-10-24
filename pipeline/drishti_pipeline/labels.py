"""B-06 and B-07: labelled polygons -> tile masks, and a spatial train/val/test split with no leakage."""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from affine import Affine
from rasterio.features import rasterize
from shapely.geometry import box, shape
from shapely.geometry.base import BaseGeometry
from shapely.strtree import STRtree

WASTE = "waste"
# Look-alikes the model must learn to reject (hard negatives).
NEGATIVE_TYPES = ("construction", "bare_soil", "quarry", "industrial", "other")
ALLOWED_LABELS = (WASTE, *NEGATIVE_TYPES)
TARGET_POSITIVES_PER_CITY = 150


@dataclass(frozen=True)
class Label:
    geom: BaseGeometry   # EPSG:4326
    label: str           # "waste" or a negative type
    source: str = ""     # where we know it from: news link, municipal list, field visit


def load_labels(path: str | Path) -> list[Label]:
    """Read a labelling GeoJSON. Every feature needs properties.label from ALLOWED_LABELS."""
    data = json.loads(Path(path).read_text())
    out: list[Label] = []
    for i, feat in enumerate(data.get("features", [])):
        props = feat.get("properties") or {}
        label = props.get("label")
        if label not in ALLOWED_LABELS:
            raise ValueError(f"feature {i}: label must be one of {ALLOWED_LABELS}, got {label!r}")
        geom = shape(feat["geometry"])
        if geom.geom_type not in ("Polygon", "MultiPolygon") or not geom.is_valid:
            raise ValueError(f"feature {i}: needs a valid Polygon or MultiPolygon")
        out.append(Label(geom, label, props.get("source", "")))
    return out


def label_stats(labels: list[Label]) -> dict[str, int]:
    return dict(Counter(lbl.label for lbl in labels))


def meets_target(labels: list[Label], target: int = TARGET_POSITIVES_PER_CITY) -> bool:
    return label_stats(labels).get(WASTE, 0) >= target


def rasterize_mask(waste_geoms: list[BaseGeometry], transform: Affine, shape_hw: tuple[int, int]) -> np.ndarray:
    """Burn waste polygons (already in the raster's CRS) into a uint8 mask: 1 = waste, 0 = not waste."""
    if not waste_geoms:
        return np.zeros(shape_hw, dtype="uint8")
    return rasterize(((g, 1) for g in waste_geoms), out_shape=shape_hw, transform=transform,
                     fill=0, dtype="uint8", all_touched=False)


@dataclass(frozen=True)
class TileFootprint:
    name: str
    bounds: tuple[float, float, float, float]  # minx, miny, maxx, maxy in metres (UTM)


def spatial_split(tiles: list[TileFootprint], block_m: float = 2000.0, seed: int = 42,
                  fractions: tuple[float, float, float] = (0.7, 0.15, 0.15)) -> dict[str, str]:
    """Assign tiles to train/val/test by 2 km blocks, so neighbouring tiles share a split.
    Any val/test tile that still touches a tile of another split is dropped, so no pixel leaks.
    Reproducible for a given seed."""
    if abs(sum(fractions) - 1.0) > 1e-6:
        raise ValueError("fractions must sum to 1")

    def block_of(t: TileFootprint) -> tuple[int, int]:
        cx = (t.bounds[0] + t.bounds[2]) / 2
        cy = (t.bounds[1] + t.bounds[3]) / 2
        return int(cx // block_m), int(cy // block_m)

    blocks = sorted({block_of(t) for t in tiles})
    order = np.random.default_rng(seed).permutation(len(blocks))
    n_train = round(fractions[0] * len(blocks))
    n_val = round(fractions[1] * len(blocks))
    split_of_block = {}
    for rank, idx in enumerate(order):
        split_of_block[blocks[idx]] = "train" if rank < n_train else "val" if rank < n_train + n_val else "test"

    assigned = {t.name: split_of_block[block_of(t)] for t in tiles}

    # Drop evaluation tiles whose area overlaps a tile from a different split.
    geoms = [box(*t.bounds) for t in tiles]
    tree = STRtree(geoms)
    for i, t in enumerate(tiles):
        if assigned[t.name] == "train":
            continue
        for j in tree.query(geoms[i]):
            other = tiles[int(j)]
            if other.name != t.name and assigned[other.name] != assigned[t.name] \
                    and geoms[i].intersection(geoms[int(j)]).area > 0:
                assigned[t.name] = "dropped"
                break
    return assigned
