-- Project Drishti — full database schema (section 6 of the brief).
-- OWNER: Member A runs this. Shared here so C can build against it and A
-- is unblocked. Run in the Supabase SQL editor (or via `supabase db reset`).

create extension if not exists postgis;

create table if not exists cities (
  id          text primary key,
  name        text not null,
  state       text,
  bbox        geometry(Polygon, 4326),
  is_pilot    boolean default false
);

create table if not exists wards (
  id            text primary key,
  city_id       text references cities(id),
  ward_no       int,
  name          text,
  officer_email text,
  geom          geometry(MultiPolygon, 4326)
);

create table if not exists profiles (
  user_id   uuid primary key,
  full_name text,
  role      text check (role in ('citizen','officer','board','admin')) default 'citizen',
  city_id   text references cities(id),
  ward_id   text references wards(id),
  language  text default 'English'
);

create table if not exists scenes (
  id           text primary key,
  city_id      text references cities(id),
  acquired_at  timestamptz,
  cloud_cover  real,
  stac_item_id text,
  status       text check (status in ('new','processed','failed')) default 'new'
);

create table if not exists sites (
  id         text primary key,
  city_id    text references cities(id),
  ward_id    text references wards(id),
  geom       geometry(Polygon, 4326),
  centroid   geometry(Point, 4326),
  first_seen date,
  last_seen  date,
  area_m2    real,
  near_water boolean default false,
  status     text check (status in ('active','complaint_sent','cleanup_reported','cleared','dismissed')) default 'active',
  fire_risk  int default 0
);

create table if not exists detections (
  id           text primary key,
  site_id      text references sites(id),
  scene_id     text references scenes(id),
  geom         geometry(Polygon, 4326),
  confidence   real,
  area_m2      real,
  thumb_url    text,
  detected_on  date          -- read by the API (site timeline, verification)
);

create table if not exists fire_events (
  id          text primary key,
  site_id     text references sites(id),
  detected_at timestamptz,
  lat         double precision,
  lon         double precision,
  frp         real,
  confidence  real,
  source      text default 'VIIRS'
);

create table if not exists complaints (
  id          text primary key,
  site_id     text references sites(id),
  ward_id     text references wards(id),
  draft_text  text,
  language    text,
  pdf_url     text,
  status      text check (status in ('draft','approved','sent','closed')) default 'draft',
  approved_by uuid,
  sent_at     timestamptz
);

create table if not exists verifications (
  id                  text primary key,
  site_id             text references sites(id),
  complaint_id        text references complaints(id),
  checked_at          timestamptz,
  result              text check (result in ('still_present','shrinking','cleared')),
  evidence_detection_id text references detections(id)
);

create table if not exists citizen_reports (
  id             text primary key,
  user_id        uuid,
  location       geometry(Point, 4326),
  photo_url      text,
  note           text,
  linked_site_id text references sites(id),
  status         text check (status in ('new','matched','rejected')) default 'new'
);

create table if not exists city_scores (
  city_id             text references cities(id),
  period              text,
  score               int,
  active_sites        int,
  burn_events         int,
  median_days_to_clear real,
  pct_verified_cleared real,
  primary key (city_id, period)
);

create table if not exists pipeline_runs (
  id              text primary key,
  city_id         text references cities(id),
  started_at      timestamptz,
  finished_at     timestamptz,
  scenes_processed int,
  sites_new       int,
  sites_updated   int,
  error           text
);

create table if not exists audit_log (
  id        bigint generated always as identity primary key,
  actor     text,
  action    text,
  entity    text,
  entity_id text,
  at        timestamptz default now(),
  details   jsonb
);

-- GIST indexes for spatial queries (A-03)
create index if not exists idx_sites_geom on sites using gist (geom);
create index if not exists idx_sites_centroid on sites using gist (centroid);
create index if not exists idx_wards_geom on wards using gist (geom);

-- Ward lookup for a point (C-05/C-06). The API calls this through
-- supabase.rpc("ward_for_point", {lon, lat, p_city_id}).
create or replace function ward_for_point(lon double precision,
                                          lat double precision,
                                          p_city_id text default null)
returns setof wards
language sql stable as $$
  select w.*
  from wards w
  where st_contains(w.geom, st_setsrid(st_point(lon, lat), 4326))
    and (p_city_id is null or w.city_id = p_city_id)
  limit 1;
$$;

-- GeoJSON view the app reads for the map (A-03)
create or replace view sites_geojson as
select
  s.id,
  json_build_object(
    'type','Feature',
    'geometry', st_asgeojson(s.geom)::json,
    'properties', json_build_object(
      'id', s.id, 'city_id', s.city_id, 'ward_id', s.ward_id,
      'area_m2', s.area_m2, 'status', s.status,
      'near_water', s.near_water, 'fire_risk', s.fire_risk
    )
  ) as feature
from sites s;
