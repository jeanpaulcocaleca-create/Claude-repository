-- =====================================================================================================
-- Canopy OS · APAGAR la ventana de descuento anterior (pos_free_discount = off) · para el SQL Editor de PRODUCCIÓN
-- Supabase → SQL Editor → New query → pegar TODO → Run. Una sola transacción: si algo falla, no cambia nada.
--
-- Qué hace: deja el ajuste pos_free_discount en «off» y escribe la misma línea «setting_change» que escribe Inicio
--   (quién: «owner (SQL Editor)», antes → después). Con «off», approve_discount (la ventana libre de la Caja anterior:
--   porcentaje o monto con el PIN de un encargado) ya no aprueba: una página vieja muestra «Esto necesita una
--   actualización de la base de datos… recargue esta página» y, al recargar, la ventana nueva. La Caja sigue vendiendo.
--   Las aprobaciones viejas ya dadas (hasta 30 minutos) y las ventas guardadas sin internet con ellas se siguen
--   registrando como hoy.
-- Cuándo: SOLO el dueño, como último paso de la activación (docs/ACTIVACION-DESCUENTOS.md §4), cuando todas las cajas
--   ya muestran la ventana nueva. Mientras E-06 no esté resuelto (sin código del teléfono) este archivo es la única forma;
--   con el código, Inicio → ajustes del sistema hace lo mismo.
-- Vuelta atrás: supabase/tools/descuento-libre-encender.sql.
-- Se niega si la 0038 no está aplicada. Si ya estaba en «off», no cambia nada ni escribe nada.
-- Resultado: una celda con el valor vigente («off»).
-- =====================================================================================================
do $$
declare before jsonb; after jsonb := '"off"';
begin
  if not exists (select 1 from canopy.migrations where version = 38)
     or not exists (select 1 from canopy.setting_defs where key = 'pos_free_discount') then
    raise exception 'La migración 0038 no está aplicada: el ajuste pos_free_discount todavía no existe. No se cambió nada.';
  end if;
  before := public.setting('pos_free_discount');
  if before = after then return; end if;
  insert into public.settings (key, value, updated_at, updated_by) values ('pos_free_discount', after, now(), 'owner (SQL Editor)')
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('setting_change', null, 'owner (SQL Editor)', 'pos_free_discount',
            'pos_free_discount: ' || (before #>> '{}') || ' → ' || (after #>> '{}'),
            jsonb_build_object('before', before, 'after', after, 'how', 'sql_editor'));
end $$;
select public.setting('pos_free_discount') as pos_free_discount;
