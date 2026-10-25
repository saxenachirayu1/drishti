-- Project Drishti database schema.
--
-- Table and column names follow section 6 of the team brief, so Member C's API
-- (api/app/repo.py) and Member B's pipeline (pipeline/drishti_pipeline/store.py)
-- work against it unchanged. On top of the brief it adds the columns B and C
-- write, row level security, storage buckets, map views and RPCs for the app.
--
-- Ids are text so C can choose ids like 'site-1' and B can let the database
-- generate them. Writes from pipeline/ and api/ use the service role key, which
-- bypasses RLS. The Flutter app uses the anon key and the policies below.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------

create table public.cities (
  id          text primary key default gen_random_uuid()::text,
  name        text not null,
  state       text,
  bbox        geometry(Polygon, 4326),
  area_km2    real,
  is_pilot    boolean not null default false,
  created_at  timestamptz not null default now()
);

create table public.wards (
  id             text primary key default gen_random_uuid()::text,
  city_id        text not null references public.cities (id) on delete cascade,
  ward_no        int,
  name           text,
  officer_name   text,
  officer_email  text,
  officer_phone  text,
  geom           geometry(Geometry, 4326)
                   check (geom is null or ST_GeometryType(geom) in ('ST_Polygon', 'ST_MultiPolygon')),
  created_at     timestamptz not null default now()
);
create index wards_city_idx on public.wards (city_id);
create index idx_wards_geom on public.wards using gist (geom);

-- Dumps already on government records, for the "M aren't on any record" pitch line.
create table public.official_sites (
  id          text primary key default gen_random_uuid()::text,
  city_id     text not null references public.cities (id) on delete cascade,
  name        text not null,
  geom        geometry(Geometry, 4326) not null,
  source      text,
  created_at  timestamptz not null default now()
);
create index official_sites_geom_idx on public.official_sites using gist (geom);

-- ---------------------------------------------------------------------------
-- Users and roles
-- ---------------------------------------------------------------------------

create table public.profiles (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  email       text,
  full_name   text,
  role        text not null default 'citizen' check (role in ('citizen', 'officer', 'board', 'admin')),
  city_id     text references public.cities (id) on delete set null,
  ward_id     text references public.wards (id) on delete set null,
  language    text not null default 'English' check (language in ('English', 'Hindi')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (user_id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Copies the role into the JWT's app_metadata (which users cannot edit), so the
-- API can read it from the token: payload["app_metadata"]["role"].
create or replace function public.sync_role_to_auth()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', new.role)
  where id = new.user_id;
  new.updated_at := now();
  return new;
end;
$$;
create trigger profiles_sync_role before insert or update on public.profiles
  for each row execute function public.sync_role_to_auth();

create or replace function public.app_role()
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select role from public.profiles where user_id = auth.uid()), 'anon');
$$;

-- Officers, the pollution control board and admins can see everything.
create or replace function public.is_staff()
returns boolean language sql stable as $$
  select public.app_role() in ('officer', 'board', 'admin');
$$;

-- Only officers and admins act: draft, approve and send complaints, review reports.
create or replace function public.can_act()
returns boolean language sql stable as $$
  select public.app_role() in ('officer', 'admin');
$$;

create or replace function public.set_user_role(target uuid, new_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.app_role() <> 'admin' then
    raise exception 'only an admin can change roles';
  end if;
  update public.profiles set role = new_role where user_id = target;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pipeline: runs, scenes, sites, detections, fires
-- ---------------------------------------------------------------------------

-- C's API inserts a row (POST /pipeline/run); B's worker claims rows in 'queued'.
create table public.pipeline_runs (
  id                text primary key default gen_random_uuid()::text,
  city_id           text references public.cities (id) on delete cascade,
  kind              text not null default 'detect' check (kind in ('detect', 'fires')),
  params            jsonb not null default '{}',
  status            text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed')),
  queued_at         timestamptz not null default now(),
  started_at        timestamptz,
  finished_at       timestamptz,
  scenes_processed  int not null default 0,
  sites_new         int not null default 0,
  sites_updated     int not null default 0,
  error             text
);
create index pipeline_runs_queue_idx on public.pipeline_runs (status, queued_at);

create table public.scenes (
  id            text primary key default gen_random_uuid()::text,
  city_id       text not null references public.cities (id) on delete cascade,
  stac_item_id  text not null,
  acquired_at   timestamptz,
  cloud_cover   real,
  status        text not null default 'new' check (status in ('new', 'processed', 'failed')),
  created_at    timestamptz not null default now(),
  unique (city_id, stac_item_id)
);

create table public.sites (
  id                 text primary key default gen_random_uuid()::text,
  city_id            text not null references public.cities (id) on delete cascade,
  ward_id            text references public.wards (id) on delete set null,
  geom               geometry(Geometry, 4326)
                       check (geom is null or ST_GeometryType(geom) in ('ST_Polygon', 'ST_MultiPolygon')),
  centroid           geometry(Point, 4326),
  first_seen         date,
  last_seen          date,
  area_m2            real not null default 0,
  near_water         boolean not null default false,
  status             text not null default 'active'
                       check (status in ('active', 'complaint_sent', 'cleanup_reported', 'cleared', 'dismissed')),
  fire_risk          int not null default 0 check (fire_risk between 0 and 100),
  confidence         real check (confidence between 0 and 1),
  missed_scenes      int not null default 0,
  cleared_candidate  boolean not null default false,
  growth             text,
  cleared_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index sites_city_status_idx on public.sites (city_id, status);
create index sites_ward_idx on public.sites (ward_id);
create index idx_sites_geom on public.sites using gist (geom);
create index idx_sites_centroid on public.sites using gist (centroid);

-- Fills centroid and area from the polygon, assigns the ward, stamps cleared_at.
-- C's /ingest sends a centroid and area without a polygon; that is kept as is.
create or replace function public.sites_derive()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.geom is not null and (tg_op = 'INSERT' or new.geom is distinct from old.geom) then
    new.centroid := ST_PointOnSurface(new.geom);
    new.area_m2 := ST_Area(new.geom::geography);
  end if;
  if new.ward_id is null and new.centroid is not null then
    select w.id into new.ward_id
    from public.wards w
    where w.city_id = new.city_id and ST_Contains(w.geom, new.centroid)
    limit 1;
  end if;
  if new.status = 'cleared' and (tg_op = 'INSERT' or old.status is distinct from 'cleared') then
    new.cleared_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger sites_derive before insert or update on public.sites
  for each row execute function public.sites_derive();

create table public.detections (
  id           text primary key default gen_random_uuid()::text,
  site_id      text references public.sites (id) on delete cascade,
  scene_id     text,  -- scenes.id; not a foreign key so C's /ingest can send B's ids in any order
  geom         geometry(Geometry, 4326)
                 check (geom is null or ST_GeometryType(geom) in ('ST_Polygon', 'ST_MultiPolygon')),
  confidence   real check (confidence between 0 and 1),
  area_m2      real,
  thumb_url    text,
  detected_on  date,
  created_at   timestamptz not null default now(),
  unique (site_id, scene_id)
);
create index detections_site_date_idx on public.detections (site_id, detected_on);

create or replace function public.detections_derive()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.geom is not null then
    new.area_m2 := ST_Area(new.geom::geography);
  end if;
  if new.detected_on is null then
    select s.acquired_at::date into new.detected_on from public.scenes s where s.id = new.scene_id;
    new.detected_on := coalesce(new.detected_on, current_date);
  end if;
  return new;
end;
$$;
create trigger detections_derive before insert or update on public.detections
  for each row execute function public.detections_derive();

create table public.fire_events (
  id           text primary key default gen_random_uuid()::text,
  city_id      text references public.cities (id) on delete cascade,
  site_id      text references public.sites (id) on delete set null,
  detected_at  timestamptz,
  lat          double precision,
  lon          double precision,
  frp          real,
  confidence   text,  -- VIIRS gives l/n/h, MODIS 0-100
  source       text not null default 'VIIRS',
  created_at   timestamptz not null default now(),
  unique (lat, lon, detected_at, source)
);
create index fire_events_site_idx on public.fire_events (site_id);
create index fire_events_city_date_idx on public.fire_events (city_id, detected_at desc);

create or replace function public.fire_events_fill_city()
returns trigger language plpgsql as $$
begin
  if new.city_id is null and new.site_id is not null then
    select s.city_id into new.city_id from public.sites s where s.id = new.site_id;
  end if;
  return new;
end;
$$;
create trigger fire_events_fill_city before insert on public.fire_events
  for each row execute function public.fire_events_fill_city();

-- ---------------------------------------------------------------------------
-- Action: complaints, verification, citizen reports, scores, audit
-- ---------------------------------------------------------------------------

create table public.complaints (
  id           text primary key default gen_random_uuid()::text,
  site_id      text not null references public.sites (id) on delete cascade,
  ward_id      text references public.wards (id) on delete set null,
  draft_text   text not null default '',
  language     text not null default 'English',
  pdf_url      text,
  status       text not null default 'draft' check (status in ('draft', 'approved', 'sent', 'closed')),
  approved_by  text,
  sent_at      timestamptz,
  closed_at    timestamptz,
  created_by   text default auth.uid()::text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index complaints_site_idx on public.complaints (site_id);
create index complaints_ward_status_idx on public.complaints (ward_id, status);

create or replace function public.complaints_derive()
returns trigger language plpgsql as $$
begin
  if new.ward_id is null then
    select s.ward_id into new.ward_id from public.sites s where s.id = new.site_id;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger complaints_derive before insert or update on public.complaints
  for each row execute function public.complaints_derive();

create table public.verifications (
  id                     text primary key default gen_random_uuid()::text,
  site_id                text not null references public.sites (id) on delete cascade,
  complaint_id           text references public.complaints (id) on delete set null,
  checked_at             timestamptz not null default now(),
  result                 text not null check (result in ('still_present', 'shrinking', 'cleared')),
  evidence_detection_id  text references public.detections (id) on delete set null
);
create index verifications_site_idx on public.verifications (site_id, checked_at desc);

create table public.citizen_reports (
  id              text primary key default gen_random_uuid()::text,
  user_id         text default auth.uid()::text,
  city_id         text references public.cities (id) on delete set null,
  location        geometry(Point, 4326),
  photo_url       text,
  note            text,
  linked_site_id  text references public.sites (id) on delete set null,
  status          text not null default 'new' check (status in ('new', 'matched', 'rejected')),
  created_at      timestamptz not null default now()
);
create index citizen_reports_user_idx on public.citizen_reports (user_id);
create index citizen_reports_status_idx on public.citizen_reports (status);

create table public.city_scores (
  city_id               text not null references public.cities (id) on delete cascade,
  period                text not null,  -- YYYY-MM
  score                 int,
  active_sites          int,
  burn_events           int,
  median_days_to_clear  real,
  pct_verified_cleared  real,
  parts                 jsonb not null default '{}',
  weights               jsonb not null default '{}',
  computed_at           timestamptz not null default now(),
  primary key (city_id, period)
);

create table public.audit_log (
  id         bigint generated always as identity primary key,
  actor      text,
  action     text,
  entity     text,
  entity_id  text,
  at         timestamptz default now(),
  details    jsonb
);

-- ---------------------------------------------------------------------------
-- Views for the app: plain lat/lng and GeoJSON instead of raw PostGIS
-- ---------------------------------------------------------------------------

create view public.site_map with (security_invoker = true) as
select
  s.id, s.city_id, s.ward_id, w.ward_no, w.name as ward_name, w.officer_email,
  s.status, s.area_m2, s.fire_risk, s.near_water, s.confidence, s.growth,
  s.first_seen, s.last_seen, s.cleared_candidate, s.cleared_at,
  ST_Y(s.centroid) as lat, ST_X(s.centroid) as lng,
  ST_AsGeoJSON(s.geom)::jsonb as geojson,
  exists (
    select 1 from public.official_sites o
    where o.city_id = s.city_id
      and ST_DWithin(o.geom::geography, coalesce(s.geom, s.centroid)::geography, 100)
  ) as on_official_record
from public.sites s
left join public.wards w on w.id = s.ward_id;

-- The brief's GeoJSON view (A-03), kept for anything that reads it.
create view public.sites_geojson with (security_invoker = true) as
select
  s.id,
  json_build_object(
    'type', 'Feature',
    'geometry', ST_AsGeoJSON(coalesce(s.geom, s.centroid))::json,
    'properties', json_build_object(
      'id', s.id, 'city_id', s.city_id, 'ward_id', s.ward_id,
      'area_m2', s.area_m2, 'status', s.status,
      'near_water', s.near_water, 'fire_risk', s.fire_risk
    )
  ) as feature
from public.sites s;

create view public.detection_timeline with (security_invoker = true) as
select d.id, d.site_id, d.scene_id, d.detected_on, d.area_m2, d.confidence, d.thumb_url,
  ST_AsGeoJSON(d.geom)::jsonb as geojson
from public.detections d;

create view public.ward_map with (security_invoker = true) as
select w.id, w.city_id, w.ward_no, w.name, w.officer_name, w.officer_email,
  ST_AsGeoJSON(w.geom)::jsonb as geojson
from public.wards w;

create view public.city_list with (security_invoker = true) as
select c.id, c.name, c.state, c.is_pilot, c.area_km2,
  ST_Y(ST_Centroid(c.bbox)) as lat, ST_X(ST_Centroid(c.bbox)) as lng,
  ST_XMin(c.bbox) as west, ST_YMin(c.bbox) as south, ST_XMax(c.bbox) as east, ST_YMax(c.bbox) as north
from public.cities c;

create view public.fire_map with (security_invoker = true) as
select f.id, f.city_id, f.site_id, f.detected_at, f.frp, f.confidence, f.source,
  f.lat, f.lon as lng
from public.fire_events f
where f.lat is not null and f.lon is not null;

create view public.report_map with (security_invoker = true) as
select r.id, r.user_id, r.city_id, r.note, r.photo_url, r.status, r.linked_site_id, r.created_at,
  ST_Y(r.location) as lat, ST_X(r.location) as lng
from public.citizen_reports r;

create view public.city_leaderboard with (security_invoker = true) as
select c.id as city_id, c.name, c.state, latest.period, latest.score, latest.active_sites,
  latest.burn_events, latest.median_days_to_clear, latest.pct_verified_cleared, latest.parts,
  rank() over (order by latest.score desc) as rank
from public.cities c
join lateral (
  select * from public.city_scores cs
  where cs.city_id = c.id
  order by cs.period desc
  limit 1
) latest on true;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Called by C's API: supabase.rpc("ward_for_point", {lon, lat, p_city_id}).
create or replace function public.ward_for_point(lon double precision, lat double precision,
                                                 p_city_id text default null)
returns setof public.wards
language sql stable set search_path = public, extensions as $$
  select w.*
  from public.wards w
  where ST_Contains(w.geom, ST_SetSRID(ST_Point(lon, lat), 4326))
    and (p_city_id is null or w.city_id = p_city_id)
  limit 1;
$$;

create or replace function public.sites_in_bbox(min_lng double precision, min_lat double precision,
                                                max_lng double precision, max_lat double precision)
returns setof public.site_map
language sql stable set search_path = public, extensions as $$
  select m.*
  from public.site_map m
  join public.sites s on s.id = m.id
  where coalesce(s.geom, s.centroid) && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326);
$$;

-- A citizen files a report. It is matched to the nearest visible site within
-- 150 m (same radius as C's REPORT_MATCH_RADIUS_M), else left 'new' for review.
create or replace function public.submit_report(lng double precision, lat double precision,
                                                note text default null, photo_url text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  pt geometry := ST_SetSRID(ST_Point(lng, lat), 4326);
  near_id text;
  near_m double precision;
  new_id text;
begin
  if auth.uid() is null then
    raise exception 'sign in to report a site';
  end if;
  select s.id, ST_Distance(coalesce(s.geom, s.centroid)::geography, pt::geography)
    into near_id, near_m
  from public.sites s
  where s.status <> 'dismissed' and coalesce(s.confidence, 1) >= 0.6
    and coalesce(s.geom, s.centroid) is not null
  order by coalesce(s.geom, s.centroid) <-> pt
  limit 1;

  insert into public.citizen_reports (user_id, city_id, location, note, photo_url, linked_site_id, status)
  values (
    auth.uid()::text,
    (select c.id from public.cities c where ST_Contains(c.bbox, pt) limit 1),
    pt, submit_report.note, submit_report.photo_url,
    case when near_m <= 150 then near_id end,
    case when near_m <= 150 then 'matched' else 'new' end
  )
  returning id into new_id;

  return jsonb_build_object(
    'id', new_id,
    'status', case when near_m <= 150 then 'matched' else 'flagged_for_review' end,
    'site_id', case when near_m <= 150 then near_id end,
    'nearest_site_id', near_id,
    'distance_m', round(near_m)
  );
end;
$$;
revoke execute on function public.submit_report from public, anon;
grant execute on function public.submit_report to authenticated;

-- The cleanliness score (C-14), same formula and defaults as api/app/services/scoring.py,
-- so the app can refresh scores when the API is not running.
create or replace function public.refresh_city_score(p_city_id text)
returns public.city_scores
language plpgsql security definer set search_path = public, extensions as $$
declare
  n_total int; n_active int; n_cleared int; n_burns int; km2 real;
  a real; b real; c real; d real; days real := 30; row_out public.city_scores;
begin
  if not public.can_act() and auth.role() <> 'service_role' then
    raise exception 'only officers and admins can refresh scores';
  end if;
  select count(*), count(*) filter (where status = 'active'), count(*) filter (where status = 'cleared'),
         count(*) filter (where fire_risk >= 60)
    into n_total, n_active, n_cleared, n_burns
  from public.sites where city_id = p_city_id;
  select coalesce(area_km2, 400) into km2 from public.cities where id = p_city_id;

  select percentile_cont(0.5) within group (order by extract(epoch from s.cleared_at - cm.sent_at) / 86400)
    into days
  from public.complaints cm join public.sites s on s.id = cm.site_id
  where s.city_id = p_city_id and cm.sent_at is not null and s.cleared_at is not null;
  days := coalesce(days, 30);

  a := greatest(0, 1 - (n_active / km2) / 5.0);
  b := greatest(0, 1 - n_burns / 20.0);
  c := greatest(0, 1 - days / 60.0);
  d := case when n_total > 0 then n_cleared::real / n_total else 0 end;

  insert into public.city_scores (city_id, period, score, active_sites, burn_events,
                                  median_days_to_clear, pct_verified_cleared, parts, weights, computed_at)
  values (p_city_id, to_char(now(), 'YYYY-MM'), round(40 * a + 25 * b + 20 * c + 15 * d),
          n_active, n_burns, round(days::numeric, 1), round(d::numeric, 2),
          jsonb_build_object('active', round(a::numeric, 3), 'burn', round(b::numeric, 3),
                             'clear_time', round(c::numeric, 3), 'verified', round(d::numeric, 3)),
          '{"active": 40, "burn": 25, "clear_time": 20, "verified": 15}', now())
  on conflict (city_id, period) do update set
    score = excluded.score, active_sites = excluded.active_sites, burn_events = excluded.burn_events,
    median_days_to_clear = excluded.median_days_to_clear,
    pct_verified_cleared = excluded.pct_verified_cleared, parts = excluded.parts,
    weights = excluded.weights, computed_at = excluded.computed_at
  returning * into row_out;
  return row_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'cities', 'wards', 'official_sites', 'profiles', 'pipeline_runs', 'scenes', 'sites',
    'detections', 'fire_events', 'complaints', 'verifications', 'citizen_reports',
    'city_scores', 'audit_log'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;

  foreach t in array array['cities', 'wards', 'official_sites', 'scenes', 'detections',
                           'fire_events', 'verifications', 'city_scores'] loop
    execute format('create policy "Public read" on public.%I for select to anon, authenticated using (true)', t);
  end loop;
end;
$$;

-- N-06: low-confidence and dismissed sites stay off the public map.
create policy "Public reads confident sites, staff reads all" on public.sites
  for select to anon, authenticated
  using ((status <> 'dismissed' and coalesce(confidence, 1) >= 0.6) or public.is_staff());
create policy "Officers update sites" on public.sites
  for update to authenticated using (public.can_act()) with check (public.can_act());

create policy "Public reads sent complaints, staff reads all" on public.complaints
  for select to anon, authenticated using (status in ('sent', 'closed') or public.is_staff());
create policy "Officers create complaints" on public.complaints
  for insert to authenticated with check (public.can_act());
create policy "Officers update complaints" on public.complaints
  for update to authenticated using (public.can_act()) with check (public.can_act());

create policy "Officers record verifications" on public.verifications
  for insert to authenticated with check (public.can_act());

create policy "Citizens read own reports, staff read all" on public.citizen_reports
  for select to authenticated using (user_id = auth.uid()::text or public.is_staff());
create policy "Citizens file new reports" on public.citizen_reports
  for insert to authenticated
  with check (user_id = auth.uid()::text and status = 'new' and linked_site_id is null);
create policy "Officers review reports" on public.citizen_reports
  for update to authenticated using (public.can_act()) with check (public.can_act());

create policy "Read own profile, staff read all" on public.profiles
  for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "Update own profile" on public.profiles
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Users edit their name, language and home ward, never their role (admins use set_user_role).
revoke update on public.profiles from authenticated;
grant update (full_name, language, city_id, ward_id) on public.profiles to authenticated;

create policy "Staff read runs" on public.pipeline_runs
  for select to authenticated using (public.is_staff());
create policy "Officers queue runs" on public.pipeline_runs
  for insert to authenticated with check (public.can_act());

create policy "Staff read audit log" on public.audit_log
  for select to authenticated using (public.is_staff());
create policy "Officers write audit log" on public.audit_log
  for insert to authenticated with check (public.can_act() and actor = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('thumbnails', 'thumbnails', true, 5242880, array['image/png', 'image/jpeg', 'image/webp']),
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
