"""Member B's ingest seam (POST /ingest)."""
import os

os.environ["RUN_SCHEDULER"] = "0"



BATCH = {
    "run_id": "run-test",
    "sites": [{
        "id": "site-42", "city_id": "indore",
        "centroid_lon": 75.80, "centroid_lat": 22.65,
        "area_m2": 2400, "first_seen": "2026-10-01", "last_seen": "2026-10-20",
        "near_water": False, "fire_risk": 35,
        "growth": "grew ~400 m2 since first seen",
    }],
    "detections": [{
        "id": "det-42-1", "site_id": "site-42", "scene_id": "sc-9",
        "confidence": 0.88, "area_m2": 2400, "detected_on": "2026-10-20",
    }],
    "fire_events": [{
        "id": "fe-42-1", "site_id": "site-42",
        "detected_at": "2026-10-19T06:00:00Z", "frp": 8.2,
        "confidence": 0.7, "source": "VIIRS",
    }],
}


def test_ingest_writes_and_assigns_a_ward(client):
    r = client.post("/ingest", json=BATCH)
    assert r.status_code == 200, r.text
    wrote = r.json()["written"]
    assert wrote == {"sites": 1, "detections": 1, "fire_events": 1,
                     "wards_assigned": 1}

    site = client.get("/ingest/sites/site-42").json()
    assert site["ward_id"] == "w-ind-12", "B's site was not mapped to a ward"
    assert site["area_m2"] == 2400


def test_ingest_is_idempotent(client):
    client.post("/ingest", json=BATCH)
    before = len(client.get("/sites").json())
    client.post("/ingest", json=BATCH)
    assert len(client.get("/sites").json()) == before
    assert len(client.get("/sites/site-42/timeline").json()) == 1


def test_ingest_does_not_overwrite_an_officer_status(client):
    """B re-reporting a site must not undo 'complaint_sent' or 'cleared'."""
    client.post("/ingest", json=BATCH)
    client.post("/sites/site-42/dismiss", json={"reason": "not waste"})
    assert client.get("/ingest/sites/site-42").json()["status"] == "dismissed"

    client.post("/ingest", json={"sites": [dict(BATCH["sites"][0], status="active")]})
    assert client.get("/ingest/sites/site-42").json()["status"] == "dismissed"


def test_detection_for_an_unknown_site_is_skipped_not_dropped_silently(client):
    r = client.post("/ingest", json={"detections": [{
        "id": "det-ghost", "site_id": "site-does-not-exist",
        "confidence": 0.5, "area_m2": 10,
    }]}).json()
    assert r["written"]["detections"] == 0
    assert r["skipped_unknown_site_ids"] == ["site-does-not-exist"]


def test_unknown_field_is_a_422_naming_it(client):
    """A schema mismatch with B must be loud, not silently dropped."""
    bad = {"sites": [dict(BATCH["sites"][0], area_sqm=2400)]}
    r = client.post("/ingest", json=bad)
    assert r.status_code == 422
    assert "area_sqm" in r.text


def test_out_of_range_confidence_is_rejected(client):
    r = client.post("/ingest", json={"detections": [{
        "id": "det-bad", "site_id": "site-1", "confidence": 1.5, "area_m2": 10,
    }]})
    assert r.status_code == 422


def test_empty_batch_is_accepted(client):
    assert client.post("/ingest", json={}).json()["written"]["sites"] == 0


def test_the_example_matches_what_ingest_accepts(client):
    """The documented example must not drift from the real schema."""
    example = client.get("/ingest/example").json()
    assert client.post("/ingest", json=example).status_code == 200


def test_ingest_key_is_accepted_when_configured(client, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "INGEST_API_KEY", "s3cret")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", "jwt")  # turn role auth on
    assert client.post("/ingest", json={}, headers={"X-Ingest-Key": "s3cret"}).status_code == 200
    assert client.post("/ingest", json={}, headers={"X-Ingest-Key": "wrong"}).status_code == 401
