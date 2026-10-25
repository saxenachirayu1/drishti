"""Drishti API — Member C. FastAPI app wiring every router together."""
import logging
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routers import (
    assistant,
    cities,
    complaints,
    health,
    ingest,
    legal,
    pipeline,
    reports,
    sites,
    verifications,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("drishti")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # On startup: warn about bad config, assign sites to wards, start scheduler.
    for problem in settings.check():
        log.warning("config: %s", problem)
    log.info("backend=%s granite=%s",
             "supabase" if not settings.offline else "in-memory",
             "on" if settings.granite_on else "template-fallback")
    try:
        from .services.ward_mapping import assign_all
        assign_all()
    except Exception as e:
        log.warning("ward assignment skipped: %s", e)
    try:
        from .scheduler import start_scheduler
        start_scheduler()
    except Exception as e:
        log.warning("scheduler not started: %s", e)
    yield


app = FastAPI(
    title="Project Drishti API (Member C)",
    version="1.0",
    description="API, action engine and AI assistant for Drishti.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # tighten to the app's domains for deploy (N-10)
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_id(request: Request, call_next):
    """C-03: request logging with an id."""
    rid = uuid.uuid4().hex[:8]
    log.info("req %s %s %s", rid, request.method, request.url.path)
    response = await call_next(request)
    response.headers["x-request-id"] = rid
    return response


for r in (health, sites, complaints, verifications, cities,
          reports, pipeline, assistant, legal, ingest):
    app.include_router(r.router)
