"""B-12: run a model over every usable tile of a scene and stitch one city-wide probability map."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

import numpy as np
from affine import Affine

from . import bands, cloudmask, config, tiling
from .evaluation import spectral_baseline


class Predictor(Protocol):
    name: str

    def predict(self, batch: np.ndarray) -> np.ndarray:
        """(N, 6, S, S) normalised tiles -> (N, S, S) waste probabilities in [0, 1]."""


class PrithviPredictor:
    """Fine-tuned Prithvi checkpoint from TerraTorch (needs the `train` extra and ideally a GPU)."""

    name = "prithvi"

    def __init__(self, checkpoint: str, device: str | None = None):
        import torch
        from terratorch.tasks import SemanticSegmentationTask

        self._torch = torch
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.task = SemanticSegmentationTask.load_from_checkpoint(checkpoint, map_location=self.device)
        self.task.eval()

    def predict(self, batch: np.ndarray) -> np.ndarray:
        torch = self._torch
        with torch.no_grad():
            x = torch.from_numpy(batch).float().to(self.device)
            out = self.task.model(x)
            logits = out.output if hasattr(out, "output") else out
            return torch.softmax(logits, dim=1)[:, 1].cpu().numpy()


class BaselinePredictor:
    """B-10 spectral rule. Works without a trained model, so the pipeline runs end to end from day 1."""

    name = "baseline"

    def predict(self, batch: np.ndarray) -> np.ndarray:
        # Undo the normalisation to get reflectance back, then apply the index rule.
        m = np.asarray(config.PRITHVI_MEANS)[None, :, None, None]
        s = np.asarray(config.PRITHVI_STDS)[None, :, None, None]
        refl = batch * s + m
        return np.stack([spectral_baseline(t) for t in refl])


@dataclass
class SceneResult:
    probability: np.ndarray   # (H, W) waste probability, 0 where not covered
    coverage: np.ndarray      # (H, W) True where the model actually saw clear ground
    tiles_total: int
    tiles_used: int


def predict_scene(reflectance: np.ndarray, scl: np.ndarray, predictor: Predictor,
                  batch_size: int = 8) -> SceneResult:
    """reflectance (6, H, W) x 10000 with NaN = no data; scl (H, W)."""
    h, w = scl.shape
    valid = cloudmask.valid_mask(scl) & np.isfinite(reflectance).all(axis=0)
    norm = bands.normalize(cloudmask.apply_mask(reflectance, valid))
    tiles = tiling.make_tiles(norm, Affine.identity())
    valid_tiles = tiling.make_tiles(valid[None].astype("float32"), Affine.identity())

    usable = [i for i, vt in enumerate(valid_tiles) if cloudmask.tile_is_usable(vt.data[0] > 0.5)]
    preds: list[np.ndarray] = []
    for start in range(0, len(usable), batch_size):
        idx = usable[start:start + batch_size]
        preds.extend(predictor.predict(np.stack([tiles[i].data for i in idx])))

    used_tiles = [tiles[i] for i in usable]
    if used_tiles:
        prob = tiling.stitch(preds, used_tiles, h, w)
        seen = tiling.stitch([np.ones_like(p) for p in preds], used_tiles, h, w) > 0
    else:
        prob, seen = np.zeros((h, w), "float32"), np.zeros((h, w), bool)
    coverage = seen & valid
    return SceneResult(np.where(coverage, prob, 0.0).astype("float32"), coverage, len(tiles), len(usable))
