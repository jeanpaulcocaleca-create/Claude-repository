-- =====================================================================================================
-- Canopy OS · migración 0019 · Entradas y salidas de dinero de la caja; conciliación de efectivo ₡ y $
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0018.
--
-- Qué hace
--   * public.cash_movements: cada vez que se saca o se mete dinero en la gaveta durante el día, con el PIN de
--     un encargado y el motivo: depósito al banco o cambio traído del banco, caja chica, un pago hecho con
--     dinero de la caja (una compra en el súper, un proveedor que cobra al entregar), o el dueño que saca o
--     pone dinero. En colones o en dólares.
--   * Lo esperado en la gaveta al cierre ya cuenta esas entradas y salidas (antes el cierre salía "faltante").
--   * Libros: cada movimiento se asienta con el día (caja contra banco, caja chica, pagos por documentar o el
--     dueño). Un pago hecho con dinero de la caja queda en "Pagos de caja por documentar" (1104) hasta que el
--     contador registra su factura como gasto o pago a proveedor "pagado con un retiro de la caja".
--   * cash_reconciliation: cada día de caja con fondo, ventas en efectivo, entradas y salidas, esperado,
--     contado y diferencia, en colones y en dólares. cash_payouts: los pagos de caja y cuánto falta documentar.
--   * Un movimiento se anula solo mientras la caja de ese día está abierta, y si no tiene factura registrada.
-- Qué cambia para el personal: un botón nuevo "Entrada o salida de dinero" en la ventana de la caja (POS).
-- Reversión: drop function register_cash_move, register_cash_void, register_cash_moves (los movimientos quedan).
-- =====================================================================================================
select canopy.migration_begin(19, 'cash_movements');

insert into acct.accounts (code, name, type, cash, system) values
  ('1104', 'Pagos de caja por documentar', 'asset', false, true),
  ('3102', 'Retiros del dueño', 'equity', false, true)
on conflict (code) do nothing;
insert into acct.mappings (key, account, label) values
  ('move_bank', '1110', 'Dinero de la caja depositado en el banco, o cambio traído del banco'),
  ('move_petty', '1103', 'Dinero de la caja pasado a caja chica, o devuelto'),
  ('move_payout', '1104', 'Pagos hechos con dinero de la caja, por documentar'),
  ('owner_draw', '3102', 'El dueño saca dinero de la caja'),
  ('owner_contribution', '3101', 'El dueño pone dinero en la caja'),
  ('from_payout', '1104', 'Gasto o pago a proveedor hecho con un retiro de la caja')
on conflict (key) do nothing;

create table if not exists public.cash_movements (
  id            uuid primary key,                       -- the page's request id
  business_date date not null,
  at            timestamptz not null default now(),
  direction     text not null check (direction in ('in', 'out')),
  purpose       text not null check (purpose in ('bank', 'petty', 'payout', 'owner')),
  currency      text not null check (currency in ('CRC', 'USD')),
  amount        numeric(14,2) not null check (amount > 0 and amount <= 10000000),
  fx_rate       numeric(10,2),                          -- dollars: the day's rate, to value them in colones
  amount_crc    numeric(14,2) not null,
  reason        text not null,
  staff_id      uuid,
  staff_name    text not null,
  station       text,
  voided_at     timestamptz,
  void_reason   text,
  voided_by     text,
  check (not (direction = 'in' and purpose = 'payout')),
  check (currency = 'CRC' or fx_rate is not null)
);
create index if not exists cash_movements_day_idx on public.cash_movements (business_date);
alter table public.cash_movements enable row level security;
revoke all on public.cash_movements from anon, authenticated;

-- an expense or a supplier payment can be paid with money taken from the drawer
alter table public.expenses drop constraint if exists expenses_paid_from_check;
alter table public.expenses add constraint expenses_paid_from_check check (paid_from in ('cash', 'petty', 'bank', 'credit', 'payout'));
alter table public.expenses add column if not exists payout_id uuid references public.cash_movements(id);
alter table public.supplier_payments drop constraint if exists supplier_payments_paid_from_check;
alter table public.supplier_payments add constraint supplier_payments_paid_from_check check (paid_from in ('cash', 'petty', 'bank', 'payout'));
alter table public.supplier_payments add column if not exists payout_id uuid references public.cash_movements(id);

-- what the drawer should hold now counts the money put in and taken out
create or replace function public._register_expected(p_day date, out cash_crc bigint, out usd numeric)
language sql stable security definer set search_path = public as $$
  select (select coalesce(sum(case when t.order_id is not null then t.crc_in - t.change_crc
                                   when o.payment_method in ('cash_crc', 'cash_usd') then o.total_crc else 0 end), 0)
            from public.orders o left join public.cash_tenders t on t.order_id = o.id
           where o.created_at >= public.cr_day_start(p_day) and o.created_at < public.cr_day_start(p_day + 1)
             and o.voided_at is null and coalesce(o.paid, true))
       + (select coalesce(round(sum(case when direction = 'in' then amount else -amount end)), 0)::bigint
            from public.cash_movements where business_date = p_day and currency = 'CRC' and voided_at is null),
         (select coalesce(sum(t.usd_in), 0)
            from public.orders o join public.cash_tenders t on t.order_id = o.id
           where o.created_at >= public.cr_day_start(p_day) and o.created_at < public.cr_day_start(p_day + 1)
             and o.voided_at is null and coalesce(o.paid, true))
       + (select coalesce(sum(case when direction = 'in' then amount else -amount end), 0)
            from public.cash_movements where business_date = p_day and currency = 'USD' and voided_at is null);
$$;
revoke all on function public._register_expected(date) from public, anon, authenticated;

-- the counter: put money in or take it out, with a manager's PIN and the reason
create or replace function public.register_cash_move(p_manager_id uuid, p_pin text, p_move jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; r public.register_days; m public.cash_movements; dir text; pur text; cur text; amt numeric; fx numeric; why text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into m from public.cash_movements where id = p_request_id;
  if m.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'id', m.id); end if;
  select * into v from public._verify_pin(p_manager_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  select * into r from public.register_days where closed_at is null order by business_date limit 1;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  dir := p_move->>'direction'; pur := p_move->>'purpose'; cur := coalesce(p_move->>'currency', 'CRC');
  amt := round(nullif(p_move->>'amount', '')::numeric, 2); why := nullif(left(trim(coalesce(p_move->>'reason', '')), 200), '');
  if dir not in ('in', 'out') or pur not in ('bank', 'petty', 'payout', 'owner') or cur not in ('CRC', 'USD')
     or amt is null or amt <= 0 or amt > 10000000 or (dir = 'in' and pur = 'payout') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if why is null then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  if cur = 'USD' then
    select rate into fx from public._fx_for(r.business_date);
    if fx is null then return jsonb_build_object('ok', false, 'error', 'no_rate'); end if;
  end if;
  insert into public.cash_movements (id, business_date, direction, purpose, currency, amount, fx_rate, amount_crc, reason, staff_id, staff_name, station)
    values (p_request_id, r.business_date, dir, pur, cur, amt, fx, case when cur = 'USD' then round(amt * fx, 2) else amt end, why, v.sid, v.sname,
            nullif(left(p_move->>'station', 40), ''))
    returning * into m;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('cash_move', v.sid, v.sname, m.id::text,
            case dir when 'in' then 'put ' else 'took ' end || amt || case cur when 'USD' then ' dollars' else ' colones' end ||
              case dir when 'in' then ' into' else ' out of' end || ' the drawer: ' || why,
            jsonb_build_object('business_date', m.business_date, 'direction', dir, 'purpose', pur, 'currency', cur, 'amount', amt));
  return jsonb_build_object('ok', true, 'id', m.id, 'business_date', m.business_date);
end $$;

-- a movement typed wrong is voided while its day is open and nothing was filed against it
create or replace function public.register_cash_void(p_manager_id uuid, p_pin text, p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; m public.cash_movements;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_manager_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into m from public.cash_movements where id = p_id for update;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if m.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if exists (select 1 from public.register_days where business_date = m.business_date and closed_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'closed_day'); end if;
  if exists (select 1 from public.expenses where payout_id = m.id and voided_at is null)
     or exists (select 1 from public.supplier_payments where payout_id = m.id and voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'documented'); end if;
  update public.cash_movements set voided_at = now(), void_reason = left(trim(p_reason), 200), voided_by = v.sname where id = m.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('cash_move_void', v.sid, v.sname, m.id::text, trim(p_reason),
            jsonb_build_object('business_date', m.business_date, 'direction', m.direction, 'purpose', m.purpose, 'currency', m.currency, 'amount', m.amount));
  return jsonb_build_object('ok', true);
end $$;

-- the open day's movements, for the counter screen
create or replace function public.register_cash_moves()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.register_days;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into r from public.register_days where closed_at is null or business_date = public.cr_today()
   order by (closed_at is null) desc, business_date limit 1;
  if r.id is null then return jsonb_build_object('ok', true, 'moves', '[]'::jsonb); end if;
  return jsonb_build_object('ok', true, 'business_date', r.business_date, 'moves', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'at', at, 'direction', direction, 'purpose', purpose, 'currency', currency,
                                                 'amount', amount, 'reason', reason, 'staff_name', staff_name, 'voided', voided_at is not null) order by at), '[]')
      from public.cash_movements where business_date = r.business_date));
end $$;

-- the day's entry: as in 0013, plus the drawer's money in and out
create or replace function acct.day_target(p_day date)
returns table(account text, amount numeric, memo text) language sql stable security definer set search_path = acct, public as $$
  with pays as (           -- money received (or given back) that day, by where it went
    select case when o.payment_method in ('cash_crc', 'cash_usd') and t.order_id is not null then 'pay_cash_crc'
                when o.payment_method in ('cash_crc', 'cash_usd') then 'pay_cash_crc'
                when o.payment_method = 'card' then 'pay_card'
                when o.payment_method = 'sinpe' then 'pay_sinpe'
                else 'pay_other' end as k,
           case when o.payment_method in ('cash_crc', 'cash_usd') and t.order_id is not null then t.crc_in - t.change_crc
                else o.total_crc end::numeric as amt
      from public.orders o left join public.cash_tenders t on t.order_id = o.id
     where o.business_date = p_day and o.voided_at is null and coalesce(o.paid, true) and o.payment_method <> 'pending'
    union all
    select 'pay_cash_usd', round(t.usd_in * t.fx_rate, 2)
      from public.orders o join public.cash_tenders t on t.order_id = o.id
     where o.business_date = p_day and o.voided_at is null and coalesce(o.paid, true) and t.usd_in > 0
  ),
  sales as (               -- what was sold that day (a bill counts on the day it is paid in full)
    select o.id, o.refund_of is not null as refund,
           case when o.refund_of is not null then o.total_crc
                when exists (select 1 from public.order_items i where i.order_id = o.id)
                  then (select sum(i.price_crc * i.qty) from public.order_items i where i.order_id = o.id) - coalesce(o.discount_crc, 0)
                else o.total_crc + coalesce(o.parts_crc, 0) end::numeric as gross,
           o.tax_crc
      from public.orders o
     where o.business_date = p_day and o.part_of is null and o.voided_at is null and coalesce(o.paid, true)
  ),
  s2 as (select refund, gross, coalesce(tax_crc, round(gross * 13 / 113))::numeric as tax, tax_crc is null as estimated from sales),
  stock as (               -- inventory at cost
    select m.kind, round(sum(m.qty * coalesce(m.unit_cost, 0)), 2) as cost
      from public.stock_moves m
     where (m.at at time zone 'America/Costa_Rica')::date = p_day
     group by m.kind
  ),
  moves as (              -- money put into or taken out of the drawer (0019), valued in colones
    select m.currency, case when m.direction = 'in' then m.amount_crc else -m.amount_crc end as amt,
           case m.purpose when 'bank' then 'move_bank' when 'petty' then 'move_petty' when 'payout' then 'move_payout'
                          else case when m.direction = 'out' then 'owner_draw' else 'owner_contribution' end end as k
      from public.cash_movements m where m.business_date = p_day and m.voided_at is null
  ),
  reg as (select r.cash_diff_crc, r.cash_diff_usd, r.fx_rate from public.register_days r where r.business_date = p_day and r.closed_at is not null),
  rows as (
    select acct.map(k) as account, sum(amt) as amount, 'cobros del día' as memo from pays group by k
    union all select acct.map('revenue'), -sum(gross - tax), 'ventas sin IVA' || case when bool_or(estimated) then ' (IVA estimado 13 % en ventas anteriores a 0009)' else '' end from s2 where not refund
    union all select acct.map('returns'), -sum(gross - tax), 'devoluciones sin IVA' from s2 where refund
    union all select acct.map('iva_out'), -sum(tax), 'IVA de las ventas' from s2
    -- what was paid but not yet sold (parts of open bills), or sold now but paid earlier
    union all select acct.map('advances'), (select coalesce(sum(gross), 0) from s2) - (select coalesce(sum(amt), 0) from pays), 'cuentas abiertas pagadas en parte'
    -- the drawer as counted at the close
    union all select acct.map('pay_cash_crc'), cash_diff_crc, 'diferencia del cierre (colones)' from reg where cash_diff_crc is not null
    union all select acct.map('cash_over_short'), -cash_diff_crc, 'diferencia del cierre (colones)' from reg where cash_diff_crc is not null
    union all select acct.map('pay_cash_usd'), round(cash_diff_usd * fx_rate, 2), 'diferencia del cierre (dólares)' from reg where cash_diff_usd is not null and fx_rate is not null
    union all select acct.map('cash_over_short'), -round(cash_diff_usd * fx_rate, 2), 'diferencia del cierre (dólares)' from reg where cash_diff_usd is not null and fx_rate is not null
    -- the drawer's cash in and out: the cash account against where it came from or went
    union all select acct.map(case when currency = 'USD' then 'pay_cash_usd' else 'pay_cash_crc' end), sum(amt), 'entradas y salidas de caja' from moves group by currency
    union all select acct.map(k), -sum(amt), 'entradas y salidas de caja' from moves group by k
    -- inventory: sold and given back at cost, waste, counts and adjustments, purchases
    union all select acct.map('cogs'), -cost, 'costo de lo vendido' from stock where kind in ('sale', 'void')
    union all select acct.map('waste'), -cost, 'mermas' from stock where kind = 'waste'
    union all select acct.map('stock_adjust'), -cost, 'conteos y ajustes' from stock where kind in ('count', 'adjust')
    union all select acct.map('ap'), -cost, 'compras de inventario' from stock where kind = 'purchase'
    union all select acct.map('inventory'), coalesce(sum(cost), 0), 'movimientos de inventario' from stock
  )
  select account, round(sum(amount), 2), string_agg(distinct memo, ' · ') from rows where amount is not null group by account having round(sum(amount), 2) <> 0;
$$;

-- expenses and supplier payments: as in 0014 and 0016, plus "paid with a payout from the drawer"
create or replace function public.expense_save(p_expense jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; a acct.accounts; amt numeric; iva numeric; src text; inv text; vid uuid; vname text; eid bigint; who text; po uuid;
begin
  if not (public.is_owner() or acct.can_read()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into x from public.expenses where id = p_request_id;
  if x.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'id', x.id); end if;
  amt := round(nullif(p_expense->>'amount_crc', '')::numeric, 2);
  iva := round(coalesce(nullif(p_expense->>'iva_crc', '')::numeric, 0), 2);
  src := p_expense->>'paid_from';
  inv := nullif(left(trim(coalesce(p_expense->>'invoice_no', '')), 40), '');
  vid := nullif(p_expense->>'vendor_id', '')::uuid;
  vname := nullif(left(trim(coalesce(p_expense->>'vendor_name', '')), 80), '');
  if vid is not null then select name into vname from public.vendors where id = vid; end if;
  select * into a from acct.accounts where code = p_expense->>'account';
  if a.code is null or not a.active or a.type <> 'expense' then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  po := nullif(p_expense->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if amt is null or amt <= 0 or iva < 0 or iva >= amt or src not in ('cash', 'petty', 'bank', 'credit', 'payout')
     or coalesce(trim(p_expense->>'description'), '') = '' or nullif(p_expense->>'date', '') is null then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if (p_expense->>'date')::date > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'future_date'); end if;
  if inv is not null and exists (select 1 from public.expenses e where e.voided_at is null and lower(e.invoice_no) = lower(inv)
                                    and coalesce(e.vendor_id::text, lower(e.vendor_name)) = coalesce(vid::text, lower(vname))) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_invoice'); end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  begin
    eid := acct.post((p_expense->>'date')::date, 'Gasto: ' || trim(p_expense->>'description') || coalesce(' · ' || vname, '') || coalesce(' · fact. ' || inv, ''),
                     'expense', 'expense:' || p_request_id,
                     jsonb_build_array(jsonb_build_object('account', a.code, 'debit', amt - iva),
                                       jsonb_build_object('account', acct.map('iva_in'), 'debit', iva),
                                       jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty'
                                                                                       when 'bank' then 'from_bank' when 'payout' then 'from_payout' else 'from_credit' end), 'credit', amt)),
                     null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  insert into public.expenses (id, date, vendor_id, vendor_name, description, account, amount_crc, iva_crc, paid_from, invoice_no, invoice_date, entry_id, created_by, payout_id)
    values (p_request_id, (p_expense->>'date')::date, vid, vname, left(trim(p_expense->>'description'), 200), a.code, amt, iva, src, inv,
            nullif(p_expense->>'invoice_date', '')::date, eid, who, case when src = 'payout' then po end);
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid);
end $$;

create or replace function public.supplier_payment_save(p_payment jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare v public.vendors; amt numeric; left_amt numeric; src text; d date; inv record; part numeric; eid bigint; who text; owed numeric; po uuid;
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if exists (select 1 from public.supplier_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  select * into v from public.vendors where id = nullif(p_payment->>'vendor_id', '')::uuid;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  amt := round(nullif(p_payment->>'amount_crc', '')::numeric, 2); src := p_payment->>'paid_from'; d := nullif(p_payment->>'date', '')::date;
  po := nullif(p_payment->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if p_request_id is null or amt is null or amt <= 0 or src not in ('cash', 'petty', 'bank', 'payout') or d is null or d > public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select coalesce(sum(public._invoice_open(id)), 0) into owed from public.supplier_invoices where vendor_id = v.id and voided_at is null;
  if amt > owed then return jsonb_build_object('ok', false, 'error', 'more_than_owed', 'owed', owed); end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  begin
    eid := acct.post(d, 'Pago a ' || v.name || coalesce(' · ' || nullif(trim(p_payment->>'reference'), ''), ''), 'ap', 'suppay:' || p_request_id,
             jsonb_build_array(jsonb_build_object('account', acct.map('ap'), 'debit', amt, 'memo', v.name),
                               jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty' when 'payout' then 'from_payout' else 'from_bank' end), 'credit', amt)),
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

-- each register day, in colones and in dollars: float, cash sales, money in and out, expected, counted
create or replace function public.cash_reconciliation(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'days', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'date', r.business_date, 'closed', r.closed_at is not null, 'fx_rate', r.fx_rate,
             'float_crc', r.float_crc, 'float_usd', r.float_usd,
             'in_crc', coalesce(mv.in_crc, 0), 'out_crc', coalesce(mv.out_crc, 0), 'in_usd', coalesce(mv.in_usd, 0), 'out_usd', coalesce(mv.out_usd, 0),
             'sales_crc', e.cash_crc - coalesce(mv.in_crc, 0) + coalesce(mv.out_crc, 0),     -- cash taken for sales, change given back
             'sales_usd', e.usd - coalesce(mv.in_usd, 0) + coalesce(mv.out_usd, 0),
             'expected_crc', coalesce(r.expected_cash_crc, r.float_crc + e.cash_crc), 'counted_crc', r.cash_counted_crc, 'diff_crc', r.cash_diff_crc,
             'expected_usd', coalesce(r.expected_cash_usd, r.float_usd + e.usd), 'counted_usd', r.cash_counted_usd, 'diff_usd', r.cash_diff_usd)
           order by r.business_date), '[]')
      from public.register_days r
      cross join lateral public._register_expected(r.business_date) e
      left join lateral (select sum(amount) filter (where direction = 'in' and currency = 'CRC') as in_crc, sum(amount) filter (where direction = 'out' and currency = 'CRC') as out_crc,
                                sum(amount) filter (where direction = 'in' and currency = 'USD') as in_usd, sum(amount) filter (where direction = 'out' and currency = 'USD') as out_usd
                           from public.cash_movements m where m.business_date = r.business_date and m.voided_at is null) mv on true
     where r.business_date between p_from and p_to));
end $$;

-- payouts from the drawer and how much of each has its document filed
create or replace function public.cash_payouts(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'payouts', (
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'date', m.business_date, 'at', m.at, 'currency', m.currency, 'amount', m.amount,
             'amount_crc', m.amount_crc, 'reason', m.reason, 'staff_name', m.staff_name,
             'documented_crc', coalesce((select sum(e.amount_crc) from public.expenses e where e.payout_id = m.id and e.voided_at is null), 0)
                             + coalesce((select sum(p.amount_crc) from public.supplier_payments p where p.payout_id = m.id and p.voided_at is null), 0))
           order by m.at desc), '[]')
      from public.cash_movements m
     where m.purpose = 'payout' and m.voided_at is null and m.business_date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, public.cr_today())));
end $$;

revoke all on function public.register_cash_move(uuid, text, jsonb, uuid), public.register_cash_void(uuid, text, uuid, text), public.register_cash_moves(),
                       public.cash_reconciliation(date, date), public.cash_payouts(date, date) from public, anon;
grant execute on function public.register_cash_move(uuid, text, jsonb, uuid), public.register_cash_void(uuid, text, uuid, text), public.register_cash_moves(),
                          public.cash_reconciliation(date, date), public.cash_payouts(date, date) to authenticated;
revoke all on function acct.day_target(date) from public, anon, authenticated;

select canopy.migration_end(19, 'cash_movements');
notify pgrst, 'reload schema';
