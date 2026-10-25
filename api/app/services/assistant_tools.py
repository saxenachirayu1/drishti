"""
Assistant tools (C-15, C-16, C-19). The assistant never writes SQL and never
reads anything outside this fixed set of read-only tools. A guardrail blocks
off-topic questions and ignores instructions hidden in the question text.
"""
from ..config import settings
from ..repo import get_repo

ON_TOPIC = ("site", "dump", "waste", "ward", "fire", "burn", "city", "river",
            "water", "clean", "score", "complaint")

# crude injection guard: refuse if the user tries to redirect the assistant
INJECTION = ("ignore previous", "ignore the above", "system prompt",
             "reveal", "api key", "password", "secret")


def guard(question: str):
    q = question.lower()
    if any(bad in q for bad in INJECTION):
        return "I can only answer questions about dumpsites, wards, fires and city scores."
    if not any(word in q for word in ON_TOPIC):
        return "I can only help with Drishti's dumpsite, ward, fire and city-score data."
    return None  # ok


# --- the fixed tool set ---
def search_sites(city_id=None, near_water=None, status=None):
    return get_repo().list_sites(city_id=city_id, near_water=near_water, status=status)


def site_details(site_id):
    return get_repo().get_site(site_id)


def city_stats(city_id):
    sites = get_repo().list_sites(city_id=city_id)
    active = [s for s in sites if s["status"] == "active"]
    return {"city_id": city_id, "total_sites": len(sites), "active_sites": len(active),
            "near_water": sum(1 for s in active if s["near_water"])}


def ward_ranking(city_id):
    sites = get_repo().list_sites(city_id=city_id)
    by_ward = {}
    for s in sites:
        by_ward[s.get("ward_id")] = by_ward.get(s.get("ward_id"), 0) + 1
    return sorted(by_ward.items(), key=lambda kv: kv[1], reverse=True)


def _city_in(question: str):
    """Pick a known city out of the question, so stats work without city_id."""
    q = question.lower()
    for city in get_repo().list_cities():
        if city["id"] in q or city["name"].lower() in q:
            return city["id"]
    return None


def route(question: str, city_id=None):
    """Pick a tool from the question, run it, return (tool_name, rows)."""
    q = question.lower()
    if "fire" in q or "burn" in q:
        rows = [s for s in search_sites(city_id=city_id)
                if s["fire_risk"] >= settings.FIRE_RISK_THRESHOLD]
        return "search_sites(fire)", rows
    if "river" in q or "water" in q:
        return "search_sites(near_water)", search_sites(city_id=city_id, near_water=True)
    if "how many" in q or "count" in q or "stats" in q:
        target = city_id or _city_in(q)
        return "city_stats", [city_stats(target)] if target else []
    if "ward" in q and ("most" in q or "rank" in q or "worst" in q):
        return "ward_ranking", ward_ranking(city_id or _city_in(q))
    return "search_sites", search_sites(city_id=city_id)
