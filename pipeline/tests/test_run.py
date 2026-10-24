"""End to end, offline: B-12 to B-22 through run_detect / run_fires with MemoryStore."""

import contextlib
from datetime import date, datetime, timezone

from conftest import make_stack, scene_ref
from drishti_pipeline import firms, run, weather
from drishti_pipeline.inference import BaselinePredictor
from drishti_pipeline.store import MemoryStore
from drishti_pipeline.water import WaterIndex


def runner(scenes, stacks):
    """Fake STAC search and loader: scene id -> stack (or an exception to raise)."""
    def search(city, start, end):
        return scenes

    def load(scene, bbox):
        s = stacks[scene.stac_item_id]
        if isinstance(s, Exception):
            raise s
        return s
    return search, load


def detect(city, store, scenes, stacks, **kw):
    search, load = runner(scenes, stacks)
    return run.run_detect(city, date(2026, 10, 1), date(2026, 10, 31), store, BaselinePredictor(),
                          search=search, load=load, **kw)


def test_detect_creates_sites_detections_thumbnails_and_run_log(city):
    store = MemoryStore()
    s1 = scene_ref(3)
    stats = detect(city, store, [s1], {s1.stac_item_id: make_stack(dumps=[(100, 100, 12), (200, 40, 8)])})
    assert stats.errors == [] and stats.scenes_processed == 1 and stats.sites_new == 2
    assert len(store.sites) == 2 and len(store.detections) == 2 and len(store.files) == 2
    site = max(store.sites.values(), key=lambda s: s["confidence"])
    assert site["first_seen"] == s1.acquired_at and site["status"] == "active"
    assert all(d["thumb_url"].endswith(".png") for d in store.detections.values())
    (r,) = store.runs.values()
    assert r["status"] == "done" and r["scenes_processed"] == 1 and r["sites_new"] == 2


def test_rerun_is_idempotent(city):
    store = MemoryStore()
    s1 = scene_ref(3)
    stacks = {s1.stac_item_id: make_stack()}
    detect(city, store, [s1], stacks)
    snapshot = (len(store.sites), len(store.detections), len(store.scenes))
    again = detect(city, store, [s1], stacks)
    assert again.scenes_processed == 0                       # B-18: nothing changes
    assert (len(store.sites), len(store.detections), len(store.scenes)) == snapshot


def test_site_keeps_id_and_becomes_cleared_candidate(city):
    store = MemoryStore()
    s1, s2, s3, s4 = scene_ref(3), scene_ref(8), scene_ref(13), scene_ref(18)
    stacks = {
        s1.stac_item_id: make_stack(dumps=[(100, 100, 12)]),
        s2.stac_item_id: make_stack(dumps=[(100, 101, 13)]),   # slightly bigger, same place
        s3.stac_item_id: make_stack(dumps=[]),                  # cleaned up
        s4.stac_item_id: make_stack(dumps=[]),
    }
    detect(city, store, [s1, s2], stacks)
    assert len(store.sites) == 1
    (sid, site), = store.sites.items()
    assert site["last_seen"] == s2.acquired_at and len(store.detections) == 2

    detect(city, store, [s3], stacks)
    assert store.sites[sid]["missed_scenes"] == 1 and not store.sites[sid]["cleared_candidate"]
    detect(city, store, [s4], stacks)
    assert store.sites[sid]["cleared_candidate"] is True
    assert store.sites[sid]["status"] == "active"            # status is Member C's call, not ours


def test_cloudy_scene_is_not_evidence_of_cleanup(city):
    store = MemoryStore()
    s1, s2 = scene_ref(3), scene_ref(8)
    detect(city, store, [s1, s2], {s1.stac_item_id: make_stack(),
                                   s2.stac_item_id: make_stack(dumps=[], cloud=(60, 160, 60, 160))})
    (site,) = store.sites.values()
    assert site["missed_scenes"] == 0


def test_failed_scene_is_logged_and_retried_next_run(city, monkeypatch):
    monkeypatch.setattr("drishti_pipeline.util.time.sleep", lambda s: None)
    store = MemoryStore()
    s1, s2 = scene_ref(3), scene_ref(8)
    stats = detect(city, store, [s1, s2], {s1.stac_item_id: RuntimeError("read timed out"),
                                          s2.stac_item_id: make_stack()})
    assert stats.scenes_processed == 1 and "read timed out" in stats.errors[0]
    assert sorted(s["status"] for s in store.scenes.values()) == ["failed", "processed"]
    assert next(iter(store.runs.values()))["status"] == "failed"
    retry = detect(city, store, [s1, s2], {s1.stac_item_id: make_stack(), s2.stac_item_id: make_stack()})
    assert retry.scenes_processed == 1 and retry.errors == []


def test_new_sites_get_near_water_flag(city):
    from shapely.geometry import LineString

    from drishti_pipeline.geo import to_wgs84
    # river 50 m south of the dump at rows 100-112 (y = 2050000 - 10*112 = 2048880)
    river = to_wgs84(LineString([(378000, 2048830), (381000, 2048830)]), 32643)
    store = MemoryStore()
    s1 = scene_ref(3)
    detect(city, store, [s1], {s1.stac_item_id: make_stack(dumps=[(100, 100, 12), (10, 250, 10)])},
           water=WaterIndex([river], 32643))
    flags = sorted(s["near_water"] for s in store.sites.values())
    assert flags == [False, True]


def test_fire_run_links_events_scores_risk_and_is_idempotent(city):
    store = MemoryStore()
    s1 = scene_ref(3)
    detect(city, store, [s1], {s1.stac_item_id: make_stack()})
    (sid, site), = store.sites.items()
    c = site["geom"].centroid
    now = datetime(2026, 10, 24, 12, tzinfo=timezone.utc)
    calls = []

    def fake_fetch(key, bbox, city_id, start, days, today):
        calls.append((start, days))
        return [firms.FireEvent(city_id, datetime(2026, 10, 22, 8, 12, tzinfo=timezone.utc), round(c.y, 5),
                                round(c.x, 5), 3.2, "n"),
                firms.FireEvent(city_id, datetime(2026, 10, 22, 9, 0, tzinfo=timezone.utc), 18.70, 74.20, 1.0, "l")]

    def fake_weather(lat, lon, today):
        return weather.Weather(36, 25, 12, 20)

    res = run.run_fires(city, store, start=date(2026, 10, 22), end=date(2026, 10, 23), map_key="KEY",
                        fetch_fires=fake_fetch, fetch_weather=fake_weather, now=now)
    assert res == {"events": 2, "new_events": 2, "linked": 1, "risk_updated": 1, "error": None}
    assert calls == [(date(2026, 10, 22), 2)]
    # fire 2 days ago 30 + dry 20 days 13.3 + 36 C 11 + 25 % humidity 7.8 + 12 km/h wind 4 = 66
    assert store.sites[sid]["fire_risk"] == 66

    again = run.run_fires(city, store, start=date(2026, 10, 22), end=date(2026, 10, 23), map_key="KEY",
                          fetch_fires=fake_fetch, fetch_weather=fake_weather, now=now)
    assert again["new_events"] == 0 and len(store.fires) == 2


def test_backfill_requests_a_year_without_touching_risk(city):
    store = MemoryStore()
    calls = []
    res = run.run_backfill(city, store, months=12, map_key="KEY", today=date(2026, 10, 24),
                           fetch_fires=lambda *a: calls.append(a) or [],
                           fetch_weather=lambda *a: (_ for _ in ()).throw(AssertionError("no weather")))
    assert res["error"] is None and all(a[4] <= 10 for a in calls)
    assert calls[0][3] == date(2025, 10, 29) and sum(a[4] for a in calls) == 361   # 360 days back to today


def test_retry_gives_up_after_three_attempts():
    from drishti_pipeline.util import retry
    calls, waits = [], []

    def flaky():
        calls.append(1)
        raise TimeoutError("down")
    with contextlib.suppress(TimeoutError):
        retry(flaky, sleep=waits.append)
    assert len(calls) == 3 and waits == [2.0, 4.0]
    assert retry(lambda: "ok", sleep=waits.append) == "ok"
