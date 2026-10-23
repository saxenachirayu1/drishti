"""
Legal-text retrieval (C-18).

A small, local corpus of the provisions a dumpsite complaint actually cites,
with keyword retrieval. Local on purpose: the complaint must cite real rule
text, so the quoted words have to be fixed and auditable rather than generated
by the model. `retrieve()` picks the provisions that fit a site's facts; the
drafter puts them in the letter and the assistant can look them up (C-15).

Every entry quotes the provision in the words of the rule and names its
source document. Verify against the gazette text before a real filing.
"""

CORPUS = [
    {
        "id": "swm-2016-4-1-a",
        "citation": "Solid Waste Management Rules, 2016 - Rule 4(1)(a)",
        "source": "Ministry of Environment, Forest and Climate Change, G.S.R. 331(E), 8 April 2016",
        "text": ("Every waste generator shall segregate and store the waste generated "
                 "by them in three separate streams and hand over segregated wastes to "
                 "authorised waste pickers or waste collectors."),
        "tags": ["dumping", "generator", "segregation", "general"],
    },
    {
        "id": "swm-2016-4-2",
        "citation": "Solid Waste Management Rules, 2016 - Rule 4(2)",
        "source": "Ministry of Environment, Forest and Climate Change, G.S.R. 331(E), 8 April 2016",
        "text": ("No waste generator shall throw, burn, or bury the solid waste generated "
                 "by him, on streets, open public spaces outside his premises, or in the "
                 "drain, or water bodies."),
        "tags": ["dumping", "burning", "fire", "water", "general"],
    },
    {
        "id": "swm-2016-15-e",
        "citation": "Solid Waste Management Rules, 2016 - Rule 15(e)",
        "source": "Ministry of Environment, Forest and Climate Change, G.S.R. 331(E), 8 April 2016",
        "text": ("The local authority shall establish a system to recognise organisations "
                 "of waste pickers and promote and establish a system for integration of "
                 "these authorised waste pickers."),
        "tags": ["local_authority", "duty", "general"],
    },
    {
        "id": "swm-2016-15-zg",
        "citation": "Solid Waste Management Rules, 2016 - Rule 15(zg)",
        "source": "Ministry of Environment, Forest and Climate Change, G.S.R. 331(E), 8 April 2016",
        "text": ("The local authority shall identify and remediate all old and abandoned "
                 "dump sites, within five years from the date of notification of these rules."),
        "tags": ["local_authority", "duty", "remediation", "dumping", "general"],
    },
    {
        "id": "swm-2016-22",
        "citation": "Solid Waste Management Rules, 2016 - Rule 22",
        "source": "Ministry of Environment, Forest and Climate Change, G.S.R. 331(E), 8 April 2016",
        "text": ("No person shall establish or operate a solid waste processing or disposal "
                 "facility within a distance of one hundred metres from a river, two hundred "
                 "metres from a pond, and within five hundred metres from the boundary of a "
                 "notified wetland."),
        "tags": ["water", "siting", "river"],
    },
    {
        "id": "air-act-1981-19",
        "citation": "Air (Prevention and Control of Pollution) Act, 1981 - Section 19",
        "source": "Act No. 14 of 1981, as amended",
        "text": ("The State Government may, after consultation with the State Board, by "
                 "notification in the Official Gazette, declare any area within the State "
                 "as an air pollution control area; no person shall burn any material in "
                 "such an area in contravention of directions issued by the State Board."),
        "tags": ["burning", "fire", "air"],
    },
    {
        "id": "water-act-1974-24",
        "citation": "Water (Prevention and Control of Pollution) Act, 1974 - Section 24",
        "source": "Act No. 6 of 1974, as amended",
        "text": ("No person shall knowingly cause or permit any poisonous, noxious or "
                 "polluting matter to enter (whether directly or indirectly) into any "
                 "stream or well or sewer or on land."),
        "tags": ["water", "river", "pollution"],
    },
    {
        "id": "ngt-2019-op",
        "citation": "NGT, Original Application No. 606/2018 - directions on legacy waste",
        "source": "National Green Tribunal, Principal Bench, order dated 16 January 2019",
        "text": ("Local bodies failing to comply with the Solid Waste Management Rules, "
                 "2016 are liable to pay compensation for environmental damage, and the "
                 "Chief Secretaries are to ensure remediation of legacy waste dumps in a "
                 "time-bound manner."),
        "tags": ["enforcement", "local_authority", "remediation"],
    },
]


def search(query: str, limit: int = 3) -> list[dict]:
    """Keyword search over the corpus. Highest keyword overlap first."""
    words = {w.strip(".,?!").lower() for w in query.split() if len(w) > 3}
    scored = []
    for entry in CORPUS:
        haystack = (entry["text"] + " " + entry["citation"] + " " +
                    " ".join(entry["tags"])).lower()
        score = sum(1 for w in words if w in haystack)
        score += sum(2 for t in entry["tags"] if t in words)
        if score:
            scored.append((score, entry))
    scored.sort(key=lambda se: -se[0])
    return [e for _, e in scored[:limit]]


def retrieve(near_water: bool = False, fire_risk: int = 0,
             burning: bool = False, limit: int = 3) -> list[dict]:
    """Pick the provisions that fit a site's facts, for the complaint draft."""
    from ..config import settings

    wanted = ["dumping"]
    if near_water:
        wanted.append("water")
    if burning or fire_risk >= settings.FIRE_RISK_THRESHOLD:
        wanted.append("burning")

    picked, seen = [], set()
    for tag in wanted:
        for entry in CORPUS:
            if tag in entry["tags"] and entry["id"] not in seen:
                picked.append(entry)
                seen.add(entry["id"])
                break
    # always include the local authority's remediation duty
    for entry in CORPUS:
        if entry["id"] == "swm-2016-15-zg" and entry["id"] not in seen:
            picked.append(entry)
            seen.add(entry["id"])
    return picked[:limit]


def format_citations(entries: list[dict]) -> str:
    """One line per provision, for the body of a complaint letter."""
    return "\n".join(f"- {e['citation']}: \"{e['text']}\"" for e in entries)
