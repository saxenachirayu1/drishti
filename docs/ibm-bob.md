# IBM Bob in Drishti

> **STATUS: PLAN, NOT YET A RECORD OF WORK DONE.**
> This document describes how IBM Bob is applied to Drishti. Sections marked
> **FILL IN** must be replaced with what actually happened — with file names,
> commits and screenshots — before this is submitted as a description of
> completed work. Do not submit it with the placeholders still in it.

## Why a lifecycle tool fits this project

Drishti is not one codebase. It is three, built in parallel by three people,
all agreeing on one Postgres schema:

| Area | Owner | Language |
|---|---|---|
| `app/` Flutter mobile + web dashboard | Member A | Dart |
| `pipeline/` Sentinel-2 ingestion, Prithvi inference | Member B | Python |
| `api/` FastAPI complaints, scoring, assistant | Member C | Python |
| `supabase/` Postgres + PostGIS schema, RLS | Member A | SQL |

Almost nothing that went wrong in this project was a hard algorithmic problem.
It was *contract drift* — three components quietly disagreeing about the same
field. The real defects found during integration were:

- the API read a user's role from `user_metadata`, which users can edit
  themselves, while the database wrote the real role to `app_metadata` — a
  privilege escalation, not a typo
- the API verified tokens with `HS256` while the project signs them `ES256`,
  so every logged-in user was rejected
- `detections.detected_on` was read by the API but missing from the schema
- the ingest endpoint sent `datetime.date` objects to PostgREST, which cannot
  serialise them, so the pipeline could not deliver detections at all
- the shared `.env.example` used `WATSONX_API_KEY` while the API read
  `WATSONX_APIKEY`, so filling in the team's own file left the model switched off

Every one of these is invisible in a single file and obvious across the repo.
That is the class of problem a development assistant with a view of the whole
project is positioned to catch, and it is where we apply IBM Bob.

## Where we apply it

### 1. Cross-component contract checking
The highest-value use. Drishti has unusually explicit ground truth to check
against: a declarative SQL schema in `supabase/migrations/`, a published
OpenAPI spec from FastAPI, a documented ingest contract in `api/app/models.py`,
`docs/pipeline-db-contract.md`, and 228 passing tests. Bob is pointed at the
schema and asked whether `api/app/repo.py` and
`pipeline/drishti_pipeline/store.py` still agree with it — so a renamed column
surfaces while editing rather than in production.

> **FILL IN:** which drift Bob actually caught, and the commit that fixed it.

### 2. Wiring the Flutter client to the API
The app currently falls back to its own local logic
(`lib/services/local_assistant.dart`, `complaint_drafter.dart`,
`verification_logic.dart`) whenever `API_BASE_URL` is empty, which it is in the
deployed build. Closing that gap means generating a typed Dart client against
the API's OpenAPI spec and verifying each call against the live service.

> **FILL IN:** the generated/edited files and how Bob was prompted.

### 3. Deployment
Producing the IBM Cloud Code Engine configuration from the existing
`api/Dockerfile`, including the environment variables the service reads
(documented in `api/INTEGRATION.md`), and the CORS tightening noted in
`api/app/main.py` before the API is exposed publicly.

> **FILL IN:** the deployment manifest produced and whether it worked first try.

### 4. Test generation
Extending the 30-question assistant test set (`api/tests/assistant_questions.json`,
requirement C-20) with new grounding and prompt-injection cases, and adding
coverage for the Hindi complaint path and the legal-provision retrieval.

> **FILL IN:** which tests Bob wrote and whether they found a real bug.

### 5. A Bob Skill for the repo's conventions
Drishti has rules that are easy to violate and expensive to get wrong:

- a complaint must never accuse a person — it reports a *suspected* site
  detected by satellite and states its confidence (requirement C-08)
- legal provisions are quoted **verbatim** from the stored corpus in
  `api/app/services/legal.py`, never paraphrased or generated
- schema changes are new files in `supabase/migrations/`, owned by Member A
- officer-set statuses (`complaint_sent`, `cleared`, `dismissed`) must never be
  overwritten by the pipeline re-reporting a site

Packaging these as a Bob Skill means any team member gets help consistent with
them instead of plausible-looking code that breaks a rule a reviewer would catch.

> **FILL IN:** the Skill definition and where it lives.

## Workflow

> **FILL IN — this section must describe what you actually did.** Cover:
> - How Bob was accessed: IDE extension, CLI, or web
> - A typical loop: what you asked for, what came back, how you iterated
> - Whether it had repository context or worked file by file
> - How its output was reviewed before committing — for this project, every
>   change still had to pass `ruff check .` and `pytest -q`

## A concrete example

> **FILL IN.** One real before/after is worth more to a reader than any amount
> of general description. Include the prompt, what Bob produced, what you
> changed, and the resulting commit.

## Where it did not help

> **FILL IN.** Honest limitations read as credible. Candidates specific to this
> project: anything requiring live credentials (watsonx, Supabase console),
> judgement calls about real municipal data such as ward boundaries and officer
> email addresses, and decisions about what *should* be built — Drishti's
> remaining work is mostly keys, clicks and real-world data rather than code.

## Verification

Whatever Bob contributed is held to the same bar as anything else in this repo:

- `ruff check .` and `pytest -q` — 228 tests, green in CI
- `flutter analyze` and `flutter test` — 21 tests, green in CI
- the API runs fully offline with no credentials, so any reviewer can clone and
  run it: `pip install -r requirements.txt && uvicorn app.main:app --reload`
