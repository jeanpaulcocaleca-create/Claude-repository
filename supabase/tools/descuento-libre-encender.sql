-- =====================================================================================================
-- Canopy OS · ENCENDER otra vez la ventana de descuento anterior (pos_free_discount = on) · SQL Editor de PRODUCCIÓN
-- Supabase → SQL Editor → New query → pegar TODO → Run. Una sola transacción: si algo falla, no cambia nada.
--
-- Qué hace: deja el ajuste pos_free_discount en «on» (su valor por omisión) y escribe la misma línea «setting_change»
--   que escribe Inicio (quién: «owner (SQL Editor)», antes → después). Con «on», approve_discount (la ventana libre de la
--   Caja anterior) aprueba como antes de la 0038, salvo un motivo que diga una de las cuatro categorías («Otro · Local»,
--   «Empleado»…), que contesta «Elija el motivo del descuento».
-- Cuándo: SOLO el dueño, para volver atrás (docs/ACTIVACION-DESCUENTOS.md §6): primero este archivo, luego volver a
--   publicar las páginas anteriores. También antes de supabase/tools/reversion-0038.sql.
-- Se niega si la 0038 no está aplicada. Si ya estaba en «on», no cambia nada ni escribe nada.
-- Resultado: una celda con el valor vigente («on»).
-- =====================================================================================================
do $$
declare before jsonb; after jsonb := '"on"';
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
