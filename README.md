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

## Status (25 Oct 2026)

### Done: Member A (Supabase + app)
- **Supabase is live** and seeded with demo data. The full table-by-table reference, keys, roles and functions are in **[docs/schema.md](docs/schema.md)**. The schema follows the brief's section 6, so B's `store.py` and C's `repo.py` work against it unchanged (tested).
- **Flutter app** (Android + web) in `app/`, connected to Supabase. Features: national-to-street map with live pins, wards and fires; site page with the before/after growth slider; complaint draft → approve → send → close in English and Hindi; citizen reports with photos (auto-matched to sites within 150 m); city leaderboard; English/Hindi assistant; officials dashboard (reports, complaints, pipeline queue, user roles). Run it with `cd app && flutter run -d chrome`. See [app/README.md](app/README.md).
- **Tested:** 16 unit tests, 20 end-to-end tests against the live database (citizen, officer and admin accounts), web and Android builds, and C's API run against the same database (sites, timeline, complaints, reports, score, assistant, verification, pipeline run).

### To do: Member B (pipeline)
- [ ] Put the service role key in `.env` and run against Supabase: `SupabaseStore` matches the schema as is (scenes, sites, detections, fire_events, pipeline_runs, `thumbnails` bucket).
- [ ] Pick the pilot cities with the team. `pipeline/configs/cities.yaml` ids must exist in `cities`; Pune and Delhi already use your uuids, Indore and Bhopal use `indore` / `bhopal`.
- [ ] Run `drishti-pipeline worker`: it picks up runs queued from the app (Officials → Pipeline) or C's `POST /pipeline/run`.
- [ ] Replace the demo sites with real detections and give the team the real N (sites found) and M (not on any record) for the pitch.

### To do: Member C (API)
- [ ] `api/app/auth.py`: read the role from `payload["app_metadata"]["role"]`, not `user_metadata` (users can edit their own `user_metadata`, so they could make themselves admin). The database already writes the role into `app_metadata`.
- [ ] `api/app/routers/ingest.py`: `det.model_dump()` → `det.model_dump(mode="json")` (and the same for sites and fire events). Today `/ingest` fails with "Object of type date is not JSON serializable" when it saves a detection.
- [ ] Set `REPO_BACKEND=supabase`, the service role key and `SUPABASE_JWT_SECRET` (Supabase → Project Settings → API → JWT secret).
- [ ] `/pipeline/run` already queues work for B's worker through `pipeline_runs`, so no webhook is needed.
- [ ] Add the watsonx keys for Granite, deploy to IBM Code Engine, and send Member A the public URL. The app then uses it with `--dart-define=API_BASE_URL=<url>`.

### To do: everyone
- [ ] Review and merge the open branches into `main` (`a/supabase-schema`, `b/pipeline`, `c/api-action-engine-assistant`). C's branch has an older copy of `supabase/migrations/20261023000000_initial_schema.sql`; keep the one from `a/supabase-schema`.
- [ ] Replace the demo wards with real ward boundaries and officer emails for the pilot cities, and add real government dump lists to `official_sites`.
- [ ] Arnav and Divyam: the IBM Bob part.
- [ ] Pitch deck with the real numbers.

## Working agreements

- Branch from `main`, open a pull request, get one review before merging.
- Schema changes only as new files in `supabase/migrations/`, through Member A.
- Secrets go in `.env` (copied from `.env.example`), never in commits or the Flutter app.
- Branch names: `a/<feature>`, `b/<feature>`, `c/<feature>`.

## Tech stack

Flutter, Supabase (Postgres + PostGIS), Python, FastAPI, IBM Prithvi-EO with TerraTorch, IBM Granite on watsonx.ai, NASA FIRMS, Open-Meteo, IBM Cloud Code Engine.
