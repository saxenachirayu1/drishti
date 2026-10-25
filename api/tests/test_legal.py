"""C-18: legal-text retrieval, and the complaint citing it."""
import os

os.environ["RUN_SCHEDULER"] = "0"


from app.granite import draft_complaint
from app.services import legal


def test_every_provision_has_citation_text_and_source():
    for e in legal.CORPUS:
        assert e["citation"] and e["text"] and e["source"]
        assert e["tags"]


def test_search_finds_the_burning_provision():
    hits = legal.search("waste being burned in the open")
    assert hits
    assert any("burn" in h["text"].lower() for h in hits)


def test_search_finds_the_water_provision():
    hits = legal.search("dumping next to a river")
    assert any("water" in h["tags"] or "river" in h["tags"] for h in hits)


def test_retrieve_picks_water_rule_for_a_waterside_site():
    picked = legal.retrieve(near_water=True, fire_risk=10)
    assert any("water" in e["tags"] for e in picked)


def test_retrieve_picks_burning_rule_for_a_high_fire_site():
    picked = legal.retrieve(near_water=False, fire_risk=80)
    assert any("burning" in e["tags"] for e in picked)


def test_complaint_quotes_real_provisions_verbatim():
    facts = {"city": "Indore", "ward_no": 12, "ward_name": "Rau", "area_m2": 3200,
             "first_seen": "2026-08-14", "last_seen": "2026-10-18",
             "growth": "grew", "near_water": True, "fire_risk": 72,
             "confidence_pct": 86}
    text = draft_complaint(facts, "English")
    picked = legal.retrieve(near_water=True, fire_risk=72)
    assert picked
    for e in picked:
        assert e["citation"] in text
        assert e["text"] in text        # quoted verbatim, not paraphrased


def test_legal_search_endpoint(client):
    r = client.get("/legal/search", params={"q": "burning waste near a river"})
    assert r.status_code == 200
    assert r.json()["results"]


def test_legal_search_rejects_empty_query(client):
    r = client.get("/legal/search", params={"q": "  "})
    assert r.status_code == 400


def test_provisions_endpoint_lists_the_corpus(client):
    assert len(client.get("/legal/provisions").json()) == len(legal.CORPUS)
