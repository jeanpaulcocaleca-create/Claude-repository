-- =====================================================================================================
-- Canopy OS · VERIFICACIÓN DE LA CUENTA DE RESPALDO "canopy_backup" (SOLO LECTURA: no cambia nada)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Resultado: UNA celda ("verificacion"). Copie la celda
-- completa y péguela en el chat.
--
-- Sirve en cualquier momento: antes y después del paso 2 (supabase/tools/backup-account.sql), antes y después del
-- paso 3.4 (supabase/tools/backup-password.sql) y después de cada tanda de migraciones (docs/RESPALDOS.md). No
-- muestra contraseñas, correos, PINs, montos ni nombres del personal: solo los permisos de la cuenta canopy_backup
-- (nombres de tablas y funciones) y los ajustes de registro que revisa backup-password.sql. Si la cuenta no existe,
-- lo dice ("exists": false): lo demás queda en 0, null o vacío, app_tables_not_readable lista todas las tablas y
-- backup_password_would_refuse es true (backup-password.sql se niega sin la cuenta).
-- Qué debe decir:
--   * account: exists true; can_login false ANTES del paso 3.4 y true DESPUÉS (la única diferencia entre las dos
--     corridas); bypassrls true (sin eso la copia saldría incompleta); superuser, create_role, create_db y
--     replication false; valid_until null (sin vencimiento: el pooler rechaza una cuenta vencida); memberships 0,
--     member_of [] y pg_read_all_data_member false (no hereda nada); owns_objects 0.
--   * reads: app_tables_readable igual a app_tables_total (hoy 26: las tablas del café en public; también canopy y
--     acct cuando las migraciones los creen) y app_tables_not_readable []; lo mismo con las secuencias;
--     storage_objects_readable true (la lista de fotos); storage_buckets_readable false.
--   * must_not: writable_relations 0 y writable_names [] (nada que pueda cambiar fuera de los catálogos);
--     can_create_in_database false y schemas_it_can_create_in []; auth_schema_usage false y auth_relations_readable 0
--     (no lee las cuentas de acceso); can_read_pg_authid_rolpassword false (no lee las contraseñas de las cuentas de
--     la base); vault_readable false o null; owner_rights_functions_executable [] (ninguna función que corra con los
--     permisos de su dueño; canopy.backup_report, la única permitida desde la migración 0002, no se lista, y
--     backup_report_executable es true desde la 0002); set_role_targets [].
--   * logging (lo que backup-password.sql revisa antes de generar la contraseña): pg_stat_statements_track distinto
--     de "all" (en Supabase: "top"), pgaudit_log "none" o sin "all"/"role", log_min_messages sin "debug",
--     pgtle_passcheck_functions 0 o null, password_encryption "scram-sha-256" y backup_password_would_refuse false.
--     log_statement, log_min_error_statement, log_lock_waits y deadlock_timeout se muestran solo como información.
-- Si algo no coincide, copie la celda en el chat; no cambie ningún ajuste.
-- =====================================================================================================
-- Primero: la base misma rechaza cualquier cambio dentro de esta consulta (todo lo pegado corre como una sola
-- transacción de solo lectura).
set transaction read only;
select jsonb_pretty(jsonb_build_object(
  'checked_at', now(),
  'checked_by', current_user,
  'server_version', current_setting('server_version'),
  'account', jsonb_build_object(
      'name', 'canopy_backup',
      'exists', r.oid is not null,
      'can_login', r.rolcanlogin,
      'bypassrls', r.rolbypassrls,
      'superuser', r.rolsuper,
      'create_role', r.rolcreaterole,
      'create_db', r.rolcreatedb,
      'replication', r.rolreplication,
      'inherit', r.rolinherit,
      'valid_until', r.rolvaliduntil,
      'connection_limit', r.rolconnlimit,
      'memberships', (select count(*) from pg_auth_members m where m.member = r.oid),
      'member_of', (select coalesce(jsonb_agg(m.roleid::regrole::text order by 1), '[]') from pg_auth_members m where m.member = r.oid),
      'pg_read_all_data_member', case when r.oid is null then null else pg_has_role(r.oid, 'pg_read_all_data', 'MEMBER') end,
      'owns_objects', (select count(*) from pg_shdepend d where d.refclassid = 'pg_authid'::regclass and d.refobjid = r.oid and d.deptype = 'o'
                          and d.dbid in (0, (select oid from pg_database where datname = current_database())))),
  'reads', jsonb_build_object(
      'app_schemas_usable', (select coalesce(jsonb_agg(n.nspname order by 1), '[]') from pg_namespace n
                               where n.nspname in ('public', 'canopy', 'acct') and has_schema_privilege(r.oid, n.oid, 'USAGE')),
      'app_tables_readable', (select count(*) from pg_class c
                                where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                                  and c.relkind in ('r', 'p') and has_table_privilege(r.oid, c.oid, 'SELECT')),
      'app_tables_total', (select count(*) from pg_class c
                             where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                               and c.relkind in ('r', 'p')),
      'app_tables_not_readable', (select coalesce(jsonb_agg(c.oid::regclass::text order by 1), '[]') from pg_class c
                                    where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                                      and c.relkind in ('r', 'p') and not coalesce(has_table_privilege(r.oid, c.oid, 'SELECT'), false)),
      -- has_sequence_privilege only on sequences (behind CASE: the planner may evaluate it on other relations otherwise)
      'app_sequences_readable', (select count(*) from pg_class c
                                   where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                                     and c.relkind = 'S'
                                     and case when c.relkind = 'S' then has_sequence_privilege(r.oid, c.oid, 'SELECT') else false end),
      'app_sequences_total', (select count(*) from pg_class c
                                where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct')) and c.relkind = 'S'),
      'storage_objects_readable', case when o.photo_list is null then null else
                                    coalesce(has_schema_privilege(r.oid, to_regnamespace('storage'), 'USAGE')
                                             and has_table_privilege(r.oid, o.photo_list, 'SELECT'), false) end,
      'storage_buckets_readable', case when o.bucket_list is null then null
                                       else coalesce(has_table_privilege(r.oid, o.bucket_list, 'SELECT'), false) end),
  'must_not', jsonb_build_object(
      -- INSERT/UPDATE/DELETE/TRUNCATE on any table, view, materialized view or foreign table outside the catalogs
      -- (a column-level INSERT/UPDATE counts), or USAGE/UPDATE (nextval/setval) on any sequence
      'writable_relations', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                               where c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
                                 and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_(toast|temp)'
                                 and case when c.relkind = 'S' then has_sequence_privilege(r.oid, c.oid, 'USAGE, UPDATE')
                                          else has_table_privilege(r.oid, c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE')
                                               or has_any_column_privilege(r.oid, c.oid, 'INSERT, UPDATE') end),
      'writable_names', (select coalesce(jsonb_agg(x.rel order by x.rel), '[]') from (
                           select c.oid::regclass::text as rel from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
                              and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_(toast|temp)'
                              and case when c.relkind = 'S' then has_sequence_privilege(r.oid, c.oid, 'USAGE, UPDATE')
                                       else has_table_privilege(r.oid, c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE')
                                            or has_any_column_privilege(r.oid, c.oid, 'INSERT, UPDATE') end
                            order by 1 limit 20) x),
      'can_create_in_database', case when r.oid is null then null
                                     else has_database_privilege(r.oid, (select oid from pg_database where datname = current_database()), 'CREATE') end,
      'schemas_it_can_create_in', (select coalesce(jsonb_agg(n.nspname order by 1), '[]') from pg_namespace n
                                     where n.nspname !~ '^pg_(toast_)?temp_' and has_schema_privilege(r.oid, n.oid, 'CREATE')),
      'auth_schema_usage', case when to_regnamespace('auth') is null or r.oid is null then null
                                else has_schema_privilege(r.oid, to_regnamespace('auth'), 'USAGE') end,
      'auth_relations_readable', (select count(*) from pg_class c
                                    where c.relnamespace = to_regnamespace('auth') and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
                                      and (has_table_privilege(r.oid, c.oid, 'SELECT') or has_any_column_privilege(r.oid, c.oid, 'SELECT'))),
      'auth_relations_total', (select count(*) from pg_class c
                                 where c.relnamespace = to_regnamespace('auth') and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')),
      'can_read_pg_authid_rolpassword', case when r.oid is null then null
                                             else has_column_privilege(r.oid, 'pg_catalog.pg_authid'::regclass, 'rolpassword', 'SELECT') end,
      'vault_readable', case when to_regnamespace('vault') is null or r.oid is null then null else
                          exists (select 1 from pg_class c where c.relnamespace = to_regnamespace('vault') and c.relkind in ('r', 'p', 'v', 'm')
                                   and has_table_privilege(r.oid, c.oid, 'SELECT')) end,
      -- functions that run with their owner's rights, callable by name (schema usable + EXECUTE); the backup's own
      -- report function (migration 0002) is the one allowed and is left out
      'owner_rights_functions_executable', (select coalesce(jsonb_agg(p.oid::regprocedure::text order by 1), '[]') from pg_proc p
                                              where p.prosecdef and p.prokind in ('f', 'p') and p.prorettype <> 'event_trigger'::regtype
                                                and p.oid is distinct from o.report_fn
                                                and has_schema_privilege(r.oid, p.pronamespace, 'USAGE')
                                                and has_function_privilege(r.oid, p.oid, 'EXECUTE')),
      'backup_report_executable', case when o.report_fn is null or r.oid is null then null
                                       else has_function_privilege(r.oid, o.report_fn, 'EXECUTE') end,
      'set_role_targets', (select coalesce(jsonb_agg(x.rolname order by 1), '[]') from pg_roles x
                             where r.oid is not null and x.oid <> r.oid and pg_has_role(r.oid, x.oid, 'USAGE'))),
  -- what backup-password.sql looks at before it generates the password (names and values of server settings only)
  'logging', jsonb_build_object(
      'log_statement', current_setting('log_statement', true),
      'log_min_error_statement', current_setting('log_min_error_statement', true),
      'log_lock_waits', current_setting('log_lock_waits', true),
      'deadlock_timeout', current_setting('deadlock_timeout', true),
      'log_min_messages', current_setting('log_min_messages', true),
      'pg_stat_statements_track', current_setting('pg_stat_statements.track', true),
      'pgaudit_log', coalesce(current_setting('pgaudit.log', true), 'none'),
      'pgtle_enable_password_check', current_setting('pgtle.enable_password_check', true),
      -- read only when pg_tle's table exists and is readable (query_to_xml: the table name is parsed only then)
      'pgtle_passcheck_functions', case when o.passcheck_list is null then null
                                        when not (has_schema_privilege(to_regnamespace('pgtle'), 'USAGE') and has_table_privilege(o.passcheck_list, 'SELECT')) then to_jsonb('not readable'::text)
                                        else to_jsonb((xpath('/row/n/text()', query_to_xml(
                                               'select count(*) as n from pgtle.feature_info where feature::text = ''passcheck''', false, true, '')))[1]::text::int) end,
      'password_encryption', current_setting('password_encryption', true),
      'backup_password_would_refuse', r.oid is null
                               or coalesce(current_setting('pg_stat_statements.track', true), 'none') = 'all'
                               or coalesce(current_setting('pgaudit.log', true), 'none') ~* '(^|[ ,])(all|role)([ ,]|$)'
                               or coalesce(current_setting('log_min_messages', true), '') ~* '^debug'
                               or (coalesce(current_setting('pgtle.enable_password_check', true), 'off') in ('on', 'true', 'yes', '1', 'require')
                                   and o.passcheck_list is not null
                                   and has_schema_privilege(to_regnamespace('pgtle'), 'USAGE') and has_table_privilege(o.passcheck_list, 'SELECT')
                                   and coalesce((xpath('/row/n/text()', query_to_xml(
                                         'select count(*) as n from pgtle.feature_info where feature::text = ''passcheck''', false, true, '')))[1]::text::int, 0) > 0))
)) as verificacion
  from (select 1) one left join pg_roles r on r.rolname = 'canopy_backup'
  -- the optional objects, found through the catalogs: to_regclass and to_regprocedure would need USAGE on their schemas
  cross join lateral (select
    (select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'storage' and c.relname = 'objects' and c.relkind in ('r', 'p', 'v')) as photo_list,
    (select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'storage' and c.relname = 'buckets' and c.relkind in ('r', 'p', 'v')) as bucket_list,
    (select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pgtle' and c.relname = 'feature_info' and c.relkind in ('r', 'p', 'v')) as passcheck_list,
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'canopy' and p.proname = 'backup_report'
       and oidvectortypes(p.proargtypes) = 'text, text, timestamp with time zone, bigint, text, text, jsonb, text') as report_fn) o;
