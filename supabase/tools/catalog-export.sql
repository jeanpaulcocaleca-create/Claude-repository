-- =====================================================================================================
-- Canopy OS · EXPORTAR LA ESTRUCTURA DE LA BASE (solo lectura)
-- Pegar en Supabase → SQL Editor → New query → Run.  No cambia nada y no muestra datos del negocio:
-- solo la estructura (tablas, columnas, funciones, reglas de acceso, permisos). Sin contraseñas ni claves.
--
-- Resultado: UNA fila con UNA celda ("ddl"). Copie la celda completa (clic derecho → Copy cell) y créela en
-- GitHub como el archivo supabase/baseline/production-schema.sql (vea docs/MIGRACIONES.md, "Línea base").
-- Así las pruebas usan exactamente la estructura real de producción.
-- =====================================================================================================
with
tabs as (
  select c.oid, n.nspname, c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, c.relacl
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p', 'v', 'm')
),
cols as (
  select t.nspname, t.relname,
         string_agg(format('  %I %s%s%s', a.attname, format_type(a.atttypid, a.atttypmod),
                           case when a.attnotnull then ' not null' else '' end,
                           coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')), E',\n' order by a.attnum) as body
    from tabs t join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where t.relkind in ('r', 'p')
   group by t.nspname, t.relname
),
ddl as (
  -- 1 tables
  select 1 as k, format('%I.%I', nspname, relname) as obj,
         format(E'create table %I.%I (\n%s\n);', nspname, relname, body) as txt
    from cols
  union all
  -- 2 constraints (primary keys, foreign keys with their ON DELETE rule, checks, uniques)
  select 2, format('%I.%I.%I', t.nspname, t.relname, con.conname),
         format('alter table %I.%I add constraint %I %s;', t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid))
    from tabs t join pg_constraint con on con.conrelid = t.oid
  union all
  -- 3 indexes that are not constraints
  select 3, format('%I.%I', t.nspname, ic.relname), pg_get_indexdef(i.indexrelid) || ';'
    from tabs t join pg_index i on i.indrelid = t.oid join pg_class ic on ic.oid = i.indexrelid
   where not exists (select 1 from pg_constraint con where con.conindid = i.indexrelid)
  union all
  -- 4 views
  select 4, format('%I.%I', nspname, relname), format(E'create or replace view %I.%I as\n%s', nspname, relname, pg_get_viewdef(oid, true))
    from tabs where relkind = 'v'
  union all
  -- 5 row level security switches
  select 5, format('%I.%I', nspname, relname),
         format('alter table %I.%I %s row level security;', nspname, relname, case when relrowsecurity then 'enable' else 'disable' end)
         || case when relforcerowsecurity then format(' alter table %I.%I force row level security;', nspname, relname) else '' end
    from tabs where relkind in ('r', 'p')
  union all
  -- 6 policies
  select 6, format('%I.%I.%I', schemaname, tablename, policyname),
         format('create policy %I on %I.%I as %s for %s to %s%s%s;', policyname, schemaname, tablename, permissive, cmd,
                array_to_string(roles, ', '),
                coalesce(' using (' || qual || ')', ''), coalesce(' with check (' || with_check || ')', ''))
    from pg_policies where schemaname in ('public', 'canopy', 'acct', 'storage')
  union all
  -- 7 functions
  select 7, format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), pg_get_functiondef(p.oid) || ';'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'canopy', 'acct') and p.prokind in ('f', 'p')
     and not exists (select 1 from pg_depend dep where dep.objid = p.oid and dep.deptype = 'e')
  union all
  -- 8 triggers
  select 8, format('%I.%I.%I', t.nspname, t.relname, tg.tgname), pg_get_triggerdef(tg.oid) || ';'
    from tabs t join pg_trigger tg on tg.tgrelid = t.oid where not tg.tgisinternal
  union all
  -- 9 table and column permissions for the API roles
  select 9, format('%I.%I', t.nspname, t.relname), format('-- grants on %I.%I: %s', t.nspname, t.relname, coalesce(t.relacl::text, 'default'))
    from tabs t
  union all
  select 9, format('%I.%I.%I', t.nspname, t.relname, a.attname), format('-- column grants %I.%I.%I: %s', t.nspname, t.relname, a.attname, a.attacl::text)
    from tabs t join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and a.attacl is not null
  union all
  -- 10 function permissions
  select 10, format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)),
         format('-- execute on %I.%I(%s): %s', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid), coalesce(p.proacl::text, 'default'))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'canopy', 'acct')
     and not exists (select 1 from pg_depend dep where dep.objid = p.oid and dep.deptype = 'e')
  union all
  -- 11 extensions and storage buckets (configuration only, never files)
  select 11, e.extname, format('-- extension %s %s in schema %s', e.extname, e.extversion, n.nspname)
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  union all
  select 11, 'storage.buckets', format('-- storage bucket %s public=%s', b.id, b.public) from storage.buckets b
)
select format(E'-- Canopy OS · estructura de producción exportada %s · %s\n-- %s\n\n',
              to_char(now() at time zone 'America/Costa_Rica', 'YYYY-MM-DD HH24:MI'), current_database(), version())
       || string_agg(txt, E'\n\n' order by k, obj) as ddl
  from ddl;
