-- =====================================================================================================
-- Canopy OS · CUENTA DE RESPALDO (antes de la migración 0000) · versión 2: lectura limitada
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: queda todo o no queda nada.
--
-- Qué hace: crea la cuenta "canopy_backup", que solo sirve para COPIAR la base cada noche.
--   * Lee las tablas del café (esquema public; también canopy y acct cuando las migraciones los creen) y la LISTA
--     de fotos del menú (storage.objects: nombre y tamaño). Ignora las reglas de filas (bypassrls): sin eso la
--     copia saldría vacía o incompleta.
--   * NO lee las cuentas de acceso (auth: correos, contraseñas cifradas, sesiones abiertas, enlaces de recuperación,
--     códigos del teléfono) ni las contraseñas de las cuentas de la base. Si su contraseña se filtrara, nadie podría
--     entrar con ella como usted, como Jorge ni como los aparatos del café. Sí vería los datos del negocio (ventas,
--     personal y sus PIN cifrados, teléfonos de huéspedes): guárdela solo en el secreto de GitHub.
--   * No puede cambiar ni borrar datos del café, crear tablas ni actuar como otra cuenta. Como toda cuenta que entra,
--     sí puede guardar objetos temporales u "objetos grandes" (podría llenar el espacio de la base), enviar avisos
--     (NOTIFY) y cambiar su propia contraseña o ajustes (eso solo dejaría sin respaldo). Desde la migración 0002 anota
--     sus respaldos: la tarjeta verde de Inicio es lo que el respaldo dice de sí mismo; la prueba es el resumen del
--     trabajo en GitHub o restaurar la copia descargada.
--   * Se crea SIN contraseña y sin poder entrar; la contraseña la genera la base en docs/RESPALDOS.md, paso 3.4 (no
--     queda escrita en la consulta ni en los registros).
--   * Quita a todas las cuentas (PUBLIC) el permiso de ejecutar las funciones internas de los disparadores del café
--     (hoy 3: audit_menu, _order_discount_check, _order_tab_voided); siguen funcionando igual. Con ese permiso, cualquier
--     cuenta que entra a la base podía usarlas con los permisos de su dueño y cambiar una venta.
-- Qué NO hace: no toca ventas, inventario, personal, fotos, cuentas de acceso, aparatos del café ni otros permisos de
-- otras cuentas. No da el rol pg_read_all_data (lee TODO, también auth); si la cuenta ya lo tenía, se lo quita. Si este
-- script termina en ERROR, la cuenta queda como estaba; si todavía lo tiene, el mensaje empieza con "ATENCIÓN".
-- Al final se revisa a sí misma. Si la cuenta pudiera escribir o crear algo, ejecutar código con permisos de su
-- dueño (fuera de canopy.backup_report), pertenecer a otro rol, leer auth o, a través de una vista del café, algo que
-- no puede leer, si la base guardara a la vista de toda cuenta un ajuste que parece una clave, o si le faltara algo
-- para copiar, se detiene con un ERROR y NO cambia nada.
-- Copie ese mensaje en el chat.
-- Si todo está bien muestra UNA fila que empieza con "lista: la cuenta canopy_backup …".
-- Se puede ejecutar varias veces. Ejecútelo otra vez después de cada tanda de migraciones, como revisión: debe decir
-- "lista". Desde la 0002 también deja leíbles las tablas que creen las migraciones siguientes.
-- Reversión: supabase/tools/backup-account-rollback.sql (quita la cuenta y todos sus permisos; no toca nada más).
-- =====================================================================================================
-- On Supabase the SQL Editor's postgres has CREATEROLE and BYPASSRLS, owns the café's tables and has
-- USAGE + SELECT WITH GRANT OPTION on schema storage / storage.objects (storage-api 0046/0049, supabase/postgres
-- 20250709135250). All changes happen in ONE statement (the DO block), so they are atomic in the SQL Editor and in
-- psql -f. The result row says "lista" only when that block finished (canopy.cuenta_respaldo_ok = 'si').
set canopy.cuenta_respaldo_ok = 'no';
do $$
declare
  app_schemas oid[] := array(select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'));
  photo_list  regclass := to_regclass('storage.objects');
  report_fn   regprocedure := to_regprocedure('canopy.backup_report(text,text,timestamptz,bigint,text,text,jsonb,text)');
  this_db     oid := (select oid from pg_database where datname = current_database());
  write_privs text := 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
                      || case when current_setting('server_version_num')::int >= 170000 then ', MAINTAIN' else '' end;
  secret_re   text := '(secret|passw|token|api_?key|private_?key|service_?key)';
  had_all     boolean;   -- the account existed and could read everything (pg_read_all_data) before this paste
  had_login   boolean;   -- the account existed and could log in before this paste
  rid         oid;
  r           record;
  rattr       record;
  probs       text[] := '{}';
begin
  perform set_config('lock_timeout', '5s', true);   -- never queue the tills behind a lock
  select coalesce(bool_or(pg_has_role(oid, 'pg_read_all_data', 'MEMBER')), false), coalesce(bool_or(rolcanlogin), false)
    into had_all, had_login from pg_roles where rolname = 'canopy_backup';

  -- 1. the account: no login, no password, reads past row rules
  if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then
    create role canopy_backup nologin bypassrls;
  elsif not (select rolbypassrls from pg_roles where rolname = 'canopy_backup') then
    begin
      alter role canopy_backup bypassrls;   -- only when needed: altering a role needs ADMIN on it (PostgreSQL 16+)
    exception when others then probs := probs || ('no se pudo ajustar la cuenta existente: ' || sqlerrm);
    end;
  end if;
  rid := (select oid from pg_roles where rolname = 'canopy_backup');

  -- 2. version 1 of this script (and the old migration 0002) gave it pg_read_all_data: taken away
  for r in select am.grantor::regrole::text as grantor from pg_auth_members am
            where am.member = rid and am.roleid = 'pg_read_all_data'::regrole loop
    begin
      execute format('revoke pg_read_all_data from canopy_backup granted by %s', r.grantor);
    exception when others then probs := probs || format('no se pudo quitar pg_read_all_data (dado por %s): %s', r.grantor, sqlerrm);
    end;
  end loop;

  -- 3. read the café's tables and sequences (base tables only: no views), only where it cannot already
  for r in select n.oid, n.nspname from pg_namespace n where n.oid = any (app_schemas) loop
    if not has_schema_privilege(rid, r.oid, 'USAGE') then
      execute format('grant usage on schema %I to canopy_backup', r.nspname);
    end if;
  end loop;
  for r in select c.oid::regclass as rel, c.relkind from pg_class c
            where c.relnamespace = any (app_schemas) and c.relkind in ('r', 'p', 'S')
              and not has_table_privilege(rid, c.oid, 'SELECT') loop
    execute format('grant select on %s %s to canopy_backup', case r.relkind when 'S' then 'sequence' else 'table' end, r.rel);
  end loop;

  -- 3b. the café's owner-rights trigger functions: EXECUTE is checked only when a trigger is created, never when it
  --     fires, so taking it from every account (PUBLIC) changes nothing for the café's own triggers, and a login can no
  --     longer attach one to a temporary table of its own. What is left (granted by name, other owner) stops at 6d.
  for r in select p.oid::regprocedure as fn from pg_proc p
            where p.pronamespace = any (app_schemas) and p.prosecdef and p.prorettype = 'trigger'::regtype
              and has_function_privilege(rid, p.oid, 'EXECUTE') loop
    begin
      execute format('revoke execute on function %s from public', r.fn);
    exception when others then null;   -- 6d names it
    end;
  end loop;

  -- 4. the photo list (names and sizes; the photos themselves are downloaded from their public address)
  if photo_list is not null then
    if not has_schema_privilege(rid, 'storage', 'USAGE') then grant usage on schema storage to canopy_backup; end if;
    if not has_table_privilege(rid, photo_list, 'SELECT') then grant select on storage.objects to canopy_backup; end if;
  end if;

  -- 5. after migration 0002: the one write it may make ("backup done" in canopy.backup_runs), and reading the tables
  --    and sequences later migrations create (they run as this same SQL Editor account), as 0002 and 0013 set up.
  --    Repeating these is harmless; they matter when the account was removed and made again after 0002.
  if report_fn is not null then
    if not has_function_privilege(rid, report_fn, 'EXECUTE') then
      execute format('grant execute on function %s to canopy_backup', report_fn);
    end if;
    for r in select n.nspname from pg_namespace n where n.oid = any (app_schemas) order by 1 loop
      execute format('alter default privileges in schema %I grant select on tables to canopy_backup', r.nspname);
      execute format('alter default privileges in schema %I grant select on sequences to canopy_backup', r.nspname);
    end loop;
  end if;

  -- 6. SELF-CHECK. Any problem stops everything: the paste is rolled back and nothing above remains.
  -- 6a. attributes and memberships: no role it could act as or inherit from
  select * into rattr from pg_roles where oid = rid;
  probs := probs || array_remove(array[
             case when rattr.rolsuper then 'es superusuario' end,
             case when rattr.rolcreaterole then 'puede crear cuentas' end,
             case when rattr.rolcreatedb then 'puede crear bases' end,
             case when rattr.rolreplication then 'puede replicar la base' end,
             case when not rattr.rolbypassrls then 'no ignora las reglas de filas (la copia saldría incompleta)' end], null);
  probs := probs || array(select format('pertenece al rol %s (heredaría sus permisos)', roleid::regrole)
                            from pg_auth_members where member = rid order by 1);
  probs := probs || array(select format('es dueña de %s', pg_describe_object(classid, objid, objsubid))
                            from pg_shdepend where refclassid = 'pg_authid'::regclass and refobjid = rid and deptype = 'o'
                             and dbid in (0, this_db) order by 1);
  -- 6b. create anything (schemas in the database, objects in any schema)
  if has_database_privilege(rid, this_db, 'CREATE') then probs := probs || 'puede crear esquemas en la base'::text; end if;
  probs := probs || array(select format('puede crear objetos en el esquema %s', nspname) from pg_namespace n
                           where nspname !~ '^pg_(toast_)?temp_' and has_schema_privilege(rid, n.oid, 'CREATE') order by 1);
  -- 6c. write anywhere: tables, views, columns, sequences (in every schema). Not pg_settings: every account may
  --     UPDATE it, which is only the SET command for its own session.
  probs := probs || array(select format('puede escribir en %s', c.oid::regclass) from pg_class c
                           where c.relkind in ('r', 'p', 'v', 'm', 'f') and c.oid <> 'pg_catalog.pg_settings'::regclass
                             and c.relnamespace not in (select oid from pg_namespace where nspname ~ '^pg_(toast_)?temp_')
                             and (has_table_privilege(rid, c.oid, write_privs) or has_any_column_privilege(rid, c.oid, 'INSERT, UPDATE, REFERENCES'))
                           order by 1);
  probs := probs || array(select format('puede avanzar o cambiar la secuencia %s', c.oid::regclass) from pg_class c
                           where c.relkind = 'S' and c.relnamespace not in (select oid from pg_namespace where nspname ~ '^pg_(toast_)?temp_')
                             and case when c.relkind = 'S' then has_sequence_privilege(rid, c.oid, 'USAGE, UPDATE') else false end
                           order by 1);
  -- 6d. run a function with its owner's rights (SECURITY DEFINER) in a schema it can use, except backup_report.
  --     Trigger functions count: any login can attach one to a temporary table of its own, and EXECUTE is not checked
  --     again when it fires (only event triggers need a superuser). Any SQL login can fake the app's login
  --     (request.jwt.claims), so a callable owner-rights function would be a way around every rule.
  probs := probs || array(select format('puede ejecutar %s con los permisos de su dueño', p.oid::regprocedure) from pg_proc p
                           where p.prosecdef and p.prokind in ('f', 'p') and p.prorettype <> 'event_trigger'::regtype
                             and p.oid is distinct from report_fn
                             and has_schema_privilege(rid, p.pronamespace, 'USAGE') and has_function_privilege(rid, p.oid, 'EXECUTE')
                           order by 1);
  -- 6d'. the same, reached without calling the function by name (no USAGE on its schema needed): the parts of an
  --      aggregate it can run (only the aggregate's owner needs EXECUTE on them), an operator or its estimators, a
  --      type cast, or a view it can read (the caller needs EXECUTE on the functions the view calls)
  probs := probs || array(select distinct format('puede ejecutar %s con los permisos de su dueño (a través de %s)', f.oid::regprocedure, x.via)
                            from (select format('la función de agregado %s', a.aggfnoid::regprocedure) as via, c.fn, false as needs_execute
                                    from pg_aggregate a join pg_proc ap on ap.oid = a.aggfnoid
                                    cross join lateral unnest(array[a.aggtransfn, a.aggfinalfn, a.aggcombinefn, a.aggserialfn, a.aggdeserialfn,
                                                                    a.aggmtransfn, a.aggminvtransfn, a.aggmfinalfn]::oid[]) as c(fn)
                                   where has_schema_privilege(rid, ap.pronamespace, 'USAGE') and has_function_privilege(rid, ap.oid, 'EXECUTE')
                                  union all
                                  select format('el operador %s', o.oid::regoperator), c.fn, c.fn = o.oprcode from pg_operator o
                                    cross join lateral unnest(array[o.oprcode, o.oprrest, o.oprjoin]::oid[]) as c(fn)
                                   where has_schema_privilege(rid, o.oprnamespace, 'USAGE')
                                  union all
                                  select format('la conversión %s -> %s', c.castsource::regtype, c.casttarget::regtype), c.castfunc, true
                                    from pg_cast c where c.castfunc <> 0
                                  union all
                                  select format('la vista %s', v.oid::regclass), d.refobjid, true
                                    from pg_class v join pg_rewrite w on w.ev_class = v.oid
                                    join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_proc'::regclass
                                   where v.relkind = 'v' and has_schema_privilege(rid, v.relnamespace, 'USAGE') and has_table_privilege(rid, v.oid, 'SELECT')) x
                            join pg_proc f on f.oid = x.fn
                           where f.prosecdef and f.oid is distinct from report_fn
                             and (not x.needs_execute or has_function_privilege(rid, f.oid, 'EXECUTE'))
                           order by 1);
  -- 6e. read logins or passwords: auth (tables, views, columns), a view built on auth, the database's password list
  probs := probs || array(select format('puede leer %s', c.oid::regclass) from pg_class c
                           where c.relnamespace = (select oid from pg_namespace where nspname = 'auth') and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
                             and (has_table_privilege(rid, c.oid, 'SELECT') or has_any_column_privilege(rid, c.oid, 'SELECT'))
                           order by 1);
  --     (a view on a view on auth too, at any depth)
  probs := probs || array(select format('puede leer auth a través de la vista %s', v.oid::regclass)
                            from pg_class v where v.relkind in ('v', 'm') and has_table_privilege(rid, v.oid, 'SELECT')
                             and exists (with recursive dep(rel) as (
                                           select d.refobjid from pg_rewrite w
                                             join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_class'::regclass
                                            where w.ev_class = v.oid and d.refobjid <> v.oid
                                           union
                                           select d.refobjid from dep join pg_rewrite w on w.ev_class = dep.rel
                                             join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_class'::regclass
                                            where d.refobjid <> w.ev_class)
                                         select 1 from dep join pg_class t on t.oid = dep.rel
                                          where t.relnamespace = (select oid from pg_namespace where nspname = 'auth'))
                           order by 1);
  -- 6e'. a view of the café that shows what the account cannot read itself (0002 and 0013 give it SELECT on every
  --      future view of public, canopy and acct too; a view reads with its owner's rights): only its direct sources
  --      count, a source it can read is checked on its own. The system catalogs (pg_authid...) are never in pg_depend,
  --      so for them the view's text is searched for their names.
  probs := probs || array(select distinct format('puede leer %s a través de la vista %s', x.src, x.via)
                            from (select t.oid::regclass as src, v.oid::regclass as via
                                    from pg_class v join pg_rewrite w on w.ev_class = v.oid
                                    join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_class'::regclass
                                    join pg_class t on t.oid = d.refobjid
                                   where v.relnamespace = any (app_schemas) and v.relkind in ('v', 'm') and t.oid <> v.oid
                                     and has_table_privilege(rid, v.oid, 'SELECT') and not has_table_privilege(rid, t.oid, 'SELECT')
                                  union all
                                  select t.oid::regclass, v.oid::regclass
                                    from pg_class v join pg_class t on t.relnamespace = 'pg_catalog'::regnamespace and t.relkind in ('r', 'v', 'm')
                                   where v.relnamespace = any (app_schemas) and v.relkind in ('v', 'm')
                                     and has_table_privilege(rid, v.oid, 'SELECT') and not has_table_privilege(rid, t.oid, 'SELECT')
                                     and pg_get_viewdef(v.oid) ~ ('\m' || t.relname || '\M')) x);
  if has_column_privilege(rid, 'pg_catalog.pg_authid'::regclass, 'rolpassword', 'SELECT') then
    probs := probs || 'puede leer las contraseñas de las cuentas de la base (pg_authid)'::text;
  end if;
  -- 6f. read anything else that not every account can read (vault, other storage tables, pg_catalog's hidden ones...)
  probs := probs || array(select format('puede leer %s, que no necesita', c.oid::regclass) from pg_class c
                           where c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
                             and c.relnamespace not in (select oid from pg_namespace
                                                         where oid = any (app_schemas) or nspname = 'auth' or nspname ~ '^pg_(toast_)?temp_')
                             and c.oid is distinct from photo_list
                             and has_table_privilege(rid, c.oid, 'SELECT')
                             and not exists (select 1 from aclexplode(coalesce(c.relacl, acldefault((case c.relkind when 'S' then 's' else 'r' end)::"char", c.relowner))) a
                                              where a.grantee = 0 and a.privilege_type = 'SELECT')
                           order by 1);
  -- 6g. any permission given to it by name on something outside the list above (or more than reading it); a view of
  --     the café is in the list (0002's default rights give it one; 6c, 6d' and 6e/6e' check what it shows)
  probs := probs || array(select format('tiene un permiso inesperado sobre %s', pg_describe_object(d.classid, d.objid, d.objsubid))
                            from pg_shdepend d
                           where d.refclassid = 'pg_authid'::regclass and d.refobjid = rid and d.deptype = 'a' and d.dbid in (0, this_db)
                             and not ((d.classid = 'pg_class'::regclass
                                        and (d.objid = photo_list
                                             or exists (select 1 from pg_class c where c.oid = d.objid and c.relnamespace = any (app_schemas)
                                                                                    and c.relkind in ('r', 'p', 'S', 'v', 'm'))))
                                   or (d.classid = 'pg_namespace'::regclass
                                        and (d.objid = any (app_schemas) or d.objid = (select oid from pg_namespace where nspname = 'storage')))
                                   or (d.classid = 'pg_proc'::regclass and d.objid = report_fn)
                                   or (d.classid = 'pg_default_acl'::regclass
                                        and exists (select 1 from pg_default_acl a where a.oid = d.objid and a.defaclnamespace = any (app_schemas)
                                                                                     and a.defaclobjtype in ('r', 'S')
                                                                                     and not exists (select 1 from aclexplode(a.defaclacl) x
                                                                                                      where x.grantee = rid and x.privilege_type <> 'SELECT'))))
                           order by 1);
  -- 6h. what the backup must copy: every table and sequence of the café, the photo list, the run log (after 0002)
  probs := probs || array(select format('no puede entrar al esquema %s', nspname) from pg_namespace n
                           where n.oid = any (app_schemas) and not has_schema_privilege(rid, n.oid, 'USAGE') order by 1);
  probs := probs || array(select format('no puede leer %s', c.oid::regclass) from pg_class c
                           where c.relnamespace = any (app_schemas) and c.relkind in ('r', 'p', 'S')
                             and not has_table_privilege(rid, c.oid, 'SELECT') order by 1);
  if photo_list is not null and not (has_schema_privilege(rid, 'storage', 'USAGE') and has_table_privilege(rid, photo_list, 'SELECT')) then
    probs := probs || 'no puede leer la lista de fotos (storage.objects): esta cuenta del SQL Editor no puede darle ese permiso'::text;
  end if;
  if report_fn is not null and not has_function_privilege(rid, report_fn, 'EXECUTE') then
    probs := probs || 'no puede anotar el respaldo (canopy.backup_report)'::text;
  end if;
  -- 6i. a key kept where every login can read it (a custom setting of a database or an account, e.g. an old
  --     app.settings.jwt_secret): this account's password would then be enough to act as anyone. Names only.
  --     Only a setting that can hold text and is not empty can hold a key: a switch, a number or a choice from a list
  --     (an extension's on/off setting like pgtle.enable_password_check on Supabase) cannot, whatever its name says.
  --     A database or account setting that nothing defines is text, so it is always judged; one the server knows as
  --     a switch, number or list choice is skipped only when its stored value is a valid one of those (a superuser
  --     could store any text under such a name while the extension is not loaded). A server-file setting that nothing
  --     defines is not listed in pg_settings and cannot be found from SQL: Supabase's configuration sets none.
  probs := probs || array(select distinct format('la base guarda, a la vista de toda cuenta que entra, un ajuste que parece una clave: %s (%s)',
                                                 split_part(x.cfg, '=', 1),
                                                 case when s.setrole = 0 then 'para todas las cuentas' else 'de la cuenta ' || coalesce(pg_get_userbyid(s.setrole), '?') end)
                            from pg_catalog.pg_db_role_setting s cross join lateral unnest(s.setconfig) as x(cfg)
                           where split_part(x.cfg, '=', 1) like '%.%' and split_part(x.cfg, '=', 1) ~* secret_re
                             and substr(x.cfg, strpos(x.cfg, '=') + 1) <> ''
                             and not exists (select 1 from pg_catalog.pg_settings ps
                                              cross join lateral (select lower(btrim(substr(x.cfg, strpos(x.cfg, '=') + 1))) as v) val
                                              where lower(ps.name) = lower(split_part(x.cfg, '=', 1))
                                                and case ps.vartype
                                                      when 'bool' then val.v in ('on', 'off', 'true', 'false', 'yes', 'no', '1', '0', 't', 'f', 'y', 'n')
                                                      when 'enum' then val.v = any (select lower(e) from unnest(ps.enumvals) e)
                                                      when 'integer' then val.v ~ '^[-+]?[0-9]+ *[a-z]*$'
                                                      when 'real' then val.v ~ '^[-+]?[0-9.]+(e[-+]?[0-9]+)? *[a-z]*$'
                                                      else false end));
  probs := probs || array(select format('el servidor tiene, a la vista de toda cuenta, un ajuste que parece una clave: %s', ps.name)
                            from pg_catalog.pg_settings ps
                           where ps.name like '%.%' and ps.name ~* secret_re
                             and ps.vartype = 'string' and coalesce(ps.setting, '') <> '' order by 1);

  if cardinality(probs) > 0 then
    raise exception '%NO SE CREÓ NI SE CAMBIÓ NADA. La cuenta canopy_backup: %',
      case when had_all then 'ATENCIÓN: la cuenta canopy_backup ya existía y TODAVÍA puede leer todo, también las cuentas de acceso '
                             || '(pg_read_all_data). Pegue supabase/tools/backup-account-rollback.sql para quitarla. '
           when had_login then 'ATENCIÓN: la cuenta canopy_backup ya existía, puede entrar y quedó como estaba. '
           else '' end,
      left(array_to_string(probs, '; '), 1500)
      using hint = 'Copie este mensaje en el chat. Este pegado no cambió nada en la base.';
  end if;
  perform set_config('canopy.cuenta_respaldo_ok', 'si', false);   -- read by the row below; undone if the paste fails
end $$;

-- the result: one row, read from the database as it is now ("lista" only if the block above finished)
select case when current_setting('canopy.cuenta_respaldo_ok', true) is distinct from 'si'
              then 'REVISAR: la revisión de arriba no terminó bien (vea el ERROR); la cuenta NO está lista'
            when r.oid is null then 'REVISAR: la cuenta canopy_backup no existe; no se cambió nada'
            when r.rolbypassrls and not r.rolsuper
                 and not exists (select 1 from pg_auth_members where member = r.oid)
                 and not exists (select 1 from pg_class c where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                                    and c.relkind in ('r', 'p', 'S') and not has_table_privilege(r.oid, c.oid, 'SELECT'))
                 and not exists (select 1 from pg_class c where c.relnamespace in (select oid from pg_namespace where nspname = 'auth')
                                    and has_table_privilege(r.oid, c.oid, 'SELECT'))
                 and (to_regclass('storage.objects') is null or has_table_privilege(r.oid, 'storage.objects', 'SELECT'))
              then format('lista: la cuenta canopy_backup puede leer %s tablas del café y la lista de fotos; no puede cambiar los datos del café ni leer las cuentas de acceso%s',
                          (select count(*) from pg_class where relkind in ('r', 'p')
                              and relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))),
                          case when r.rolcanlogin then '' else ' (aún no puede entrar: paso 3.4)' end)
            else 'REVISAR: la cuenta canopy_backup existe pero no está como debe; ejecute este script otra vez y copie el mensaje en el chat' end
         as cuenta_de_respaldo
  from (select 1) one left join pg_roles r on r.rolname = 'canopy_backup';
