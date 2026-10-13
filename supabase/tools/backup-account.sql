-- =====================================================================================================
-- Canopy OS · CUENTA DE RESPALDO (antes de la migración 0000)
-- Supabase → SQL Editor → New query → pegar TODO → Run.
--
-- Qué hace: crea la cuenta "canopy_backup", que solo puede LEER la base para copiarla. No puede cambiar ni
-- borrar nada, pero lee TODO, también los datos de inicio de sesión: su contraseña vale tanto como la del dueño.
-- Se crea SIN contraseña y sin poder entrar; la contraseña la genera la base en docs/RESPALDOS.md, paso 3.4 (no
-- queda escrita en la consulta ni en los registros). No toca ventas, inventario, personal ni ningún otro dato del negocio.
-- Es lo mismo que hace la migración 0002 con esa cuenta: cuando aplique la 0002, no cambia nada aquí.
-- Se puede ejecutar dos veces sin problema. Si algún día el respaldo dice "permission denied" después de una
-- migración, vuelva a ejecutarlo.
-- Reversión: drop role canopy_backup;
-- =====================================================================================================
-- On Supabase the SQL Editor's postgres has CREATEROLE, BYPASSRLS and ADMIN on pg_read_all_data (snapshot 2026-10-12),
-- and supautils lets all three statements through: neither name is a reserved role or reserved membership.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then
    create role canopy_backup nologin bypassrls;
  elsif not (select rolbypassrls from pg_roles where rolname = 'canopy_backup') then
    alter role canopy_backup bypassrls;   -- only when needed: altering a role needs ADMIN on it (PostgreSQL 16+)
  end if;
end $$;

do $$
declare sch text;
begin
  grant pg_read_all_data to canopy_backup;
exception when others then
  -- if this server does not allow it, read access table by table (also for tables created later)
  raise notice 'pg_read_all_data no disponible (%); se dan permisos de lectura tabla por tabla', sqlerrm;
  for sch in select nspname from pg_namespace where nspname in ('public', 'canopy', 'acct') loop
    execute format('grant usage on schema %I to canopy_backup', sch);
    execute format('grant select on all tables in schema %I to canopy_backup', sch);
    execute format('grant select on all sequences in schema %I to canopy_backup', sch);
    execute format('alter default privileges in schema %I grant select on tables to canopy_backup', sch);
    execute format('alter default privileges in schema %I grant select on sequences to canopy_backup', sch);
  end loop;
  grant usage on schema storage to canopy_backup;
  grant select on storage.objects, storage.buckets to canopy_backup;
end $$;

do $$
begin
  if to_regnamespace('canopy') is not null then grant usage on schema canopy to canopy_backup; end if;
end $$;

-- the result: "lista" when the account can read every table (and every row) it has to copy
select case when problems = '[]'::jsonb then 'lista: la cuenta canopy_backup puede leer todo y no puede cambiar nada'
            else 'REVISAR: ' || problems::text end as cuenta_de_respaldo
  from (select coalesce(jsonb_agg(p), '[]'::jsonb) as problems from (
          select 'no ignora las reglas de filas (bypassrls)' as p
            from pg_roles where rolname = 'canopy_backup' and not rolbypassrls
          union all
          select 'no puede leer ' || n.nspname || '.' || c.relname
            from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p', 'S')
             and not has_table_privilege('canopy_backup', c.oid, 'select')
          union all
          select 'puede escribir en ' || n.nspname || '.' || c.relname
            from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p')
             and (has_table_privilege('canopy_backup', c.oid, 'insert') or has_table_privilege('canopy_backup', c.oid, 'update')
                  or has_table_privilege('canopy_backup', c.oid, 'delete') or has_table_privilege('canopy_backup', c.oid, 'truncate'))
          union all
          select 'no puede leer la lista de fotos (storage.objects)'
           where not has_table_privilege('canopy_backup', 'storage.objects', 'select')
        ) q) r;
