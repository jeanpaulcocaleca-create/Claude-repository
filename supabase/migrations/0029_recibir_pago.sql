-- =====================================================================================================
-- Canopy OS · migración 0029 · Recibir pedido con factura y pago en un solo paso (Inventario → Pedidos → Recibir)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0028.
--
-- Qué hace (propuesta aprobada por el dueño el 2026-10-15, docs/RECIBIR-PEDIDO.md)
--   * po_receive_and_settle: la entrega (lo que ya hace po_receive_delivery), la factura del proveedor y los pagos
--     en UNA transacción. Si algo falla, nada queda a medias; repetir el envío devuelve lo ya guardado. Reúne las
--     funciones que ya existen (po_receive_delivery, supplier_invoice_save, register_cash_move, supplier_payment_save):
--     ningún asiento nuevo, ninguna cuenta se mueve distinto de hoy.
--   * La factura puede quedar «pendiente» (todavía no llegó), «en revisión» (se capturó pero nadie la confirmó) o
--     «confirmada». Solo la confirmada registra IVA, cuentas por pagar y pagos; la mercadería entra a existencias
--     igual en los tres casos. Lo pendiente se ve en po_pending.
--   * Pagos: parciales o combinados, cada uno con su método: efectivo de la caja registradora (crea el retiro de caja
--     con el PIN del encargado y lo documenta en el acto, así el cierre cuadra y no se descuenta dos veces), efectivo
--     de la caja fuerte, SINPE o transferencia (banco), tarjeta de débito (banco) y tarjeta de crédito (cuenta nueva
--     2160 «Tarjeta de crédito por pagar»; el contador puede apuntar el mapeo a otra cuenta). Todo pago exige el PIN
--     de un encargado. El saldo queda en cuentas por pagar con su vencimiento.
--   * Facturas en colones o en dólares: la de dólares guarda su tipo de cambio y sus montos en dólares; las cuentas
--     por pagar y los libros siguen en colones (al tipo de cambio de la factura; el diferencial cambiario espera A-06).
--   * po_receipt_settle (factura y pagos de una entrega ya guardada), po_receipt_pay (más pagos después),
--     po_history (todo lo de un pedido) y po_pending (facturas pendientes y lo que se debe) para la página.
-- Qué cambia para el personal: en «Recibir» aparece la sección «Factura y pago»; los cinco botones del pedido siguen
--   iguales. Nada cambia en la caja ni en Contabilidad (solo acepta los dos métodos de tarjeta nuevos).
-- Reversión: drop function po_receive_and_settle, po_receipt_settle, po_receipt_pay, po_history, po_pending,
--   _settle_fail, _settle_uuid; volver a crear supplier_payment_save como en la 0025 (las columnas y la cuenta 2160
--   quedan; las filas de purchase_receipts conservan su estado).
-- =====================================================================================================
select canopy.migration_begin(29, 'recibir_pago');

-- 1) cuentas y mapeos para los dos métodos de tarjeta ---------------------------------------------------------------
-- la cuenta de la tarjeta de crédito del negocio: un código libre (2120 ya es «Anticipos de clientes» desde la 0013)
do $$ begin
  if exists (select 1 from acct.accounts where code = '2160' and name <> 'Tarjeta de crédito por pagar') then
    raise exception 'La cuenta 2160 ya existe con otro nombre: revisar el plan de cuentas antes de aplicar la 0029.'; end if;
end $$;
insert into acct.accounts (code, name, type, cash, system) values ('2160', 'Tarjeta de crédito por pagar', 'liability', false, true)
on conflict (code) do nothing;
insert into acct.mappings (key, account, label) values
  ('from_card_debit', '1110', 'Pago a proveedor con tarjeta de débito (sale de la cuenta del banco)'),
  ('from_card_credit', '2160', 'Pago a proveedor con tarjeta de crédito (queda por pagar al banco)')
on conflict (key) do nothing;

alter table public.supplier_payments drop constraint if exists supplier_payments_paid_from_check;
alter table public.supplier_payments add constraint supplier_payments_paid_from_check
  check (paid_from in ('cash', 'petty', 'bank', 'payout', 'card_debit', 'card_credit'));

-- 2) la factura en dólares guarda su moneda, su tipo de cambio y sus montos en dólares; net_crc/iva_crc siguen en colones
alter table public.supplier_invoices add column if not exists currency text not null default 'CRC' check (currency in ('CRC', 'USD'));
alter table public.supplier_invoices add column if not exists fx_rate numeric(10,2);
alter table public.supplier_invoices add column if not exists net_fx numeric(14,2);
alter table public.supplier_invoices add column if not exists iva_fx numeric(14,2);

-- 3) el estado de la factura de cada entrega ----------------------------------------------------------------------
alter table public.purchase_receipts add column if not exists invoice_status text not null default 'pending'
  check (invoice_status in ('pending', 'review', 'confirmed'));
alter table public.purchase_receipts add column if not exists invoice_draft jsonb;           -- lo capturado antes de confirmar
alter table public.purchase_receipts add column if not exists payout_id uuid references public.cash_movements(id);  -- dinero de la caja antes de la factura
alter table public.purchase_receipts add column if not exists settled_at timestamptz;
alter table public.purchase_receipts add column if not exists settled_by text;
-- las entregas ya facturadas desde Contabilidad quedan como confirmadas (no cambia ningún monto)
update public.purchase_receipts set invoice_status = 'confirmed' where invoice_id is not null and invoice_status = 'pending';
-- el estado sigue a la factura por cualquier camino: la guarda Contabilidad (confirmada) o la anula (vuelve a «por revisar»)
create or replace function public._receipt_invoice_status() returns trigger language plpgsql set search_path = public as $$
begin
  if new.invoice_id is not null and new.invoice_status <> 'confirmed' then
    new.invoice_status := 'confirmed'; new.settled_at := coalesce(new.settled_at, now()); new.settled_by := coalesce(new.settled_by, public._inv_actor());
  elsif new.invoice_id is null and old.invoice_id is not null and new.invoice_status = 'confirmed' then
    new.invoice_status := 'review';
  end if;
  return new;
end $$;
drop trigger if exists purchase_receipts_invoice_status on public.purchase_receipts;
create trigger purchase_receipts_invoice_status before update of invoice_id on public.purchase_receipts
  for each row execute function public._receipt_invoice_status();

-- los archivos de cada entrega (foto, PDF o XML de la factura): la tabla aquí; el depósito y sus reglas en la 0030
create table if not exists public.purchase_receipt_files (
  id         uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.purchase_receipts(id),
  path       text not null unique,                    -- <id de la entrega>/<archivo> en el depósito purchase-invoices
  kind       text not null check (kind in ('image', 'pdf', 'xml', 'other')),
  by_name    text,
  created_at timestamptz not null default now()
);
alter table public.purchase_receipt_files enable row level security;
revoke all on public.purchase_receipt_files from anon, authenticated;

-- 4) supplier_payment_save acepta tarjeta de débito y de crédito (lo demás igual que en la 0025) -----------------------
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

-- 5) ayudas internas: deshacer todo cuando una función de hoy contesta {ok:false}, e ids derivados del id de la entrega
create or replace function public._settle_fail(p_step text, p_result jsonb)
returns void language plpgsql as $$
begin
  if coalesce((p_result->>'ok')::boolean, false) then return; end if;
  raise exception 'settle:%:%', p_step, coalesce(p_result->>'error', 'error') using errcode = 'P0001';
end $$;
revoke all on function public._settle_fail(text, jsonb) from public, anon, authenticated;

create or replace function public._settle_uuid(p_base uuid, p_tag text, p_i int)
returns uuid language sql immutable as $$
  select md5(p_base::text || ':' || p_tag || ':' || p_i)::uuid;
$$;
revoke all on function public._settle_uuid(uuid, text, int) from public, anon, authenticated;

-- el error que una función envoltura devuelve a la página: {ok:false, error, step}
create or replace function public._settle_error(p_sqlerrm text)
returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'error', split_part(p_sqlerrm, ':', 3), 'step', split_part(p_sqlerrm, ':', 2));
$$;
revoke all on function public._settle_error(text) from public, anon, authenticated;

-- 6) la factura y los pagos de una entrega ya guardada -------------------------------------------------------------
-- p_invoice: {mode: 'pending'|'review'|'confirm', vendor_id (solo si el pedido no tiene proveedor), number, date, due_date,
--             currency 'CRC'|'USD', fx_rate (dólares), net, iva (en la moneda de la factura), source, notes, receipt_ids,
--             station}
-- p_payments: [{method: 'register'|'cash'|'bank'|'card_debit'|'card_credit', amount_crc, reference}]
--   'register' = efectivo de la caja registradora: retiro de caja (PIN de encargado, caja abierta) documentado en el acto.
--   Con la factura pendiente o en revisión solo se admite un retiro de caja (el dinero ya salió); se documenta al confirmar.
create or replace function public.po_receipt_settle(p_receipt_id uuid, p_invoice jsonb, p_payments jsonb default '[]'::jsonb,
                                                    p_manager_id uuid default null, p_pin text default null)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.purchase_receipts; po public.purchase_orders; v public.vendors; mode text; vid uuid; pays jsonb; p jsonb; n_pay int := 0;
        total_pay numeric := 0; amt numeric; method text; ref text; pin record; actor text; draft jsonb; cur text; rate numeric; d date; due date;
        num text; net numeric; iva numeric; v_net_crc numeric; v_iva_crc numeric; v_total_crc numeric; rids uuid[]; res jsonb; paid numeric := 0;
        pamt numeric; i int := 0; mv jsonb; reason text; station text; src text; pin_sid uuid; pmv public.cash_movements; inv_id uuid; k int := 0; adj numeric := 0;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_receipt_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  p_invoice := coalesce(p_invoice, '{}'::jsonb);
  -- the manager's PIN is checked before the transaction block: a wrong try stays counted (inside it, the rollback would undo the count)
  if jsonb_typeof(coalesce(p_payments, '[]'::jsonb)) = 'array' and jsonb_array_length(coalesce(p_payments, '[]'::jsonb)) > 0 then
    select * into pin from public._verify_pin(p_manager_id, p_pin, true);
    if pin.err is not null then return jsonb_build_object('ok', false, 'error', pin.err, 'step', 'pin'); end if;
    pin_sid := pin.sid;
  end if;
  begin
    select * into r from public.purchase_receipts where id = p_receipt_id for update;
    if r.id is null then raise exception 'settle:receipt:not_found'; end if;
    select * into po from public.purchase_orders where id = r.po_id for update;
    mode := coalesce(p_invoice->>'mode', 'pending');
    if mode not in ('pending', 'review', 'confirm') then raise exception 'settle:invoice:bad_request'; end if;
    pays := coalesce(p_payments, '[]'::jsonb);
    if jsonb_typeof(pays) <> 'array' then raise exception 'settle:payment:bad_request'; end if;
    actor := public._inv_actor();
    station := nullif(left(coalesce(p_invoice->>'station', ''), 40), '');
    -- the supplier: the order's, or the one chosen now for an order made without one
    vid := coalesce(r.vendor_id, po.vendor_id, nullif(p_invoice->>'vendor_id', '')::uuid);
    if vid is null and (mode <> 'pending' or jsonb_array_length(pays) > 0) then raise exception 'settle:invoice:no_vendor'; end if;
    if vid is not null then
      select * into v from public.vendors where id = vid;
      if v.id is null then raise exception 'settle:invoice:no_vendor'; end if;
      if po.vendor_id is null then update public.purchase_orders set vendor_id = vid where id = po.id; end if;
      if r.vendor_id is null then
        -- the number typed at the delivery must not repeat one of this supplier's (the index would refuse it with a raw error)
        if r.invoice_no is not null and exists (select 1 from public.purchase_receipts x where x.vendor_id = vid and lower(x.invoice_no) = lower(r.invoice_no) and x.id <> r.id) then
          raise exception 'settle:invoice:duplicate_invoice'; end if;
        update public.purchase_receipts set vendor_id = vid where id = r.id; r.vendor_id := vid;
      end if;
    end if;
    -- already confirmed: the same confirmation again changes nothing (more payments go through po_receipt_pay)
    if r.invoice_status = 'confirmed' then
      if mode = 'confirm' then
        return jsonb_build_object('ok', true, 'repeat', true, 'invoice_status', 'confirmed', 'invoice_id', r.invoice_id,
                                  'total_crc', (select total_crc from public.supplier_invoices where id = r.invoice_id),
                                  'open_crc', public._invoice_open(r.invoice_id));
      end if;
      raise exception 'settle:invoice:already_confirmed';
    end if;
    -- the payments: valid, and the manager's PIN for any money
    for p in select * from jsonb_array_elements(pays) loop
      method := p->>'method'; amt := round(nullif(p->>'amount_crc', '')::numeric, 2);
      if method not in ('register', 'cash', 'bank', 'card_debit', 'card_credit') or amt is null or amt <= 0 or amt > 100000000 then
        raise exception 'settle:payment:bad_value'; end if;
      n_pay := n_pay + 1; total_pay := total_pay + amt;
    end loop;
    if mode <> 'confirm' then
      -- before the invoice is confirmed only the money that really left the drawer is recorded, once
      if n_pay > 1 or (n_pay = 1 and pays->0->>'method' <> 'register') then raise exception 'settle:payment:needs_invoice'; end if;
      if n_pay = 1 and r.payout_id is not null then
        select * into pmv from public.cash_movements where id = r.payout_id and voided_at is null;
        if pmv.id is not null then
          -- the same request again (a lost answer) adds nothing; a second withdrawal waits for the invoice
          if pmv.amount_crc = round((pays->0->>'amount_crc')::numeric, 2) and r.invoice_status = mode then
            return jsonb_build_object('ok', true, 'repeat', true, 'invoice_status', mode, 'receipt_id', r.id, 'payout_id', pmv.id);
          end if;
          raise exception 'settle:payment:payout_exists';
        end if;
      end if;
    end if;
    -- what was captured about the invoice (kept as the draft, confirmed or not)
    cur := coalesce(nullif(p_invoice->>'currency', ''), 'CRC');
    if cur not in ('CRC', 'USD') then raise exception 'settle:invoice:bad_currency'; end if;
    draft := jsonb_strip_nulls(jsonb_build_object(
      'number', nullif(left(trim(coalesce(p_invoice->>'number', '')), 50), ''), 'date', nullif(p_invoice->>'date', ''), 'due_date', nullif(p_invoice->>'due_date', ''),
      'currency', cur, 'fx_rate', nullif(p_invoice->>'fx_rate', ''), 'net', nullif(p_invoice->>'net', ''), 'iva', nullif(p_invoice->>'iva', ''),
      'source', nullif(left(coalesce(p_invoice->>'source', ''), 20), ''), 'notes', nullif(left(trim(coalesce(p_invoice->>'notes', '')), 200), ''),
      'captured_at', now(), 'captured_by', actor));
    if mode <> 'confirm' then
      -- pending or review: the goods are in, the invoice waits; a payout from the drawer may be recorded now
      if n_pay = 1 then
        amt := round((pays->0->>'amount_crc')::numeric, 2);
        reason := 'Pedido Nº ' || coalesce(po.po_number::text, '?') || ' · ' || v.name || ' · factura pendiente';
        mv := public.register_cash_move(p_manager_id, p_pin, jsonb_build_object('direction', 'out', 'purpose', 'payout', 'currency', 'CRC', 'amount', amt,
                                                                               'reason', reason, 'station', station), public._settle_uuid(coalesce(r.payout_id, r.id), 'payout', 0));   -- a voided withdrawal gives way to a new one
        perform public._settle_fail('register', mv);
        update public.purchase_receipts set payout_id = (mv->>'id')::uuid where id = r.id;
      end if;
      update public.purchase_receipts set invoice_status = mode, invoice_draft = case when mode = 'pending' and jsonb_strip_nulls(p_invoice - 'mode' - 'station' - 'currency' - 'due_date') = '{}'::jsonb then invoice_draft else draft end
        where id = r.id;
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('po_settle', pin_sid, actor, r.id::text,
                'pedido ' || coalesce(po.po_number::text, '') || ': factura ' || case mode when 'pending' then 'pendiente' else 'en revisión' end
                  || case when n_pay = 1 then ' · retiro de caja ' || amt else '' end,
                jsonb_build_object('receipt_id', r.id, 'invoice_status', mode, 'payout_crc', case when n_pay = 1 then amt end, 'draft', draft));
      return jsonb_build_object('ok', true, 'invoice_status', mode, 'receipt_id', r.id,
                                'payout_id', (select payout_id from public.purchase_receipts where id = r.id));
    end if;
    -- confirm: the supplier invoice, linked to this delivery (and to the other deliveries named), then the payments
    d := nullif(p_invoice->>'date', '')::date; due := nullif(p_invoice->>'due_date', '')::date;
    net := round(coalesce(nullif(p_invoice->>'net', '')::numeric, 0), 2); iva := round(coalesce(nullif(p_invoice->>'iva', '')::numeric, 0), 2);
    if d is null then raise exception 'settle:invoice:bad_value'; end if;
    if net < 0 or iva < 0 or net + iva = 0 then raise exception 'settle:invoice:bad_value'; end if;
    if cur = 'USD' then
      rate := round(nullif(p_invoice->>'fx_rate', '')::numeric, 2);
      if rate is null or rate < 100 or rate > 2000 then raise exception 'settle:invoice:bad_rate'; end if;
      v_net_crc := round(net * rate, 2); v_iva_crc := round(iva * rate, 2);
    else
      rate := null; v_net_crc := net; v_iva_crc := iva;
    end if;
    v_total_crc := v_net_crc + v_iva_crc;
    if total_pay - v_total_crc >= 1 then raise exception 'settle:payment:over_invoice'; end if;   -- under one colón over: paid in full (cash has no cents)
    num := coalesce(draft->>'number', 'S/N-' || to_char(d, 'YYYYMMDD') || '-' || left(r.id::text, 8));
    -- the invoice's id is the delivery's, unless an earlier (voided) invoice of this delivery already holds it
    inv_id := r.id;
    while exists (select 1 from public.supplier_invoices where id = inv_id) loop k := k + 1; inv_id := public._settle_uuid(r.id, 'invoice', k); end loop;
    -- the deliveries this invoice covers: this one and any other of the same supplier named by the page
    select coalesce(array_agg(distinct x), '{}') into rids
      from (select r.id as x union all select nullif(e, '')::uuid from jsonb_array_elements_text(coalesce(p_invoice->'receipt_ids', '[]'::jsonb)) e) q where x is not null;
    if exists (select 1 from unnest(rids) x left join public.purchase_receipts pr on pr.id = x
                where pr.id is null or pr.vendor_id is distinct from vid or pr.invoice_id is not null
                   -- another delivery's live, undocumented withdrawal is settled from that delivery, not here
                   or (pr.id <> r.id and pr.payout_id is not null and exists (select 1 from public.cash_movements m where m.id = pr.payout_id and m.voided_at is null
                        and not exists (select 1 from public.supplier_payments sp where sp.payout_id = m.id and sp.voided_at is null)
                        and not exists (select 1 from public.expenses e where e.payout_id = m.id and e.voided_at is null)))) then
      raise exception 'settle:invoice:bad_receipts'; end if;
    -- one invoice number for the delivery and for the supplier invoice
    if exists (select 1 from public.purchase_receipts x where x.vendor_id = vid and lower(x.invoice_no) = lower(num) and x.id <> all(rids)) then
      raise exception 'settle:invoice:duplicate_invoice'; end if;
    update public.purchase_receipts set invoice_no = num, invoice_date = d where id = r.id;   -- the other deliveries keep their own number; the link is invoice_id
    res := public.supplier_invoice_save(jsonb_build_object('vendor_id', vid, 'number', num, 'date', d, 'due_date', due, 'net_crc', v_net_crc, 'iva_crc', v_iva_crc,
                                                           'receipt_ids', to_jsonb(rids)), inv_id);
    perform public._settle_fail('invoice', res);
    if cur = 'USD' then update public.supplier_invoices set currency = 'USD', fx_rate = rate, net_fx = net, iva_fx = iva where id = inv_id; end if;
    -- money that left the drawer before the invoice: documented now
    if r.payout_id is not null then
      -- unless it was voided, or the accountant already documented it (as an expense or as a payment)
      select m.amount_crc into pamt from public.cash_movements m where m.id = r.payout_id and m.voided_at is null
         and not exists (select 1 from public.expenses e where e.payout_id = m.id and e.voided_at is null)
         and not exists (select 1 from public.supplier_payments sp where sp.payout_id = m.id and sp.voided_at is null);
      if pamt is not null then
        if pamt + total_pay - v_total_crc >= 1 then raise exception 'settle:payment:payout_exceeds'; end if;
        res := public.supplier_payment_save(jsonb_build_object('vendor_id', vid, 'date', public.cr_today(), 'amount_crc', pamt, 'paid_from', 'payout',
                 'payout_id', r.payout_id, 'invoice_ids', jsonb_build_array(inv_id), 'reference', 'Pedido Nº ' || coalesce(po.po_number::text, '?') || ' · retiro de caja'),
                 public._settle_uuid(inv_id, 'payout-doc', 0));
        perform public._settle_fail('payment', res);
        paid := paid + pamt;
      end if;
    end if;
    -- the payments of this confirmation; the last one is trimmed by the cents the invoice does not have
    adj := greatest(0, paid + total_pay - v_total_crc);
    for p in select * from jsonb_array_elements(pays) loop
      method := p->>'method'; amt := round((p->>'amount_crc')::numeric, 2); ref := nullif(left(trim(coalesce(p->>'reference', '')), 80), '');
      if i = n_pay - 1 and adj > 0 then amt := amt - adj; if amt <= 0 then raise exception 'settle:payment:over_invoice'; end if; end if;
      if method = 'register' then
        reason := 'Pedido Nº ' || coalesce(po.po_number::text, '?') || ' · ' || v.name || ' · factura ' || num;
        mv := public.register_cash_move(p_manager_id, p_pin, jsonb_build_object('direction', 'out', 'purpose', 'payout', 'currency', 'CRC', 'amount', amt,
                                                                               'reason', reason, 'station', station), public._settle_uuid(inv_id, 'payout', i + 1));
        perform public._settle_fail('register', mv);
        res := public.supplier_payment_save(jsonb_build_object('vendor_id', vid, 'date', public.cr_today(), 'amount_crc', amt, 'paid_from', 'payout',
                 'payout_id', mv->>'id', 'invoice_ids', jsonb_build_array(inv_id), 'reference', coalesce(ref, 'Retiro de caja')), public._settle_uuid(inv_id, 'pay', i));
      else
        src := method;   -- cash (caja fuerte), bank (SINPE o transferencia), card_debit, card_credit
        res := public.supplier_payment_save(jsonb_build_object('vendor_id', vid, 'date', public.cr_today(), 'amount_crc', amt, 'paid_from', src,
                 'invoice_ids', jsonb_build_array(inv_id), 'reference', ref), public._settle_uuid(inv_id, 'pay', i));
      end if;
      perform public._settle_fail('payment', res);
      paid := paid + amt; i := i + 1;
    end loop;
    update public.purchase_receipts set invoice_status = 'confirmed', invoice_draft = draft, settled_at = now(), settled_by = actor where id = any(rids);
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('po_settle', pin_sid, actor, r.id::text,
              'pedido ' || coalesce(po.po_number::text, '') || ': factura ' || num || ' · ' || cur || ' ' || v_total_crc || ' · pagado ' || paid || ' · saldo ' || (v_total_crc - paid),
              jsonb_build_object('receipt_ids', to_jsonb(rids), 'invoice_id', inv_id, 'currency', cur, 'fx_rate', rate, 'total_crc', v_total_crc, 'paid_crc', paid,
                                 'payments', n_pay, 'manager_id', pin_sid));
    return jsonb_build_object('ok', true, 'invoice_status', 'confirmed', 'receipt_id', r.id, 'invoice_id', inv_id, 'number', num, 'currency', cur,
                              'total_crc', v_total_crc, 'paid_crc', round(paid, 2), 'open_crc', round(v_total_crc - paid, 2));
  exception when others then
    if sqlerrm like 'settle:%' then return public._settle_error(sqlerrm); end if;
    raise;
  end;
end $$;
revoke all on function public.po_receipt_settle(uuid, jsonb, jsonb, uuid, text) from public, anon;
grant execute on function public.po_receipt_settle(uuid, jsonb, jsonb, uuid, text) to authenticated;

-- 7) la entrega, la factura y los pagos en una sola llamada ---------------------------------------------------------
-- El número y la fecha de la factura escritos al recibir quedan en la entrega como hoy (y la misma factura del mismo
-- proveedor se rechaza ahí); al confirmar se pueden corregir.
create or replace function public.po_receive_and_settle(p_po_id uuid, p_lines jsonb, p_receipt_id uuid, p_final boolean default false,
                                                        p_invoice jsonb default '{}'::jsonb, p_payments jsonb default '[]'::jsonb,
                                                        p_manager_id uuid default null, p_pin text default null)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r1 jsonb; r2 jsonb; mode text; existed boolean; pin record;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_receipt_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  p_invoice := coalesce(p_invoice, '{}'::jsonb);
  mode := coalesce(p_invoice->>'mode', 'pending');
  -- the manager's PIN is checked before the transaction block (a wrong try stays counted; inside it, the rollback would undo the count)
  if jsonb_typeof(coalesce(p_payments, '[]'::jsonb)) = 'array' and jsonb_array_length(coalesce(p_payments, '[]'::jsonb)) > 0 then
    select * into pin from public._verify_pin(p_manager_id, p_pin, true);
    if pin.err is not null then return jsonb_build_object('ok', false, 'error', pin.err, 'step', 'pin'); end if;
  end if;
  existed := exists (select 1 from public.purchase_receipts where id = p_receipt_id);
  -- a delivery with nothing in it is a mistake, unless it closes the order
  if not existed and not coalesce(p_final, false)
     and not exists (select 1 from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l where coalesce((l->>'qty')::numeric, 0) > 0) then
    return jsonb_build_object('ok', false, 'error', 'empty', 'step', 'receive'); end if;
  begin
    r1 := public.po_receive_delivery(p_po_id, p_lines, p_receipt_id, nullif(left(trim(coalesce(p_invoice->>'number', '')), 40), ''),
            nullif(p_invoice->>'date', '')::date, coalesce(p_final, false));
    perform public._settle_fail('receive', r1);
    if mode = 'pending' and jsonb_array_length(coalesce(p_payments, '[]'::jsonb)) = 0 and jsonb_strip_nulls(p_invoice - 'mode' - 'station' - 'currency' - 'due_date') = '{}'::jsonb then
      return r1 || jsonb_build_object('receipt_id', p_receipt_id, 'invoice_status', 'pending');
    end if;
    r2 := public.po_receipt_settle(p_receipt_id, p_invoice, p_payments, p_manager_id, p_pin);
    perform public._settle_fail('settle', r2);
    return r1 || r2 || jsonb_build_object('repeat', coalesce((r1->>'repeat')::boolean, false) and coalesce((r2->>'repeat')::boolean, false));
  exception when others then
    if sqlerrm like 'settle:settle:%' then
      -- the inner function already said what failed; everything (the delivery too) is undone
      return r2;
    elsif sqlerrm like 'settle:%' then return public._settle_error(sqlerrm); end if;
    raise;
  end;
end $$;
revoke all on function public.po_receive_and_settle(uuid, jsonb, uuid, boolean, jsonb, jsonb, uuid, text) from public, anon;
grant execute on function public.po_receive_and_settle(uuid, jsonb, uuid, boolean, jsonb, jsonb, uuid, text) to authenticated;

-- 8) más pagos después, sobre la factura confirmada de una entrega --------------------------------------------------
create or replace function public.po_receipt_pay(p_receipt_id uuid, p_payments jsonb, p_request_id uuid, p_manager_id uuid, p_pin text,
                                                 p_station text default null)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.purchase_receipts; po public.purchase_orders; v public.vendors; inv public.supplier_invoices; p jsonb; method text; amt numeric; ref text;
        total_pay numeric := 0; n_pay int := 0; pin record; mv jsonb; res jsonb; i int := 0; openv numeric; actor text; adj numeric := 0;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_receipt_id is null or p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  -- the manager's PIN first, outside the transaction block: a wrong try stays counted
  select * into pin from public._verify_pin(p_manager_id, p_pin, true);
  if pin.err is not null then return jsonb_build_object('ok', false, 'error', pin.err, 'step', 'pin'); end if;
  begin
    select * into r from public.purchase_receipts where id = p_receipt_id for update;
    if r.id is null then raise exception 'settle:receipt:not_found'; end if;
    if r.invoice_status <> 'confirmed' or r.invoice_id is null then raise exception 'settle:invoice:not_confirmed'; end if;
    select * into inv from public.supplier_invoices where id = r.invoice_id;
    if inv.id is null or inv.voided_at is not null then raise exception 'settle:invoice:not_confirmed'; end if;
    select * into po from public.purchase_orders where id = r.po_id;
    select * into v from public.vendors where id = inv.vendor_id for update;   -- one payment of a supplier at a time (the lock supplier_payment_save takes)
    if exists (select 1 from public.supplier_payments where id = public._settle_uuid(p_request_id, 'pay', 0)) then
      return jsonb_build_object('ok', true, 'repeat', true, 'invoice_id', inv.id, 'open_crc', public._invoice_open(inv.id)); end if;
    if jsonb_typeof(coalesce(p_payments, '[]'::jsonb)) <> 'array' then raise exception 'settle:payment:bad_request'; end if;
    for p in select * from jsonb_array_elements(p_payments) loop
      method := p->>'method'; amt := round(nullif(p->>'amount_crc', '')::numeric, 2);
      if method not in ('register', 'cash', 'bank', 'card_debit', 'card_credit') or amt is null or amt <= 0 or amt > 100000000 then
        raise exception 'settle:payment:bad_value'; end if;
      n_pay := n_pay + 1; total_pay := total_pay + amt;
    end loop;
    if n_pay = 0 then raise exception 'settle:payment:bad_request'; end if;
    openv := public._invoice_open(inv.id);
    if total_pay - openv >= 1 then raise exception 'settle:payment:over_invoice'; end if;   -- under one colón over: paid in full
    adj := greatest(0, total_pay - openv);
    actor := public._inv_actor();
    for p in select * from jsonb_array_elements(p_payments) loop
      method := p->>'method'; amt := round((p->>'amount_crc')::numeric, 2); ref := nullif(left(trim(coalesce(p->>'reference', '')), 80), '');
      if i = n_pay - 1 and adj > 0 then amt := amt - adj; if amt <= 0 then raise exception 'settle:payment:over_invoice'; end if; end if;
      if method = 'register' then
        mv := public.register_cash_move(p_manager_id, p_pin, jsonb_build_object('direction', 'out', 'purpose', 'payout', 'currency', 'CRC', 'amount', amt,
                'reason', 'Pedido Nº ' || coalesce(po.po_number::text, '?') || ' · ' || v.name || ' · factura ' || inv.number, 'station', nullif(left(coalesce(p_station, ''), 40), '')),
                public._settle_uuid(p_request_id, 'payout', i));
        perform public._settle_fail('register', mv);
        res := public.supplier_payment_save(jsonb_build_object('vendor_id', inv.vendor_id, 'date', public.cr_today(), 'amount_crc', amt, 'paid_from', 'payout',
                 'payout_id', mv->>'id', 'invoice_ids', jsonb_build_array(inv.id), 'reference', coalesce(ref, 'Retiro de caja')), public._settle_uuid(p_request_id, 'pay', i));
      else
        res := public.supplier_payment_save(jsonb_build_object('vendor_id', inv.vendor_id, 'date', public.cr_today(), 'amount_crc', amt, 'paid_from', method,
                 'invoice_ids', jsonb_build_array(inv.id), 'reference', ref), public._settle_uuid(p_request_id, 'pay', i));
      end if;
      perform public._settle_fail('payment', res);
      i := i + 1;
    end loop;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('po_pay', pin.sid, actor, r.id::text, 'pedido ' || coalesce(po.po_number::text, '') || ': pago ' || (total_pay - adj) || ' a factura ' || inv.number,
              jsonb_build_object('invoice_id', inv.id, 'paid_crc', total_pay - adj, 'payments', n_pay, 'request_id', p_request_id));
    return jsonb_build_object('ok', true, 'invoice_id', inv.id, 'paid_crc', total_pay - adj, 'open_crc', public._invoice_open(inv.id));
  exception when others then
    if sqlerrm like 'settle:%' then return public._settle_error(sqlerrm); end if;
    raise;
  end;
end $$;
revoke all on function public.po_receipt_pay(uuid, jsonb, uuid, uuid, text, text) from public, anon;
grant execute on function public.po_receipt_pay(uuid, jsonb, uuid, uuid, text, text) to authenticated;

-- 9) todo lo de un pedido: entregas, factura, pagos, archivos --------------------------------------------------------
create or replace function public.po_history(p_po_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare po public.purchase_orders;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select * into po from public.purchase_orders where id = p_po_id;
  if po.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true,
    'order', jsonb_build_object('id', po.id, 'po_number', po.po_number, 'status', po.status, 'vendor_id', po.vendor_id,
                                'vendor', (select name from public.vendors where id = po.vendor_id), 'created_at', po.created_at, 'received_at', po.received_at),
    'receipts', (select coalesce(jsonb_agg(x order by x->>'received_at'), '[]') from (
      select jsonb_build_object('id', r.id, 'received_at', r.received_at, 'by_name', r.by_name, 'lines', r.lines, 'total_crc', r.total_crc, 'final', r.final,
               'invoice_no', r.invoice_no, 'invoice_date', r.invoice_date, 'invoice_status', r.invoice_status, 'draft', r.invoice_draft,
               'settled_at', r.settled_at, 'settled_by', r.settled_by,
               'payout', (select jsonb_build_object('id', m.id, 'amount_crc', m.amount_crc, 'business_date', m.business_date, 'voided', m.voided_at is not null,
                                                    'documented', exists (select 1 from public.supplier_payments sp where sp.payout_id = m.id and sp.voided_at is null)
                                                                              or exists (select 1 from public.expenses e where e.payout_id = m.id and e.voided_at is null))
                            from public.cash_movements m where m.id = r.payout_id),
               'invoice', (select jsonb_build_object('id', i.id, 'number', i.number, 'date', i.date, 'due_date', i.due_date, 'currency', i.currency, 'fx_rate', i.fx_rate,
                                                     'net_crc', i.net_crc, 'iva_crc', i.iva_crc, 'total_crc', i.total_crc, 'net_fx', i.net_fx, 'iva_fx', i.iva_fx,
                                                     'open_crc', public._invoice_open(i.id), 'voided', i.voided_at is not null, 'receipt_ids', to_jsonb(i.receipt_ids))
                             from public.supplier_invoices i where i.id = r.invoice_id),
               'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', sp.id, 'date', sp.date, 'paid_from', sp.paid_from, 'amount_crc', a.amount_crc,
                                                                         'reference', sp.reference, 'voided', sp.voided_at is not null, 'by', sp.created_by)
                                                      order by sp.created_at), '[]')
                              from public.supplier_payment_allocations a join public.supplier_payments sp on sp.id = a.payment_id
                             where a.invoice_id = r.invoice_id),
               'files', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'path', f.path, 'kind', f.kind, 'created_at', f.created_at) order by f.created_at), '[]')
                           from public.purchase_receipt_files f where f.receipt_id = r.id)) as x
        from public.purchase_receipts r where r.po_id = po.id) q));
end $$;
revoke all on function public.po_history(uuid) from public, anon;
grant execute on function public.po_history(uuid) to authenticated;

-- 10) lo pendiente: facturas por recibir o revisar, facturas abiertas y lo que se debe a cada proveedor -----------------
create or replace function public.po_pending()
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  return jsonb_build_object('ok', true, 'as_of', public.cr_today(),
    'receipts', (select coalesce(jsonb_agg(x order by x->>'received_at' desc), '[]') from (
      select jsonb_build_object('id', r.id, 'po_id', r.po_id, 'po_number', po.po_number, 'vendor_id', r.vendor_id, 'vendor', v.name, 'received_at', r.received_at,
               'total_crc', r.total_crc, 'invoice_status', r.invoice_status, 'draft', r.invoice_draft,
               'payout_crc', (select m.amount_crc from public.cash_movements m where m.id = r.payout_id and m.voided_at is null),
               'files', (select count(*) from public.purchase_receipt_files f where f.receipt_id = r.id)) as x
        from public.purchase_receipts r join public.purchase_orders po on po.id = r.po_id left join public.vendors v on v.id = r.vendor_id
       where r.invoice_status in ('pending', 'review') and r.invoice_id is null and r.received_at > now() - interval '180 days') q),
    'invoices', (select coalesce(jsonb_agg(x order by x->>'due_date', x->>'date'), '[]') from (
      select jsonb_build_object('id', i.id, 'vendor_id', i.vendor_id, 'vendor', v.name, 'number', i.number, 'date', i.date, 'due_date', coalesce(i.due_date, i.date + 30),
               'currency', i.currency, 'total_crc', i.total_crc, 'open_crc', public._invoice_open(i.id),
               'overdue', coalesce(i.due_date, i.date + 30) < public.cr_today(),
               'receipt_id', (select r.id from public.purchase_receipts r where r.invoice_id = i.id order by r.received_at limit 1),
               'po_number', (select po.po_number from public.purchase_receipts r join public.purchase_orders po on po.id = r.po_id where r.invoice_id = i.id order by r.received_at limit 1)) as x
        from public.supplier_invoices i join public.vendors v on v.id = i.vendor_id
       where i.voided_at is null and public._invoice_open(i.id) > 0) q),
    'vendors', (select coalesce(jsonb_agg(x order by x->>'name'), '[]') from (
      select jsonb_build_object('vendor_id', v.id, 'name', v.name, 'open_crc', sum(public._invoice_open(i.id))) as x
        from public.supplier_invoices i join public.vendors v on v.id = i.vendor_id
       where i.voided_at is null and public._invoice_open(i.id) > 0 group by v.id, v.name) q));
end $$;
revoke all on function public.po_pending() from public, anon;
grant execute on function public.po_pending() to authenticated;

select canopy.migration_end(29, 'recibir_pago');
notify pgrst, 'reload schema';
