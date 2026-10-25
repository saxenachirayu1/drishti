"""Write training tiles to disk in the layout TerraTorch's generic segmentation datamodule reads:

    <out>/<split>/images/<name>_img.tif   (6 bands, int16, reflectance x 10000, 0 = no data)
    <out>/<split>/masks/<name>_mask.tif   (1 band, uint8: 1 waste, 0 not waste, 255 ignore)
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import rasterio
from affine import Affine

IGNORE = 255


def write_tile(out_dir: Path, split: str, name: str, image: np.ndarray, mask: np.ndarray,
               transform: Affine, crs) -> tuple[Path, Path]:
    img_dir = out_dir / split / "images"
    mask_dir = out_dir / split / "masks"
    img_dir.mkdir(parents=True, exist_ok=True)
    mask_dir.mkdir(parents=True, exist_ok=True)
    bands, h, w = image.shape
    img = np.nan_to_num(image, nan=0).round().clip(-32768, 32767).astype("int16")
    m = mask.astype("uint8").copy()
    m[np.isnan(image).any(axis=0)] = IGNORE   # no supervision where we have no data

    img_path = img_dir / f"{name}_img.tif"
    mask_path = mask_dir / f"{name}_mask.tif"
    profile = {"driver": "GTiff", "height": h, "width": w, "transform": transform, "crs": crs, "compress": "deflate"}
    with rasterio.open(img_path, "w", count=bands, dtype="int16", nodata=0, **profile) as dst:
        dst.write(img)
    with rasterio.open(mask_path, "w", count=1, dtype="uint8", nodata=IGNORE, **profile) as dst:
        dst.write(m, 1)
    return img_path, mask_path


def build_dataset(stack, labels_wgs84, out_dir: Path, prefix: str, seed: int = 42,
                  block_m: float = 2000.0) -> dict[str, int]:
    """B-07 end to end for one scene: label polygons -> masks -> 224 px tiles (no overlap) ->
    spatial split -> GeoTIFFs. Tiles with more than 30% cloud are left out. Returns tiles per split."""
    from . import cloudmask, config
    from .geo import to_metric
    from .labels import WASTE, TileFootprint, rasterize_mask, spatial_split
    from .tiling import make_tiles

    epsg = stack.crs.to_epsg()
    h, w = stack.shape
    waste = [to_metric(lbl.geom, epsg) for lbl in labels_wgs84 if lbl.label == WASTE]
    mask = rasterize_mask(waste, stack.transform, (h, w))
    valid = cloudmask.valid_mask(stack.scl)
    image = cloudmask.apply_mask(stack.reflectance, valid)

    img_tiles = make_tiles(image, stack.transform, config.TILE_SIZE, overlap=0, pad_value=np.nan)
    mask_tiles = make_tiles(mask[None], stack.transform, config.TILE_SIZE, overlap=0)
    valid_tiles = make_tiles(valid[None].astype("uint8"), stack.transform, config.TILE_SIZE, overlap=0)

    keep, footprints = [], []
    for i, (t, vt) in enumerate(zip(img_tiles, valid_tiles, strict=True)):
        if not cloudmask.tile_is_usable(vt.data[0].astype(bool)):
            continue
        name = f"{prefix}_{t.row:05d}_{t.col:05d}"
        x0, y0 = t.transform @ (0, 0)
        x1, y1 = t.transform @ (config.TILE_SIZE, config.TILE_SIZE)
        footprints.append(TileFootprint(name, (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))))
        keep.append((name, i))

    split = spatial_split(footprints, block_m=block_m, seed=seed)
    counts: dict[str, int] = {}
    for name, i in keep:
        s = split[name]
        if s == "dropped":
            continue
        write_tile(out_dir, s, name, img_tiles[i].data, mask_tiles[i].data[0], img_tiles[i].transform, stack.crs)
        counts[s] = counts.get(s, 0) + 1
    return counts
