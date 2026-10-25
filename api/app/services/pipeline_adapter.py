"""
Starting Member B's pipeline (section 6).

B's worker (`drishti-pipeline worker`) polls the `pipeline_runs` table for rows
with status 'queued', oldest `queued_at` first, and claims them. So triggering a
run means inserting a queued row - there is no webhook and no service to call,
which also means a run survives the worker being down.

The contract, from A's schema and B's `store.claim_next_run()`:
    kind    'detect' | 'fires'
    params  jsonb; B reads params["start"] / params["end"] as ISO dates
    status  'queued' -> B sets 'running', then 'done' | 'failed'

A webhook is still supported for a deployment where B runs as a service
instead: set PIPELINE_WEBHOOK_URL and it is called after the row is queued.
"""
import json
import logging
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Optional

from ..config import settings
from ..repo import get_repo

log = logging.getLogger("drishti.pipeline")

KINDS = ("detect", "fires")
TIMEOUT_S = 10


def queue_run(run_id: str, city_id: str, kind: str = "detect",
              start=None, end=None) -> dict:
    """Insert the queued row B's worker will claim."""
    params = {}
    if start:
        params["start"] = str(start)
    if end:
        params["end"] = str(end)

    row = {
        "id": run_id,
        "city_id": city_id,
        "kind": kind,
        "params": params,
        "status": "queued",
        "queued_at": datetime.now(timezone.utc).isoformat(),
        # B sets these when it claims the row and when it finishes.
        "started_at": None,
        "finished_at": None,
        "scenes_processed": 0,
        "sites_new": 0,
        "sites_updated": 0,
        "error": None,
    }
    get_repo().create_run(row)
    return row


def _post_webhook(payload: dict) -> dict:
    body = json.dumps(payload).encode()
    headers = {"content-type": "application/json"}
    if settings.PIPELINE_WEBHOOK_TOKEN:
        headers["authorization"] = f"Bearer {settings.PIPELINE_WEBHOOK_TOKEN}"
    req = urllib.request.Request(settings.PIPELINE_WEBHOOK_URL, body, headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            return {"notified": True, "http_status": resp.status}
    except urllib.error.HTTPError as e:
        log.warning("pipeline webhook returned %s", e.code)
        return {"notified": False, "error": f"B's pipeline returned HTTP {e.code}"}
    except Exception as e:                      # network down, bad URL, timeout
        log.warning("pipeline webhook failed: %s", e)
        return {"notified": False, "error": str(e)}


def trigger_pipeline(city_id: str, run_id: str, kind: str = "detect",
                     date_from=None, date_to=None) -> dict:
    """
    Queue a run for B. Never raises: the row is what matters, and a webhook
    that cannot be reached is reported rather than failing the request.

    status is 'queued' - the work is genuinely pending until B's worker claims
    it, so we do not claim it "started".
    """
    if kind not in KINDS:
        return {"status": "rejected",
                "error": f"kind must be one of {list(KINDS)}"}

    queue_run(run_id, city_id, kind, date_from, date_to)
    out: dict[str, Optional[str]] = {
        "status": "queued", "kind": kind,
        "detail": "waiting for B's worker (drishti-pipeline worker) to claim it",
    }

    if settings.PIPELINE_WEBHOOK_URL:
        out.update(_post_webhook({"city_id": city_id, "kind": kind,
                                  "date_from": date_from, "date_to": date_to,
                                  "run_id": run_id}))
    return out
