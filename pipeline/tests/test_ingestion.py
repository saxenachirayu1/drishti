"""B-01 to B-05."""

from datetime import datetime, timezone

import numpy as np
import pytest
from affine import Affine

from drishti_pipeline import bands, cloudmask, composite, config, tiling
from drishti_pipeline.config import load_cities
from drishti_pipeline.stac import SceneRef, select_new_scenes


def scene(i, day, cloud, baseline=5.0):
    return SceneRef(f"S2_{i}", datetime(2026, 10, day, tzinfo=timezone.utc), cloud, baseline)


# B-01 ----------------------------------------------------------------------
def test_select_new_scenes_filters_cloud_and_duplicates():
    scenes = [scene(3, 9, 5), scene(1, 3, 10), scene(2, 5, 45), scene(1, 3, 10), scene(4, 12, 8)]
    picked = select_new_scenes(scenes, existing_ids={"S2_4"})
    assert [s.stac_item_id for s in picked] == ["S2_1", "S2_3"]  # cloudy S2_2 and stored S2_4 dropped, sorted


def test_select_new_scenes_cloud_limit_is_strict():
    assert select_new_scenes([scene(1, 1, 20.0)], set()) == []


def test_cities_config_loads(tmp_path):
    cities = load_cities(config.Settings().cities_file)
    assert len(cities) >= 1
    for c in cities.values():
        w, s, e, n = c.bbox
        assert w < e and s < n and c.utm_epsg in (32643, 32644)
    bad = tmp_path / "bad.yaml"
    bad.write_text("cities:\n  - {id: x, name: X, bbox: [2, 2, 1, 1], utm_epsg: 32643}\n")
    with pytest.raises(ValueError):
        load_cities(bad)


# B-02 ----------------------------------------------------------------------
def test_scl_mask_drops_clouds_shadows_and_nodata():
    scl = np.array([[4, 5, 8], [9, 3, 0], [10, 6, 11]], dtype="uint8")
    valid = cloudmask.valid_mask(scl)
    assert valid.tolist() == [[True, True, False], [False, False, False], [False, True, True]]


def test_tile_usable_threshold():
    valid = np.ones((10, 10), bool)
    valid[:3] = False                       # exactly 30% masked -> still usable
    assert cloudmask.tile_is_usable(valid)
    valid[3, 0] = False                     # 31% -> skipped
    assert not cloudmask.tile_is_usable(valid)


def test_apply_mask_sets_nan_in_every_band():
    stack = np.ones((6, 2, 2))
    valid = np.array([[True, False], [True, True]])
    out = cloudmask.apply_mask(stack, valid)
    assert np.isnan(out[:, 0, 1]).all() and np.isfinite(out[:, 1, 1]).all()


# B-03 ----------------------------------------------------------------------
def test_reflectance_removes_offset_for_new_baseline_only():
    dn = np.array([0, 1000, 1500, 3000], dtype="uint16")
    new = bands.to_reflectance_x10000(dn, 5.09)
    old = bands.to_reflectance_x10000(dn, 3.01)
    assert np.isnan(new[0]) and new[1:].tolist() == [0, 500, 2000]
    assert np.isnan(old[0]) and old[1:].tolist() == [1000, 1500, 3000]


def test_normalize_matches_prithvi_statistics():
    h = w = 4
    means = np.array(config.PRITHVI_MEANS)[:, None, None]
    stds = np.array(config.PRITHVI_STDS)[:, None, None]
    stack = np.broadcast_to(means + stds, (6, h, w)).copy()
    stack[0, 0, 0] = np.nan
    out = bands.normalize(stack)
    assert out.shape == (6, h, w)
    assert out[0, 0, 0] == 0.0
    assert np.allclose(out[:, 1:, 1:], 1.0)


def test_normalize_rejects_wrong_band_count():
    with pytest.raises(ValueError):
        bands.normalize(np.zeros((4, 2, 2)))


def test_band_order_is_prithvis():
    assert config.BANDS == ("B02", "B03", "B04", "B8A", "B11", "B12")


# B-04 ----------------------------------------------------------------------
def test_tiles_cover_image_and_keep_georeference():
    img = np.arange(1 * 500 * 600, dtype="float32").reshape(1, 500, 600)
    tf = Affine(10, 0, 300000, 0, -10, 2000000)
    tiles = tiling.make_tiles(img, tf, size=224, overlap=32)
    covered = np.zeros((500, 600), bool)
    for t in tiles:
        assert t.data.shape == (1, 224, 224)
        covered[t.row:t.row + 224, t.col:t.col + 224] = True
        # the tile's top-left pixel maps to the same place as in the full image
        assert t.transform @ (0, 0) == tf @ (t.col, t.row)
        assert t.data[0, 0, 0] == img[0, t.row, t.col]
    assert covered.all()


def test_stitch_is_seamless():
    h, w = 500, 600
    truth = np.random.default_rng(0).random((h, w)).astype("float32")
    tiles = tiling.make_tiles(truth[None], Affine.identity(), 224, 32)
    preds = [t.data[0] for t in tiles]      # a perfect model: overlaps agree, so stitch == input
    assert np.allclose(tiling.stitch(preds, tiles, h, w), truth)


def test_small_image_is_padded():
    tiles = tiling.make_tiles(np.ones((6, 100, 50), "float32"), Affine.identity(), 224, 32)
    assert len(tiles) == 1 and tiles[0].data.shape == (6, 224, 224)
    out = tiling.stitch([np.ones((224, 224))], tiles, 100, 50)
    assert out.shape == (100, 50)


# B-05 ----------------------------------------------------------------------
def test_median_composite_ignores_clouds():
    a = np.full((6, 2, 2), 100.0)
    b = np.full((6, 2, 2), 300.0)
    c = np.full((6, 2, 2), 200.0)
    a[:, 0, 0] = np.nan                     # cloudy in one scene
    b[:, 1, 1] = c[:, 1, 1] = np.nan
    a[:, 1, 1] = np.nan                     # cloudy everywhere
    out = composite.median_composite([a, b, c])
    assert out[0, 0, 0] == 250.0 and out[0, 0, 1] == 200.0 and np.isnan(out[0, 1, 1])
    assert composite.clear_fraction(out) == 0.75


def test_group_by_month():
    s = [scene(1, 3, 1), scene(2, 20, 1),
         SceneRef("S2_x", datetime(2026, 9, 30, tzinfo=timezone.utc), 1, 5.0)]
    assert {k: len(v) for k, v in composite.group_by_month(s).items()} == {"2026-09": 1, "2026-10": 2}
