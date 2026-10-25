-- The status audit trigger is shared by sites and complaints, and complaints
-- have no dismissed_reason column, so read it through jsonb instead of NEW.
create or replace function public.audit_status_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  reason text := to_jsonb(new) ->> 'dismissed_reason';
begin
  if new.status is distinct from old.status then
    insert into public.audit_log (actor, action, entity, entity_id, details)
    values (
      coalesce(auth.uid()::text, 'service'),
      'status_change',
      tg_table_name,
      new.id,
      jsonb_build_object('from', old.status, 'to', new.status)
        || case when new.status = 'dismissed' and reason is not null
                then jsonb_build_object('reason', reason) else '{}'::jsonb end
    );
  end if;
  return new;
end;
$$;
