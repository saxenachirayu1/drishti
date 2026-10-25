"""
City "cleanliness from space" score (C-14), 0-100, higher = cleaner.

Weights (from the brief): active sites 40, burn events 25, days-to-clear 20,
verified-cleared 15. Each part is turned into a 0..1 "good" fraction against a
documented cap, then combined.

Both the weights and the caps are starting points meant to be tuned once real
data lands: set SCORE_WEIGHTS / SCORE_CAPS in .env rather than editing this
file, or pass them to compute_score() to compare tunings side by side.
"""
from typing import Optional

from ..config import settings


def _good(value, cap):
    return max(0.0, 1.0 - (value / cap))


def compute_score(active_sites: int, city_area_km2: float, burn_events: int,
                  median_days_to_clear: float, pct_verified_cleared: float,
                  weights: Optional[dict] = None,
                  caps: Optional[dict] = None) -> dict:
    """
    Score a city. `weights` and `caps` default to the configured ones; pass
    them to try a different tuning without touching the environment.

    The returned dict includes `parts`, the 0..1 fraction each component
    scored, so a reviewer can see *why* a city scored what it did.
    """
    weights = weights or settings.SCORE_WEIGHTS
    caps = caps or settings.SCORE_CAPS

    density = active_sites / city_area_km2 if city_area_km2 else active_sites
    a = _good(density, caps["active_per_km2"])
    b = _good(burn_events, caps["burn_events"])
    c = _good(median_days_to_clear, caps["median_days"])
    d = max(0.0, min(1.0, pct_verified_cleared))  # already 0..1

    score = round(weights["active"] * a + weights["burn"] * b +
                  weights["clear_time"] * c + weights["verified"] * d)
    return {
        "score": int(score),
        "active_sites": active_sites,
        "burn_events": burn_events,
        "median_days_to_clear": round(median_days_to_clear, 1),
        "pct_verified_cleared": round(d, 2),
        "parts": {"active": round(a, 3), "burn": round(b, 3),
                  "clear_time": round(c, 3), "verified": round(d, 3)},
        "weights": dict(weights),
    }
