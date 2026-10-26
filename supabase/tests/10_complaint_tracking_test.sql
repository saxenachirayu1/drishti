-- Integration test for complaint tracking, run against every migration plus
-- seed.sql (see run.sh). Each block raises on the first wrong result.
\set ON_ERROR_STOP on
set client_min_messages = warning;

-- People
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'asha@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'bilal@example.com'),
  ('00000000-0000-0000-0000-0000000000f1', 'officer@example.com');
update public.profiles set role = 'officer', department = 'swm'
  where user_id = '00000000-0000-0000-0000-0000000000f1';

create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', what; end if;
  raise notice 'ok  %', what;
end;
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;
set client_min_messages = notice;

-- 1. A resident raises a garbage dump on the satellite site in Shivajinagar.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
create temp table t_ids (k text primary key, id text, ticket text);
grant all on t_ids to authenticated, anon;
do $$
declare res jsonb; r public.citizen_reports;
begin
  res := public.submit_report(lng => 73.8606, lat => 18.5205, note => 'Behind the bus stop', category => 'dump');
  insert into t_ids values ('dump', res ->> 'id', res ->> 'ticket');
  select * into r from public.citizen_reports where id = res ->> 'id';
  perform pg_temp.check(res ->> 'status' = 'matched' and res ->> 'site_id' = 'site-5', 'matched to the satellite site');
  perform pg_temp.check(r.ticket ~ '^DRI-Q-[0-9]{4}$', 'ticket code ' || r.ticket);
  perform pg_temp.check(r.department = 'swm' and r.ward_id = 'w-pune-1', 'routed to ward 1 SWM');
  perform pg_temp.check(r.locality_id = 'loc-pune-shivajinagar', 'locality found');
  perform pg_temp.check(r.stage = 'received', 'stage received');
  perform pg_temp.check(r.reply_due_at = r.created_at + interval '24 hours', 'reply due in 24 h');
  perform pg_temp.check((select count(*) from public.report_updates u where u.report_id = r.id
                         and u.stage = 'received' and u.message like 'Sent to Ward 1 ·%') = 1,
                        'first timeline entry says where it went');
end;
$$;

-- 2. Routing by type.
do $$
declare res jsonb;
begin
  res := public.submit_report(73.8600, 18.5151, null, null, 'debris');
  perform pg_temp.check(res ->> 'department' = 'pwd', 'debris on a PWD road goes to PWD');
  insert into t_ids values ('debris_pwd', res ->> 'id', res ->> 'ticket');
  res := public.submit_report(73.8600, 18.5300, null, null, 'debris');
  perform pg_temp.check(res ->> 'department' = 'cnd', 'debris on a city road goes to the C&D cell');
  res := public.submit_report(73.8500, 18.5250, 'Smoke since morning', null, 'burning');
  perform pg_temp.check(res ->> 'department' = 'swm'
    and (res ->> 'reply_due_at')::timestamptz - now() between interval '1 hour 59 minutes' and interval '2 hours 1 minute',
    'burning is urgent: 2 h');
  insert into t_ids values ('burning', res ->> 'id', res ->> 'ticket');
  -- The old four-argument call still works and defaults to a dump.
  res := public.submit_report(lng => 73.8500, lat => 18.5200, note => 'old call', photo_url => null);
  perform pg_temp.check((select category from public.citizen_reports where id = res ->> 'id') = 'dump',
                        'old submit_report call defaults to dump');
  begin
    perform public.submit_report(73.85, 18.52, null, null, 'nonsense');
    raise exception 'FAILED: unknown type accepted';
  exception when raise_exception then
    if sqlerrm like 'FAILED%' then raise; end if;
    perform pg_temp.check(true, 'unknown type refused');
  end;
end;
$$;

-- 3. A direct insert cannot set its own stage or department.
do $$
declare r public.citizen_reports;
begin
  insert into public.citizen_reports (user_id, location, category, stage, department, first_reply_at)
  values (auth.uid()::text, ST_SetSRID(ST_Point(73.85, 18.52), 4326), 'bin', 'resolved', 'pwd', now())
  returning * into r;
  perform pg_temp.check(r.stage = 'received' and r.department = 'swm' and r.first_reply_at is null,
                        'direct insert is normalised by the trigger');
end;
$$;

-- 4. A resident cannot post department updates.
do $$
begin
  perform public.post_report_update((select id from t_ids where k = 'dump'), 'assigned', 'x');
  raise exception 'FAILED: citizen posted an update';
exception when raise_exception then
  if sqlerrm like 'FAILED%' then raise; end if;
  perform pg_temp.check(sqlerrm like 'only officers%', 'citizen cannot post updates');
end;
$$;

-- 5. Another resident sees nothing of it.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$
begin
  perform pg_temp.check((select count(*) from public.citizen_reports) = 0, 'other resident sees no complaints');
  perform pg_temp.check((select count(*) from public.report_updates) = 0, 'other resident sees no updates');
  begin
    perform public.reopen_report((select id from t_ids where k = 'dump'), 'mine now');
    raise exception 'FAILED: stranger reopened';
  exception when raise_exception then
    if sqlerrm like 'FAILED%' then raise; end if;
    perform pg_temp.check(true, 'stranger cannot reopen');
  end;
end;
$$;

-- 6. The officer works the complaint.
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';
do $$
declare rid text := (select id from t_ids where k = 'dump'); r public.citizen_reports;
begin
  perform pg_temp.check((select count(*) from public.report_map where overdue is not null) >= 5, 'officer sees the queue');
  perform public.post_report_update(rid, 'assigned', 'Sanitary Inspector assigned');
  select * into r from public.citizen_reports where id = rid;
  perform pg_temp.check(r.stage = 'assigned' and r.first_reply_at is not null, 'assigned, first reply recorded');
  perform public.post_report_update(rid, 'in_progress', 'Team on site');
  begin
    perform public.post_report_update(rid, 'scheduled', 'going back');
    raise exception 'FAILED: moved backwards';
  exception when raise_exception then
    if sqlerrm like 'FAILED%' then raise; end if;
    perform pg_temp.check(sqlerrm like 'cannot move%', 'cannot move backwards');
  end;
  begin
    perform public.post_report_update(rid, 'resolved', 'Done');
    raise exception 'FAILED: resolved without a photo';
  exception when raise_exception then
    if sqlerrm like 'FAILED%' then raise; end if;
    perform pg_temp.check(sqlerrm like 'attach an after photo%', 'resolving needs a photo');
  end;
  perform public.post_report_update(rid, 'resolved', 'Cleared and sprayed', rid || '/after.jpg');
  select * into r from public.citizen_reports where id = rid;
  perform pg_temp.check(r.stage = 'resolved' and r.resolved_at is not null, 'resolved');
  perform public.transfer_report((select id from t_ids where k = 'burning'), 'pwd');
  perform pg_temp.check((select department from public.citizen_reports where id = (select id from t_ids where k = 'burning')) = 'pwd',
                        'transfer changes the department');
end;
$$;

-- 7. Proof from space: the site clears, the complaint becomes proven clean.
reset role;
update public.sites set status = 'cleared' where id = 'site-5';
do $$
begin
  perform pg_temp.check((select stage from public.citizen_reports where id = (select id from t_ids where k = 'dump')) = 'proven_clean',
                        'cleared site proves the complaint clean');
end;
$$;

-- 8. The resident sees the whole timeline and can reopen.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$
declare rid text := (select id from t_ids where k = 'dump');
begin
  perform pg_temp.check((select array_agg(stage order by created_at) from public.report_updates where report_id = rid)
    = array['received', 'assigned', 'in_progress', 'resolved', 'proven_clean'], 'resident reads the full timeline');
  perform public.reopen_report(rid, 'It is back');
  perform pg_temp.check((select stage from public.citizen_reports where id = rid) = 'reopened', 'reopened');
  begin
    perform public.reopen_report(rid);
    raise exception 'FAILED: reopened twice';
  exception when raise_exception then
    if sqlerrm like 'FAILED%' then raise; end if;
    perform pg_temp.check(true, 'cannot reopen an open complaint');
  end;
end;
$$;

-- 9. Follows are private.
do $$
begin
  insert into public.area_follows (locality_id) values ('loc-pune-kothrud');
  perform pg_temp.check((select count(*) from public.area_follows) = 1, 'follow saved');
end;
$$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$
begin
  perform pg_temp.check((select count(*) from public.area_follows) = 0, 'follows are private');
end;
$$;

-- 10. Public, signed out: track by ticket, search areas, impact numbers.
set role anon;
set request.jwt.claim.sub = '';
do $$
declare t jsonb; a record; n int; imp jsonb;
begin
  t := public.track_report(lower((select ticket from t_ids where k = 'dump')));
  perform pg_temp.check(t ->> 'stage' = 'reopened' and jsonb_array_length(t -> 'updates') = 6, 'track by ticket, any case');
  perform pg_temp.check(not (t ? 'user_id') and not (t ? 'note') and not (t::text like '%Behind the bus stop%'),
                        'tracking shows nothing personal');
  perform pg_temp.check(public.track_report('DRI-Q-9999') is null, 'unknown ticket gives nothing');

  select * into a from public.area_lookup('kothrud');
  perform pg_temp.check(a.id = 'loc-pune-kothrud' and a.city_name = 'Pune', 'area search by name');
  perform pg_temp.check(a.next_pass > current_date and a.next_pass <= current_date + 5, 'next pass within five days');
  select * into a from public.area_lookup('411005');
  perform pg_temp.check(a.id = 'loc-pune-shivajinagar', 'area search by PIN code');
  select count(*) into n from public.area_lookup('zz');
  perform pg_temp.check(n = 0, 'no match gives nothing');
  select count(*) into n from public.area_lookup('शिवा');
  perform pg_temp.check(n = 1, 'area search in Hindi');

  t := public.route_preview(73.8600, 18.5151, 'debris');
  perform pg_temp.check(t ->> 'department' = 'pwd' and (t ->> 'ward_no')::int = 1 and (t ->> 'reply_hours')::int = 48,
                        'route preview for debris on a PWD road');
  t := public.route_preview(73.80, 18.50, 'burning');
  perform pg_temp.check(t ->> 'department' = 'swm' and t ->> 'ward_id' is null
                        and t ->> 'city_id' = '11111111-1111-1111-1111-111111111111', 'route preview outside any ward');
  imp := public.impact_summary();
  perform pg_temp.check((imp ->> 'complaints')::int >= 6 and (imp ->> 'complaints_proven')::int = 0
                        and (imp ->> 'sites_cleared')::int = 1 and imp ? 'replied_on_time_pct',
                        'impact numbers');
  perform pg_temp.check((select count(*) from public.report_categories) = 4, 'categories are public');
  begin
    perform public.submit_report(73.85, 18.52);
    raise exception 'FAILED: anon submitted';
  exception when insufficient_privilege then
    perform pg_temp.check(true, 'signed-out users cannot submit');
  end;
end;
$$;
reset role;
\echo 'complaint tracking: all checks passed'
