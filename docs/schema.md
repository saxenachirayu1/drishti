# Database schema

The live Supabase project is `ofudjcrzdgltpoyavibr` (region ap-northeast-2). Its schema is
[`supabase/migrations/20261023000000_initial_schema.sql`](../supabase/migrations/20261023000000_initial_schema.sql);
demo data is [`supabase/seed.sql`](../supabase/seed.sql). Both are already applied.

Names follow section 6 of the brief. Every id is `text` with a generated default, so you can pass your own id
(`site-1`) or leave it out and read back the generated one. Geometry is SRID 4326: write EWKT
(`SRID=4326;POLYGON((lng lat, ...))`), read GeoJSON (PostgREST returns geometry columns as GeoJSON).

Schema changes: new file in `supabase/migrations/`, through Member A.

## Connecting

| Who | Key | Notes |
| --- | --- | --- |
| `app/` (Flutter) | anon key | Already in `app/lib/config.dart`. RLS applies. |
| `pipeline/`, `api/` | service role key | Bypasses RLS. Ask Member A privately. Never commit it or put it in the app. |
| SQL / psycopg | session pooler | `postgresql://postgres.ofudjcrzdgltpoyavibr:<password>@aws-0-ap-northeast-2.pooler.supabase.com:5432/postgres`. The direct `db.<ref>.supabase.co` host is IPv6-only. |

`.env` (copy `.env.example`): `SUPABASE_URL=https://ofudjcrzdgltpoyavibr.supabase.co`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`.

## Tables

Columns marked *auto* are filled by a trigger; you do not need to send them.

### cities
| Column | Type | Notes |
| --- | --- | --- |
| id | text | `indore`, `bhopal` (C's ids), `11111111-1111-1111-1111-111111111111` Pune, `22222222-2222-2222-2222-222222222222` Delhi (B's `cities.yaml`) |
| name, state | text | |
| bbox | geometry(Polygon) | city extent |
| area_km2 | real | used by the score |
| is_pilot | boolean | |

### wards
| Column | Type | Notes |
| --- | --- | --- |
| id | text | e.g. `w-ind-12` |
| city_id | text | -> cities |
| ward_no | int | |
| name, officer_name, officer_email, officer_phone | text | complaints go to `officer_email` |
| geom | geometry (Polygon or MultiPolygon) | |

Seed wards are demo squares with `@example.com` emails. Replace them with real boundaries.

### sites (one physical dump, tracked over time)
| Column | Type | Notes |
| --- | --- | --- |
| id | text | |
| city_id | text | required |
| ward_id | text | *auto* from the centroid if empty |
| geom | geometry (Polygon or MultiPolygon) | optional (C's `/ingest` sends only a centroid) |
| centroid | geometry(Point) | *auto* from `geom` |
| area_m2 | real | *auto* from `geom` (geodesic m²), otherwise as sent |
| first_seen, last_seen | date | |
| status | text | `active`, `complaint_sent`, `cleanup_reported`, `cleared`, `dismissed` |
| fire_risk | int 0-100 | B writes it |
| confidence | real 0-1 | below 0.6 the site is hidden from the public (N-06) |
| near_water | boolean | |
| missed_scenes, cleared_candidate | int, boolean | B's tracker |
| growth | text | free text shown to officers |
| cleared_at | timestamptz | *auto* when status becomes `cleared` |

### detections (one sighting of a site in one scene)
| Column | Type | Notes |
| --- | --- | --- |
| id | text | |
| site_id | text | -> sites |
| scene_id | text | scenes.id (not a foreign key) |
| geom | geometry | |
| confidence | real 0-1 | |
| area_m2 | real | *auto* from `geom` |
| thumb_url | text | public URL in the `thumbnails` bucket |
| detected_on | date | *auto* from the scene's `acquired_at` |

Unique per `(site_id, scene_id)`, so B can upsert with `on_conflict="site_id,scene_id"`.

### scenes
`id, city_id, stac_item_id, acquired_at, cloud_cover, status (new|processed|failed)`. Unique per `(city_id, stac_item_id)`.

### fire_events
`id, city_id (auto from site), site_id, detected_at, lat, lon, frp, confidence (text: l/n/h or a number), source`.
Unique per `(lat, lon, detected_at, source)`.

### pipeline_runs (job queue between C and B)
| Column | Notes |
| --- | --- |
| id, city_id | |
| kind | `detect` (default) or `fires` |
| params | jsonb, e.g. `{"start": "2026-10-01", "end": "2026-10-10"}` |
| status | `queued` (default), `running`, `done`, `failed` |
| queued_at, started_at, finished_at | |
| scenes_processed, sites_new, sites_updated, error | |

A new row is queued by default, so `POST /pipeline/run` (C) or the app's Officials → Pipeline tab queues work, and
`drishti-pipeline worker` (B) claims it.

### complaints
`id, site_id, ward_id (auto from site), draft_text, language (English|Hindi), pdf_url,
status (draft|approved|sent|closed), approved_by, sent_at, closed_at, created_by, created_at`.

### verifications
`id, site_id, complaint_id, checked_at, result (still_present|shrinking|cleared), evidence_detection_id`.

### citizen_reports
`id, user_id, city_id, location (Point), photo_url, note, linked_site_id, status (new|matched|rejected), created_at`.

### city_scores
`city_id, period (YYYY-MM), score, active_sites, burn_events, median_days_to_clear, pct_verified_cleared,
parts (jsonb), weights (jsonb)`. Primary key `(city_id, period)`.

### official_sites
`id, city_id, name, geom, source`: dumps already on a government list. A site within 100 m of one shows as
"on record" (the pitch line "M aren't on any government record").

### profiles
`user_id, email, full_name, role (citizen|officer|board|admin), city_id, ward_id, language`. Created
automatically on sign-up. The role is copied into the JWT as `app_metadata.role`.

### audit_log
`id, actor, action, entity, entity_id, at, details`.

## Views (read these from the app; they return lat/lng and GeoJSON)

| View | What |
| --- | --- |
| `site_map` | sites + ward number/name + officer email + `lat`, `lng`, `geojson`, `on_official_record` |
| `detection_timeline` | detections with `geojson`, for the before/after slider |
| `ward_map` | wards with `geojson` |
| `city_list` | cities with centre `lat`/`lng` and `west/south/east/north` |
| `fire_map` | fire points with `lat`/`lng` |
| `report_map` | citizen reports with `lat`/`lng` |
| `city_leaderboard` | latest score per city with `rank` |
| `sites_geojson` | the brief's GeoJSON Feature view |

## Functions (`supabase.rpc(...)`)

| Function | Who | What |
| --- | --- | --- |
| `ward_for_point(lon, lat, p_city_id)` | C | ward containing a point |
| `sites_in_bbox(min_lng, min_lat, max_lng, max_lat)` | app | sites in a map window |
| `submit_report(lng, lat, note, photo_url)` | app (signed in) | files a report, links it to a site within 150 m |
| `refresh_city_score(p_city_id)` | officers | recomputes this month's score (same formula as C's `scoring.py`) |
| `set_user_role(target, new_role)` | admins | change a user's role |

## Who can do what (row level security)

| | Public (anon) | citizen | board | officer | admin | service role |
| --- | --- | --- | --- | --- | --- | --- |
| Map data, scores, fires | read | read | read | read | read | all |
| Low-confidence / dismissed sites | - | - | read | read | read | all |
| Complaints | sent/closed | sent/closed | read all | read, create, update | same | all |
| Citizen reports | - | file, read own | read all | read, review | same | all |
| Site status, verifications, pipeline queue | - | - | read | write | write | all |
| Roles | - | - | - | - | change | all |

## Storage buckets

| Bucket | Public | Who writes |
| --- | --- | --- |
| `thumbnails` | yes | B (detection image chips) |
| `report-photos` | yes | citizens, into `<user id>/...` |
| `complaints` | no (staff read) | C (PDFs) |
