# Changing this API when A's and B's work lands

Written for whoever picks this up next. Everything below is a seam that was
put there on purpose, so the usual answer to "where do I change this?" is one
file, not a search.

**The rule of thumb:** numbers live in `.env`, data access lives behind
`get_repo()`, and B's pipeline lives behind `pipeline_adapter.py`. If you find
yourself editing a router to change behaviour, check this file first — there is
probably a knob for it.

---

## Tuning numbers without touching Python

Every threshold is an environment variable with the old hardcoded value as its
default. Change it in `.env`, restart, done. Full list in `app/config.py`.

| What | Variable | Default |
|------|----------|---------|
| Score weights | `SCORE_WEIGHTS` (JSON) | `{"active":40,"burn":25,"clear_time":20,"verified":15}` |
| Score caps (where a part scores 0) | `SCORE_CAPS` (JSON) | `{"active_per_km2":5.0,"burn_events":20,"median_days":60.0}` |
| City areas, km² | `CITY_AREA_KM2` (JSON) | `{"indore":530.0,"bhopal":463.0}` |
| Fire-risk cut-off for "burning" | `FIRE_RISK_THRESHOLD` | `60` |
| Scenes with no detection = cleared | `VERIFY_CLEAR_SCENES` | `2` |
| Shrink ratio for "shrinking" | `VERIFY_SHRINK_RATIO` | `0.8` |
| Citizen-report match radius, m | `REPORT_MATCH_RADIUS_M` | `150` |
| Days-to-clear before real history | `DEFAULT_MEDIAN_DAYS_TO_CLEAR` | `30.0` |

`GET /health` prints the ones in force, and bad values are reported at startup
rather than silently ignored.

`compute_score()` and `decide_result()` also take their thresholds as
arguments, so you can compare two tunings in a notebook without changing
anything global:

```python
compute_score(..., weights={"active": 50, "burn": 20, "clear_time": 15, "verified": 15})
```

The score response includes `parts` — the 0–1 fraction each component scored —
so you can see *why* a city scored what it did before you retune.

---

## Member A — Supabase and the web app

### Pointing at the real database
1. Put `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` in `.env`.
2. Set `REPO_BACKEND=supabase`. Without this, a typo'd key silently falls back
   to the in-memory data and everything *looks* fine — this makes it fail loudly.
3. Have A run `supabase/migrations/20261023000000_initial_schema.sql`. It includes the `ward_for_point`
   PostGIS function this API calls, and `detections.detected_on`.
4. Run the contract test against it (below).
5. Set `SUPABASE_JWT_SECRET` to turn real login checks on. Until it is set,
   every request is treated as `DEV_ROLE` (default `officer`).

### If A's schema differs from ours
`SupabaseRepo` is the **only** class that names tables and columns. Routers
never see them. So a renamed column is a one-line change in `app/repo.py`, not
a hunt through the codebase.

Two helpers handle the geometry mismatch, and they are where to look if a
geography column misbehaves:
- `_hydrate()` — PostGIS GeoJSON → shapely on the way in
- `_dehydrate()` — shapely → EWKT on the way out

### The contract test is the integration checklist
`tests/test_repo_contract.py` asserts both backends expose the same methods
*with the same signatures*. It is what catches the class of bug where the
offline path works and the live one crashes.

To run it against A's real project:

```python
# in a scratch test file
from app.repo import SupabaseRepo, set_repo
set_repo(SupabaseRepo())        # now the whole app is on A's database
```

`set_repo()` returns the previous repo so you can put it back. `reset_repo()`
drops the cache so the next call rebuilds from settings. Adding a method to
`REPO_METHODS` makes the contract test fail until every backend implements it
— that is deliberate; it is how a backend learns what it still owes.

### What A needs from this API
- `GET /sites` — the map (`centroid_lon` / `centroid_lat` are plain floats)
- `GET /sites/{id}/timeline` — the before/after slider
- `GET /cities/{id}/score` — the score, with `parts` for a breakdown
- `GET /legal/provisions` — if the UI wants to show the cited rules
- CORS is `allow_origins=["*"]` in `app/main.py`. **Tighten this to A's domains
  before deploying.**

---

## Member B — the detection pipeline

B's pipeline is a separate service. Two directions to connect, and they are
independent — do whichever is ready first.

### 1. B sends results in: `POST /ingest`
Already built. B posts any mix of sites, detections and fire events:

```bash
curl -X POST localhost:8000/ingest -H 'content-type: application/json' \
     -d "$(curl -s localhost:8000/ingest/example)"
```

`GET /ingest/example` returns a batch in exactly the accepted shape — and a
test asserts the example still validates, so it cannot drift from the schema.

What it handles for B, so B does not have to:
- **Ward assignment** happens on the way in (C-05/06). B never needs wards.
- **Idempotent**: re-posting the same ids updates rather than duplicates, so
  retries are safe.
- **Officer decisions are protected**: B re-reporting a site will *not*
  overwrite a status an officer set (`complaint_sent`, `cleared`, `dismissed`).
- **Mismatches are loud**: an unexpected field is a 422 naming it, not a
  silently dropped column. Detections for an unknown site are returned in
  `skipped_unknown_site_ids`.

The payload contract is `SiteIn` / `DetectionIn` / `FireEventIn` in
`app/models.py`. **If B's field names differ, change them there** — that is the
whole contract, in one place.

Auth: an officer/admin token, or set `INGEST_API_KEY` and have B send it as
`X-Ingest-Key` (easier for a cron job).

### 2. This API starts B's run: `POST /pipeline/run`
All of that lives in `app/services/pipeline_adapter.py`. Pick one:

- **Webhook** — set `PIPELINE_WEBHOOK_URL` (+ `PIPELINE_WEBHOOK_TOKEN`).
  No code to write. It POSTs `{city_id, date_from, date_to, run_id}`.
- **Direct call** — B ships an importable package: fill in
  `_call_b_directly()`. It is the only function to touch.
- **Queue** — publish from the same function.

Until one is configured the endpoint records the run and returns
`status: "pending"` rather than claiming work started. If B is configured but
unreachable, you get `status: "failed"` with the error stored on the run —
it never raises.

### Fields that are B's to fill
- `fire_risk` (0–100) and `growth` (free text, shown to officers) come from B
  and are passed straight through.
- Burn events in the city score are currently proxied by
  `fire_risk >= FIRE_RISK_THRESHOLD` (`app/routers/cities.py`). Once B sends
  real fire history, count `repo.list_fire_events()` instead — one function.
- `median_days_to_clear` already computes from real complaint→cleared history
  when any exists (`_median_days_to_clear`), falling back to the configured
  default until then. No change needed; it starts working on its own.

---

## Swapping the other services

| Service | File | How |
|---------|------|-----|
| AI model | `app/granite.py` | `call_granite()` is the only caller. Returns `None` → templates take over, so the API never hard-depends on the model. |
| Email | `app/emailer.py` | `send_email()`. Blank `RESEND_API_KEY` = console mode. |
| PDF | `app/pdf.py` | `make_complaint_pdf()`. |
| Legal corpus | `app/services/legal.py` | Add to `CORPUS`; `retrieve()` picks by tag. Keep quotes verbatim. |
| Languages | `app/granite.py` | Add to `SUPPORTED_LANGUAGES` + a `_<lang>_letter()`. Unsupported = 400, never silent English. |

---

## Working on the tests

`tests/conftest.py` gives every module a `client` over a **freshly seeded
database**, so test files cannot leak state into each other and the suite does
not depend on alphabetical order. Write a new test file with just:

```python
def test_something(client):
    assert client.get("/sites").json()
```

No fixture boilerplate, no `RUN_SCHEDULER` dance — conftest handles both.

Before pushing: `ruff check . && pytest -q` — the same two steps CI runs.

---

## Known gaps

- **C-04 is unaccounted for.** It is not in the brief excerpt we have and
  nothing implements it. Check the brief and add it.
- **`SupabaseRepo` has never run against a live project.** The contract test
  covers its shape, not its behaviour. Expect to fix something on first contact.
- **`docker build` is untested** — Docker was not installed on the machine this
  was written on. The Hindi font path inside the container
  (`/usr/share/fonts/truetype/noto/`) is likewise unverified.
