-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0036 (pantallas para los clientes: la TV del menú y la de promociones)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0036 causa un problema y así lo decide el dueño. No bloquea ventas (la 0036 no tocó ninguna tabla
-- existente), pero mejor fuera del horario de atención.
--
-- Qué hace
--   * Quita las funciones de la 0036: pantalla_datos (lo que leen las TV nuevas), pantallas_estado, pantalla_guardar,
--     diapositiva_guardar, diapositiva_estado (la gestión de pantallas.html) y sus internas _screen_log, _slide_json,
--     _screen_json, _screen_text_problem, _screen_hhmm, _screen_actor y _screen_owner_any_device (la guardia de la regla de fotos
--     «screen photos owner write»).
--   * Quita la 0036 del registro de migraciones: la base vuelve a la versión 35.
-- También vuelve a crear la regla de Storage «menu photos owner write» de la 0033 (para todo el depósito) y quita
-- «screen photos owner write».
-- Qué NO hace: no borra las tablas screens, screen_slides ni screen_changes (quedan con lo que tengan, sin uso y cerradas:
--   ni los visitantes ni las cuentas de ingreso pueden leerlas ni escribirlas) y no borra ninguna fila. El registro de
--   cambios (screen_changes) sigue sin poder modificarse ni borrarse: su guardia (_screen_changes_immutable y sus dos
--   disparadores) se queda, como el historial de recetas en la reversión de la 0030. No toca el menú, la TV actual
--   (tv.html, board_settings, board_group_slides), la Caja, la Cocina, la Contabilidad ni el menú QR.
-- Después: las TV nuevas siguen encendidas con los ajustes de su dirección (?tv=…) y la Pantalla B muestra solo la
--   presentación de la marca, sin precios; pantallas.html no puede leer ni guardar nada hasta que se aplique otra vez la
--   0036. release-check.sql mostrará
--   36 en migrations_missing y las cinco funciones de las pantallas en functions_missing; es lo esperado. Aplicar otra vez
--   la 0036 devuelve todo con las TV y las diapositivas tal como quedaron.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 36) then
    raise exception 'La migración 0036 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 36) then
    raise exception 'Hay migraciones posteriores a la 0036: revierta primero esas. No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

-- what the TVs read, then the owner's management, then the internal helpers (each one only after whatever calls it)
drop function if exists public.pantalla_datos(text);
drop function if exists public.pantallas_estado();
drop function if exists public.pantalla_guardar(jsonb);
drop function if exists public.diapositiva_guardar(jsonb);
drop function if exists public.diapositiva_estado(uuid, text);
drop function if exists public._screen_log(text, text, text, text, jsonb, jsonb);
drop function if exists public._slide_json(public.screen_slides);
drop function if exists public._screen_json(public.screens);
drop function if exists public._screen_text_problem(text);
drop function if exists public._screen_actor();
drop function if exists public._screen_hhmm(text);
-- the Storage rules as before the 0036: one rule for the whole bucket (manager-mode.sql, 0033), none for pantallas/
drop policy if exists "screen photos owner write" on storage.objects;
drop function if exists public._screen_owner_any_device();
drop policy if exists "menu photos owner write" on storage.objects;
create policy "menu photos owner write" on storage.objects for all to authenticated using (bucket_id = 'menu-photos' and ((select public.is_owner()) or (select public._unlocked_any_device()))) with check (bucket_id = 'menu-photos' and ((select public.is_owner()) or (select public._unlocked_any_device())));

-- the three tables stay with every row; they were born closed (row security on, nothing granted to anon or authenticated)
-- and stay so; the backup account keeps reading them. The change log keeps its guard: rows are only ever added.
delete from canopy.migrations where version = 36;
notify pgrst, 'reload schema';
select 'listo: la 0036 se revirtió; las TV nuevas quedan solo con la presentación de la marca (las tablas y sus filas se conservan)' as resultado;
