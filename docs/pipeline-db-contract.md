# Pipeline ↔ database contract

What `pipeline/` (Member B) reads and writes in Supabase, so Member A's migrations and Member C's API line up with it.
The pipeline uses the **service role key** and never changes a site's `status`. Status belongs to Member C's verification job.

## Tables the pipeline writes

| Table | Columns the pipeline sets | Unique key it relies on (for safe re-runs) |
| --- | --- | --- |
| `scenes` | city_id, stac_item_id, acquired_at, cloud_cover, status (`new`, `processed`, `failed`) | (city_id, stac_item_id) |
| `sites` | city_id, geom (Polygon, 4326), first_seen, last_seen, confidence, near_water, fire_risk, **missed_scenes**, **cleared_candidate** | none (rows are matched in code) |
| `detections` | site_id, scene_id, geom, confidence, thumb_url | (site_id, scene_id) |
| `fire_events` | city_id, site_id (nullable), detected_at, lat, lon, frp, confidence, source | (lat, lon, detected_at, source) |
| `pipeline_runs` | status (`running`, `done`, `failed`), started_at, finished_at, scenes_processed, sites_new, sites_updated, error | none |

Storage: public bucket **`thumbnails`**, path `<site_id>/<scene_id>.png`.

## Columns Member A needs to add beyond the requirements doc

- `sites.missed_scenes integer not null default 0`: clear scenes in a row where the site was not detected.
- `sites.cleared_candidate boolean not null default false`: true after 2 such scenes (B-15). Member C's verification reads it.
- `pipeline_runs.status text default 'queued'`, `pipeline_runs.kind text`, `pipeline_runs.params jsonb`, `pipeline_runs.queued_at timestamptz`: the job queue between the API and the worker.
- Triggers that keep `sites.centroid` and `sites.area_m2` (and `detections.area_m2`) in sync with `geom`. The pipeline sends only the geometry.

Geometry is sent as EWKT text (`SRID=4326;POLYGON(...)`) and read back as GeoJSON.

## Job queue (Member C → pipeline)

Member C's `POST /pipeline/run` inserts a row into `pipeline_runs`:

```json
{ "city_id": "<cities.id>", "kind": "detect", "status": "queued", "params": { "start": "2026-10-01", "end": "2026-10-20" } }
```

`kind` is `detect` or `fires`. The worker (`drishti-pipeline worker`) claims queued rows oldest first, runs them, and sets `status` to `done` or `failed` with an `error` message. Other kinds (`verify`, `scores`) belong to Member C's scheduler and are marked failed if they reach the pipeline.

## City ids

`pipeline/configs/cities.yaml` lists the cities the pipeline covers. Each `id` must equal the row's `id` in `public.cities`.
