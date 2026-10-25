-- Member A requirements on top of the initial schema:
--   A-03 GIST indexes on every geometry column
--   A-04 private `reports` bucket (owner + officers)
--   A-07 audit_log rows for every status change on sites and complaints
--   A-16 dismiss reason, A-22 detection review, A-18 officer city

-- A-03 ----------------------------------------------------------------------
create index if not exists cities_bbox_idx on public.cities using gist (bbox);
create index if not exists detections_geom_idx on public.detections using gist (geom);
create index if not exists citizen_reports_location_idx on public.citizen_reports using gist (location);

-- A-16, A-22 ----------------------------------------------------------------
alter table public.sites add column if not exists dismissed_reason text;
alter table public.sites add column if not exists reviewed_at timestamptz;
alter table public.sites add column if not exists reviewed_by text;

create or replace view public.site_map with (security_invoker = true) as
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
  ) as on_official_record,
  s.dismissed_reason, s.reviewed_at
from public.sites s
left join public.wards w on w.id = s.ward_id;

-- A-07: status changes are audited by the database, whoever makes them ----------
create or replace function public.audit_status_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    insert into public.audit_log (actor, action, entity, entity_id, details)
    values (
      coalesce(auth.uid()::text, 'service'),
      'status_change',
      tg_table_name,
      new.id,
      jsonb_build_object('from', old.status, 'to', new.status)
        || case when tg_table_name = 'sites' and new.status = 'dismissed'
                then jsonb_build_object('reason', new.dismissed_reason) else '{}'::jsonb end
    );
  end if;
  return new;
end;
$$;
drop trigger if exists sites_audit_status on public.sites;
create trigger sites_audit_status after update of status on public.sites
  for each row execute function public.audit_status_change();
drop trigger if exists complaints_audit_status on public.complaints;
create trigger complaints_audit_status after update of status on public.complaints
  for each row execute function public.audit_status_change();

-- A-18: admins set a user's role and home city together ----------------------------
create or replace function public.set_user_access(target uuid, new_role text, new_city text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.app_role() <> 'admin' then
    raise exception 'only an admin can change roles';
  end if;
  update public.profiles set role = new_role, city_id = new_city where user_id = target;
end;
$$;

-- A-04: citizen photos are private to the reporter and staff ------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reports', 'reports', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "Reporters upload to own folder" on storage.objects;
create policy "Reporters upload to own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'reports' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Reporters and staff read report photos" on storage.objects;
create policy "Reporters and staff read report photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'reports'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));

-- A-19: new reports reach admins live ------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and tablename = 'citizen_reports') then
    alter publication supabase_realtime add table public.citizen_reports;
  end if;
end;
$$;
