-- Canopy OS rehearsal · make a local copy behave like Supabase for the account that runs the migrations.
-- On Supabase the SQL Editor runs as "postgres", which is NOT a superuser: it owns the café's tables and functions,
-- can create roles and bypass row rules, but cannot do superuser-only things. Here "rehearsal_editor" plays that
-- part, so a migration that would need a superuser fails in the rehearsal instead of in production.
-- It also does not hold ADMIN on pg_read_all_data, so migration 0002's fallback is what gets exercised.
-- Local test databases only.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'rehearsal_editor') then
    create role rehearsal_editor login password 'rehearsal-only' nosuperuser createrole createdb bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'rehearsal_storage_admin') then
    create role rehearsal_storage_admin nologin;
  end if;
end $$;
grant anon, authenticated, service_role to rehearsal_editor;
grant rehearsal_storage_admin to rehearsal_editor;   -- Supabase lets the SQL Editor manage Storage policies and buckets
-- the backup account is created by the SQL Editor account in production (supabase/tools/backup-account.sql), which
-- makes it its admin; roles are shared by every database of this test server, so it may already exist here
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'canopy_backup') then grant canopy_backup to rehearsal_editor with admin option; end if;
end $$;
do $$ begin execute format('grant create on database %I to rehearsal_editor', current_database()); end $$;
alter schema public owner to rehearsal_editor;

-- everything the historical scripts created belongs to the SQL Editor account, as on Supabase
do $$
declare r record;
begin
  for r in select c.oid::regclass as obj, c.relkind from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'S')
              and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype in ('a', 'i')) loop
    execute format('alter %s %s owner to rehearsal_editor',
                   case r.relkind when 'v' then 'view' when 'm' then 'materialized view' when 'S' then 'sequence' else 'table' end, r.obj);
  end loop;
  for r in select p.oid::regprocedure as f from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') loop
    execute format('alter function %s owner to rehearsal_editor', r.f);
  end loop;
end $$;
alter table storage.objects owner to rehearsal_storage_admin;
alter table storage.buckets owner to rehearsal_storage_admin;
grant usage on schema storage, auth, extensions to rehearsal_editor;
grant select on all tables in schema auth to rehearsal_editor;
-- Supabase's default grants also cover what the SQL Editor account creates later
alter default privileges for role rehearsal_editor in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role rehearsal_editor in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges for role rehearsal_editor in schema public grant all on sequences to anon, authenticated, service_role;
