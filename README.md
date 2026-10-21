# Drishti

India's garbage, seen from space. Drishti finds illegal waste dumps and open burning in Indian cities from free Sentinel-2 satellite imagery, using a fine-tuned IBM-NASA Prithvi model. It alerts the responsible ward with an IBM Granite-drafted complaint and verifies cleanup from space.

Built for the IBM SkillsBuild hackathon. The full brief and requirements are in the team doc (see `docs/`).

## Repo structure

| Folder | What lives here | Owner |
| --- | --- | --- |
| `app/` | Flutter app: mobile for citizens, web dashboard for officials | Member A |
| `supabase/` | Database migrations (Postgres + PostGIS), RLS, storage, seed data | Member A |
| `pipeline/` | Geospatial AI: satellite ingestion, Prithvi fine-tuning and inference, site tracking, fire layer | Member B |
| `api/` | FastAPI service: complaints, verification, city scores, Granite assistant, scheduler | Member C |
| `docs/` | Architecture notes, API contract, decisions | Everyone |

## Working agreements

- Branch from `main`, open a pull request, get one review before merging.
- Schema changes only as new files in `supabase/migrations/`, through Member A.
- Secrets go in `.env` (copied from `.env.example`), never in commits or the Flutter app.
- Branch names: `a/<feature>`, `b/<feature>`, `c/<feature>`.

## Tech stack

Flutter, Supabase (Postgres + PostGIS), Python, FastAPI, IBM Prithvi-EO with TerraTorch, IBM Granite on watsonx.ai, NASA FIRMS, Open-Meteo, IBM Cloud Code Engine.
