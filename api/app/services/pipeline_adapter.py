"""
The one place that knows how to start Member B's pipeline (section 6).

B's pipeline is a separate service and we do not yet know how it will be
reachable. Rather than scatter that unknown, every trigger goes through
`trigger_pipeline()` here. Three ways to point it at B, cheapest first:

1. **A webhook** - set PIPELINE_WEBHOOK_URL (and PIPELINE_WEBHOOK_TOKEN).
   Nothing to write: this module POSTs {city_id, date_from, date_to, run_id}.
2. **A Python call** - B ships an importable package: replace the body of
   `_call_b_directly()` below with the import and the call. It is the only
   function you need to touch.
3. **A queue** - same place, publish a message instead.

Whichever you pick, B reports results back through `POST /ingest`, so nothing
downstream changes. Until one is configured the run is recorded and returned as
`pending`, which keeps the endpoint honest instead of pretending work started.
"""
import json
import logging
import urllib.error
import urllib.request
from typing import Optional

from ..config import settings

log = logging.getLogger("drishti.pipeline")

TIMEOUT_S = 10


def _call_b_directly(payload: dict) -> Optional[dict]:
    """
    Replace this with B's real entrypoint when their code is importable, e.g.

        from drishti_pipeline import run_city
        result = run_city(payload["city_id"],
                          date_from=payload["date_from"],
                          date_to=payload["date_to"])
        return {"mode": "direct", "status": "started", "detail": result}

    Return None to mean "not wired up", which is the default.
    """
    return None


def _post_webhook(payload: dict) -> dict:
    body = json.dumps(payload).encode()
    headers = {"content-type": "application/json"}
    if settings.PIPELINE_WEBHOOK_TOKEN:
        headers["authorization"] = f"Bearer {settings.PIPELINE_WEBHOOK_TOKEN}"
    req = urllib.request.Request(settings.PIPELINE_WEBHOOK_URL, body, headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            return {"mode": "webhook", "status": "started",
                    "http_status": resp.status}
    except urllib.error.HTTPError as e:
        log.warning("pipeline webhook returned %s", e.code)
        return {"mode": "webhook", "status": "failed", "http_status": e.code,
                "error": f"B's pipeline returned HTTP {e.code}"}
    except Exception as e:                      # network down, bad URL, timeout
        log.warning("pipeline webhook failed: %s", e)
        return {"mode": "webhook", "status": "failed", "error": str(e)}


def trigger_pipeline(city_id: str, date_from=None, date_to=None,
                     run_id: Optional[str] = None) -> dict:
    """
    Ask B to process a city. Never raises: a failure to reach B is reported in
    the return value so the caller can record it on the run.
    """
    payload = {"city_id": city_id, "date_from": date_from,
               "date_to": date_to, "run_id": run_id}

    direct = _call_b_directly(payload)
    if direct is not None:
        return direct

    if settings.PIPELINE_WEBHOOK_URL:
        return _post_webhook(payload)

    log.info("no pipeline target configured; run %s recorded only", run_id)
    return {"mode": "none", "status": "pending",
            "detail": "Set PIPELINE_WEBHOOK_URL or wire _call_b_directly() "
                      "in app/services/pipeline_adapter.py"}
