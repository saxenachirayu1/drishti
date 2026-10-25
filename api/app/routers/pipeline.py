import uuid

from fastapi import APIRouter, Depends

from ..auth import require
from ..errors import api_error
from ..models import PipelineRunRequest
from ..repo import get_repo
from ..services.pipeline_adapter import trigger_pipeline

router = APIRouter()


@router.post("/pipeline/run")
def run_pipeline(body: PipelineRunRequest, user=Depends(require("admin"))):
    """
    C triggers B's pipeline (section 6) by queueing a `pipeline_runs` row.

    B's worker claims queued rows and reports progress back on the same row,
    so poll GET /pipeline/runs/{run_id} for status and counts.
    """
    rid = uuid.uuid4().hex[:8]
    result = trigger_pipeline(city_id=body.city_id, run_id=rid, kind=body.kind,
                              date_from=body.start, date_to=body.end)
    if result.get("status") == "rejected":
        raise api_error(400, "bad_kind", result["error"])

    get_repo().audit_add(user.user_id, "pipeline_run", "pipeline_run", rid, result)
    return {"run_id": rid, **result}


@router.get("/pipeline/runs/{run_id}")
def run_status(run_id: str, user=Depends(require("officer", "admin"))):
    """Progress of a run, as B's worker updates it."""
    run = get_repo().get_run(run_id)
    if not run:
        raise api_error(404, "not_found", "No such run")
    return run


@router.get("/pipeline/runs")
def list_runs(status: str = None, user=Depends(require("officer", "admin"))):
    """Recent runs, newest first. `status`: queued|running|done|failed."""
    return get_repo().list_runs(status=status)
