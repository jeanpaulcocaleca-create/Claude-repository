-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0040 (Proveedores: lecturas, facturas, pagos y anticipos)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo por una falla de una función de la 0040, así lo decide el dueño, fuera del horario de atención, y solo
-- DESPUÉS de volver a publicar las páginas anteriores (v2026.11.04-1): la página Proveedores deja de funcionar sin la
-- 0040. Para quitar también la 0039, siga con supabase/tools/reversion-0039.sql.
--
-- Qué hace
--   * Quita las 19 funciones nuevas de la 0040 (10 que llama la página, 9 internas): las lecturas de Proveedores, las
--     facturas, los pagos por SINPE o tarjeta, su aplicación a facturas y sus anulaciones.
--   * Quita la 0040 del registro de migraciones (la base vuelve a la versión 39).
-- Qué NO hace: no borra ningún dato ni cambia ninguna función de antes (la 0040 no reemplazó ninguna). Los pagos
--   registrados (supplier_advances), los pagos aplicados (supplier_payments con 'advance') y sus asientos, la cuenta 1160,
--   los mapeos supplier_advance y from_advance y la regla supplier_payments_paid_from_check con 'advance' quedan como
--   están: Contabilidad sigue viendo esos pagos y sus facturas, y el libro sigue cuadrado. Un pago que todavía no se
--   aplicó queda en la 1160 hasta que se vuelva a aplicar la 0040 (o el contador lo resuelva).
-- Se niega si la 0040 no está aplicada o si hay una migración posterior aplicada (revierta esa primero).
-- Después: release-check.sql dice migrations_missing = [40]; production-snapshot.sql, migrations_applied termina en 39
--   y functions_changed = [].
-- =====================================================================================================
do $$
begin
  if not exists (select 1 from canopy.migrations where version = 40) then
    raise exception 'La migración 0040 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 40) then
    raise exception 'Hay una migración posterior a la 0040 aplicada (%): revierta esa primero. No se cambió nada.',
      (select string_agg(version::text, ', ' order by version) from canopy.migrations where version > 40);
  end if;
end $$;
set local lock_timeout = '8s';

-- 1) las funciones nuevas (primero las que llama la página, después las internas) ----------------------------------------
drop function if exists public.proveedor_anticipos_aplicar(uuid);
drop function if exists public.proveedor_factura_anular(uuid, text);
drop function if exists public.proveedor_factura_registrar(uuid, uuid[], jsonb, uuid);
drop function if exists public.proveedor_ficha(uuid, text);
drop function if exists public.proveedor_historial(uuid, timestamptz, int);
drop function if exists public.proveedor_pago_anular(uuid, text, uuid, text);
drop function if exists public.proveedor_pago_registrar(jsonb, uuid, uuid, text);
drop function if exists public.proveedor_pedido(uuid, text);
drop function if exists public.proveedores_lista(text, boolean);
drop function if exists public.proveedores_por_recibir(text);
drop function if exists public._prov_aplicar(uuid);
drop function if exists public._prov_can();
drop function if exists public._prov_date(jsonb);
drop function if exists public._prov_dinero(uuid);
drop function if exists public._prov_mode(text);
drop function if exists public._prov_po_brief(uuid, boolean);
drop function if exists public._prov_reverse(bigint, text, text);
drop function if exists public._prov_vendor_money(uuid);
drop function if exists public._prov_void_payment(uuid, text, text);

-- 2) el registro de migraciones --------------------------------------------------------------------------------------------
delete from canopy.migrations where version = 40;
notify pgrst, 'reload schema';
