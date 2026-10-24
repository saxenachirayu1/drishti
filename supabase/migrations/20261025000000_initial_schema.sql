-- Drishti initial schema: cities, wards, satellite detections, sites, fire layer,
-- complaints, clean-up verification, citizen reports, city scores.
-- Writes from pipeline/ and api/ use the service role key, which bypasses RLS.
-- The Flutter app uses the anon key and is limited by the policies below.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.user_role as enum ('citizen', 'official', 'admin');
create type public.site_type as enum ('dumpsite', 'burning', 'landfill', 'riverbank');
create type public.site_status as enum (
  'detected', 'confirmed', 'complaint_sent', 'cleanup_in_progress', 'cleared', 'false_positive'
);
create type public.complaint_status as enum ('draft', 'sent', 'acknowledged', 'resolved', 'escalated');
create type public.verification_result as enum ('cleared', 'partially_cleared', 'not_cleared', 'grown');
create type public.report_status as enum ('pending', 'linked', 'rejected');
create type public.run_status as enum ('running', 'succeeded', 'failed');

-- ---------------------------------------------------------------------------
-- Shared trigger functions
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------

create table public.cities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  state       text not null,
  slug        text not null unique,
  boundary    geometry(Geometry, 4326),
  center      geometry(Point, 4326),
  population  integer,
  is_pilot    boolean not null default false,
  created_at  timestamptz not null default now()
);
create index cities_boundary_idx on public.cities using gist (boundary);

create table public.wards (
  id              uuid primary key default gen_random_uuid(),
  city_id         uuid not null references public.cities (id) on delete cascade,
  ward_number     text not null,
  name            text not null,
  boundary        geometry(Geometry, 4326) not null,
  officer_name    text,
  officer_email   text,
  officer_phone   text,
  office_address  text,
  created_at      timestamptz not null default now(),
  unique (city_id, ward_number)
);
create index wards_city_idx on public.wards (city_id);
create index wards_boundary_idx on public.wards using gist (boundary);

-- Sites on government records, for the "M aren't on any official record" comparison.
create table public.official_sites (
  id          uuid primary key default gen_random_uuid(),
  city_id     uuid not null references public.cities (id) on delete cascade,
  name        text not null,
  geom        geometry(Geometry, 4326) not null,
  source      text,
  notes       text,
  created_at  timestamptz not null default now()
);
create index official_sites_geom_idx on public.official_sites using gist (geom);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  full_name           text,
  role                public.user_role not null default 'citizen',
  city_id             uuid references public.cities (id) on delete set null,
  ward_id             uuid references public.wards (id) on delete set null,
  preferred_language  text not null default 'en' check (preferred_language in ('en', 'hi')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('official', 'admin')
  );
$$;

-- ---------------------------------------------------------------------------
-- Pipeline: runs, scenes, sites, detections
-- ---------------------------------------------------------------------------

create table public.pipeline_runs (
  id                uuid primary key default gen_random_uuid(),
  city_id           uuid references public.cities (id) on delete cascade,
  status            public.run_status not null default 'running',
  model_version     text,
  scenes_processed  integer not null default 0,
  detections_count  integer not null default 0,
  error             text,
  stats             jsonb not null default '{}',
  started_at        timestamptz not null default now(),
  finished_at       timestamptz
);
create index pipeline_runs_city_idx on public.pipeline_runs (city_id, started_at desc);

create table public.scenes (
  id           uuid primary key default gen_random_uuid(),
  city_id      uuid not null references public.cities (id) on delete cascade,
  run_id       uuid references public.pipeline_runs (id) on delete set null,
  source       text not null default 'sentinel-2-l2a',
  scene_id     text not null unique,
  acquired_at  timestamptz not null,
  cloud_cover  real,
  footprint    geometry(Geometry, 4326),
  rgb_path     text,  -- path in the imagery bucket
  created_at   timestamptz not null default now()
);
create index scenes_city_date_idx on public.scenes (city_id, acquired_at desc);

-- A site is one physical dump tracked over time; detections are per-scene sightings of it.
create table public.sites (
  id                  uuid primary key default gen_random_uuid(),
  city_id             uuid not null references public.cities (id) on delete cascade,
  ward_id             uuid references public.wards (id) on delete set null,
  official_site_id    uuid references public.official_sites (id) on delete set null,
  name                text,
  site_type           public.site_type not null default 'dumpsite',
  status              public.site_status not null default 'detected',
  geom                geometry(Geometry, 4326) not null
                        check (ST_GeometryType(geom) = 'ST_MultiPolygon'),
  centroid            geometry(Point, 4326),
  area_m2             double precision,
  confidence          real check (confidence between 0 and 1),
  fire_risk_score     real check (fire_risk_score between 0 and 100),
  near_water          boolean not null default false,
  on_official_record  boolean not null default false,
  first_seen_at       timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index sites_city_status_idx on public.sites (city_id, status);
create index sites_ward_idx on public.sites (ward_id);
create index sites_geom_idx on public.sites using gist (geom);
create index sites_centroid_idx on public.sites using gist (centroid);

-- Normalises the polygon, fills centroid and area, and assigns the ward the site falls in.
create or replace function public.sites_derive_fields()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.geom := ST_Multi(new.geom);
  new.centroid := ST_PointOnSurface(new.geom);
  new.area_m2 := ST_Area(new.geom::geography);
  if new.ward_id is null then
    select w.id into new.ward_id
    from public.wards w
    where w.city_id = new.city_id and ST_Contains(w.boundary, new.centroid)
    limit 1;
  end if;
  return new;
end;
$$;
create trigger sites_derive before insert or update of geom, ward_id on public.sites
  for each row execute function public.sites_derive_fields();
create trigger sites_updated_at before update on public.sites
  for each row execute function public.set_updated_at();

create table public.detections (
  id             uuid primary key default gen_random_uuid(),
  city_id        uuid not null references public.cities (id) on delete cascade,
  site_id        uuid references public.sites (id) on delete cascade,
  scene_id       uuid references public.scenes (id) on delete set null,
  run_id         uuid references public.pipeline_runs (id) on delete set null,
  detected_on    date not null,  -- scene acquisition date
  site_type      public.site_type not null default 'dumpsite',
  geom           geometry(Geometry, 4326) not null
                   check (ST_GeometryType(geom) = 'ST_MultiPolygon'),
  area_m2        double precision,
  confidence     real not null check (confidence between 0 and 1),
  model_version  text not null,
  tile_path      text,  -- image chip in the imagery bucket, used by the before/after slider
  created_at     timestamptz not null default now()
);
create index detections_site_date_idx on public.detections (site_id, detected_on);
create index detections_city_date_idx on public.detections (city_id, detected_on desc);
create index detections_geom_idx on public.detections using gist (geom);

create or replace function public.detections_derive_fields()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.geom := ST_Multi(new.geom);
  new.area_m2 := ST_Area(new.geom::geography);
  return new;
end;
$$;
create trigger detections_derive before insert or update of geom on public.detections
  for each row execute function public.detections_derive_fields();

-- ---------------------------------------------------------------------------
-- Fire layer
-- ---------------------------------------------------------------------------

create table public.fire_events (
  id           uuid primary key default gen_random_uuid(),
  city_id      uuid references public.cities (id) on delete cascade,
  site_id      uuid references public.sites (id) on delete set null,
  source       text not null,  -- e.g. VIIRS_SNPP_NRT, MODIS_NRT
  firms_key    text not null unique,  -- dedupe key: source + lat + lng + acq datetime
  geom         geometry(Point, 4326) not null,
  acquired_at  timestamptz not null,
  frp          real,
  brightness   real,
  confidence   text,  -- FIRMS gives l/n/h for VIIRS, 0-100 for MODIS
  created_at   timestamptz not null default now()
);
create index fire_events_city_date_idx on public.fire_events (city_id, acquired_at desc);
create index fire_events_site_idx on public.fire_events (site_id);
create index fire_events_geom_idx on public.fire_events using gist (geom);

create table public.fire_risk_scores (
  id                uuid primary key default gen_random_uuid(),
  site_id           uuid not null references public.sites (id) on delete cascade,
  score             real not null check (score between 0 and 100),
  temperature_c     real,
  humidity_pct      real,
  wind_kmh          real,
  days_since_rain   integer,
  factors           jsonb not null default '{}',
  scored_at         timestamptz not null default now()
);
create index fire_risk_site_idx on public.fire_risk_scores (site_id, scored_at desc);

create or replace function public.fire_risk_to_site()
returns trigger language plpgsql as $$
begin
  update public.sites set fire_risk_score = new.score where id = new.site_id;
  return new;
end;
$$;
create trigger fire_risk_latest after insert on public.fire_risk_scores
  for each row execute function public.fire_risk_to_site();

-- ---------------------------------------------------------------------------
-- Action: complaints and verification
-- ---------------------------------------------------------------------------

create table public.complaints (
  id                uuid primary key default gen_random_uuid(),
  site_id           uuid not null references public.sites (id) on delete cascade,
  city_id           uuid references public.cities (id) on delete cascade,
  ward_id           uuid references public.wards (id) on delete set null,
  status            public.complaint_status not null default 'draft',
  language          text not null default 'en' check (language in ('en', 'hi')),
  subject           text not null,
  body              text not null,
  recipient_email   text,
  pdf_path          text,  -- path in the complaints bucket
  model_id          text,  -- Granite model that drafted it
  created_by        uuid references auth.users (id) on delete set null,
  sent_at           timestamptz,
  acknowledged_at   timestamptz,
  resolved_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index complaints_site_idx on public.complaints (site_id);
create index complaints_ward_status_idx on public.complaints (ward_id, status);

-- Copies city, ward and officer email from the site when not given.
create or replace function public.complaints_fill_from_site()
returns trigger language plpgsql as $$
begin
  select coalesce(new.city_id, s.city_id), coalesce(new.ward_id, s.ward_id)
    into new.city_id, new.ward_id
  from public.sites s where s.id = new.site_id;
  if new.recipient_email is null and new.ward_id is not null then
    select w.officer_email into new.recipient_email from public.wards w where w.id = new.ward_id;
  end if;
  return new;
end;
$$;
create trigger complaints_fill before insert on public.complaints
  for each row execute function public.complaints_fill_from_site();
create trigger complaints_updated_at before update on public.complaints
  for each row execute function public.set_updated_at();

create table public.verifications (
  id                  uuid primary key default gen_random_uuid(),
  site_id             uuid not null references public.sites (id) on delete cascade,
  complaint_id        uuid references public.complaints (id) on delete set null,
  scene_id            uuid references public.scenes (id) on delete set null,
  result              public.verification_result not null,
  area_before_m2      double precision,
  area_after_m2       double precision,
  before_image_path   text,
  after_image_path    text,
  method              text not null default 'satellite',
  notes               text,
  checked_at          timestamptz not null default now()
);
create index verifications_site_idx on public.verifications (site_id, checked_at desc);

-- ---------------------------------------------------------------------------
-- Citizens, scores, assistant
-- ---------------------------------------------------------------------------

create table public.citizen_reports (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  city_id      uuid references public.cities (id) on delete set null,
  site_id      uuid references public.sites (id) on delete set null,
  location     geometry(Point, 4326) not null,
  report_type  public.site_type not null default 'dumpsite',
  description  text,
  photo_path   text,  -- path in the report-photos bucket: <user id>/<file>
  status       public.report_status not null default 'pending',
  reviewed_by  uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index citizen_reports_user_idx on public.citizen_reports (user_id);
create index citizen_reports_status_idx on public.citizen_reports (city_id, status);
create index citizen_reports_location_idx on public.citizen_reports using gist (location);

create table public.city_scores (
  id              uuid primary key default gen_random_uuid(),
  city_id         uuid not null references public.cities (id) on delete cascade,
  period_start    date not null,
  period_end      date not null,
  score           real not null check (score between 0 and 100),
  active_sites    integer not null default 0,
  new_sites       integer not null default 0,
  cleared_sites   integer not null default 0,
  burning_events  integer not null default 0,
  total_area_m2   double precision not null default 0,
  details         jsonb not null default '{}',
  computed_at     timestamptz not null default now(),
  unique (city_id, period_start, period_end)
);

create table public.assistant_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users (id) on delete cascade,
  session_id  uuid not null,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null,
  language    text not null default 'en',
  sources     jsonb not null default '[]',  -- site ids used for the RAG answer
  created_at  timestamptz not null default now()
);
create index assistant_messages_session_idx on public.assistant_messages (session_id, created_at);

-- ---------------------------------------------------------------------------
-- Read views for the app (lat/lng and GeoJSON instead of raw PostGIS)
-- ---------------------------------------------------------------------------

create view public.site_map with (security_invoker = true) as
select
  s.id, s.city_id, s.ward_id, w.name as ward_name, s.name, s.site_type, s.status,
  s.area_m2, s.confidence, s.fire_risk_score, s.near_water, s.on_official_record,
  s.first_seen_at, s.last_seen_at,
  ST_Y(s.centroid) as lat, ST_X(s.centroid) as lng,
  ST_AsGeoJSON(s.geom)::jsonb as geojson
from public.sites s
left join public.wards w on w.id = s.ward_id;

create view public.detection_timeline with (security_invoker = true) as
select
  d.id, d.site_id, d.city_id, d.detected_on, d.site_type, d.area_m2, d.confidence,
  d.model_version, d.tile_path, ST_AsGeoJSON(d.geom)::jsonb as geojson
from public.detections d;

create view public.ward_map with (security_invoker = true) as
select w.id, w.city_id, w.ward_number, w.name, w.officer_name, w.officer_email,
  ST_AsGeoJSON(w.boundary)::jsonb as geojson
from public.wards w;

create view public.city_list with (security_invoker = true) as
select c.id, c.name, c.state, c.slug, c.population, c.is_pilot,
  ST_Y(c.center) as lat, ST_X(c.center) as lng
from public.cities c;

create view public.fire_map with (security_invoker = true) as
select f.id, f.city_id, f.site_id, f.source, f.acquired_at, f.frp, f.confidence,
  ST_Y(f.geom) as lat, ST_X(f.geom) as lng
from public.fire_events f;

create view public.city_leaderboard with (security_invoker = true) as
select c.id as city_id, c.name, c.state, latest.score, latest.active_sites,
  latest.cleared_sites, latest.period_start, latest.period_end,
  rank() over (order by latest.score desc) as rank
from public.cities c
join lateral (
  select * from public.city_scores cs
  where cs.city_id = c.id
  order by cs.period_end desc
  limit 1
) latest on true;

-- ---------------------------------------------------------------------------
-- RPC functions (call with supabase.rpc(...))
-- ---------------------------------------------------------------------------

create or replace function public.sites_in_bbox(
  min_lng double precision, min_lat double precision,
  max_lng double precision, max_lat double precision
)
returns setof public.site_map
language sql stable set search_path = public, extensions as $$
  select m.*
  from public.site_map m
  join public.sites s on s.id = m.id
  where s.geom && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326);
$$;

create or replace function public.ward_for_point(lng double precision, lat double precision)
returns table (id uuid, city_id uuid, ward_number text, name text, officer_name text, officer_email text)
language sql stable set search_path = public, extensions as $$
  select w.id, w.city_id, w.ward_number, w.name, w.officer_name, w.officer_email
  from public.wards w
  where ST_Contains(w.boundary, ST_SetSRID(ST_MakePoint(lng, lat), 4326))
  limit 1;
$$;

create or replace function public.submit_report(
  lng double precision, lat double precision,
  description text default null,
  report_type public.site_type default 'dumpsite',
  photo_path text default null
)
returns uuid
language sql set search_path = public, extensions as $$
  insert into public.citizen_reports (user_id, city_id, location, description, report_type, photo_path)
  select auth.uid(),
    (select c.id from public.cities c where ST_Contains(c.boundary, pt.g) limit 1),
    pt.g, submit_report.description, submit_report.report_type, submit_report.photo_path
  from (select ST_SetSRID(ST_MakePoint(lng, lat), 4326) as g) pt
  returning id;
$$;
revoke execute on function public.submit_report from public, anon;
grant execute on function public.submit_report to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'cities', 'wards', 'official_sites', 'profiles', 'pipeline_runs', 'scenes', 'sites',
    'detections', 'fire_events', 'fire_risk_scores', 'complaints', 'verifications',
    'citizen_reports', 'city_scores', 'assistant_messages'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;

  -- Map data is public: anyone can see what the satellites found.
  foreach t in array array[
    'cities', 'wards', 'official_sites', 'pipeline_runs', 'scenes', 'sites',
    'detections', 'fire_events', 'fire_risk_scores', 'verifications', 'city_scores'
  ] loop
    execute format('create policy "Public read" on public.%I for select to anon, authenticated using (true)', t);
  end loop;
end;
$$;

create policy "Staff update sites" on public.sites
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

create policy "Public reads sent complaints, staff reads all" on public.complaints
  for select to anon, authenticated using (status <> 'draft' or public.is_staff());
create policy "Staff create complaints" on public.complaints
  for insert to authenticated with check (public.is_staff());
create policy "Staff update complaints" on public.complaints
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

create policy "Citizens create own reports" on public.citizen_reports
  for insert to authenticated with check (user_id = auth.uid());
create policy "Citizens read own reports, staff read all" on public.citizen_reports
  for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "Staff review reports" on public.citizen_reports
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

create policy "Read own profile, staff read all" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_staff());
create policy "Update own profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- Users may edit their name, language and home ward, never their role.
revoke update on public.profiles from authenticated;
grant update (full_name, preferred_language, city_id, ward_id) on public.profiles to authenticated;

create policy "Read own assistant messages" on public.assistant_messages
  for select to authenticated using (user_id = auth.uid());
create policy "Write own assistant messages" on public.assistant_messages
  for insert to authenticated with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('imagery', 'imagery', true, 10485760, array['image/png', 'image/jpeg', 'image/webp']),
  ('report-photos', 'report-photos', true, 5242880, array['image/png', 'image/jpeg', 'image/webp']),
  ('complaints', 'complaints', false, 5242880, array['application/pdf'])
on conflict (id) do nothing;

create policy "Citizens upload report photos to own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'report-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Staff read complaint PDFs" on storage.objects
  for select to authenticated
  using (bucket_id = 'complaints' and public.is_staff());

-- ---------------------------------------------------------------------------
-- Realtime: new pins and fires appear on the live map without a refresh
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.sites, public.fire_events;
  end if;
end;
$$;
