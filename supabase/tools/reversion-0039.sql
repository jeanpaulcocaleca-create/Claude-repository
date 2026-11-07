-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0039 (Proveedores: catálogo, pedidos, recepción, sesiones de turno)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo por una falla de una función de la 0039, así lo decide el dueño, fuera del horario de atención, DESPUÉS de
-- revertir la 0040 (supabase/tools/reversion-0040.sql) y de volver a publicar las páginas anteriores (v2026.11.04-1): la
-- página de Inventario publicada sigue pidiendo y recibiendo como antes.
--
-- Qué hace
--   * Quita los siete disparadores nuevos (stock_items_vendor_catalog, purchase_lines_protect_new,
--     purchase_orders_version, purchase_lines_po_version, purchase_receipts_po_version, time_entries_work_session_end,
--     staff_work_session_end) y las 54 funciones nuevas de la 0039 (17 que llama la página, 37 internas).
--   * Quita la 0039 del registro de migraciones (la base vuelve a la versión 38).
-- Qué NO hace: no borra ningún dato ni cambia ninguna función de antes (la 0039 no reemplazó ninguna). Las tablas
--   nuevas (vendor_items, purchase_drafts, purchase_receipt_lines, supplier_advances, vendor_pay_info, work_sessions,
--   staff_pin_changes) con
--   sus filas, las columnas nuevas de purchase_orders, purchase_lines, purchase_receipts y supplier_payments, sus reglas e
--   índices quedan como están, sin uso. Las sesiones de turno abiertas dejan de servir (nadie las lee).
-- Se niega si la 0039 no está aplicada o si hay una migración posterior aplicada (revierta esa primero).
-- Después: release-check.sql dice migrations_missing = [39, 40]; production-snapshot.sql, migrations_applied termina en
--   38 y functions_changed = [].
-- =====================================================================================================
do $$
begin
  if not exists (select 1 from canopy.migrations where version = 39) then
    raise exception 'La migración 0039 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 39) then
    raise exception 'Hay una migración posterior a la 0039 aplicada (%): revierta esa primero. No se cambió nada.',
      (select string_agg(version::text, ', ' order by version) from canopy.migrations where version > 39);
  end if;
end $$;
set local lock_timeout = '8s';

-- 1) los disparadores nuevos ---------------------------------------------------------------------------------------------
drop trigger if exists stock_items_vendor_catalog on public.stock_items;
drop trigger if exists purchase_lines_protect_new on public.purchase_lines;
drop trigger if exists purchase_orders_version on public.purchase_orders;
drop trigger if exists purchase_lines_po_version on public.purchase_lines;
drop trigger if exists purchase_receipts_po_version on public.purchase_receipts;
drop trigger if exists time_entries_work_session_end on public.time_entries;
drop trigger if exists staff_work_session_end on public.staff;

-- 2) las funciones nuevas (primero las que llama la página, después las internas) ----------------------------------------
drop function if exists public.proveedor_borrador_descartar(uuid, int);
drop function if exists public.proveedor_borrador_guardar(uuid, jsonb, text, int);
drop function if exists public.proveedor_guardar(jsonb, uuid, text);
drop function if exists public.proveedor_pedido_asignar(uuid, int, uuid);
drop function if exists public.proveedor_pedido_cancelar(uuid, int, text);
drop function if exists public.proveedor_pedido_cerrar(uuid, int, text);
drop function if exists public.proveedor_pedido_confirmar(uuid, int);
drop function if exists public.proveedor_pedido_crear(uuid, jsonb, text, uuid, int, date);
drop function if exists public.proveedor_pedido_editar(uuid, int, jsonb, text, date);
drop function if exists public.proveedor_producto_guardar(jsonb);
drop function if exists public.proveedor_recepcion_corregir(uuid, uuid, jsonb, text);
drop function if exists public.proveedor_recibir(uuid, uuid, int, jsonb, text, boolean, text, text, boolean, boolean);
drop function if exists public.proveedores_alertas();
drop function if exists public.turno_aqui(uuid, text, text, boolean);
drop function if exists public.turno_desde_caja(text, text);
drop function if exists public.turno_estado(text[]);
drop function if exists public.turno_terminar(text);
drop function if exists public._prov_actor();
drop function if exists public._prov_books();
drop function if exists public._prov_bool(jsonb);
drop function if exists public._prov_caught(text, text, text, text);
drop function if exists public._prov_close(public.purchase_orders, text);
drop function if exists public._prov_draft_json(public.purchase_drafts);
drop function if exists public._prov_draft_lines(uuid, jsonb, int);
drop function if exists public._prov_entry_end();
drop function if exists public._prov_fail(text, jsonb);
drop function if exists public._prov_id(jsonb);
drop function if exists public._prov_item_vendor();
drop function if exists public._prov_late_post();
drop function if exists public._prov_line_protect();
drop function if exists public._prov_lines(uuid);
drop function if exists public._prov_log(text, uuid, text, text, text, jsonb);
drop function if exists public._prov_manage();
drop function if exists public._prov_mint(uuid, text, uuid, timestamptz, text, text, timestamptz);
drop function if exists public._prov_fresh_until(public.work_sessions);
drop function if exists public._prov_fresh_window();
drop function if exists public._prov_new_line(public.purchase_orders, jsonb, int);
drop function if exists public._prov_num(jsonb);
drop function if exists public._prov_packs(jsonb, boolean, text);
drop function if exists public._prov_payout_open(uuid);
drop function if exists public._prov_po_bump();
drop function if exists public._prov_po_lock(uuid, int);
drop function if exists public._prov_po_state(uuid);
drop function if exists public._prov_po_version();
drop function if exists public._prov_pqe(numeric, numeric, numeric, numeric);
drop function if exists public._prov_price(jsonb);
drop function if exists public._prov_staff_end();
drop function if exists public._prov_station(text);
drop function if exists public._prov_turno(text);
drop function if exists public._prov_txt(jsonb, int);
drop function if exists public._prov_lock_items(uuid[]);
drop function if exists public._prov_excess_guard(uuid, numeric);
drop function if exists public._prov_excess(uuid);
drop function if exists public._prov_unapplied(uuid);
drop function if exists public._prov_uuid(text);
drop function if exists public._prov_vi_match(uuid, uuid, numeric);

-- 3) el registro de migraciones --------------------------------------------------------------------------------------------
delete from canopy.migrations where version = 39;
notify pgrst, 'reload schema';
