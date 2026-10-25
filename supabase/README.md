# supabase/ (Member A)

- `migrations/20261023000000_initial_schema.sql` the schema: tables, PostGIS, triggers, views, RPCs, RLS, storage, realtime
- `seed.sql` demo data (cities, wards, sites with six months of detections, fires, scores)

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
