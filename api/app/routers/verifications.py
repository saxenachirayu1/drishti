import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from ..auth import require
from ..repo import get_repo
from ..services.verification import decide_result

router = APIRouter()


@router.post("/verifications/run")
def run_verification(user=Depends(require("admin"))):
    """
    C-12: for every site with a sent complaint, look at its detection history
    and set the result (still_present / shrinking / cleared).
    """
    repo = get_repo()
    results = []
    for site in repo.list_sites(status="complaint_sent"):
        dets = sorted(repo.list_detections(site["id"]),
                      key=lambda d: str(d.get("detected_on", "")))
        areas = [d["area_m2"] for d in dets] or [site.get("area_m2", 0)]
        result = decide_result(areas)
        vid = uuid.uuid4().hex[:8]
        repo.add_verification({"id": vid, "site_id": site["id"],
                               "complaint_id": None, "result": result,
                               "checked_at": datetime.now(timezone.utc).isoformat()})
        if result == "cleared":
            repo.update_site(site["id"], status="cleared")
        results.append({"site_id": site["id"], "result": result})
    return {"checked": len(results), "results": results}
