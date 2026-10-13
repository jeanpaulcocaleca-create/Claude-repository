-- Canopy OS rehearsal · what production has that the historical scripts do not give it, so the rehearsal starts from
-- production as it is (read-only follow-up 2026-10-13, docs/DECISIONS.md D-031). Fake data never goes here.
--   * orders.note: already in tests/db/01_base_tables.sql (every test database has it).
--   * audit_menu(): production's text, supabase/accounts.sql's without the inline comment after "return new;" (same
--     code, same trigger, settings and owner). tests/tools/snapshot-known.sh accepts it (ACCEPTED), so the BEFORE
--     snapshot must still report functions_changed [] and every function legacy; run.sh then checks that its text
--     (md5), settings and owner are the same after the migrations, so no migration touches it.
-- Used by tests/rehearsal/run.sh right after the legacy build. Never run on a real Supabase project.
\set ON_ERROR_STOP on
create or replace function public.audit_menu()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text; what text;
begin
  who := coalesce(auth.jwt() ->> 'email', 'owner login');
  if tg_op = 'UPDATE' and row(old.name, old.price_crc, old.available, old.description, old.category_id)
       is not distinct from row(new.name, new.price_crc, new.available, new.description, new.category_id) then
    return new;
  end if;
  what := case tg_op when 'INSERT' then 'added ' || new.name
                     when 'DELETE' then 'removed ' || old.name
                     else 'changed ' || new.name end;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('menu_change', null, who, coalesce(new.id::text, old.id::text), what,
      case when tg_op = 'UPDATE' then jsonb_build_object(
        'before', jsonb_build_object('name', old.name, 'price_crc', old.price_crc, 'available', old.available),
        'after',  jsonb_build_object('name', new.name, 'price_crc', new.price_crc, 'available', new.available))
      when tg_op = 'INSERT' then jsonb_build_object('price_crc', new.price_crc)
      else jsonb_build_object('price_crc', old.price_crc) end);
  return coalesce(new, old);
end $$;
do $$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.audit_menu()'::regprocedure) <> '4807ea7301cd2ae6fe56052d3a165352' then
    raise exception 'production-drift.sql: audit_menu() is not production''s text';
  end if;
end $$;
