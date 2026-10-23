import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from ..auth import require
from ..repo import get_repo
from ..services.pipeline_adapter import trigger_pipeline

router = APIRouter()


@router.post("/pipeline/run")
def run_pipeline(body: dict, user=Depends(require("admin"))):
    """
    C triggers B's pipeline (section 6).

    How B is reached lives in `services/pipeline_adapter.py` - that is the only
    file to change when B's service exists. The run is recorded either way, and
    `status` says whether B was actually reached:
      started | pending (nothing wired up yet) | failed (B unreachable).
    """
    repo = get_repo()
    rid = uuid.uuid4().hex[:8]
    repo.create_run({"id": rid, "city_id": body.get("city_id"),
                     "started_at": datetime.now(timezone.utc).isoformat(),
                     "finished_at": None, "scenes_processed": 0,
                     "sites_new": 0, "sites_updated": 0, "error": None})

    result = trigger_pipeline(city_id=body.get("city_id"),
                              date_from=body.get("date_from"),
                              date_to=body.get("date_to"),
                              run_id=rid)
    if result.get("status") == "failed":
        repo.update_run(rid, error=result.get("error"))
    repo.audit_add(user.user_id, "pipeline_run", "pipeline_run", rid, result)

    return {"run_id": rid, **result}


@router.get("/pipeline/runs/{run_id}")
def run_status(run_id: str, user=Depends(require("admin"))):
    run = get_repo().get_run(run_id)
    if not run:
        return {"error": {"code": "not_found", "message": "No such run"}}
    return run
