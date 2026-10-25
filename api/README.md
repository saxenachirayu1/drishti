# Project Drishti — Member C (API, action engine & AI assistant)

The complete Member C backend, built from the team brief. It **runs fully
offline out of the box** (in-memory database, template AI, console email) so
you can build and demo without waiting on A or B. As you get real keys, drop
them into `.env` and the same code switches to Supabase, Granite and real
email — no code changes.

## Run it offline (2 commands)
```bash
pip install -r requirements.txt
uvicorn app.main:app --reload
```
Open http://127.0.0.1:8000/docs — every endpoint is clickable there.
(Run the tests any time with `pytest -q`, and the linter with `ruff check .`)

Or in one command with Docker (C-25):
```bash
docker compose up --build
```

## The demo flow (all on /docs)
1. `GET /sites` — 3 seeded sites, each already auto-assigned to its ward.
2. `POST /complaints` → `{"site_id": "site-1"}` — Granite drafts the letter,
   citing the provisions `/legal/search` retrieves. Add
   `"language": "Hindi"` for a Hindi complaint.
3. `POST /complaints/{id}/approve` — locks it, writes a PDF to `out/`.
4. `POST /complaints/{id}/send` — emails the ward officer (console in offline mode).
5. `POST /reports` → `{"lon": 75.8005, "lat": 22.6503}` — a citizen report,
   matched to the nearest site within 150 m.
6. `POST /assistant/chat` → `{"message": "which wards have dumps near the river?"}`.
7. `GET /cities/indore/score` — the cleanliness score with its parts.
8. `POST /verifications/run` and `POST /pipeline/run` are **admin-only**. In
   offline mode every request is the `DEV_ROLE` role, which defaults to
   `officer`, so start the server with `DEV_ROLE=admin uvicorn app.main:app`
   to try them (a 403 with `{"error": {"code": "forbidden"}}` means the guard
   is working, not that it is broken).

## Changing it later
Everything meant to be adjusted when A's and B's work arrives is listed in
**[INTEGRATION.md](INTEGRATION.md)**: the tunable numbers (all environment
variables, no code edits), the data-backend swap for A, and the two seams for
B's pipeline. The short version:

| You want to | Change |
|-------------|--------|
| Retune the score, thresholds, match radius | `.env` - see the table in INTEGRATION.md |
| Point at A's real Supabase | `REPO_BACKEND=supabase` + the keys |
| Cope with A renaming a column | `SupabaseRepo` in `app/repo.py` - the only class that names tables |
| Receive B's detections | Already built: `POST /ingest` (`GET /ingest/example` shows the shape) |
| Start B's pipeline | `app/services/pipeline_adapter.py` - one function |
| Swap the model, email, or PDF | `app/granite.py`, `app/emailer.py`, `app/pdf.py` |

`GET /health` reports the configuration actually in force, so you can confirm
an `.env` change took effect.

## What's implemented (maps to the brief's C-xx requirements)
| Area | Requirements | File |
|------|--------------|------|
| FastAPI + Pydantic + OpenAPI | C-01 | `app/main.py`, `app/models.py` |
| JWT auth + role guard | C-02 | `app/auth.py` |
| One error shape, request-id logging, /health | C-03 | `app/errors.py`, `app/main.py`, `routers/health.py` |
| Ward import + mapping (point-in-polygon) | C-05, C-06 | `services/ward_mapping.py` |
| Complaint drafting (Granite, never accuses) | C-07, C-08 | `app/granite.py`, `routers/complaints.py` |
| Approve-before-send + PDF | C-09, C-10 | `routers/complaints.py`, `app/pdf.py` |
| Email the officer | C-11 | `app/emailer.py` |
| Verification (shrinking/present/cleared) | C-12 | `services/verification.py`, `routers/verifications.py` |
| Citizen-report filing + matching | C-13 | `routers/reports.py` |
| City score 0–100 | C-14 | `services/scoring.py`, `routers/cities.py` |
| Tool-grounded assistant + guardrails | C-15, C-16, C-19 | `services/assistant_tools.py`, `routers/assistant.py` |
| Hindi complaints (draft + PDF) | C-17 | `app/granite.py`, `app/pdf.py`, `app/fonts.py` |
| Legal-text retrieval, quoted verbatim | C-18 | `services/legal.py`, `routers/legal.py` |
| 30-question assistant test set | C-20 | `tests/assistant_questions.json`, `tests/test_assistant_questions.py` |
| Scheduler | C-21 | `app/scheduler.py` |
| Docker + one-command start | C-22, C-25 | `Dockerfile`, `docker-compose.yml` |
| CI (lint + test on PR) | C-23 | `.github/workflows/api-ci.yml` |
| Unit tests | C-24 | `tests/` (196 tests) |
| Ingest from B + pipeline trigger seam | section 6 | `routers/ingest.py`, `services/pipeline_adapter.py` |

**C-04 is not in this list.** The brief's C-04 was never recorded here and
nobody has built it — check the brief and add it. Everything from C-01 to
C-25 other than C-04 is implemented.

## Hindi PDFs (C-17)
Hindi complaints need a Devanagari font plus harfbuzz shaping. The Dockerfile
installs `fonts-noto-devanagari`; on macOS the system font is found
automatically. To be certain on any machine, drop a TTF into `fonts/` — see
`fonts/README.md`. With no font at all the PDF is still written, in English,
saying the Hindi text is on the complaint record (it is never silently lost).

## Legal citations (C-18)
`services/legal.py` holds a small local corpus (SWM Rules 2016, the Air and
Water Acts, an NGT order). It is local on purpose: a complaint must quote real
rule text, so the wording has to be fixed and auditable rather than generated.
`GET /legal/search?q=...` looks provisions up; the drafter inserts the ones
that fit each site's facts. **Verify the quoted text against the gazette
before any real filing.**

## Going live (do these as each service becomes available)
Copy `.env.example` to `.env`, then fill in:

1. **Supabase (from A):** `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`. Also set
   `SUPABASE_JWT_SECRET` to turn on real login checks. The schema A must run is
   in `supabase/migrations/20261023000000_initial_schema.sql` — hand it to A (it's their job, included
   here to unblock everyone). It now also contains the `ward_for_point`
   PostGIS function the API calls for ward mapping.
2. **Granite:** `WATSONX_APIKEY`, `WATSONX_PROJECT_ID`. Confirm `GRANITE_MODEL_ID`
   is a model your watsonx project can access.
3. **Email:** `RESEND_API_KEY` (or leave blank to keep console mode for the demo).
4. Restart the server. `GET /health` shows which services are live.

## Deploy (C-22)
```bash
docker build -t drishti-api .
# push to IBM Container Registry, then deploy on Code Engine with the .env values
# set as environment variables. The web app (A) points at the public URL.
```

## Still to finish for production
- `SupabaseRepo` is wired but **not live-tested** — run it once A's project
  exists. Its geometry columns are converted to shapely on read (`_hydrate`)
  so both backends behave alike, but that path has only ever run offline.
- Fire-risk and real detection history come from B; the API already reads them
  wherever B writes them. `POST /pipeline/run` records a run and still needs
  B's entrypoint wired in (`routers/pipeline.py`).
- The city score uses two demo constants: `median_days_to_clear=30` and burn
  events proxied by `fire_risk >= 60` (`routers/cities.py`). Replace both with
  real history once complaints have been through a full cycle.
- The assistant's tool routing is keyword-based (`services/assistant_tools.py`).
  Fine for the demo; move to Granite tool-calling if the question set grows.
