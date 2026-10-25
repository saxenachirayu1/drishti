"""Every tunable number in one place. Requirement IDs refer to the team requirements doc."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml

_PIPELINE_ROOT = Path(__file__).resolve().parent.parent

# --- Imagery (B-01 to B-04) ------------------------------------------------
STAC_URL = "https://planetarycomputer.microsoft.com/api/stac/v1"
COLLECTION = "sentinel-2-l2a"
MAX_CLOUD_COVER = 20.0          # % scene-level cloud cover (B-01)
MAX_TILE_MASKED = 0.30          # skip tiles with more than 30% cloud/shadow/no-data (B-02)

# Prithvi-EO uses 6 HLS bands. Their Sentinel-2 equivalents, in Prithvi's order (B-03).
BANDS = ("B02", "B03", "B04", "B8A", "B11", "B12")
BAND_NAMES = ("blue", "green", "red", "nir_narrow", "swir1", "swir2")
TARGET_RESOLUTION = 10.0        # metres; 20 m bands are resampled to this grid

# Normalisation in reflectance x 10000, the scale HLS and Prithvi use.
# Values for the Prithvi-EO-2.0 300M backbone used in training/prithvi_dumpsite.yaml.
# CONFIRM against the config.json of the exact checkpoint on Hugging Face before training;
# the same numbers must appear in the training YAML.
PRITHVI_BACKBONE = "prithvi_eo_v2_300"
PRITHVI_MEANS = (1087.0, 1342.0, 1433.0, 2734.0, 1958.0, 1363.0)
PRITHVI_STDS = (2248.0, 2179.0, 2178.0, 1850.0, 1242.0, 1049.0)

TILE_SIZE = 224                 # pixels (B-04)
TILE_OVERLAP = 32               # pixels shared with each neighbour, removes seams

# --- Detection and polygons (B-12, B-13) -----------------------------------
PROB_THRESHOLD = 0.5
MIN_SITE_AREA_M2 = 900.0        # about 3 x 3 Sentinel-2 pixels
SIMPLIFY_TOLERANCE_M = 5.0
PUBLIC_MIN_CONFIDENCE = 0.6     # N-06: below this, sites stay off the public map

# --- Site tracking (B-14, B-15) --------------------------------------------
MATCH_IOU = 0.3
MATCH_CENTROID_M = 50.0
CLEARED_AFTER_MISSES = 2        # missing from 2 clear scenes -> cleared candidate

# --- Near water (B-17) -----------------------------------------------------
NEAR_WATER_M = 200.0
OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# --- Fire layer (B-19 to B-22) ---------------------------------------------
FIRMS_URL = "https://firms.modaps.eosdis.nasa.gov/api/area/csv"
FIRMS_NRT_SOURCE = "VIIRS_SNPP_NRT"   # near real time, recent weeks
FIRMS_ARCHIVE_SOURCE = "VIIRS_SNPP_SP"  # standard product, for backfill of older dates
FIRMS_NRT_MAX_AGE_DAYS = 60
FIRMS_MAX_DAY_RANGE = 10              # the area API returns at most 10 days per call
FIRE_MATCH_M = 500.0                  # VIIRS pixels are about 375 m
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

# Fire-risk weights (B-21). Starting values; tune against past fires at known sites.
RISK_WEIGHTS = {"recent_fires": 40, "dry_days": 20, "temperature": 20, "humidity": 10, "wind": 10}


@dataclass(frozen=True)
class City:
    """A city the pipeline covers. Adding a city is config only (N-19)."""

    id: str                     # cities.id in Supabase
    name: str
    bbox: tuple[float, float, float, float]  # west, south, east, north (EPSG:4326)
    utm_epsg: int               # 32643 for most of western/central India, 32644 for eastern India
    labels: str | None = None   # path to the labelled GeoJSON, if any


@dataclass
class Settings:
    supabase_url: str = field(default_factory=lambda: os.getenv("SUPABASE_URL", ""))
    supabase_key: str = field(default_factory=lambda: os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""))
    firms_map_key: str = field(default_factory=lambda: os.getenv("FIRMS_MAP_KEY", ""))
    checkpoint: str = field(default_factory=lambda: os.getenv("DRISHTI_CHECKPOINT", ""))
    cities_file: Path = field(
        default_factory=lambda: Path(os.getenv("DRISHTI_CITIES", str(_PIPELINE_ROOT / "configs" / "cities.yaml")))
    )
    data_dir: Path = field(default_factory=lambda: Path(os.getenv("DRISHTI_DATA", "data")))


def load_cities(path: Path) -> dict[str, City]:
    """Read configs/cities.yaml into City objects, keyed by city id."""
    raw = yaml.safe_load(Path(path).read_text()) or {}
    cities: dict[str, City] = {}
    for entry in raw.get("cities", []):
        bbox = tuple(float(v) for v in entry["bbox"])
        if len(bbox) != 4 or not (bbox[0] < bbox[2] and bbox[1] < bbox[3]):
            raise ValueError(f"bad bbox for {entry.get('name')}: {bbox}")
        city = City(id=str(entry["id"]), name=entry["name"], bbox=bbox,  # type: ignore[arg-type]
                    utm_epsg=int(entry["utm_epsg"]), labels=entry.get("labels"))
        cities[city.id] = city
    return cities
