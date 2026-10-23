from app.services.scoring import compute_score


def test_clean_city_scores_high():
    r = compute_score(active_sites=1, city_area_km2=500, burn_events=0,
                      median_days_to_clear=5, pct_verified_cleared=1.0)
    assert r["score"] > 85


def test_dirty_city_scores_low():
    r = compute_score(active_sites=3000, city_area_km2=500, burn_events=20,
                      median_days_to_clear=60, pct_verified_cleared=0.0)
    assert r["score"] < 15


def test_score_in_range():
    r = compute_score(active_sites=50, city_area_km2=500, burn_events=5,
                      median_days_to_clear=30, pct_verified_cleared=0.4)
    assert 0 <= r["score"] <= 100
