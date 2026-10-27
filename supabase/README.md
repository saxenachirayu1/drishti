# supabase/ (Member A)

- `migrations/20261023000000_initial_schema.sql` the schema: tables, PostGIS, triggers, views, RPCs, RLS, storage, realtime
- `migrations/20261027000000_complaint_tracking.sql` complaints raised by residents: routing by type, ticket codes, the live timeline, area search, impact counts
- `seed.sql` demo data (cities, wards, sites with six months of detections, fires, scores, localities, one demo PWD road)
- `tests/` runs every migration and the seed on plain PostgreSQL + PostGIS and checks them (`tests/run.sh`; CI: `.github/workflows/db.yml`)

Set up a new project: paste the migration, then `seed.sql`, into the Supabase SQL editor. Or with the CLI, `supabase db reset`.

Schema changes go in a new migration file, through Member A.

## How it fits B and C

Table and column names are the ones in section 6 of the brief, which `api/app/repo.py` and `pipeline/drishti_pipeline/store.py` already use. Ids are text with a generated default, so C can choose ids like `site-1` and B can let the database pick.

| Table | Written by | Notes |
| --- | --- | --- |
| `cities`, `wards` | A | Ward has the officer email complaints go to. City ids match `api/` (`indore`, `bhopal`) and `pipeline/configs/cities.yaml` (Pune and Delhi uuids). |
| `official_sites` | A | Dumps already on government records (the "M aren't on any record" pitch line) |
| `pipeline_runs` | C or the app inserts, B's worker runs | New rows default to `status='queued'`, `kind='detect'`, so `POST /pipeline/run` queues work for `drishti-pipeline worker` |
| `scenes` | B | Unique per `(city_id, stac_item_id)` |
| `sites` | B, C's `/ingest`, officers | Trigger fills `centroid` and `area_m2` from `geom`, assigns `ward_id`, stamps `cleared_at` |
| `detections` | B | Unique per `(site_id, scene_id)`. Trigger fills `area_m2` and `detected_on` (from the scene date) |
| `fire_events` | B | Unique per `(lat, lon, detected_at, source)`; `city_id` filled from the site |
| `complaints`, `verifications` | C, officers in the app | `ward_id` filled from the site |
| `citizen_reports` | Citizens (via `submit_report`), C | |
| `city_scores` | C's `/cities/{id}/score`, `refresh_city_score()` | Includes `parts` and `weights` |
| `audit_log` | C, the app | |
| `profiles` | Auto on sign-up | `role` is citizen, officer, board or admin |

Geometries are SRID 4326. PostgREST returns geometry columns as GeoJSON and accepts EWKT (`SRID=4326;POLYGON((lng lat, ...))`) on write.

## Reading from the app

Views return `lat`/`lng` and `geojson` instead of raw PostGIS: `site_map`, `detection_timeline`, `ward_map`, `city_list`, `fire_map`, `report_map`, `city_leaderboard`, plus the brief's `sites_geojson`.

RPCs: `ward_for_point(lon, lat, p_city_id)` (used by C), `sites_in_bbox(...)`, `submit_report(lng, lat, note, photo_url)` (files and matches within 150 m), `refresh_city_score(p_city_id)` (same formula as C's scoring), `set_user_role(target, new_role)` (admins only).

## Access

- `pipeline/` and `api/` use the service role key, which bypasses RLS. Never put it in the app.
- Public (anon key): cities, wards, scenes, detections, fires, verifications, scores, and sites with confidence >= 0.6 that are not dismissed (N-06). Sent and closed complaints are public too.
- Citizens: file reports and see their own; edit their name and language, never their role.
- `board`: reads everything. `officer` and `admin`: also act (complaints, site status, reports, runs, audit log). `admin`: changes roles.
- A user's role is copied into their JWT as `app_metadata.role`, which users cannot edit. **Member C:** read it from there in `api/app/auth.py` (`payload["app_metadata"]["role"]`). `user_metadata` is user-editable, so a role read from it can be forged.
- Storage buckets: `thumbnails` (public, B's detection chips), `report-photos` (public, citizens upload to `<user id>/...`), `complaints` (private PDFs, staff only).

## Complaint tracking

A resident raises a complaint of one of four types. A trigger gives it a ticket code, a ward and a locality, picks the department and sets the first-reply deadline:

| Type | Goes to | First reply target |
| --- | --- | --- |
| `dump` | `swm` municipal SWM office | 24 h |
| `burning` | `swm` (top of the list) | 2 h |
| `bin` | `swm` | 24 h |
| `debris` | `pwd` if within 30 m of a `pwd_roads` line, else `cnd` (municipal C&D cell) | 48 h |

The targets are placeholders until a ward office confirms them (`report_categories.reply_hours`).

The timeline is `report_updates`: `received` (automatic), then `assigned`, `scheduled`, `in_progress` and `resolved`, posted by officers through `post_report_update`. A department cannot move a complaint backwards, and `resolved` needs an after photo. When B's pipeline or an officer sets a site to `cleared`, every `resolved` complaint linked to it becomes `proven_clean`. The resident can `reopen_report`, which restarts the clock.

| RPC | Who | What |
| --- | --- | --- |
| `submit_report(lng, lat, note, photo_url, category)` | signed in | files it; returns `ticket`, `department`, `reply_due_at` too |
| `route_preview(lng, lat, category)` | anyone | where it would go, before sending |
| `post_report_update(p_report_id, p_stage, p_message, p_photo_path)` | officer, admin | adds to the timeline |
| `transfer_report(p_report_id, p_department)` | officer, admin | changes department, notes it on the timeline |
| `reopen_report(p_report_id, p_reason)` | the reporter | reopens a resolved complaint |
| `track_report(p_ticket)` | anyone | the public view by code: stage, department, ward and updates, never the reporter, note or photos |
| `area_lookup(q)` | anyone | home page search by area name (English or Hindi) or PIN code, with open sites within 3 km and the next Sentinel-2 pass |
| `impact_summary(p_city_id)` | anyone | counts for the impact page |

`report_map` now also returns `ticket`, `category`, `department`, `ward_no`, `ward_name`, `locality`, `stage`, `reply_due_at`, `first_reply_at`, `resolved_at` and `overdue`. Department photos go to the private `report-updates` bucket under `<report id>/`, readable by staff and the reporter. `report_updates` is in the realtime publication, so the reporter's timeline updates live.

## Sign-in emails

The app signs people in with an email that carries **both a 6-digit code and a link**. The link returns to the page the user asked from, which only works if that address is allowed. These settings are in `config.toml` and `templates/sign_in.html`; apply them with `supabase config push`, or by hand in the dashboard:

1. **Authentication → URL Configuration**
   - **Site URL:** `https://saxenachirayu1.github.io/drishti/`
   - **Redirect URLs:** `https://saxenachirayu1.github.io/drishti/**`, `http://localhost:5173/**`, `http://127.0.0.1:5173/**`, `http://localhost:8080/**`
2. **Authentication → Emails → Magic Link** and **Confirm signup**
   - **Subject:** `Your Drishti sign-in code`
   - **Body:** paste `templates/sign_in.html`. It must contain `{{ .Token }}` for the code to appear.

Without these, the email has only a link, and the link goes to `localhost:3000`, which is not running ("not found").
