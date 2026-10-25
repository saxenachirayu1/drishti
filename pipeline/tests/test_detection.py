"""B-12 to B-17."""

import io
from datetime import datetime, timezone

import numpy as np
import pytest
from PIL import Image
from shapely.geometry import LineString, box

from conftest import EPSG, SIZE, TRANSFORM, make_stack
from drishti_pipeline import config, thumbnails, tracking, water
from drishti_pipeline.geo import to_wgs84
from drishti_pipeline.inference import BaselinePredictor, predict_scene
from drishti_pipeline.polygonize import Detection, polygonize

T0 = datetime(2026, 10, 1, tzinfo=timezone.utc)


# B-12 ----------------------------------------------------------------------
def test_predict_scene_finds_the_dump_and_respects_clouds():
    stack = make_stack(dumps=[(100, 100, 12), (20, 250, 10)], cloud=(0, 60, 200, 300))
    res = predict_scene(stack.reflectance, stack.scl, BaselinePredictor())
    assert res.probability.shape == (SIZE, SIZE)
    assert res.probability[105, 105] == 1.0 and res.probability[200, 50] == 0.0
    assert res.probability[25, 255] == 0.0            # dump under the cloud is not reported
    assert not res.coverage[25, 255] and res.coverage[150, 150]
    assert res.tiles_used == res.tiles_total          # this cloud is under 30% of every tile


def test_cloudy_tiles_are_skipped():
    stack = make_stack(cloud=(0, SIZE, 0, SIZE))
    res = predict_scene(stack.reflectance, stack.scl, BaselinePredictor())
    assert res.tiles_used == 0 and not res.coverage.any() and res.probability.sum() == 0


# B-13 ----------------------------------------------------------------------
def test_polygonize_area_confidence_and_min_size():
    prob = np.zeros((SIZE, SIZE), "float32")
    prob[100:112, 100:112] = 0.9                      # 120 m x 120 m = 14,400 m2
    prob[200:202, 200:202] = 0.95                     # 400 m2 -> under 900 m2, dropped
    dets = polygonize(prob, TRANSFORM, EPSG)
    assert len(dets) == 1
    d = dets[0]
    assert d.area_m2 == pytest.approx(14400)
    assert d.confidence == pytest.approx(0.9)
    lon, lat = d.geom.centroid.x, d.geom.centroid.y
    assert 73.8 < lon < 73.9 and 18.4 < lat < 18.6    # stored in EPSG:4326 near Pune


# B-14 / B-15 ----------------------------------------------------------------
def det_at(x, y, size=100, conf=0.8):
    gm = box(x, y, x + size, y + size)
    return Detection(to_wgs84(gm, EPSG), gm, gm.area, conf)


def site_from(det, sid, **kw):
    return tracking.Site(sid, det.geom, T0, T0, **kw)


def test_same_dump_keeps_its_id():
    old = site_from(det_at(380000, 2049000), "s1")
    moved = det_at(380030, 2049000)                  # shifted 30 m: IoU 0.54 -> same site
    far = det_at(381000, 2049000)                    # 1 km away -> new site
    ups = tracking.match_detections([moved, far], [old], EPSG)
    assert {u.site_id for u in ups} == {"s1", None}


def test_centroid_rule_matches_low_iou_detections():
    old = site_from(det_at(380000, 2049000, size=200), "s1")
    small = det_at(380070, 2049070, size=40)          # IoU 0.04, but centroids 10 m apart
    assert tracking.match_detections([small], [old], EPSG)[0].site_id == "s1"


def test_two_detections_on_one_site_merge():
    old = site_from(det_at(380000, 2049000, size=150), "s1")
    a, b = det_at(380000, 2049000), det_at(380050, 2049050)       # overlap 50 m x 50 m
    ups = tracking.match_detections([a, b], [old], EPSG)
    assert len(ups) == 1 and ups[0].site_id == "s1"
    assert ups[0].detection.area_m2 == pytest.approx(17500)     # union, overlap counted once


def test_cleared_candidate_after_two_clear_misses():
    det = det_at(380000, 2049000)
    site = site_from(det, "s1")
    full = np.ones((SIZE, SIZE), bool)
    u1 = tracking.scene_updates([site], [], full, TRANSFORM, EPSG, T0)[0]
    assert u1.fields == {"missed_scenes": 1, "cleared_candidate": False}
    site.missed_scenes = 1
    u2 = tracking.scene_updates([site], [], full, TRANSFORM, EPSG, T0)[0]
    assert u2.fields == {"missed_scenes": 2, "cleared_candidate": True}


def test_cloud_over_site_is_not_a_miss_and_dismissed_sites_are_left_alone():
    site = site_from(det_at(380000, 2049000), "s1")
    dismissed = site_from(det_at(380500, 2049000), "s2", status="dismissed")
    none = np.zeros((SIZE, SIZE), bool)
    assert tracking.scene_updates([site, dismissed], [], none, TRANSFORM, EPSG, T0) == []


def test_redetection_resets_misses():
    det = det_at(380000, 2049000)
    site = site_from(det, "s1", missed_scenes=1, cleared_candidate=True)
    u = tracking.scene_updates([site], [det], np.ones((SIZE, SIZE), bool), TRANSFORM, EPSG, T0)[0]
    assert u.site_id == "s1" and u.fields["missed_scenes"] == 0 and u.fields["cleared_candidate"] is False


# B-16 ----------------------------------------------------------------------
def test_thumbnail_is_a_png_with_the_outline():
    stack = make_stack()
    site = box(*(TRANSFORM @ (100, 112)), *(TRANSFORM @ (112, 100)))
    png = thumbnails.render(np.moveaxis(stack.reflectance[[2, 1, 0]], 0, -1), TRANSFORM, site)
    img = Image.open(io.BytesIO(png))
    assert img.format == "PNG" and img.size == (256, 256)
    assert (np.asarray(img)[..., 0] == 255).any()     # red outline drawn
    assert thumbnails.storage_path("site", "scene") == "site/scene.png"


# B-17 ----------------------------------------------------------------------
def test_overpass_parse_and_near_water():
    data = {"elements": [
        {"type": "way", "tags": {"waterway": "river"},
         "geometry": [{"lat": 18.520, "lon": 73.840}, {"lat": 18.520, "lon": 73.860}]},
        {"type": "way", "tags": {"natural": "water"},
         "geometry": [{"lat": 18.53, "lon": 73.87}, {"lat": 18.53, "lon": 73.871},
                      {"lat": 18.531, "lon": 73.871}, {"lat": 18.53, "lon": 73.87}]},
    ]}
    geoms = water.parse_overpass(data)
    assert [g.geom_type for g in geoms] == ["LineString", "Polygon"]
    idx = water.WaterIndex(geoms, EPSG)
    near = box(73.850, 18.5210, 73.851, 18.5215)      # about 110 m north of the river
    far = box(73.850, 18.5100, 73.851, 18.5105)       # about 1 km south
    assert idx.near(near) and not idx.near(far)
    assert not water.WaterIndex([], EPSG).near(near)
    assert 'way["natural"="water"](18.5,73.8,18.6,73.9)' in water.overpass_query((73.8, 18.5, 73.9, 18.6))


def test_near_water_threshold_is_200m():
    river_m = LineString([(378000, 2048000), (384000, 2048000)])   # straight, in metres
    idx = water.WaterIndex([to_wgs84(river_m, EPSG)], EPSG)
    for gap, expected in ((190, True), (210, False)):
        y = 2048000 + gap
        site = to_wgs84(box(381000, y, 381050, y + 50), EPSG)
        assert idx.near(site) is expected
    assert config.NEAR_WATER_M == 200
