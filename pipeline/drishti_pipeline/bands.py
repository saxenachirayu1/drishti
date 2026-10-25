"""B-03: build the 6-band stack Prithvi expects, on one 10 m grid, and normalise it."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
from affine import Affine

from . import config
from .stac import SceneRef

BOA_OFFSET = 1000          # added to Sentinel-2 L2A digital numbers from processing baseline 04.00 (2022)
NODATA = 0


def to_reflectance_x10000(dn: np.ndarray, baseline: float | None) -> np.ndarray:
    """Convert L2A digital numbers to reflectance x 10000 (the HLS / Prithvi scale).
    No-data (0) becomes NaN. Newer products carry a +1000 offset that must be removed."""
    out = dn.astype("float32")
    nodata = dn == NODATA
    if baseline is not None and baseline >= 4.0:
        out -= BOA_OFFSET
    np.clip(out, 0, None, out=out)
    out[nodata] = np.nan
    return out


def normalize(stack: np.ndarray, means=config.PRITHVI_MEANS, stds=config.PRITHVI_STDS) -> np.ndarray:
    """(bands, H, W) reflectance x 10000 -> zero-mean, unit-variance per band. NaN -> 0 (the mean)."""
    if stack.shape[0] != len(means):
        raise ValueError(f"expected {len(means)} bands, got {stack.shape[0]}")
    m = np.asarray(means, dtype="float32")[:, None, None]
    s = np.asarray(stds, dtype="float32")[:, None, None]
    out = (stack.astype("float32") - m) / s
    return np.nan_to_num(out, nan=0.0)


@dataclass
class SceneStack:
    """One scene clipped to a city: 6 bands + SCL on a common grid."""

    reflectance: np.ndarray   # (6, H, W) reflectance x 10000, NaN = no data
    scl: np.ndarray           # (H, W) scene classification
    transform: Affine         # pixel -> projected coordinates
    crs: Any                  # CRS of `transform` (the scene's UTM zone)

    @property
    def shape(self) -> tuple[int, int]:
        return self.reflectance.shape[1], self.reflectance.shape[2]


def load_stack(scene: SceneRef, bbox: tuple[float, float, float, float]) -> SceneStack:
    """Read the six bands and SCL for one scene, clipped to the city bbox and resampled to 10 m.
    Network and disk I/O; needs the `geo` extra (rioxarray)."""
    import rioxarray  # registers the .rio accessor
    from rasterio.enums import Resampling

    if scene.item is None:
        raise ValueError("scene has no STAC item to read")
    assets = scene.item.assets
    ref = rioxarray.open_rasterio(assets["B02"].href, masked=False).squeeze(drop=True)
    ref = ref.rio.clip_box(*bbox, crs="EPSG:4326")

    layers = []
    for band in config.BANDS:
        da = rioxarray.open_rasterio(assets[band].href, masked=False).squeeze(drop=True)
        da = da.rio.clip_box(*bbox, crs="EPSG:4326")
        if da.shape != ref.shape:
            da = da.rio.reproject_match(ref, resampling=Resampling.bilinear)
        layers.append(to_reflectance_x10000(da.values, scene.processing_baseline))

    scl = rioxarray.open_rasterio(assets["SCL"].href, masked=False).squeeze(drop=True)
    scl = scl.rio.clip_box(*bbox, crs="EPSG:4326").rio.reproject_match(ref, resampling=Resampling.nearest)

    return SceneStack(np.stack(layers), scl.values.astype("uint8"), ref.rio.transform(), ref.rio.crs)


def rgb(stack: np.ndarray) -> np.ndarray:
    """(H, W, 3) red-green-blue view of a (6, H, W) stack, for thumbnails."""
    return np.stack([stack[2], stack[1], stack[0]], axis=-1)
