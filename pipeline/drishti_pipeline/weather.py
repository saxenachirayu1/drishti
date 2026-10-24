"""Open-Meteo weather for the fire-risk score (B-21). Free, no key."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from . import config

RAIN_DAY_MM = 1.0


@dataclass(frozen=True)
class Weather:
    temperature_c: float
    humidity_pct: float
    wind_kmh: float
    days_since_rain: int


def params(lat: float, lon: float) -> dict:
    return {
        "latitude": lat, "longitude": lon,
        "current": "temperature_2m,relative_humidity_2m,wind_speed_10m",
        "daily": "precipitation_sum",
        "past_days": 30, "forecast_days": 1, "timezone": "Asia/Kolkata",
    }


def parse(data: dict, today: date) -> Weather:
    cur = data["current"]
    days = data["daily"]["time"]
    rain = data["daily"]["precipitation_sum"]
    last_rain = None
    for d, mm in zip(days, rain, strict=False):
        if mm is not None and mm >= RAIN_DAY_MM and date.fromisoformat(d) <= today:
            last_rain = date.fromisoformat(d)
    since = (today - last_rain).days if last_rain else len([d for d in days if date.fromisoformat(d) <= today])
    return Weather(float(cur["temperature_2m"]), float(cur["relative_humidity_2m"]),
                   float(cur["wind_speed_10m"]), since)


def fetch(lat: float, lon: float, today: date) -> Weather:
    import httpx

    from .util import retry

    def call():
        r = httpx.get(config.OPEN_METEO_URL, params=params(lat, lon), timeout=30)
        r.raise_for_status()
        return r.json()

    return parse(retry(call), today)
