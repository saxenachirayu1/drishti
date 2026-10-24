"""B-05: monthly cloud-free median composites, used by the time slider when single scenes are cloudy."""

from __future__ import annotations

import warnings
from collections import defaultdict
from collections.abc import Iterable

import numpy as np

from .stac import SceneRef


def month_key(scene: SceneRef) -> str:
    return scene.acquired_at.strftime("%Y-%m")


def group_by_month(scenes: Iterable[SceneRef]) -> dict[str, list[SceneRef]]:
    groups: dict[str, list[SceneRef]] = defaultdict(list)
    for s in scenes:
        groups[month_key(s)].append(s)
    return dict(sorted(groups.items()))


def median_composite(stacks: list[np.ndarray]) -> np.ndarray:
    """Per-pixel median of several (bands, H, W) stacks that share a grid, ignoring NaN (masked) pixels.
    A pixel that is cloudy in every scene stays NaN."""
    if not stacks:
        raise ValueError("need at least one stack")
    shapes = {s.shape for s in stacks}
    if len(shapes) != 1:
        raise ValueError(f"stacks must share a grid, got shapes {shapes}")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", category=RuntimeWarning)  # all-NaN slices
        return np.nanmedian(np.stack(stacks), axis=0).astype("float32")


def clear_fraction(composite: np.ndarray) -> float:
    """Share of pixels with a value in every band."""
    return float(np.isfinite(composite).all(axis=0).mean())
