-- =====================================================================================================
-- Canopy OS · QUITAR LA CUENTA DE RESPALDO "canopy_backup"
-- (reversión de supabase/tools/backup-account.sql y de la parte "cuenta" de la migración 0002)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción.
--
-- Qué hace, en este orden:
--   1. la cuenta ya no puede entrar: sin contraseña y sin permiso de entrar (NOLOGIN);
--   2. cierra las conexiones que tenga abiertas (un respaldo a medias falla y no se guarda);
--   3. le quita todo lo que se le dio en esta base: lectura de tablas y secuencias, uso de esquemas, la lista de
--      fotos (storage.objects), la función canopy.backup_report (0002), los permisos para tablas futuras (0002, 0013)
--      y pg_read_all_data si se la había dado la versión 1 de backup-account.sql;
--   4. borra la cuenta y vuelve a cerrar cualquier conexión suya que haya entrado mientras tanto;
--   5. muestra UNA fila: "listo: la cuenta canopy_backup ya no existe", o "REVISAR: …" con lo que faltó.
-- Si dice "REVISAR" o sale un ERROR, copie la fila o el mensaje en el chat; ejecutarlo otra vez no hace daño.
-- Qué NO hace: no borra canopy.backup_runs (el historial de respaldos), ni canopy.backup_report, ni
-- public.backup_status, ni ninguna tabla, venta, foto, cuenta de acceso, aparato del café ni permiso de otra cuenta.
-- No usa DROP OWNED: si la cuenta fuera dueña de algo, no lo borra; lo dice en la fila y deja la cuenta sin entrar.
-- Tampoco devuelve a todas las cuentas (PUBLIC) el permiso de ejecutar las funciones internas de los disparadores que
-- quitó backup-account.sql: no hace falta, el café sigue funcionando igual.
-- Si la cuenta no existe, no cambia nada (solo cierra conexiones que hayan quedado abiertas de una cuenta ya borrada:
-- esas ya no pueden leer nada del café; si no puede cerrarlas, dice "REVISAR").
-- Orden: 1) GitHub → canopy-respaldos → Actions: desactive "Respaldo nocturno" y "Ensayo en pruebas" (Disable workflow);
-- 2) pegue esto; 3) borre el secreto CANOPY_DB_URL (ya no sirve: la contraseña quedó anulada).
-- NO borre la copia cifrada que guardó ni las dos llaves age: sin ellas esa copia no se puede abrir.
-- Para volver a tener la cuenta: supabase/tools/backup-account.sql (también después de las migraciones: vuelve a dar la
-- lectura de las tablas que creen las migraciones siguientes) y docs/RESPALDOS.md, paso 3.4.
-- No sirve "drop role canopy_backup" solo: falla en cuanto la cuenta tiene permisos (siempre con la versión 2) y no
-- cierra las conexiones abiertas.
-- =====================================================================================================
-- the result row reads these session settings, so it keeps its details under psql -f too
set canopy.quitar_respaldo = '';
set canopy.quitar_respaldo_extra = '';
set canopy.quitar_respaldo_oid = '';
do $$
declare
  rid      oid := (select oid from pg_roles where rolname = 'canopy_backup');
  r        record;
  stmt     text;
  notes    text[] := '{}';
  revoked  int := 0;
  closed   int := 0;
  det      text;
  tried    int[] := '{}';
begin
  if rid is null then
    -- already gone: only close connections left open by an account that no longer exists (they can read nothing).
    -- Not by backend_type: the SQL Editor's account (not a superuser) sees it empty on another account's sessions.
    for r in select pid from pg_stat_activity
              where datname = current_database() and usesysid is not null and pid <> pg_backend_pid()
                and not exists (select 1 from pg_roles where oid = usesysid) loop
      begin
        if pg_terminate_backend(r.pid, 3000) then closed := closed + 1; end if;
      exception when others then notes := notes || format('conexión %s sin cerrar: %s', r.pid, sqlerrm);
      end;
    end loop;
    perform pg_stat_clear_snapshot();                       -- the result row looks at the connections again
    perform set_config('canopy.quitar_respaldo', 'no existía', false);
    perform set_config('canopy.quitar_respaldo_extra',
                       case when closed > 0 then format('; se cerraron %s conexiones de una cuenta ya borrada', closed) else '' end
                       || case when cardinality(notes) > 0 then '; AVISOS: ' || array_to_string(notes, ' | ') else '' end, false);
    return;
  end if;
  perform set_config('canopy.quitar_respaldo_oid', rid::text, false);
  perform set_config('lock_timeout', '5s', true);          -- never freeze the tills waiting for a lock
  perform set_config('statement_timeout', '60s', true);

  -- 1. no new logins (takes effect when this paste commits; the old password is gone for good)
  begin
    alter role canopy_backup nologin password null;
  exception when others then notes := notes || ('no se pudo bloquear la entrada: ' || sqlerrm);
  end;
  begin
    alter role canopy_backup nobypassrls;
  exception when others then notes := notes || ('bypassrls: ' || sqlerrm);
  end;

  -- 2. end its open connections now (waits up to 3 s each; their temporary objects go with them)
  for r in select pid from pg_stat_activity where usesysid = rid and pid <> pg_backend_pid() loop
    tried := tried || r.pid;
    begin
      if pg_terminate_backend(r.pid, 3000) then closed := closed + 1; end if;
    exception when others then notes := notes || format('conexión %s sin cerrar: %s', r.pid, sqlerrm);
    end;
  end loop;

  -- 3a. role memberships it was given (pg_read_all_data on the main path)
  for r in select am.roleid::regrole::text as granted, am.grantor::regrole::text as grantor
             from pg_auth_members am where am.member = rid loop
    begin
      execute format('revoke %s from canopy_backup granted by %s', r.granted, r.grantor);
      revoked := revoked + 1;
    exception when others then notes := notes || format('no se pudo quitar %s (dado por %s): %s', r.granted, r.grantor, sqlerrm);
    end;
  end loop;

  -- 3b. every privilege it holds on an object of THIS database or on a shared object (fallback path, 0002)
  for r in select d.classid, d.objid, d.objsubid, d.deptype
             from pg_shdepend d
            where d.refclassid = 'pg_authid'::regclass and d.refobjid = rid and d.deptype = 'a'
              and d.dbid in (0, (select oid from pg_database where datname = current_database()))
            order by (d.classid = 'pg_default_acl'::regclass) desc, d.classid, d.objid loop
    stmt := null;
    if r.classid = 'pg_class'::regclass then
      stmt := format('revoke all on %s %s from canopy_backup',
                     case (select relkind from pg_class where oid = r.objid) when 'S' then 'sequence' else 'table' end,
                     r.objid::regclass);                   -- also revokes its column privileges
    elsif r.classid = 'pg_namespace'::regclass then
      stmt := format('revoke all on schema %s from canopy_backup', r.objid::regnamespace);
    elsif r.classid = 'pg_proc'::regclass then
      stmt := format('revoke all on routine %s from canopy_backup', r.objid::regprocedure);
    elsif r.classid = 'pg_type'::regclass then
      stmt := format('revoke all on type %s from canopy_backup', r.objid::regtype);
    elsif r.classid = 'pg_default_acl'::regclass then
      select format('alter default privileges for role %I%s revoke all on %s from canopy_backup',
                    a.defaclrole::regrole,
                    case when a.defaclnamespace = 0 then '' else format(' in schema %I', a.defaclnamespace::regnamespace) end,
                    case a.defaclobjtype when 'r' then 'tables' when 'S' then 'sequences' when 'f' then 'functions'
                                         when 'T' then 'types' when 'n' then 'schemas' end)
        into stmt from pg_default_acl a where a.oid = r.objid;
    elsif r.classid = 'pg_database'::regclass then
      stmt := format('revoke all on database %I from canopy_backup', (select datname from pg_database where oid = r.objid));
    elsif r.classid = 'pg_parameter_acl'::regclass then
      stmt := format('revoke all on parameter %s from canopy_backup', (select parname from pg_parameter_acl where oid = r.objid));
    elsif r.classid = 'pg_foreign_server'::regclass then
      stmt := format('revoke all on foreign server %I from canopy_backup', (select srvname from pg_foreign_server where oid = r.objid));
    elsif r.classid = 'pg_foreign_data_wrapper'::regclass then
      stmt := format('revoke all on foreign data wrapper %I from canopy_backup', (select fdwname from pg_foreign_data_wrapper where oid = r.objid));
    elsif r.classid = 'pg_largeobject_metadata'::regclass then
      stmt := format('revoke all on large object %s from canopy_backup', r.objid);
    end if;
    if stmt is null then
      notes := notes || format('permiso sin quitar: %s %s', r.classid::regclass, r.objid);
      continue;
    end if;
    begin
      execute stmt;
      revoked := revoked + 1;
    exception when others then notes := notes || format('%s: %s', stmt, sqlerrm);
    end;
  end loop;

  -- 4. drop the account (only an account: never DROP OWNED, never CASCADE)
  begin
    drop role canopy_backup;
  exception when others then
    get stacked diagnostics det = pg_exception_detail;
    notes := notes || ('la cuenta NO se borró: ' || sqlerrm || coalesce(' — ' || replace(det, E'\n', '; '), ''));
  end;

  -- 5. again, right before this paste commits: a connection made since step 2 still saw the old LOGIN
  perform pg_stat_clear_snapshot();
  for r in select pid from pg_stat_activity where usesysid = rid and pid <> pg_backend_pid() and pid <> all (tried) loop
    begin
      if pg_terminate_backend(r.pid, 3000) then closed := closed + 1; end if;
    exception when others then notes := notes || format('conexión %s sin cerrar: %s', r.pid, sqlerrm);
    end;
  end loop;
  perform pg_stat_clear_snapshot();                         -- the check below looks at the connections again

  perform set_config('canopy.quitar_respaldo',
                     format('permisos quitados: %s; conexiones cerradas: %s', revoked, closed)
                     || case when cardinality(notes) > 0 then '; AVISOS: ' || array_to_string(notes, ' | ') else '' end, false);
end $$;

-- the result: one row
select case
         when current_setting('canopy.quitar_respaldo', true) = 'no existía'
              and exists (select 1 from pg_stat_activity
                           where datname = current_database() and usesysid is not null and pid <> pg_backend_pid()
                             and not exists (select 1 from pg_roles where oid = usesysid))
           then 'REVISAR: la cuenta canopy_backup no existía, pero quedan conexiones abiertas de una cuenta ya borrada: '
                || (select count(*) from pg_stat_activity
                     where datname = current_database() and usesysid is not null and pid <> pg_backend_pid()
                       and not exists (select 1 from pg_roles where oid = usesysid))
                || current_setting('canopy.quitar_respaldo_extra', true)
         when current_setting('canopy.quitar_respaldo', true) = 'no existía'
           then 'listo: la cuenta canopy_backup no existía' || current_setting('canopy.quitar_respaldo_extra', true)
         when not exists (select 1 from pg_roles where rolname = 'canopy_backup')
              and not exists (select 1 from pg_stat_activity where usesysid = nullif(current_setting('canopy.quitar_respaldo_oid', true), '')::oid)
           then 'listo: la cuenta canopy_backup ya no existe (' || current_setting('canopy.quitar_respaldo', true) || ')'
         else 'REVISAR: ' || concat_ws('; ',
                case when exists (select 1 from pg_roles where rolname = 'canopy_backup')
                     then 'la cuenta sigue existiendo (puede entrar: '
                          || (select case when rolcanlogin then 'SÍ' else 'no' end from pg_roles where rolname = 'canopy_backup') || ')' end,
                (select 'conexiones abiertas: ' || count(*) from pg_stat_activity
                  where usesysid = nullif(current_setting('canopy.quitar_respaldo_oid', true), '')::oid having count(*) > 0),
                current_setting('canopy.quitar_respaldo', true))
       end as quitar_cuenta_de_respaldo;
