"""Synthetic Sentinel-2 scenes over Pune (UTM 43N), so the whole pipeline runs offline."""

from datetime import datetime, timezone

import numpy as np
import pytest
from affine import Affine
from rasterio.crs import CRS

from drishti_pipeline.bands import SceneStack
from drishti_pipeline.config import City
from drishti_pipeline.stac import SceneRef

EPSG = 32643
TRANSFORM = Affine(10, 0, 378000, 0, -10, 2050000)   # 10 m pixels, top-left near 73.85 E, 18.54 N
SIZE = 300                                           # 3 km x 3 km

VEGETATION = [400, 700, 500, 4000, 2000, 1200]       # high NIR -> not waste
DUMP = [1200, 1400, 1600, 1900, 3000, 2600]          # bare, SWIR-bright -> waste for the baseline rule


def make_stack(dumps=((100, 100, 12),), cloud=None) -> SceneStack:
    """dumps: (row, col, size_px) squares of waste. cloud: (row0, row1, col0, col1) covered by cloud."""
    refl = np.empty((6, SIZE, SIZE), "float32")
    refl[:] = np.asarray(VEGETATION, "float32")[:, None, None]
    for r, c, n in dumps:
        refl[:, r:r + n, c:c + n] = np.asarray(DUMP, "float32")[:, None, None]
    scl = np.full((SIZE, SIZE), 4, "uint8")          # 4 = vegetation
    if cloud:
        r0, r1, c0, c1 = cloud
        scl[r0:r1, c0:c1] = 9                        # 9 = high-probability cloud
    return SceneStack(refl, scl, TRANSFORM, CRS.from_epsg(EPSG))


def scene_ref(day: int, sid: str | None = None) -> SceneRef:
    return SceneRef(sid or f"S2_PUNE_{day:02d}", datetime(2026, 10, day, 5, 30, tzinfo=timezone.utc), 5.0, 5.11)


@pytest.fixture
def city():
    return City(id="pune", name="Pune", bbox=(73.83, 18.50, 73.88, 18.55), utm_epsg=EPSG)
