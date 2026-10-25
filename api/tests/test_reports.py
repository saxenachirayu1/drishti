"""C-13: citizen reports — filing one, and matching it to a site."""
import os

os.environ["RUN_SCHEDULER"] = "0"



# site-1 sits at (75.80, 22.65)
NEAR_SITE_1 = {"lon": 75.8005, "lat": 22.6503, "note": "dumping by the canal"}
FAR_AWAY = {"lon": 76.90, "lat": 21.10, "note": "new pile behind the market"}


def test_report_near_a_site_is_matched(client):
    r = client.post("/reports", json=NEAR_SITE_1)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "matched"
    assert body["site_id"] == "site-1"
    assert body["distance_m"] <= 150


def test_report_far_from_any_site_is_flagged(client):
    body = client.post("/reports", json=FAR_AWAY).json()
    assert body["status"] == "flagged_for_review"


def test_match_endpoint_404s_on_unknown_report(client):
    r = client.post("/reports/nope/match")
    assert r.status_code == 404


def test_seeded_report_can_be_matched_and_listed(client):
    assert client.post("/reports/rep-1/match").json()["status"] == "matched"
    rows = client.get("/reports", params={"status": "matched"}).json()
    assert any(row["id"] == "rep-1" and row["linked_site_id"] == "site-1"
               for row in rows)
