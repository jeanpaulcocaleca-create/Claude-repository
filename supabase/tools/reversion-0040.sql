-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0040 (Proveedores: lecturas, facturas, pagos y anticipos)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo por una falla de una función de la 0040, así lo decide el dueño, fuera del horario de atención, y solo
-- DESPUÉS de volver a publicar las páginas anteriores (v2026.11.04-1): la página Proveedores deja de funcionar sin la
-- 0040. Para quitar también la 0039, siga con supabase/tools/reversion-0039.sql.
--
-- Qué hace
--   * Quita las 23 funciones nuevas de la 0040 (11 que llaman las páginas, 12 internas): las lecturas de Proveedores, las
--     facturas, los pagos por SINPE o tarjeta, su aplicación a facturas, sus anulaciones y su bitácora para Contabilidad.
--   * Quita la 0040 del registro de migraciones (la base vuelve a la versión 39).
--   * Devuelve supplier_payment_save a su texto de la 0029 y expense_pay al de la 0035 (sin aplicar primero los pagos de
--     Proveedores ni negar un número SINPE ya registrado allí), y quita los dos disparadores de última defensa
--     (supplier_payment_allocations_within_invoice, supplier_payments_within_advance).
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

-- 0b) supplier_payment_save vuelve exactamente al texto de la 0029 -----------------------------------------------------------
create or replace function public.supplier_payment_save(p_payment jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare v public.vendors; amt numeric; left_amt numeric; src text; d date; inv record; part numeric; eid bigint; who text; owed numeric; po uuid;
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if exists (select 1 from public.supplier_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  select * into v from public.vendors where id = nullif(p_payment->>'vendor_id', '')::uuid;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  perform 1 from public.vendors where id = v.id for update;     -- one invoice or payment of a supplier at a time
  if exists (select 1 from public.supplier_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  amt := round(nullif(p_payment->>'amount_crc', '')::numeric, 2); src := p_payment->>'paid_from'; d := nullif(p_payment->>'date', '')::date;
  po := nullif(p_payment->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if p_request_id is null or amt is null or amt <= 0 or src not in ('cash', 'petty', 'bank', 'payout', 'card_debit', 'card_credit') or d is null or d > public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select coalesce(sum(public._invoice_open(id)), 0) into owed from public.supplier_invoices where vendor_id = v.id and voided_at is null;
  if amt > owed then return jsonb_build_object('ok', false, 'error', 'more_than_owed', 'owed', owed); end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  begin
    eid := acct.post(d, 'Pago a ' || v.name || coalesce(' · ' || nullif(trim(p_payment->>'reference'), ''), ''), 'ap', 'suppay:' || p_request_id,
             jsonb_build_array(jsonb_build_object('account', acct.map('ap'), 'debit', amt, 'memo', v.name),
                               jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty' when 'payout' then 'from_payout'
                                                                               when 'card_debit' then 'from_card_debit' when 'card_credit' then 'from_card_credit'
                                                                               else 'from_bank' end), 'credit', amt)),
             null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, reference, entry_id, created_by, payout_id)
    values (p_request_id, v.id, d, amt, src, nullif(left(trim(coalesce(p_payment->>'reference', '')), 80), ''), eid, who, case when src = 'payout' then po end);
  left_amt := amt;
  for inv in select id from public.supplier_invoices
              where vendor_id = v.id and voided_at is null and public._invoice_open(id) > 0
              order by (id::text = any(array(select jsonb_array_elements_text(coalesce(p_payment->'invoice_ids', '[]'::jsonb))))) desc, coalesce(due_date, date), date, id loop
    exit when left_amt <= 0;
    part := least(left_amt, public._invoice_open(inv.id));
    insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values (p_request_id, inv.id, part);
    left_amt := left_amt - part;
  end loop;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

-- 0c) expense_pay vuelve exactamente al texto de la 0035 ---------------------------------------------------------------------
create or replace function public.expense_pay(p_payment jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; amt numeric; open_amt numeric; src text; d date; eid bigint; who text; po uuid; ref text;
begin
  if not public._expense_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if exists (select 1 from public.expense_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  select * into x from public.expenses where id = nullif(p_payment->>'expense_id', '')::uuid for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if x.paid_from <> 'credit' then return jsonb_build_object('ok', false, 'error', 'not_credit'); end if;
  open_amt := public._expense_open(x.id);
  amt := round(coalesce(nullif(p_payment->>'amount_crc', '')::numeric, open_amt), 2);
  src := p_payment->>'paid_from'; d := nullif(p_payment->>'date', '')::date; po := nullif(p_payment->>'payout_id', '')::uuid;
  ref := nullif(left(trim(coalesce(p_payment->>'reference', '')), 80), '');
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if amt is null or amt = 'NaN' or amt <= 0 or src is null or src not in ('cash', 'petty', 'bank', 'payout', 'card_debit', 'card_credit') or d is null then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if d > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'future_date'); end if;
  if d < x.date then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;   -- no payment dated before its expense
  if amt > open_amt then return jsonb_build_object('ok', false, 'error', 'more_than_owed', 'owed', open_amt); end if;
  who := acct.actor();
  begin
    eid := acct.post(d, 'Pago de gasto a crédito: ' || x.description || coalesce(' · ' || x.vendor_name, '') || coalesce(' · ' || ref, ''), 'expense', 'exppay:' || p_request_id,
             jsonb_build_array(jsonb_build_object('account', acct.map('ap'), 'debit', amt, 'memo', coalesce(x.vendor_name, x.description)),
                               jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty' when 'payout' then 'from_payout'
                                                                               when 'card_debit' then 'from_card_debit' when 'card_credit' then 'from_card_credit'
                                                                               else 'from_bank' end), 'credit', amt)),
             null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    if sqlerrm ~ 'unknown_account' then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
    raise;
  end;
  insert into public.expense_payments (id, expense_id, date, amount_crc, paid_from, reference, payout_id, entry_id, created_by)
    values (p_request_id, x.id, d, amt, src, ref, case when src = 'payout' then po end, eid, who);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('expense_payment', null, who, x.id::text, 'pago de ' || amt || ' del gasto ' || x.description || coalesce(' · ' || x.vendor_name, ''),
            jsonb_build_object('payment_id', p_request_id, 'paid_from', src, 'date', d, 'open_after', open_amt - amt));
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid, 'open_crc', open_amt - amt);
end $$;

-- 0d) los dos disparadores de última defensa ------------------------------------------------------------------------------
drop trigger if exists supplier_payment_allocations_within_invoice on public.supplier_payment_allocations;
drop trigger if exists supplier_payments_within_advance on public.supplier_payments;

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
drop function if exists public._prov_sinpe_taken(text, boolean);
drop function if exists public._prov_alloc_guard();
drop function if exists public._prov_apply_guard();

-- 2) el registro de migraciones --------------------------------------------------------------------------------------------
delete from canopy.migrations where version = 40;
notify pgrst, 'reload schema';
