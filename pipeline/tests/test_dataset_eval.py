"""B-06, B-07, B-09, B-10, N-25."""

import json

import numpy as np
import pytest
import rasterio
from affine import Affine
from shapely.geometry import box

from drishti_pipeline import dataset, evaluation, labels


# B-06 ----------------------------------------------------------------------
def write_geojson(path, feats):
    path.write_text(json.dumps({"type": "FeatureCollection", "features": feats}))


def feat(label, x=73.85, y=18.52):
    return {"type": "Feature", "properties": {"label": label, "source": "test"},
            "geometry": box(x, y, x + 0.001, y + 0.001).__geo_interface__}


def test_load_labels_and_target(tmp_path):
    p = tmp_path / "city.geojson"
    write_geojson(p, [feat("waste")] * 150 + [feat("construction"), feat("bare_soil")])
    lbls = labels.load_labels(p)
    assert labels.label_stats(lbls) == {"waste": 150, "construction": 1, "bare_soil": 1}
    assert labels.meets_target(lbls)
    assert not labels.meets_target(lbls[:149])


def test_load_labels_rejects_unknown_label(tmp_path):
    p = tmp_path / "bad.geojson"
    write_geojson(p, [feat("garbage")])
    with pytest.raises(ValueError, match="label"):
        labels.load_labels(p)


# B-07 ----------------------------------------------------------------------
def test_rasterize_mask():
    tf = Affine(10, 0, 0, 0, -10, 100)            # 10 x 10 pixels of 10 m
    mask = labels.rasterize_mask([box(20, 50, 60, 90)], tf, (10, 10))
    assert mask.sum() == 4 * 4 and mask[1:5, 2:6].all()
    assert labels.rasterize_mask([], tf, (10, 10)).sum() == 0


def grid_tiles(n=20, size=2240.0):
    return [labels.TileFootprint(f"t{r}_{c}", (c * size, r * size, (c + 1) * size, (r + 1) * size))
            for r in range(n) for c in range(n)]


def test_spatial_split_is_reproducible_and_balanced():
    tiles = grid_tiles()
    a = labels.spatial_split(tiles, seed=7)
    assert a == labels.spatial_split(tiles, seed=7)
    assert a != labels.spatial_split(tiles, seed=8)
    counts = {s: list(a.values()).count(s) for s in ("train", "val", "test")}
    assert counts["train"] > counts["val"] > 0 and counts["test"] > 0


def test_spatial_split_never_leaks_overlapping_tiles():
    # Overlapping tiles (stride smaller than tile) are the leak risk.
    tiles = [labels.TileFootprint(f"t{r}_{c}", (c * 1500.0, r * 1500.0, c * 1500.0 + 2240, r * 1500.0 + 2240))
             for r in range(15) for c in range(15)]
    split = labels.spatial_split(tiles, seed=1)
    kept = [t for t in tiles if split[t.name] != "dropped"]
    for i, a in enumerate(kept):
        for b in kept[i + 1:]:
            if box(*a.bounds).intersection(box(*b.bounds)).area > 0:
                assert split[a.name] == split[b.name]


def test_write_tile_layout_and_ignore(tmp_path):
    img = np.full((6, 4, 4), 1500.0, dtype="float32")
    img[:, 0, 0] = np.nan
    mask = np.zeros((4, 4), "uint8")
    mask[2:, 2:] = 1
    ip, mp = dataset.write_tile(tmp_path, "train", "pune_0001", img, mask, Affine(10, 0, 0, 0, -10, 40), "EPSG:32643")
    assert ip.name == "pune_0001_img.tif" and ip.parent.parent.name == "train"
    with rasterio.open(ip) as src:
        assert src.count == 6 and src.dtypes[0] == "int16" and src.read(1)[1, 1] == 1500
    with rasterio.open(mp) as src:
        m = src.read(1)
        assert m[0, 0] == dataset.IGNORE and m[3, 3] == 1 and m[1, 1] == 0


# B-09 ----------------------------------------------------------------------
def test_pixel_iou():
    pred = np.array([[1, 1, 0], [0, 0, 0]])
    truth = np.array([[1, 0, 0], [0, 0, 1]])
    assert evaluation.pixel_iou(pred, truth) == pytest.approx(1 / 3)
    assert evaluation.pixel_iou(pred, truth, ignore=np.array([[0, 0, 0], [0, 0, 1]])) == pytest.approx(1 / 2)
    assert evaluation.pixel_iou(np.zeros((2, 2)), np.zeros((2, 2))) == 1.0


def test_site_scores_iou_threshold_and_one_to_one():
    truth = [box(0, 0, 10, 10), box(100, 100, 110, 110), box(200, 200, 210, 210)]
    pred = [box(0, 0, 10, 9),         # IoU 0.9 -> hit
            box(1, 1, 10, 10),        # also overlaps truth 0, but truth 0 is taken -> miss
            box(100, 100, 102, 102),  # IoU 0.04 -> miss
            box(500, 500, 510, 510)]  # nothing there -> miss
    s = evaluation.site_scores(pred, truth)
    assert (s.true_positives, s.precision, s.recall) == (1, 0.25, pytest.approx(1 / 3))
    assert "| prithvi |" in evaluation.report({"prithvi": (0.5, s)})


# B-10 ----------------------------------------------------------------------
def test_spectral_baseline_flags_bare_bright_ground_not_vegetation():
    stack = np.zeros((6, 1, 2), "float32")
    # pixel 0: vegetation (high NIR); pixel 1: bare, SWIR-bright
    stack[:, 0, 0] = [400, 700, 500, 4000, 2000, 1200]
    stack[:, 0, 1] = [1200, 1400, 1600, 1900, 3000, 2600]
    assert evaluation.spectral_baseline(stack).tolist() == [[0.0, 1.0]]


# N-25 ----------------------------------------------------------------------
def test_false_positive_breakdown():
    negs = [(box(0, 0, 10, 10), "construction"), (box(20, 0, 30, 10), "bare_soil")]
    fps = [box(1, 1, 2, 2), box(5, 5, 6, 6), box(21, 1, 22, 2), box(50, 50, 51, 51)]
    assert evaluation.false_positive_breakdown(fps, negs) == {"construction": 2, "bare_soil": 1, "unlabelled": 1}


def test_build_dataset_end_to_end(tmp_path):
    from conftest import EPSG, make_stack
    from drishti_pipeline.geo import to_wgs84

    stack = make_stack(dumps=[(120, 120, 12)], cloud=(0, 100, 0, 300))   # top tiles 45% cloudy -> left out
    x0, y0 = stack.transform @ (120, 132)
    x1, y1 = stack.transform @ (132, 120)
    lbl = labels.Label(to_wgs84(box(x0, y0, x1, y1), EPSG), "waste")
    counts = dataset.build_dataset(stack, [lbl], tmp_path, "pune", block_m=500)
    written = sum(counts.values())
    assert 1 <= written <= 2 and set(counts) <= {"train", "val", "test"}   # 2 clear tiles; a leaking one is dropped
    masks = list(tmp_path.glob("*/masks/*_mask.tif"))
    total_waste = 0
    for m in masks:
        with rasterio.open(m) as src:
            arr = src.read(1)
            total_waste += int((arr == 1).sum())
    assert total_waste == 144 * written                                  # the 12 x 12 px dump in every tile
    assert len(list(tmp_path.glob("*/images/*_img.tif"))) == len(masks) == written


def test_training_yaml_matches_pipeline_normalisation():
    import yaml

    from drishti_pipeline import config
    with open("training/prithvi_dumpsite.yaml") as fh:
        cfg = yaml.safe_load(fh)
    data = cfg["data"]["init_args"]
    assert tuple(data["means"]) == config.PRITHVI_MEANS and tuple(data["stds"]) == config.PRITHVI_STDS
    assert cfg["model"]["init_args"]["model_args"]["backbone"] == config.PRITHVI_BACKBONE
    assert cfg["model"]["init_args"]["model_args"]["num_classes"] == 2
