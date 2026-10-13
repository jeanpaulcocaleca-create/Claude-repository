-- =====================================================================================================
-- Canopy OS · CONTRASEÑA DE LA CUENTA DE RESPALDO "canopy_backup" (docs/RESPALDOS.md, paso 3.4)
-- Supabase → SQL Editor → New query (pestaña nueva y vacía) → pegar TODO → Run, SIN nada seleccionado.
-- Es una sola ejecución: la base genera la contraseña, se la pone a la cuenta y la muestra, todo en el mismo pegado.
--
-- Qué hace: SOLO dos cosas, y solo de la cuenta canopy_backup: le da permiso de entrar (LOGIN) y le pone una
--   contraseña nueva que genera la base misma (64 caracteres hexadecimales: cifras 0-9 y letras a-f, a partir de dos
--   UUID aleatorios). Nada más: no toca ventas, inventario, personal, fotos, cuentas de acceso ni aparatos del café,
--   ni los permisos de la cuenta ni ninguna otra cuenta. Los permisos de lectura los dio el paso 2
--   (supabase/tools/backup-account.sql), que debe haberse ejecutado antes.
-- Qué se niega a hacer (sale un ERROR que empieza con "NO SE CAMBIÓ NADA"):
--   * si la cuenta canopy_backup no existe (primero el paso 2);
--   * si esta base anotaría el texto de las órdenes internas y, con él, la contraseña: estadísticas de consultas
--     (pg_stat_statements.track = all), auditoría de cuentas (pgaudit.log con all o role) o mensajes de depuración
--     (log_min_messages = debug…). Con los ajustes normales de Supabase no pasa;
--   * si la base entrega cada contraseña nueva a una función de revisión (pg_tle "passcheck"): esa función la vería;
--   * si no se pudo poner la contraseña (un bloqueo que no se soltó a tiempo —se espera 0,9 s como máximo—, un permiso
--     que falta): el mensaje dice la causa SIN la orden interna, que lleva la contraseña; nada quedó puesto.
--   Cualquier ERROR, empiece o no con "NO SE CAMBIÓ NADA", deja todo como estaba: el pegado entero es una sola
--   transacción y la base deshace lo que hubiera hecho. NO cambie ningún ajuste: copie el mensaje en el chat.
-- Resultado esperado: UNA fila con una celda "contrasena" de 64 caracteres. Cópiela desde la celda y péguela en el
--   secreto CANOPY_DB_URL de GitHub en lugar de [YOUR-PASSWORD], corchetes incluidos (docs/RESPALDOS.md, paso 3.4,
--   punto 4). No trae caracteres que haya que cambiar.
--   * Si la fila empieza con "REVISAR": el pegado no corrió como una sola ejecución (por ejemplo, con una parte
--     seleccionada) y puede que se haya puesto una contraseña sin mostrarla. No pasa nada: ejecútelo otra vez,
--     completo, sin seleccionar.
--   * Se puede ejecutar cuantas veces haga falta: cada ejecución reemplaza la contraseña anterior, que deja de servir
--     (en el pooler, hasta un día después: vea el punto siguiente); actualice el secreto. Si la perdió, ejecútelo otra
--     vez: no hace falta guardarla en ningún otro lado.
--   * Si cambia la contraseña porque sospecha de la anterior: el pooler de Supabase guarda la anterior hasta un día y
--     una conexión que ya estaba abierta sigue viva. Cierre sus conexiones con supabase/tools/backup-account-rollback.sql
--     (quita la cuenta) y vuelva a crearla: paso 2 y este archivo otra vez; luego actualice el secreto.
-- Dónde NO queda la contraseña: no está en el texto de esta consulta (la consulta que Supabase guarda no la tiene);
--   no la escribe el registro del servidor ni las estadísticas de consultas (medido en PostgreSQL 16 y 17 con los
--   ajustes de Supabase; por eso el script se niega cuando un ajuste sí la anotaría); y si falla, el mensaje de error
--   no la lleva. Hasta donde se midió, vive solo en la celda del resultado mientras la tenga en pantalla, y en el
--   secreto de GitHub.
-- Higiene: nunca pegue el valor en el chat, en un correo ni en un archivo. Después de pegarlo en el secreto de GitHub,
--   copie cualquier otra cosa (un texto cualquiera) para que salga del portapapeles y, en Windows, si tiene activado
--   el historial del portapapeles (Win+V), bórrelo ("Borrar todo"). Luego cierre la pestaña del SQL Editor.
-- Para comprobar la cuenta antes y después (solo lectura, sin contraseñas): supabase/tools/backup-account-check.sql.
-- =====================================================================================================
do $$
declare
  clave      text;
  revisiones int := 0;
begin
  -- 1. Se niega, SIN cambiar nada, si la cuenta no existe o si esta base anotaría el texto de las órdenes internas
  --    (y con él, la contraseña): estadísticas de consultas, auditoría de cuentas o mensajes de depuración.
  if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then
    raise exception 'NO SE CAMBIÓ NADA: la cuenta canopy_backup no existe; primero el paso 2 (supabase/tools/backup-account.sql). Copie este mensaje en el chat.';
  end if;
  if current_setting('pg_stat_statements.track', true) = 'all'
     or coalesce(current_setting('pgaudit.log', true), 'none') ~* '(^|[ ,])(all|role)([ ,]|$)'
     or current_setting('log_min_messages') ~* '^debug' then
    raise exception 'NO SE CAMBIÓ NADA: esta base anotaría la contraseña (pg_stat_statements.track = %, pgaudit.log = %, log_min_messages = %). Copie este mensaje en el chat.',
      current_setting('pg_stat_statements.track', true), coalesce(current_setting('pgaudit.log', true), 'none'), current_setting('log_min_messages');
  end if;
  -- 1b. Tampoco si la base entrega cada contraseña nueva a una función de revisión (pg_tle "passcheck").
  if coalesce(current_setting('pgtle.enable_password_check', true), 'off') in ('on', 'true', 'yes', '1', 'require')
     and to_regclass('pgtle.feature_info') is not null then
    begin
      select count(*) into revisiones from pgtle.feature_info where feature::text = 'passcheck';
    exception when others then revisiones := 0;   -- no se puede mirar: el ajuste solo no hace nada
    end;
    if revisiones > 0 then
      raise exception 'NO SE CAMBIÓ NADA: esta base entrega cada contraseña nueva a % función(es) de revisión (pg_tle passcheck). Copie este mensaje en el chat.', revisiones;
    end if;
  end if;
  -- 2. Solo mientras dura este pegado: la contraseña se guarda cifrada con SCRAM (lo que exige el pooler), sin volcados
  --    de depuración y sin esperar por un bloqueo más de lo que tarda la base en anotarlo (deadlock_timeout; 0,9 s como
  --    máximo): un volcado o una espera anotada escribirían la orden interna, contraseña incluida, en el registro.
  perform set_config('password_encryption', 'scram-sha-256', true);
  perform set_config(s, 'off', true) from unnest(array['debug_print_parse', 'debug_print_rewritten', 'debug_print_plan']) as s;
  perform set_config('lock_timeout', least(900, greatest(1, (extract(epoch from current_setting('deadlock_timeout')::interval) * 1000)::int - 100))::text || 'ms', true);
  -- 3. La contraseña la genera la base: dos UUID al azar sin guiones = 64 caracteres (cifras 0-9 y letras a-f).
  clave := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  -- 4. Se la pone a la cuenta (solo cambia que puede entrar, y su contraseña). Si falla, el error se vuelve a lanzar SIN
  --    la orden interna: si no, PostgreSQL la escribiría, contraseña incluida, en la línea CONTEXT del registro.
  begin
    execute format('alter role canopy_backup with login password %L', clave);
  exception when others then
    raise exception 'NO SE CAMBIÓ NADA: no se pudo poner la contraseña a canopy_backup (% %). Copie este mensaje en el chat.',
      sqlstate, replace(sqlerrm, clave, '<contraseña>');
  end;
  -- 5. Solo para la fila de abajo: este valor vive dentro de este pegado y desaparece al terminar.
  perform set_config('canopy.clave', clave, true);
end $$;
select coalesce(nullif(current_setting('canopy.clave', true), ''),
                'REVISAR: la contraseña no llegó a esta fila; repita este punto completo, en una sola ejecución') as contrasena;
