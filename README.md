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
- **Flutter app** (Android + web) in `app/`, connected to Supabase. Run it with `cd app && flutter run -d chrome`. Screens and tabs per role are in [app/README.md](app/README.md).
- **Demo accounts** for each role (citizen, officer, board, admin) exist in Supabase. Ask Member A for the logins.
- **Tested:** 21 unit tests, 27 end-to-end tests against the live database (citizen, officer and admin accounts), web and Android builds, and C's API run against the same database (sites, timeline, complaints, reports, score, assistant, verification, pipeline run).

Brief section 7 (A-01 to A-24), all built:

| ID | Requirement | Where |
| --- | --- | --- |
| A-01 | Migrations for every table | `supabase/migrations/`, `supabase/config.toml` for `supabase db reset` |
| A-02 | RLS per role | tested with citizen, officer, board and admin accounts |
| A-03 | `sites_geojson` view, GIST on every geometry column | migrations |
| A-04 | Buckets: `thumbnails` public, `reports` owner + staff, `complaints` staff | migrations; tested |
| A-05 | Pilot cities, demo users per role, sample data | `seed.sql` + demo accounts |
| A-06 | Realtime on sites and fire events | tested: an update reaches an open map in under 1 s |
| A-07 | Status changes on sites and complaints audited | database trigger; tested |
| A-08 | Email code sign-in; first-time city and language; roles only by admin | app + `set_user_access` |
| A-09 | Tabs per role | Map, Scores, Report, Assistant, Profile; + Complaints; + Pipeline, Review |
| A-10 | English and Hindi from localisation files | `app/lib/l10n/*.arb` |
| A-11 | Pins clustered, coloured by status, sized by area | map |
| A-12 | Layer toggles: street/satellite, sites, fires, wards | map |
| A-13 | Combined filters with live count | map |
| A-14 | Site detail from live data | site page |
| A-15 | Before/after slider from the timeline | site page |
| A-16 | Dismiss as false positive with a reason | site page, Review |
| A-17 | Complaint draft, edit, approve, send, status timeline | complaint page |
| A-18 | Complaints list by status and ward, officer's city only | Complaints tab |
| A-19 | Report with camera/gallery photo and auto GPS | Report tab |
| A-20 | Scores with parts and monthly trend | Scores tab |
| A-21 | Assistant with "Show on map" | Assistant tab |
| A-22 | Admin: start runs, run status, review new detections | Pipeline and Review tabs |
| A-23 | Web build at a public URL | GitHub Pages workflow (needs Pages switched on, below) |
| A-24 | Loading, empty, error states; map works offline | all screens; offline cache |

### To do: Member A (2 clicks each)
- [ ] Supabase → Authentication → Emails → **Magic Link** template: add `{{ .Token }}` so the email shows the 6-digit code (A-08). Supabase's built-in email allows only a few emails per hour, so use the demo accounts (password) for the live demo.
- [ ] Repo owner (Chirayu): Settings → Pages → Source: **GitHub Actions**. After the next merge to `main`, the web app is live at `https://saxenachirayu1.github.io/drishti/` (A-23).

### To do: Member B (pipeline)
- [ ] Put the service role key in `.env` and run against Supabase: `SupabaseStore` matches the schema as is (scenes, sites, detections, fire_events, pipeline_runs, `thumbnails` bucket).
- [ ] Pick the pilot cities with the team. `pipeline/configs/cities.yaml` ids must exist in `cities`; Pune and Delhi already use your uuids, Indore and Bhopal use `indore` / `bhopal`.
- [ ] Run `drishti-pipeline worker`: it picks up runs queued from the app (Officials → Pipeline) or C's `POST /pipeline/run`.
- [ ] Replace the demo sites with real detections and give the team the real N (sites found) and M (not on any record) for the pitch.

### To do: Member C (API)
- [ ] `api/app/auth.py`: read the role from `payload["app_metadata"]["role"]`, not `user_metadata` (users can edit their own `user_metadata`, so they could make themselves admin). The database already writes the role into `app_metadata`.
- [ ] `api/app/routers/ingest.py`: `det.model_dump()` → `det.model_dump(mode="json")` (and the same for sites and fire events). Today `/ingest` fails with "Object of type date is not JSON serializable" when it saves a detection.
- [ ] Set `REPO_BACKEND=supabase` and the service role key.
- [ ] `api/app/auth.py`: the project signs user tokens with an **ECC (P-256)** key, so `jwt.decode(..., SUPABASE_JWT_SECRET, algorithms=["HS256"])` rejects every logged-in user. Verify with the public keys instead: `jwt.PyJWKClient("https://ofudjcrzdgltpoyavibr.supabase.co/auth/v1/.well-known/jwks.json")`, `algorithms=["ES256"]`, `audience="authenticated"`. The legacy secret (Project Settings → JWT Keys → Legacy JWT Secret) only verifies the old anon/service_role keys.
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
