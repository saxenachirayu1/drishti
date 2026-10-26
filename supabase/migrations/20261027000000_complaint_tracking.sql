-- Complaint tracking: a resident raises a complaint, it is routed by type to the
-- right department (municipal SWM, PWD or the municipal C&D waste cell), the
-- department posts updates the resident sees live, and a cleared site is
-- "proven clean" when the satellite record clears.
--
--   report_categories   the four complaint types, reply targets and default department
--   departments         who a complaint can go to
--   pwd_roads           roads PWD maintains; debris on them goes to PWD
--   localities          named areas and PIN codes for the home page area search
--   citizen_reports     + category, ticket, department, ward, stage, reply due time
--   report_updates      the timeline the resident sees (realtime)
--   area_follows        residents following an area
--
-- RPCs: submit_report (now takes a category), route_preview, post_report_update, transfer_report,
-- reopen_report, track_report (public, by ticket), area_lookup (public),
-- impact_summary (public aggregates).
--
-- Reply targets are placeholders until a ward office confirms them.

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------

create table public.departments (
  id       text primary key,
  name     text not null,
  name_hi  text not null
);
insert into public.departments (id, name, name_hi) values
  ('swm', 'Municipal Solid Waste Management office', 'नगर निगम ठोस अपशिष्ट प्रबंधन कार्यालय'),
  ('pwd', 'PWD road division', 'लोक निर्माण विभाग, सड़क खंड'),
  ('cnd', 'Municipal C&D waste cell', 'नगर निगम निर्माण एवं विध्वंस अपशिष्ट प्रकोष्ठ')
on conflict (id) do nothing;

create table public.report_categories (
  id                  text primary key,
  label               text not null,
  label_hi            text not null,
  reply_hours         int  not null check (reply_hours > 0),
  default_department  text not null references public.departments (id),
  sort                int  not null default 0
);
insert into public.report_categories (id, label, label_hi, reply_hours, default_department, sort) values
  ('dump',    'Garbage dump',        'कचरे का ढेर',       24, 'swm', 1),
  ('burning', 'Waste burning',       'कचरा जलाना',        2,  'swm', 2),
  ('bin',     'Bin or pickup',       'कूड़ेदान या उठान',   24, 'swm', 3),
  ('debris',  'Construction debris', 'निर्माण का मलबा',    48, 'cnd', 4)
on conflict (id) do nothing;

create table public.pwd_roads (
  id          text primary key default gen_random_uuid()::text,
  city_id     text not null references public.cities (id) on delete cascade,
  name        text not null,
  geom        geometry(Geometry, 4326) not null
);
create index pwd_roads_geom_idx on public.pwd_roads using gist (geom);

create table public.localities (
  id          text primary key default gen_random_uuid()::text,
  city_id     text not null references public.cities (id) on delete cascade,
  name        text not null,
  name_hi     text,
  pincode     text check (pincode is null or pincode ~ '^[1-9][0-9]{5}$'),
  centroid    geometry(Point, 4326) not null,
  created_at  timestamptz not null default now()
);
create index localities_city_idx on public.localities (city_id);
create index localities_geom_idx on public.localities using gist (centroid);
create index localities_name_idx on public.localities (lower(name));
create index localities_pin_idx on public.localities (pincode);

-- Officers can belong to one department; the console opens on it.
alter table public.profiles add column if not exists department text references public.departments (id);

-- ---------------------------------------------------------------------------
-- Complaints
-- ---------------------------------------------------------------------------

create sequence public.report_ticket_seq start 1;

alter table public.citizen_reports
  add column category        text not null default 'dump' references public.report_categories (id),
  add column ticket          text unique,
  add column department      text references public.departments (id),
  add column ward_id         text references public.wards (id) on delete set null,
  add column locality_id     text references public.localities (id) on delete set null,
  add column on_pwd_road     boolean not null default false,
  add column stage           text not null default 'received'
                               check (stage in ('received', 'assigned', 'scheduled', 'in_progress',
                                                'resolved', 'proven_clean', 'reopened')),
  add column reply_due_at    timestamptz,
  add column first_reply_at  timestamptz,
  add column resolved_at     timestamptz,
  add column updated_at      timestamptz not null default now();
create index citizen_reports_dept_stage_idx on public.citizen_reports (department, stage);
create index citizen_reports_ward_idx on public.citizen_reports (ward_id);

-- Which department a complaint goes to.
create or replace function public.route_department(p_category text, p_on_pwd_road boolean)
returns text language sql immutable as $$
  select case
    when p_category = 'debris' and p_on_pwd_road then 'pwd'
    when p_category = 'debris' then 'cnd'
    else 'swm'
  end;
$$;

-- Fills everything the resident does not choose. Runs on every insert, so a
-- direct insert cannot set its own stage, department or deadline.
create or replace function public.citizen_reports_route()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare hours int;
begin
  new.ticket := 'DRI-Q-' || lpad(nextval('public.report_ticket_seq')::text, 4, '0');
  new.stage := 'received';
  new.first_reply_at := null;
  new.resolved_at := null;
  new.created_at := coalesce(new.created_at, now());
  new.updated_at := now();
  if new.location is not null then
    if new.city_id is null then
      select c.id into new.city_id from public.cities c where ST_Contains(c.bbox, new.location) limit 1;
    end if;
    select w.id into new.ward_id from public.wards w
      where ST_Contains(w.geom, new.location) and (new.city_id is null or w.city_id = new.city_id)
      limit 1;
    select l.id into new.locality_id from public.localities l
      where (new.city_id is null or l.city_id = new.city_id)
        and ST_DWithin(l.centroid::geography, new.location::geography, 3000)
      order by l.centroid <-> new.location
      limit 1;
    new.on_pwd_road := exists (
      select 1 from public.pwd_roads r
      where ST_DWithin(r.geom::geography, new.location::geography, 30));
  end if;
  new.department := public.route_department(new.category, new.on_pwd_road);
  select rc.reply_hours into hours from public.report_categories rc where rc.id = new.category;
  new.reply_due_at := new.created_at + make_interval(hours => hours);
  return new;
end;
$$;
create trigger citizen_reports_route before insert on public.citizen_reports
  for each row execute function public.citizen_reports_route();

-- ---------------------------------------------------------------------------
-- The timeline
-- ---------------------------------------------------------------------------

create table public.report_updates (
  id           text primary key default gen_random_uuid()::text,
  report_id    text not null references public.citizen_reports (id) on delete cascade,
  stage        text not null check (stage in ('received', 'assigned', 'scheduled', 'in_progress',
                                              'resolved', 'proven_clean', 'reopened', 'note')),
  message      text,
  photo_path   text,
  author_id    text,
  author_role  text not null check (author_role in ('system', 'department', 'citizen')),
  created_at   timestamptz not null default now()
);
create index report_updates_report_idx on public.report_updates (report_id, created_at);

-- Moves the complaint along when an update is posted.
create or replace function public.report_updates_apply()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.citizen_reports r set
    stage = case when new.stage = 'note' then r.stage else new.stage end,
    first_reply_at = case when new.author_role = 'department' and r.first_reply_at is null
                          then new.created_at else r.first_reply_at end,
    resolved_at = case when new.stage = 'resolved' then new.created_at
                       when new.stage = 'reopened' then null else r.resolved_at end,
    reply_due_at = case when new.stage = 'reopened'
                        then new.created_at + make_interval(hours => (
                          select rc.reply_hours from public.report_categories rc where rc.id = r.category))
                        else r.reply_due_at end,
    updated_at = now()
  where r.id = new.report_id;
  return new;
end;
$$;
create trigger report_updates_apply after insert on public.report_updates
  for each row execute function public.report_updates_apply();

-- The first entry: where it went.
create or replace function public.citizen_reports_first_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare dept text; ward text;
begin
  select d.name into dept from public.departments d where d.id = new.department;
  select coalesce('Ward ' || w.ward_no || ' · ', '') into ward from public.wards w where w.id = new.ward_id;
  insert into public.report_updates (report_id, stage, message, author_role, created_at)
  values (new.id, 'received', 'Sent to ' || coalesce(ward, '') || coalesce(dept, 'the city'), 'system', new.created_at);
  return new;
end;
$$;
create trigger citizen_reports_first_update after insert on public.citizen_reports
  for each row execute function public.citizen_reports_first_update();

-- Proof from space: when the satellite record clears, resolved complaints linked
-- to that site become proven clean.
create or replace function public.sites_prove_reports()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'cleared' and old.status is distinct from 'cleared' then
    insert into public.report_updates (report_id, stage, message, author_role)
    select r.id, 'proven_clean', 'The satellite shows the site clear on two passes.', 'system'
    from public.citizen_reports r
    where r.linked_site_id = new.id and r.stage = 'resolved';
  end if;
  return new;
end;
$$;
create trigger sites_prove_reports after update of status on public.sites
  for each row execute function public.sites_prove_reports();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Replaces the four-argument version; existing named calls keep working.
drop function if exists public.submit_report(double precision, double precision, text, text);
create or replace function public.submit_report(lng double precision, lat double precision,
                                                note text default null, photo_url text default null,
                                                category text default 'dump')
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  pt geometry := ST_SetSRID(ST_Point(lng, lat), 4326);
  near_id text;
  near_m double precision;
  rec public.citizen_reports;
begin
  if auth.uid() is null then
    raise exception 'sign in to report a site';
  end if;
  if not exists (select 1 from public.report_categories rc where rc.id = submit_report.category) then
    raise exception 'unknown complaint type %', submit_report.category;
  end if;
  select s.id, ST_Distance(coalesce(s.geom, s.centroid)::geography, pt::geography)
    into near_id, near_m
  from public.sites s
  where s.status <> 'dismissed' and coalesce(s.confidence, 1) >= 0.6
    and coalesce(s.geom, s.centroid) is not null
  order by coalesce(s.geom, s.centroid) <-> pt
  limit 1;

  insert into public.citizen_reports (user_id, location, note, photo_url, linked_site_id, status, category)
  values (
    auth.uid()::text, pt, submit_report.note, submit_report.photo_url,
    case when near_m <= 150 then near_id end,
    case when near_m <= 150 then 'matched' else 'new' end,
    submit_report.category
  )
  returning * into rec;

  return jsonb_build_object(
    'id', rec.id,
    'ticket', rec.ticket,
    'status', case when near_m <= 150 then 'matched' else 'flagged_for_review' end,
    'site_id', case when near_m <= 150 then near_id end,
    'nearest_site_id', near_id,
    'distance_m', round(near_m),
    'department', rec.department,
    'ward_id', rec.ward_id,
    'reply_due_at', rec.reply_due_at
  );
end;
$$;
revoke execute on function public.submit_report from public, anon;
grant execute on function public.submit_report to authenticated;

-- Shown on the form before sending: where this complaint would go.
create or replace function public.route_preview(lng double precision, lat double precision,
                                                category text default 'dump')
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  with pt as (select ST_SetSRID(ST_Point(lng, lat), 4326) as g),
  road as (select exists (select 1 from public.pwd_roads r, pt
                          where ST_DWithin(r.geom::geography, pt.g::geography, 30)) as on_road),
  ward as (select w.* from public.wards w, pt where ST_Contains(w.geom, pt.g) limit 1)
  select jsonb_build_object(
    'department', public.route_department(route_preview.category, road.on_road),
    'on_pwd_road', road.on_road,
    'reply_hours', (select rc.reply_hours from public.report_categories rc where rc.id = route_preview.category),
    'ward_id', (select id from ward),
    'ward_no', (select ward_no from ward),
    'ward_name', (select name from ward),
    'city_id', (select c.id from public.cities c, pt where ST_Contains(c.bbox, pt.g) limit 1)
  )
  from road;
$$;
grant execute on function public.route_preview to anon, authenticated;

-- A department posts an update. Resolving needs an after photo.
create or replace function public.post_report_update(p_report_id text, p_stage text,
                                                     p_message text default null,
                                                     p_photo_path text default null)
returns public.report_updates
language plpgsql security definer set search_path = public as $$
declare
  cur text;
  out_row public.report_updates;
  ord constant text[] := array['received', 'reopened', 'assigned', 'scheduled', 'in_progress', 'resolved'];
begin
  if not public.can_act() then
    raise exception 'only officers can post updates';
  end if;
  if p_stage not in ('assigned', 'scheduled', 'in_progress', 'resolved', 'note') then
    raise exception 'a department cannot set stage %', p_stage;
  end if;
  select stage into cur from public.citizen_reports where id = p_report_id for update;
  if cur is null then
    raise exception 'no complaint %', p_report_id;
  end if;
  if cur in ('resolved', 'proven_clean') and p_stage <> 'note' then
    raise exception 'this complaint is already %', cur;
  end if;
  if p_stage <> 'note' and array_position(ord, p_stage) < array_position(ord, cur) then
    raise exception 'cannot move from % back to %', cur, p_stage;
  end if;
  if p_stage = 'resolved' and coalesce(p_photo_path, '') = '' then
    raise exception 'attach an after photo to resolve';
  end if;
  if p_stage = 'note' and coalesce(trim(p_message), '') = '' then
    raise exception 'write a message';
  end if;
  insert into public.report_updates (report_id, stage, message, photo_path, author_id, author_role)
  values (p_report_id, p_stage, nullif(trim(p_message), ''), p_photo_path, auth.uid()::text, 'department')
  returning * into out_row;
  return out_row;
end;
$$;
revoke execute on function public.post_report_update from public, anon;
grant execute on function public.post_report_update to authenticated;

-- Sends a complaint to another department (for example city debris that is on a PWD road).
create or replace function public.transfer_report(p_report_id text, p_department text)
returns void language plpgsql security definer set search_path = public as $$
declare dept_name text;
begin
  if not public.can_act() then
    raise exception 'only officers can transfer complaints';
  end if;
  select name into dept_name from public.departments where id = p_department;
  if dept_name is null then
    raise exception 'unknown department %', p_department;
  end if;
  update public.citizen_reports set department = p_department, updated_at = now() where id = p_report_id;
  if not found then
    raise exception 'no complaint %', p_report_id;
  end if;
  insert into public.report_updates (report_id, stage, message, author_id, author_role)
  values (p_report_id, 'note', 'Transferred to ' || dept_name, auth.uid()::text, 'department');
end;
$$;
revoke execute on function public.transfer_report from public, anon;
grant execute on function public.transfer_report to authenticated;

-- The resident says it is not fixed.
create or replace function public.reopen_report(p_report_id text, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare owner text; cur text;
begin
  select user_id, stage into owner, cur from public.citizen_reports where id = p_report_id for update;
  if owner is null or owner <> auth.uid()::text then
    raise exception 'only the person who raised it can reopen it';
  end if;
  if cur not in ('resolved', 'proven_clean') then
    raise exception 'it is still open';
  end if;
  insert into public.report_updates (report_id, stage, message, author_id, author_role)
  values (p_report_id, 'reopened', coalesce(nullif(trim(p_reason), ''), 'Not fixed yet'), auth.uid()::text, 'citizen');
end;
$$;
revoke execute on function public.reopen_report from public, anon;
grant execute on function public.reopen_report to authenticated;

-- Anyone with a ticket code can follow it. Returns no reporter details, no
-- note and no photos: only where it went and what the department said.
create or replace function public.track_report(p_ticket text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', r.id,
    'ticket', r.ticket,
    'category', r.category,
    'stage', r.stage,
    'department', r.department,
    'ward_no', w.ward_no,
    'ward_name', w.name,
    'locality', l.name,
    'locality_hi', l.name_hi,
    'linked_site_id', r.linked_site_id,
    'created_at', r.created_at,
    'reply_due_at', r.reply_due_at,
    'first_reply_at', r.first_reply_at,
    'resolved_at', r.resolved_at,
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'stage', u.stage, 'message', u.message, 'author_role', u.author_role,
        'has_photo', u.photo_path is not null, 'created_at', u.created_at) order by u.created_at)
      from public.report_updates u where u.report_id = r.id), '[]'::jsonb)
  )
  from public.citizen_reports r
  left join public.wards w on w.id = r.ward_id
  left join public.localities l on l.id = r.locality_id
  where r.ticket = upper(trim(p_ticket));
$$;
grant execute on function public.track_report to anon, authenticated;

-- Home page search: an area name or a PIN code.
create or replace function public.area_lookup(q text)
returns table (id text, name text, name_hi text, pincode text, city_id text, city_name text,
               lat double precision, lng double precision, open_sites int, last_pass date, next_pass date)
language sql stable security definer set search_path = public, extensions as $$
  with hits as (
    select l.* from public.localities l
    where length(trim(q)) >= 2
      and (lower(l.name) like lower(trim(q)) || '%'
           or l.name_hi like trim(q) || '%'
           or l.pincode = trim(q))
    order by (l.pincode = trim(q)) desc, length(l.name)
    limit 5
  )
  select h.id, h.name, h.name_hi, h.pincode, h.city_id, c.name,
    ST_Y(h.centroid), ST_X(h.centroid),
    (select count(*)::int from public.sites s
      where s.city_id = h.city_id and s.status in ('active', 'complaint_sent', 'cleanup_reported')
        and coalesce(s.confidence, 1) >= 0.6
        and ST_DWithin(coalesce(s.centroid, ST_Centroid(s.geom))::geography, h.centroid::geography, 3000)),
    lp.d,
    -- Sentinel-2 revisits every five days: the first pass on or after today.
    case when lp.d is null then null
         else lp.d + 5 * (div(greatest(current_date - lp.d, 0), 5) + 1)::int end
  from hits h
  join public.cities c on c.id = h.city_id
  left join lateral (
    select max(sc.acquired_at)::date as d from public.scenes sc where sc.city_id = h.city_id
  ) lp on true;
$$;
grant execute on function public.area_lookup to anon, authenticated;

-- Public numbers for the impact page. Counts only; nothing personal.
create or replace function public.impact_summary(p_city_id text default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with s as (
    select * from public.sites
    where (p_city_id is null or city_id = p_city_id) and status <> 'dismissed'
      and coalesce(confidence, 1) >= 0.6
  ), r as (
    select * from public.citizen_reports where p_city_id is null or city_id = p_city_id
  )
  select jsonb_build_object(
    'sites_found', (select count(*) from s),
    'sites_open', (select count(*) from s where status in ('active', 'complaint_sent', 'cleanup_reported')),
    'sites_cleared', (select count(*) from s where status = 'cleared'),
    'area_open_m2', (select coalesce(round(sum(area_m2)), 0) from s
                      where status in ('active', 'complaint_sent', 'cleanup_reported')),
    'complaints', (select count(*) from r),
    'complaints_open', (select count(*) from r where stage not in ('resolved', 'proven_clean')),
    'complaints_resolved', (select count(*) from r where stage in ('resolved', 'proven_clean')),
    'complaints_proven', (select count(*) from r where stage = 'proven_clean'),
    'replied_on_time_pct', (select round(100.0 * count(*) filter (where first_reply_at <= reply_due_at)
                                         / nullif(count(*) filter (where first_reply_at is not null
                                                                   or reply_due_at < now()), 0))
                            from r),
    'median_reply_hours', (select round((percentile_cont(0.5) within group (
                             order by extract(epoch from first_reply_at - created_at) / 3600))::numeric, 1)
                           from r where first_reply_at is not null),
    'fires_30d', (select count(*) from public.fire_events f
                  where f.detected_at > now() - interval '30 days'
                    and (p_city_id is null or f.city_id = p_city_id)),
    'by_category', coalesce((select jsonb_object_agg(category, n) from (
                      select category, count(*) n from r group by category) x), '{}'::jsonb)
  );
$$;
grant execute on function public.impact_summary to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Views for the app
-- ---------------------------------------------------------------------------

-- New columns go at the end so the existing ones keep their order.
create or replace view public.report_map with (security_invoker = true) as
select r.id, r.user_id, r.city_id, r.note, r.photo_url, r.status, r.linked_site_id, r.created_at,
  ST_Y(r.location) as lat, ST_X(r.location) as lng,
  r.ticket, r.category, r.department, r.ward_id, w.ward_no, w.name as ward_name,
  l.name as locality, r.stage, r.reply_due_at, r.first_reply_at, r.resolved_at, r.updated_at,
  (r.first_reply_at is null and r.reply_due_at < now()) as overdue
from public.citizen_reports r
left join public.wards w on w.id = r.ward_id
left join public.localities l on l.id = r.locality_id;

-- ---------------------------------------------------------------------------
-- Follows
-- ---------------------------------------------------------------------------

create table public.area_follows (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  locality_id  text not null references public.localities (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (user_id, locality_id)
);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.departments enable row level security;
alter table public.report_categories enable row level security;
alter table public.pwd_roads enable row level security;
alter table public.localities enable row level security;
alter table public.report_updates enable row level security;
alter table public.area_follows enable row level security;

create policy "Public read" on public.departments for select to anon, authenticated using (true);
create policy "Public read" on public.report_categories for select to anon, authenticated using (true);
create policy "Public read" on public.pwd_roads for select to anon, authenticated using (true);
create policy "Public read" on public.localities for select to anon, authenticated using (true);

-- Updates are written through the RPCs above; people read the ones on
-- complaints they can see (their own, or all of them for staff).
create policy "Read updates on visible complaints" on public.report_updates
  for select to authenticated
  using (exists (select 1 from public.citizen_reports r where r.id = report_id));

create policy "Own follows" on public.area_follows
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Citizens may only ever file a new report; the trigger fills the rest.
drop policy if exists "Citizens file new reports" on public.citizen_reports;
create policy "Citizens file new reports" on public.citizen_reports
  for insert to authenticated
  with check (user_id = auth.uid()::text and status = 'new' and linked_site_id is null);

-- ---------------------------------------------------------------------------
-- Storage: department photos, readable by staff and the person who raised it
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-updates', 'report-updates', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Path: <report id>/<file>
create policy "Officers upload update photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'report-updates' and public.can_act());

create policy "Staff and reporter read update photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'report-updates' and (
    public.is_staff()
    or exists (select 1 from public.citizen_reports r
               where r.id = (storage.foldername(name))[1] and r.user_id = auth.uid()::text)));

-- ---------------------------------------------------------------------------
-- Realtime: the resident's timeline updates live
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and tablename = 'report_updates') then
    alter publication supabase_realtime add table public.report_updates;
  end if;
end;
$$;
