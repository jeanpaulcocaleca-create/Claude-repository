-- =====================================================================================================
-- Canopy OS · migración 0016 · Facturas de proveedores, cuentas por pagar y pagos a proveedores
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0015.
--
-- Qué hace
--   * public.supplier_invoices: la factura de cada compra a proveedor (número, fecha, vencimiento, monto sin
--     IVA, IVA), unida a las entregas recibidas (purchase_receipts). Al registrarla se asienta el IVA crédito
--     fiscal y la diferencia de precio contra lo recibido; lo recibido ya estaba en cuentas por pagar.
--   * public.supplier_payments: cada pago a un proveedor (caja, caja chica o banco) aplicado a sus facturas.
--   * ap_aging: lo que se debe a cada proveedor por antigüedad (al día, 1–30, 31–60, más de 60 días).
--   * La misma factura del mismo proveedor no se registra dos veces; repetir el envío no duplica.
-- Qué cambia para el personal: nada en la caja.
--   * Anular una factura o un pago registra su reversión (nada se borra); lo anulan el dueño o el contador.
-- Reversión: drop function supplier_invoice_save, supplier_payment_save, supplier_invoice_void, supplier_payment_void,
--            ap_aging (tablas y asientos quedan).
-- =====================================================================================================
select canopy.migration_begin(16, 'payables');

insert into acct.mappings (key, account, label) values
  -- to the expense side, not to inventory: the inventory account stays equal to the stock valued at average cost
  ('price_variance', '5103', 'Diferencia entre la factura del proveedor y el costo recibido')
on conflict (key) do nothing;

create table if not exists public.supplier_invoices (
  id          uuid primary key,                         -- the page's request id
  vendor_id   uuid not null references public.vendors(id),
  number      text not null,
  date        date not null,
  due_date    date,
  net_crc     numeric(14,2) not null check (net_crc >= 0),
  iva_crc     numeric(14,2) not null default 0 check (iva_crc >= 0),
  total_crc   numeric(14,2) generated always as (net_crc + iva_crc) stored,
  receipt_ids uuid[] not null default '{}',
  account     text,                                     -- where an invoice without deliveries goes (a service, equipment)
  received_crc numeric(14,2) not null default 0,         -- cost of the linked deliveries (already owed)
  entry_id    bigint,
  void_entry_id bigint,
  voided_at   timestamptz,
  void_reason text,
  created_at  timestamptz not null default now(),
  created_by  text not null
);
create unique index if not exists supplier_invoices_once on public.supplier_invoices (vendor_id, lower(number)) where voided_at is null;
alter table public.supplier_invoices enable row level security;
revoke all on public.supplier_invoices from anon, authenticated;
alter table public.purchase_receipts add column if not exists invoice_id uuid;

create table if not exists public.supplier_payments (
  id          uuid primary key,
  vendor_id   uuid not null references public.vendors(id),
  date        date not null,
  amount_crc  numeric(14,2) not null check (amount_crc > 0),
  paid_from   text not null check (paid_from in ('cash', 'petty', 'bank')),
  reference   text,
  entry_id    bigint,
  void_entry_id bigint,
  voided_at   timestamptz,
  void_reason text,
  created_at  timestamptz not null default now(),
  created_by  text not null
);
create table if not exists public.supplier_payment_allocations (
  payment_id uuid not null references public.supplier_payments(id),
  invoice_id uuid not null references public.supplier_invoices(id),
  amount_crc numeric(14,2) not null check (amount_crc > 0),
  primary key (payment_id, invoice_id)
);
alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;
revoke all on public.supplier_payments, public.supplier_payment_allocations from anon, authenticated;

create or replace function public._ap_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_owner() or acct.can_read(), false);
$$;
revoke all on function public._ap_allowed() from public, anon;
grant execute on function public._ap_allowed() to authenticated;

-- an invoice: what is still open on it
create or replace function public._invoice_open(p_id uuid) returns numeric language sql stable security definer set search_path = public as $$
  select i.total_crc - coalesce((select sum(a.amount_crc) from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id
                                  where a.invoice_id = i.id and p.voided_at is null), 0)
    from public.supplier_invoices i where i.id = p_id;
$$;
revoke all on function public._invoice_open(uuid) from public, anon, authenticated;

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
    if a.code is null or not a.active or a.cash or a.type not in ('expense', 'asset') or a.code in (acct.map('iva_in'), acct.map('ap')) then
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

-- a payment to a supplier, applied to the oldest open invoices unless told which
create or replace function public.supplier_payment_save(p_payment jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare v public.vendors; amt numeric; left_amt numeric; src text; d date; inv record; part numeric; eid bigint; who text; owed numeric;
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if exists (select 1 from public.supplier_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  select * into v from public.vendors where id = nullif(p_payment->>'vendor_id', '')::uuid;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  amt := round(nullif(p_payment->>'amount_crc', '')::numeric, 2); src := p_payment->>'paid_from'; d := nullif(p_payment->>'date', '')::date;
  if p_request_id is null or amt is null or amt <= 0 or src not in ('cash', 'petty', 'bank') or d is null or d > public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select coalesce(sum(public._invoice_open(id)), 0) into owed from public.supplier_invoices where vendor_id = v.id and voided_at is null;
  if amt > owed then return jsonb_build_object('ok', false, 'error', 'more_than_owed', 'owed', owed); end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  begin
    eid := acct.post(d, 'Pago a ' || v.name || coalesce(' · ' || nullif(trim(p_payment->>'reference'), ''), ''), 'ap', 'suppay:' || p_request_id,
             jsonb_build_array(jsonb_build_object('account', acct.map('ap'), 'debit', amt, 'memo', v.name),
                               jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty' else 'from_bank' end), 'credit', amt)),
             null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, reference, entry_id, created_by)
    values (p_request_id, v.id, d, amt, src, nullif(left(trim(coalesce(p_payment->>'reference', '')), 80), ''), eid, who);
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

-- a wrong invoice is voided by reversing its entry; its deliveries can then be invoiced again. Not once paid.
create or replace function public.supplier_invoice_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.supplier_invoices; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into x from public.supplier_invoices where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if public._invoice_open(x.id) <> x.total_crc then return jsonb_build_object('ok', false, 'error', 'has_payments'); end if;
  if x.entry_id is not null then
    r := public.acct_entry_reverse(x.entry_id, public.cr_today(), 'factura de proveedor anulada: ' || trim(p_reason));
    if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  end if;
  update public.supplier_invoices set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = x.id;
  update public.purchase_receipts set invoice_id = null where invoice_id = x.id;
  return jsonb_build_object('ok', true);
end $$;

-- a wrong payment is voided by reversing its entry; what it paid is owed again
create or replace function public.supplier_payment_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.supplier_payments; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into x from public.supplier_payments where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  r := public.acct_entry_reverse(x.entry_id, public.cr_today(), 'pago a proveedor anulado: ' || trim(p_reason));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  update public.supplier_payments set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = x.id;
  return jsonb_build_object('ok', true);
end $$;

-- what is owed to each supplier, by age; and the deliveries not invoiced yet
create or replace function public.ap_aging(p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare d date := coalesce(p_as_of, public.cr_today());
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'as_of', d,
    'vendor_list', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]') from public.vendors where active),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts
                  where active and not cash and type in ('expense', 'asset') and code not in (acct.map('iva_in'), acct.map('ap'))),
    'vendors', (select coalesce(jsonb_agg(x order by x->>'name'), '[]') from (
      select jsonb_build_object('vendor_id', v.id, 'name', v.name,
               'current', coalesce(sum(o.open) filter (where coalesce(o.due_date, o.date + 30) >= d), 0),
               'd30', coalesce(sum(o.open) filter (where coalesce(o.due_date, o.date + 30) < d and coalesce(o.due_date, o.date + 30) >= d - 30), 0),
               'd60', coalesce(sum(o.open) filter (where coalesce(o.due_date, o.date + 30) < d - 30 and coalesce(o.due_date, o.date + 30) >= d - 60), 0),
               'older', coalesce(sum(o.open) filter (where coalesce(o.due_date, o.date + 30) < d - 60), 0),
               'total', coalesce(sum(o.open), 0),
               'invoices', jsonb_agg(jsonb_build_object('id', o.id, 'number', o.number, 'date', o.date, 'due_date', o.due_date, 'total', o.total_crc, 'open', o.open) order by o.date)) as x
        from public.vendors v
        join (select i.*, public._invoice_open(i.id) as open from public.supplier_invoices i where i.voided_at is null and i.date <= d) o on o.vendor_id = v.id
       where o.open > 0
       group by v.id, v.name) s),
    'uninvoiced', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'vendor_id', r.vendor_id, 'vendor', v.name, 'received_at', r.received_at,
                                                                 'invoice_no', r.invoice_no, 'total_crc', r.total_crc, 'po_number', po.po_number) order by r.received_at), '[]')
                     from public.purchase_receipts r left join public.vendors v on v.id = r.vendor_id left join public.purchase_orders po on po.id = r.po_id
                    where r.invoice_id is null and r.total_crc > 0),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'vendor', v.name, 'date', p.date, 'amount', p.amount_crc, 'paid_from', p.paid_from, 'reference', p.reference,
                                                               'invoices', (select string_agg(i.number, ', ' order by i.number) from public.supplier_payment_allocations a
                                                                              join public.supplier_invoices i on i.id = a.invoice_id where a.payment_id = p.id))
                                              order by p.date desc, p.created_at desc), '[]')
                   from public.supplier_payments p join public.vendors v on v.id = p.vendor_id where p.date > d - 92 and p.voided_at is null),
    'recent_invoices', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'vendor', v.name, 'number', i.number, 'date', i.date, 'due_date', i.due_date,
                                                                     'net', i.net_crc, 'iva', i.iva_crc, 'total', i.total_crc, 'received', i.received_crc,
                                                                     'open', public._invoice_open(i.id), 'voided', i.voided_at is not null)
                                                  order by i.date desc, i.created_at desc), '[]')
                          from public.supplier_invoices i join public.vendors v on v.id = i.vendor_id where i.date > d - 92),
    -- how the ledger's accounts payable is made up, so the accountant can tie it out
    'ledger', jsonb_build_object(
      'ap_balance', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l join acct.entries e on e.id = l.entry_id
                      where l.account = acct.map('ap') and e.date <= d),
      'invoices_open', (select coalesce(sum(public._invoice_open(i.id)), 0) from public.supplier_invoices i where i.voided_at is null and i.date <= d),
      'received_not_invoiced', (select coalesce(sum(r.total_crc), 0) from public.purchase_receipts r where r.invoice_id is null),
      'expenses_on_credit', (select coalesce(sum(e.amount_crc), 0) from public.expenses e where e.paid_from = 'credit' and e.voided_at is null and e.date <= d)));
end $$;

revoke all on function public.supplier_invoice_save(jsonb, uuid), public.supplier_payment_save(jsonb, uuid), public.ap_aging(date),
                       public.supplier_invoice_void(uuid, text), public.supplier_payment_void(uuid, text) from public, anon;
grant execute on function public.supplier_invoice_save(jsonb, uuid), public.supplier_payment_save(jsonb, uuid), public.ap_aging(date),
                          public.supplier_invoice_void(uuid, text), public.supplier_payment_void(uuid, text) to authenticated;

select canopy.migration_end(16, 'payables');
notify pgrst, 'reload schema';
