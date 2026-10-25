from fastapi import APIRouter, Depends

from ..auth import current_user
from ..granite import call_granite
from ..models import ChatRequest
from ..repo import get_repo
from ..services import assistant_tools as tools

router = APIRouter()


def _question(req: ChatRequest) -> str:
    if req.message:
        return req.message
    if req.messages:
        for m in reversed(req.messages):
            if m.get("role") == "user":
                return m.get("content", "")
    return ""


def _plural(n: int, word: str) -> str:
    return word if n == 1 else word + "s"


def _ward_label(repo, site) -> str:
    ward = next((w for w in repo.list_wards() if w["id"] == site.get("ward_id")), None)
    return f"{site['city_id']} ward {ward['ward_no'] if ward else '?'}"


def _describe(tool_name: str, rows, site_ids) -> str:
    """
    Plain-language answer built from the tool rows, used when Granite is off
    (the offline default). Every tool gets a sentence: a tool that returned
    rows must never be reported as "no match".
    """
    if not rows:
        return "No records match that question."

    repo = get_repo()

    if site_ids:
        return "Matching sites: " + ", ".join(_ward_label(repo, s) for s in rows) + "."

    if tool_name == "city_stats":
        st = rows[0]
        total, active = st["total_sites"], st["active_sites"]
        return (f"{st['city_id']}: {total} {_plural(total, 'site')} on record, "
                f"{active} still active, {st['near_water']} of those near water.")

    if tool_name == "ward_ranking":
        parts = []
        for ward_id, count in rows:
            ward = next((w for w in repo.list_wards() if w["id"] == ward_id), None)
            label = f"ward {ward['ward_no']}" if ward else "unassigned"
            parts.append(f"{label}: {count}")
        return "Sites per ward, most first - " + ", ".join(parts) + "."

    return f"{len(rows)} {_plural(len(rows), 'record')} match."


@router.post("/assistant/chat")
def chat(req: ChatRequest, user=Depends(current_user)):
    """C-15/16/19: tool-grounded assistant; answers only from tool results."""
    question = _question(req)

    refusal = tools.guard(question)
    if refusal:
        return {"answer": refusal, "tools_used": [], "site_ids": []}

    tool_name, rows = tools.route(question, city_id=req.city_id)

    # Build a compact, factual context for Granite from the tool rows only.
    if rows and isinstance(rows[0], dict) and "id" in rows[0]:
        facts = "; ".join(
            f"{s['id']} ({s['city_id']} ward {s.get('ward_id','?')}), "
            f"{int(s.get('area_m2',0))} m2, fire {s.get('fire_risk',0)}, "
            f"{'near water' if s.get('near_water') else 'dry'}"
            for s in rows
        )
        site_ids = [s["id"] for s in rows]
    else:
        facts = str(rows)
        site_ids = []

    prompt = (
        "Answer the user's question using ONLY these records. Invent nothing; "
        "be concise and factual.\n\n"
        f"RECORDS: {facts or 'none'}\n\nQUESTION: {question}\n\nANSWER:"
    )
    answer = call_granite(prompt, max_tokens=250)
    if not answer:
        answer = _describe(tool_name, rows, site_ids)

    return {"answer": answer, "tools_used": [tool_name], "site_ids": site_ids}
