"""C-17: Hindi complaints, end to end, and the PDF that carries them."""
import os

os.environ["RUN_SCHEDULER"] = "0"

import pytest
from pypdf import PdfReader

from app.fonts import find_unicode_font, needs_unicode
from app.granite import _growth_hindi, draft_complaint

FACTS = {"city": "Indore", "ward_no": 12, "ward_name": "Rau", "area_m2": 3200,
         "first_seen": "2026-08-14", "last_seen": "2026-10-18",
         "growth": "grew ~900 m2", "near_water": True,
         "fire_risk": 72, "confidence_pct": 86}


def test_hindi_draft_is_devanagari_and_not_english():
    text = draft_complaint(FACTS, "Hindi")
    assert needs_unicode(text), "Hindi draft came back as latin-1 (English?)"
    assert "संभावित" in text          # "suspected" — the C-08 wording rule
    assert "86%" in text               # confidence stated
    assert "Respected Sir/Madam" not in text


def test_english_draft_stays_english():
    text = draft_complaint(FACTS, "English")
    assert not needs_unicode(text)
    assert "suspected" in text.lower()


def test_unknown_language_falls_back_to_english():
    assert draft_complaint(FACTS, "Klingon") == draft_complaint(FACTS, "English")


def test_complaint_api_rejects_unsupported_language(client):
    r = client.post("/complaints", json={"site_id": "site-1", "language": "Klingon"})
    assert r.status_code == 400
    assert r.json()["detail"]["error"]["code"] == "bad_language"


def test_hindi_complaint_flow_writes_a_pdf(client, tmp_path, monkeypatch):
    monkeypatch.setattr("app.pdf.OUT_DIR", str(tmp_path))
    created = client.post("/complaints", json={"site_id": "site-1", "language": "Hindi"})
    assert created.status_code == 200
    body = created.json()
    assert body["language"] == "Hindi"
    assert "संभावित" in body["draft_text"]

    approved = client.post(f"/complaints/{body['id']}/approve").json()
    assert approved["status"] == "approved"
    pdf_path = approved["pdf_url"]
    assert os.path.exists(pdf_path)
    assert os.path.getsize(pdf_path) > 1000

    # The Hindi text must really be in the PDF, not the no-font English notice.
    # Shaped Devanagari does not round-trip through text extraction glyph for
    # glyph (conjuncts and reordered matras come back mangled), so assert that
    # the page carries Devanagari codepoints rather than an exact word.
    if find_unicode_font():
        text = "".join(p.extract_text() for p in PdfReader(pdf_path).pages)
        devanagari = [ch for ch in text if "\u0900" <= ch <= "\u097f"]
        assert len(devanagari) > 100, "PDF has no Devanagari; font fallback fired?"
        assert "No Devanagari font is installed" not in text

    assert client.post(f"/complaints/{body['id']}/send").json()["status"] == "sent"


@pytest.mark.parametrize("growth,expected_fragment", [
    ("grew ~900 m2 since first seen", "900"),
    ("stable", "स्थिर"),
    ("shrank ~200 m2", "200"),
])
def test_growth_is_restated_in_hindi(growth, expected_fragment):
    out = _growth_hindi(growth)
    assert expected_fragment in out
    assert not any("a" <= ch.lower() <= "z" for ch in out.replace(" ", ""))


@pytest.mark.parametrize("growth", ["unknown", "", None, "some phrase we don't know"])
def test_unrecognised_growth_is_dropped_not_inlined(growth):
    """Better to omit the clause than put English in a Hindi letter."""
    assert _growth_hindi(growth) == ""


def test_hindi_letter_has_no_stray_english_prose():
    """
    Proper nouns and the verbatim legal quotes stay in English on purpose - the
    rule text must be quoted as gazetted. Nothing else should be.
    """
    facts = dict(FACTS, growth="grew ~900 m2 since first seen")
    text = draft_complaint(facts, "Hindi")
    body = text.split("निम्नलिखित प्रावधान")[0]   # stop before the citations
    english = [w for w in body.replace("\n", " ").split()
               if any("a" <= c.lower() <= "z" for c in w)]
    # only the city and ward names, which come from the database
    assert all(w.strip("(),।") in ("Indore", "Rau") for w in english), english
