"""Granite (watsonx.ai) wrapper with a template fallback (C-07, C-08, C-15)."""
import re

from .config import settings
from .services import legal

SUPPORTED_LANGUAGES = ("English", "Hindi")


def call_granite(prompt: str, max_tokens: int = 500):
    """Return Granite's text, or None if Granite is not configured/available."""
    if not settings.granite_on:
        return None
    try:
        from ibm_watsonx_ai import Credentials
        from ibm_watsonx_ai.foundation_models import ModelInference

        model = ModelInference(
            model_id=settings.GRANITE_MODEL_ID,
            credentials=Credentials(url=settings.WATSONX_URL, api_key=settings.WATSONX_APIKEY),
            project_id=settings.WATSONX_PROJECT_ID,
        )
        out = model.generate_text(prompt=prompt,
                                  params={"max_new_tokens": max_tokens, "temperature": 0.2})
        return out.strip() if isinstance(out, str) else str(out)
    except Exception as e:  # never crash the API because of the model
        print("[granite] falling back to template:", e)
        return None


def _growth_hindi(growth) -> str:
    """Restate B's English `growth` string in Hindi.

    B hands us free text ("grew ~900 m2 since first seen", "stable"). Quoting
    it would drop English into a Hindi letter, so recognise the shapes we know
    and otherwise leave the clause out rather than mix languages.
    """
    if not growth:
        return ""
    g = str(growth).strip().lower()
    if g in ("unknown", ""):
        return ""
    if "stable" in g or "no change" in g:
        return "क्षेत्रफल स्थिर"
    match = re.search(r"(\d[\d,]*)\s*m2", g)
    if "grew" in g or "grow" in g or "increase" in g:
        if match:
            return f"क्षेत्रफल में लगभग {match.group(1)} वर्ग मीटर की वृद्धि"
        return "क्षेत्रफल में वृद्धि"
    if "shrank" in g or "shrink" in g or "decrease" in g or "reduced" in g:
        if match:
            return f"क्षेत्रफल में लगभग {match.group(1)} वर्ग मीटर की कमी"
        return "क्षेत्रफल में कमी"
    return ""


def _english_letter(f: dict, citations: str) -> str:
    return (
        f"To the Municipal Officer, Ward {f['ward_no']} "
        f"({f['ward_name']}), {f['city']}.\n\n"
        f"Subject: Suspected illegal waste dumpsite detected by satellite "
        f"(confidence {f['confidence_pct']}%).\n\n"
        f"Respected Sir/Madam,\n\n"
        f"A suspected illegal waste dumpsite has been detected from satellite imagery "
        f"within your ward. It covers approximately {f['area_m2']} square metres "
        f"and was first observed on {f['first_seen']}, most recently on "
        f"{f['last_seen']} ({f['growth']}). "
        f"{'It lies close to a water body. ' if f['near_water'] else ''}"
        f"Its current fire-risk score is {f['fire_risk']} out of 100.\n\n"
        f"The following provisions appear relevant:\n{citations}\n\n"
        f"This is a satellite-based detection, not an accusation against any individual. "
        f"We request inspection and, if confirmed, clearance under the Solid Waste "
        f"Management Rules, 2016.\n\nRegards,\nProject Drishti (automated detection)"
    )


def _hindi_letter(f: dict, citations: str) -> str:
    growth = _growth_hindi(f.get("growth"))
    trend = f" ({growth})" if growth else ""
    return (
        f"सेवा में,\nनगरपालिका अधिकारी, वार्ड {f['ward_no']} "
        f"({f['ward_name']}), {f['city']}।\n\n"
        f"विषय: उपग्रह चित्रों से चिन्हित संभावित अवैध कचरा स्थल "
        f"(विश्वसनीयता {f['confidence_pct']}%)।\n\n"
        f"महोदय/महोदया,\n\n"
        f"आपके वार्ड में उपग्रह चित्रों के आधार पर एक संभावित अवैध कचरा स्थल "
        f"चिन्हित किया गया है। इसका क्षेत्रफल लगभग {f['area_m2']} वर्ग मीटर है। "
        f"यह पहली बार {f['first_seen']} को तथा सबसे हाल में {f['last_seen']} को "
        f"देखा गया{trend}। "
        f"{'यह स्थल एक जल स्रोत के निकट स्थित है। ' if f['near_water'] else ''}"
        f"इसका वर्तमान अग्नि-जोखिम अंक {f['fire_risk']} (100 में से) है।\n\n"
        f"निम्नलिखित प्रावधान प्रासंगिक प्रतीत होते हैं:\n{citations}\n\n"
        f"यह उपग्रह आधारित पहचान है, किसी व्यक्ति पर लगाया गया आरोप नहीं। "
        f"कृपया स्थल का निरीक्षण कराएं और पुष्टि होने पर ठोस अपशिष्ट प्रबंधन "
        f"नियम, 2016 के अंतर्गत इसे हटवाने की कार्यवाही करें।\n\n"
        f"सादर,\nप्रोजेक्ट दृष्टि (स्वचालित पहचान प्रणाली)"
    )


def draft_complaint(site_facts: dict, language: str) -> str:
    """
    C-07/C-08: draft a complaint from the site's real numbers, citing the
    provisions C-18 retrieves. Never accuses a person; always says "suspected"
    and states the confidence. Hindi and English both templated (C-17), so the
    wording rules hold even with Granite switched off.
    """
    if language not in SUPPORTED_LANGUAGES:
        language = "English"

    provisions = legal.retrieve(near_water=site_facts.get("near_water", False),
                                fire_risk=site_facts.get("fire_risk", 0))
    citations = legal.format_citations(provisions)

    facts = (
        f"Location: {site_facts['city']}, Ward {site_facts['ward_no']} "
        f"({site_facts['ward_name']}). Area: {site_facts['area_m2']} m2. "
        f"First detected: {site_facts['first_seen']}, last seen: {site_facts['last_seen']}. "
        f"Trend: {site_facts['growth']}. "
        f"Near water: {'yes' if site_facts['near_water'] else 'no'}. "
        f"Fire risk: {site_facts['fire_risk']}/100. "
        f"Confidence: {site_facts['confidence_pct']}%."
    )
    prompt = (
        "Write a formal municipal complaint letter about a SUSPECTED illegal waste "
        "dumpsite detected by satellite. Rules: formal and polite; do NOT accuse any "
        "person; call it 'suspected site detected by satellite' and state the confidence "
        "percentage; use only the facts given; quote the legal provisions supplied "
        "verbatim and do not invent any others. "
        f"Write the entire letter in {language}.\n\n"
        f"FACTS:\n{facts}\n\nLEGAL PROVISIONS:\n{citations}\n\nLETTER:"
    )
    text = call_granite(prompt)
    if text:
        return text

    # Fallback templates (the C-08 wording rules are respected in both).
    if language == "Hindi":
        return _hindi_letter(site_facts, citations)
    return _english_letter(site_facts, citations)
