"""B-04: cut a city image into overlapping 224 x 224 tiles that keep their geo-reference,
and stitch per-tile predictions back into one seamless map."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from affine import Affine

from . import config


@dataclass(frozen=True)
class Tile:
    row: int            # top pixel in the full image
    col: int            # left pixel in the full image
    data: np.ndarray    # (bands, size, size)
    transform: Affine   # geo-reference of this tile's top-left pixel


def _starts(length: int, size: int, stride: int) -> list[int]:
    if length <= size:
        return [0]
    starts = list(range(0, length - size + 1, stride))
    if starts[-1] != length - size:   # last tile flush with the edge, so nothing is dropped
        starts.append(length - size)
    return starts


def tile_positions(height: int, width: int, size: int = config.TILE_SIZE,
                   overlap: int = config.TILE_OVERLAP) -> list[tuple[int, int]]:
    if not 0 <= overlap < size:
        raise ValueError("overlap must be in [0, size)")
    stride = size - overlap
    return [(r, c) for r in _starts(height, size, stride) for c in _starts(width, size, stride)]


def make_tiles(image: np.ndarray, transform: Affine, size: int = config.TILE_SIZE,
               overlap: int = config.TILE_OVERLAP, pad_value: float = 0.0) -> list[Tile]:
    """image is (bands, H, W). Images smaller than one tile are padded."""
    bands, h, w = image.shape
    if h < size or w < size:
        padded = np.full((bands, max(h, size), max(w, size)), pad_value, dtype=image.dtype)
        padded[:, :h, :w] = image
        image = padded
    tiles = []
    for r, c in tile_positions(image.shape[1], image.shape[2], size, overlap):
        tiles.append(Tile(r, c, image[:, r:r + size, c:c + size], transform @ Affine.translation(c, r)))
    return tiles


def stitch(predictions: list[np.ndarray], tiles: list[Tile], height: int, width: int) -> np.ndarray:
    """Average overlapping (size, size) predictions into one (height, width) map."""
    if len(predictions) != len(tiles):
        raise ValueError("one prediction per tile")
    size = predictions[0].shape[-1] if predictions else config.TILE_SIZE
    full_h, full_w = max(height, size), max(width, size)
    total = np.zeros((full_h, full_w), dtype="float64")
    weight = np.zeros((full_h, full_w), dtype="float64")
    for pred, t in zip(predictions, tiles, strict=True):
        total[t.row:t.row + size, t.col:t.col + size] += pred
        weight[t.row:t.row + size, t.col:t.col + size] += 1.0
    with np.errstate(invalid="ignore", divide="ignore"):
        out = np.where(weight > 0, total / weight, 0.0)
    return out[:height, :width].astype("float32")
