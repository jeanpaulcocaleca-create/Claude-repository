-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0040 (Proveedores: lecturas, facturas, pagos y anticipos)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo por una falla de una función de la 0040, así lo decide el dueño, fuera del horario de atención, y solo
-- DESPUÉS de volver a publicar las páginas anteriores (v2026.11.04-1): la página Proveedores deja de funcionar sin la
-- 0040. Para quitar también la 0039, siga con supabase/tools/reversion-0039.sql.
--
-- Qué hace
--   * Quita las 20 funciones nuevas de la 0040 (11 que llaman las páginas, 9 internas): las lecturas de Proveedores, las
--     facturas, los pagos por SINPE o tarjeta, su aplicación a facturas, sus anulaciones y su bitácora para Contabilidad.
--   * Quita la 0040 del registro de migraciones (la base vuelve a la versión 39).
--   * Devuelve supplier_invoice_save a su texto de la 0025 (sin las correcciones con su entrega ni el orden de bloqueo
--     de la 0040).
-- Qué NO hace: no borra ningún dato ni cambia ninguna otra función de antes. Los pagos
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

-- 0) supplier_invoice_save vuelve exactamente al texto de la 0025 -----------------------------------------------------------
create or replace function public.supplier_invoice_save(p_invoice jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.supplier_invoices; v public.vendors; net numeric; iva numeric; num text; rids uuid[]; rec numeric; eid bigint; who text; d date;
        a acct.accounts; diff_acct text;
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into x from public.supplier_invoices where id = p_request_id;
  if x.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'id', x.id); end if;
  select * into v from public.vendors where id = nullif(p_invoice->>'vendor_id', '')::uuid;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  perform 1 from public.vendors where id = v.id for update;     -- one invoice or payment of a supplier at a time
  num := nullif(left(trim(coalesce(p_invoice->>'number', '')), 50), '');
  net := round(nullif(p_invoice->>'net_crc', '')::numeric, 2); iva := round(coalesce(nullif(p_invoice->>'iva_crc', '')::numeric, 0), 2);
  d := nullif(p_invoice->>'date', '')::date;
  if num is null or net is null or net < 0 or iva < 0 or d is null or net + iva = 0
     or nullif(p_invoice->>'due_date', '')::date < d then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if d > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'future_date'); end if;
  if exists (select 1 from public.supplier_invoices where vendor_id = v.id and lower(number) = lower(num) and voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_invoice'); end if;
  select coalesce(array_agg(r::uuid), '{}') into rids from jsonb_array_elements_text(coalesce(p_invoice->'receipt_ids', '[]'::jsonb)) r;
  -- the deliveries are this vendor's and not invoiced yet
  if exists (select 1 from unnest(rids) r left join public.purchase_receipts pr on pr.id = r
              where pr.id is null or pr.vendor_id is distinct from v.id or pr.invoice_id is not null) then
    return jsonb_build_object('ok', false, 'error', 'bad_receipts'); end if;
  select coalesce(sum(total_crc), 0) into rec from public.purchase_receipts where id = any(rids);
  -- with deliveries, a price difference is an inventory adjustment; without them, the invoice says what it was for
  if cardinality(rids) > 0 then diff_acct := acct.map('price_variance');
  else
    select * into a from acct.accounts where code = p_invoice->>'account';
    if a.code is null or not a.active or a.cash or a.type not in ('expense', 'asset') or not public._ap_target(a.code) then
      return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
    diff_acct := a.code;
  end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  -- the deliveries were owed at their cost already (the day's entry); the invoice adds its IVA and any price
  -- difference. An invoice equal to what was received, without IVA, has nothing more to post.
  if iva <> 0 or net <> rec then
    begin
      eid := acct.post(d, 'Factura ' || num || ' · ' || v.name, 'ap', 'supinv:' || p_request_id,
               jsonb_build_array(jsonb_build_object('account', acct.map('iva_in'), 'debit', iva),
                                 jsonb_build_object('account', diff_acct, 'debit', net - rec),
                                 jsonb_build_object('account', acct.map('ap'), 'credit', net - rec + iva, 'memo', v.name)),
               null, who);
    exception when others then
      if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
      raise;
    end;
  end if;
  insert into public.supplier_invoices (id, vendor_id, number, date, due_date, net_crc, iva_crc, receipt_ids, account, received_crc, entry_id, created_by)
    values (p_request_id, v.id, num, d, nullif(p_invoice->>'due_date', '')::date, net, iva, rids, case when cardinality(rids) = 0 then diff_acct end, rec, eid, who);
  update public.purchase_receipts set invoice_id = p_request_id where id = any(rids);
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid, 'difference', net - rec);
end $$;

-- 1) las funciones nuevas (primero las que llama la página, después las internas) ----------------------------------------
drop function if exists public.proveedores_bitacora(date, date);
drop function if exists public.proveedor_anticipos_aplicar(uuid);
drop function if exists public.proveedor_factura_anular(uuid, text);
drop function if exists public.proveedor_factura_registrar(uuid, uuid[], jsonb, uuid);
drop function if exists public.proveedor_ficha(uuid, text);
drop function if exists public.proveedor_historial(uuid, timestamptz, int, uuid);
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
