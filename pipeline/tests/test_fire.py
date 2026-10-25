"""B-19 to B-22."""

from datetime import date, datetime, timedelta, timezone

import pytest
from shapely.geometry import box

from drishti_pipeline import firms, risk, weather
from drishti_pipeline.tracking import Site

NOW = datetime(2026, 10, 24, 12, tzinfo=timezone.utc)

HEADER = ("latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,"
          "confidence,version,bright_ti5,frp,daynight")
CSV = HEADER + """
18.52051,73.85503,331.2,0.39,0.36,2026-10-22,0812,N,VIIRS,n,2.0NRT,295.1,4.6,D
18.60000,73.95000,329.0,0.39,0.36,2026-10-23,2048,N,VIIRS,h,2.0NRT,290.0,,N
"""


# B-19 ----------------------------------------------------------------------
def test_area_url():
    url = firms.area_url("KEY", "VIIRS_SNPP_NRT", (73.74, 18.42, 73.98, 18.64), 2, date(2026, 10, 22))
    assert url == ("https://firms.modaps.eosdis.nasa.gov/api/area/csv/KEY/VIIRS_SNPP_NRT/"
                   "73.74,18.42,73.98,18.64/2/2026-10-22")
    with pytest.raises(ValueError):
        firms.area_url("KEY", "X", (0, 0, 1, 1), 11)


def test_parse_csv():
    ev = firms.parse_csv(CSV, "pune")
    assert len(ev) == 2
    assert ev[0].detected_at == datetime(2026, 10, 22, 8, 12, tzinfo=timezone.utc)
    assert (ev[0].lat, ev[0].lon, ev[0].frp, ev[0].confidence) == (18.52051, 73.85503, 4.6, "n")
    assert ev[1].frp is None
    assert firms.parse_csv("latitude,longitude\n", "pune") == []


def test_source_switches_to_archive_for_old_dates():
    today = date(2026, 10, 24)
    assert firms.source_for(today - timedelta(days=5), today) == "VIIRS_SNPP_NRT"
    assert firms.source_for(today - timedelta(days=200), today) == "VIIRS_SNPP_SP"


# B-20 ----------------------------------------------------------------------
def test_fire_points_link_to_sites_within_500m():
    site = Site("s1", box(73.850, 18.520, 73.851, 18.521), NOW, NOW)
    dismissed = Site("s2", box(73.950, 18.600, 73.951, 18.601), NOW, NOW, status="dismissed")
    ev = firms.parse_csv(CSV, "pune")
    out = firms.match_to_sites(ev, [site, dismissed], 32643)
    assert out[0].site_id == "s1"          # about 430 m from the polygon
    assert out[1].site_id is None          # next to a dismissed site only
    near = firms.FireEvent("pune", NOW, 18.5250, 73.8505, 1.0, "n")   # about 440 m north
    far = firms.FireEvent("pune", NOW, 18.5270, 73.8505, 1.0, "n")    # about 660 m north
    linked = firms.match_to_sites([near, far], [site], 32643)
    assert [e.site_id for e in linked] == ["s1", None]


# B-22 ----------------------------------------------------------------------
def test_date_windows_cover_a_year_in_10_day_requests():
    start, end = date(2025, 10, 24), date(2026, 10, 24)
    wins = firms.date_windows(start, end)
    assert all(1 <= n <= 10 for _, n in wins)
    assert wins[0][0] == start and sum(n for _, n in wins) == (end - start).days + 1
    assert firms.date_windows(date(2026, 1, 1), date(2026, 1, 3)) == [(date(2026, 1, 1), 3)]


# B-21 ----------------------------------------------------------------------
def om_payload(rain_days_ago=None):
    days = [(date(2026, 10, 24) - timedelta(days=30 - i)).isoformat() for i in range(31)]
    rain = [0.0] * 31
    if rain_days_ago is not None:
        rain[30 - rain_days_ago] = 5.0
    return {"current": {"temperature_2m": 35.0, "relative_humidity_2m": 30.0, "wind_speed_10m": 15.0},
            "daily": {"time": days, "precipitation_sum": rain}}


def test_weather_parse_days_since_rain():
    w = weather.parse(om_payload(rain_days_ago=4), date(2026, 10, 24))
    assert (w.temperature_c, w.humidity_pct, w.wind_kmh, w.days_since_rain) == (35.0, 30.0, 15.0, 4)
    assert weather.parse(om_payload(), date(2026, 10, 24)).days_since_rain == 31


def test_fire_risk_components_and_bounds():
    hot_dry = weather.Weather(45, 15, 30, 30)
    cool_wet = weather.Weather(20, 80, 0, 0)
    assert risk.fire_risk([NOW - timedelta(days=1)] * 3, hot_dry, NOW) == 100
    assert risk.fire_risk([], cool_wet, NOW) == 0
    mid = weather.Weather(35, 37.5, 15, 15)          # every weather component at 0.5
    assert risk.fire_risk([], mid, NOW) == 30         # 60 weather points x 0.5
    assert risk.fire_risk([NOW - timedelta(days=2)], mid, NOW) == 60   # + 40 x 0.75 for a fire this week
    assert risk.fire_risk([NOW - timedelta(days=40)], mid, NOW) == 30  # older than 30 days: ignored
