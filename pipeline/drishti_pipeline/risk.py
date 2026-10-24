"""B-21: fire-risk score from 0 to 100 for each site.

score = sum(weight x component), each component scaled to 0..1:
  recent_fires (40): fires at the site in the last 30 days, 3 or more = 1; any fire in the last 7 days = at least 0.75
  dry_days     (20): days since >= 1 mm of rain, 30 or more = 1
  temperature  (20): 25 C = 0 up to 45 C = 1
  humidity     (10): 60 % = 0 down to 15 % = 1
  wind         (10): 0 km/h = 0 up to 30 km/h = 1
Weights live in config.RISK_WEIGHTS; tune them against past fires at known sites.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from . import config
from .weather import Weather


def _clamp(x: float) -> float:
    return max(0.0, min(1.0, x))


def components(fire_times: list[datetime], weather: Weather, now: datetime) -> dict[str, float]:
    last30 = [t for t in fire_times if now - timedelta(days=30) <= t <= now]
    recent = _clamp(len(last30) / 3)
    if any(t >= now - timedelta(days=7) for t in last30):
        recent = max(recent, 0.75)
    return {
        "recent_fires": recent,
        "dry_days": _clamp(weather.days_since_rain / 30),
        "temperature": _clamp((weather.temperature_c - 25) / 20),
        "humidity": _clamp((60 - weather.humidity_pct) / 45),
        "wind": _clamp(weather.wind_kmh / 30),
    }


def fire_risk(fire_times: list[datetime], weather: Weather, now: datetime,
              weights: dict[str, float] = config.RISK_WEIGHTS) -> int:
    comps = components(fire_times, weather, now)
    total = sum(weights[k] * v for k, v in comps.items()) / sum(weights.values()) * 100
    return int(round(_clamp(total / 100) * 100))
