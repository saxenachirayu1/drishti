"""B-02: mask clouds, shadows and no-data with the Sentinel-2 scene classification layer (SCL)."""

from __future__ import annotations

import numpy as np

from . import config

# SCL classes treated as unusable ground.
SCL_NO_DATA = 0
SCL_SATURATED = 1
SCL_CLOUD_SHADOW = 3
SCL_CLOUD_MEDIUM = 8
SCL_CLOUD_HIGH = 9
SCL_CIRRUS = 10
INVALID_CLASSES = (SCL_NO_DATA, SCL_SATURATED, SCL_CLOUD_SHADOW, SCL_CLOUD_MEDIUM, SCL_CLOUD_HIGH, SCL_CIRRUS)


def valid_mask(scl: np.ndarray) -> np.ndarray:
    """True where the ground is visible."""
    return ~np.isin(scl, INVALID_CLASSES)


def masked_fraction(valid: np.ndarray) -> float:
    return 0.0 if valid.size == 0 else float(1.0 - valid.mean())


def tile_is_usable(valid_tile: np.ndarray, max_masked: float = config.MAX_TILE_MASKED) -> bool:
    """A tile goes to the model only if at most 30% of it is masked."""
    return masked_fraction(valid_tile) <= max_masked + 1e-9  # tolerate float rounding


def apply_mask(stack: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """Set masked pixels to NaN in every band. stack is (bands, H, W)."""
    out = stack.astype("float32", copy=True)
    out[:, ~valid] = np.nan
    return out
