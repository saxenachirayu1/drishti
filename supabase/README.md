# supabase/ (Member A)

- `migrations/` one SQL file per schema change (`YYYYMMDDHHMMSS_name.sql`); tables, PostGIS, RLS, storage
- `seed.sql` demo data for local development (everything is marked DEMO)

Set up: install the Supabase CLI, run `supabase init` here, then `supabase db reset` to apply migrations and seed.
Or paste the migration, then `seed.sql`, into the Supabase dashboard SQL editor.

## Tables

| Table | Written by | Notes |
| --- | --- | --- |
| `cities`, `wards` | Member A (boundaries) | Ward has the officer email complaints go to |
| `official_sites` | Member A | Dumps already on government records |
| `pipeline_runs`, `scenes` | Member B | One row per run / Sentinel-2 scene |
| `sites` | Member B | One physical dump; `ward_id`, `centroid`, `area_m2` are set by a trigger |
| `detections` | Member B | One sighting of a site in one scene; drives the time slider |
| `fire_events`, `fire_risk_scores` | Member B | FIRMS points; latest risk score is copied onto `sites` |
| `complaints`, `verifications` | Member C | Complaint gets city, ward and officer email from the site |
| `city_scores` | Member C | One row per city per period |
| `assistant_messages` | Member C / app | Chat history |
| `citizen_reports` | App | Insert with `rpc('submit_report', {lng, lat, ...})` |
| `profiles` | Auto on sign-up | `role` is citizen, official or admin; change it only from the dashboard |

Geometries are SRID 4326 (lng/lat). Send polygons as WKT `SRID=4326;POLYGON((lng lat, ...))` or GeoJSON via `ST_GeomFromGeoJSON`.

## Reading from the app

Use the views, which return `lat`/`lng` and `geojson` instead of raw PostGIS:
`site_map`, `detection_timeline`, `ward_map`, `city_list`, `fire_map`, `city_leaderboard`.
RPCs: `sites_in_bbox(min_lng, min_lat, max_lng, max_lat)`, `ward_for_point(lng, lat)`, `submit_report(...)`.

## Access

- `pipeline/` and `api/` use the service role key (bypasses RLS). Never put it in the Flutter app.
- The app uses the anon key. Map data is public; citizens see only their own reports; officials and admins can update site and complaint status.
- Storage buckets: `imagery` (public tiles), `report-photos` (public, upload to `<user id>/...`), `complaints` (private PDFs, staff only).
