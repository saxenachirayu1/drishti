"""B-09, B-10, N-25: how good is the model, compared with what, and where does it go wrong."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass

import numpy as np
from shapely.geometry.base import BaseGeometry

from . import config
from .geo import iou


def pixel_iou(pred: np.ndarray, truth: np.ndarray, ignore: np.ndarray | None = None) -> float:
    """IoU of the waste class. `ignore` marks pixels left out (no data)."""
    p, t = pred.astype(bool), truth.astype(bool)
    if ignore is not None:
        keep = ~ignore.astype(bool)
        p, t = p[keep], t[keep]
    union = np.logical_or(p, t).sum()
    return 1.0 if union == 0 else float(np.logical_and(p, t).sum() / union)


@dataclass(frozen=True)
class SiteScores:
    true_positives: int
    predicted: int
    actual: int

    @property
    def precision(self) -> float:
        return self.true_positives / self.predicted if self.predicted else 0.0

    @property
    def recall(self) -> float:
        return self.true_positives / self.actual if self.actual else 0.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return 2 * p * r / (p + r) if p + r else 0.0


def match_sites(pred: list[BaseGeometry], truth: list[BaseGeometry],
                threshold: float = config.MATCH_IOU) -> list[tuple[int, int]]:
    """One-to-one greedy matching, best IoU first. A pair counts if IoU > threshold."""
    pairs = sorted(((iou(p, t), i, j) for i, p in enumerate(pred) for j, t in enumerate(truth)), reverse=True)
    used_p, used_t, matches = set(), set(), []
    for score, i, j in pairs:
        if score <= threshold:
            break
        if i in used_p or j in used_t:
            continue
        used_p.add(i)
        used_t.add(j)
        matches.append((i, j))
    return matches


def site_scores(pred: list[BaseGeometry], truth: list[BaseGeometry], threshold: float = config.MATCH_IOU) -> SiteScores:
    return SiteScores(len(match_sites(pred, truth, threshold)), len(pred), len(truth))


def false_positive_breakdown(false_positives: list[BaseGeometry],
                             negatives: list[tuple[BaseGeometry, str]]) -> dict[str, int]:
    """N-25: which kinds of ground the model confuses with waste (construction, bare soil, ...)."""
    counts: Counter[str] = Counter()
    for fp in false_positives:
        kinds = [kind for geom, kind in negatives if fp.intersects(geom)]
        counts[kinds[0] if kinds else "unlabelled"] += 1
    return dict(counts)


def report(name_to_scores: dict[str, tuple[float, SiteScores]]) -> str:
    """Markdown table for the repo and the pitch: model -> (pixel IoU, site scores)."""
    lines = ["| Model | Pixel IoU | Site precision | Site recall | F1 |", "| --- | --- | --- | --- | --- |"]
    for name, (px, s) in name_to_scores.items():
        lines.append(f"| {name} | {px:.3f} | {s.precision:.3f} | {s.recall:.3f} | {s.f1:.3f} |")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# B-10 baseline: a spectral index rule with no learning.
# Waste dumps are bare (low NDVI) and bright in SWIR. So are construction sites and
# bare soil, which is exactly the confusion Prithvi should fix.
# ---------------------------------------------------------------------------
NDVI_MAX = 0.2
BSI_MIN = 0.05


def spectral_baseline(stack: np.ndarray, ndvi_max: float = NDVI_MAX, bsi_min: float = BSI_MIN) -> np.ndarray:
    """(6, H, W) reflectance -> (H, W) 0/1 'waste' map from NDVI and the bare soil index."""
    blue, _green, red, nir, swir1, _swir2 = (stack[i].astype("float64") for i in range(6))
    with np.errstate(invalid="ignore", divide="ignore"):
        ndvi = (nir - red) / (nir + red)
        bsi = ((swir1 + red) - (nir + blue)) / ((swir1 + red) + (nir + blue))
    out = (ndvi < ndvi_max) & (bsi > bsi_min)
    return np.where(np.isfinite(ndvi) & np.isfinite(bsi), out, False).astype("float32")
