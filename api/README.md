# api/ (Member C)

FastAPI service.

- `app/routers/` endpoints (health, pipeline, sites, complaints, verifications, scores, reports, assistant)
- `app/services/` Granite client, complaint drafting, PDF, email, scoring, verification, scheduler
- `app/prompts/` versioned prompt files
- `tests/` unit and API tests

Run locally: `uvicorn app.main:app --reload`, docs at `/docs`.
