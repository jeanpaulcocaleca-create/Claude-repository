-- =====================================================================================================
-- Canopy OS · migración 0034 · Contabilidad nueva (1 de 2): lecturas que faltaban, datos habituales por proveedor,
--   y los gastos solo para el dueño con código y el contador
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0033. Una sola transacción.
--
-- Qué hace (rediseño de Contabilidad aprobado por el dueño el 2026-10-26, docs/CONTABILIDAD-REDISENO.md)
--   * Proveedores: seis columnas nuevas, todas opcionales y vacías al aplicar (cédula, plazo de crédito, cuenta de gasto
--     habitual, forma de pago habitual, tasa de IVA habitual, notas de pago). Con ellas «Nuevo gasto» se registra en
--     segundos: proveedor, monto y fecha; la categoría, el IVA y la forma de pago salen de lo habitual confirmado para
--     ese proveedor. Si el proveedor no tiene nada habitual, la página pregunta solo lo que falta; el servidor nunca
--     inventa IVA, forma de pago ni categoría (needs_account / needs_paid_from / needs_iva).
--   * Gastos: registrar, anular, adjuntar y listar gastos queda SOLO para el dueño con el código del teléfono y el
--     contador (acct.can_read()). Hasta hoy una tableta del café con el PIN de un encargado (áreas de dueño abiertas)
--     también podía llamar expense_save y expense_list. Las facturas de proveedor y los pagos desde Inventario → Recibir
--     (0029) no cambian: siguen con las áreas de dueño. El depósito de fotos de facturas sigue la misma regla nueva
--     (_receipts_allowed). Decisión del dueño (2026-10-26), comprobada en el servidor, no solo en la página.
--   * Funciones de lectura nuevas para la página Contabilidad (contabilidad.html), todas solo lectura:
--       vendors_list()                        proveedores con contacto, lo habitual, saldos y última compra (áreas de dueño o libros)
--       vendor_history(id, desde, hasta)      facturas, pagos, gastos y pedidos de un proveedor (áreas de dueño o libros)
--       purchases_list(desde, hasta, prov?)   pedidos con entregas, facturas, pagos y etapa (áreas de dueño o libros)
--       sales_by_method(desde, hasta)         cobros por día y forma de pago, como los calcula el asiento del día (caja o libros)
--       cash_position()                       efectivo y bancos según los libros, con el último saldo del estado de cuenta (libros)
--       period_compare(desde, hasta)          cifras del período y del anterior, y el estado de cada mes (caja, estimado o libros)
--       acct_audit(desde, hasta)              las acciones contables de la bitácora (libros)
--   * Escrituras nuevas, pequeñas: vendor_save (proveedor nuevo o cambiado; solo el dueño con código) y
--     vendor_defaults_save (lo habitual de un proveedor; dueño con código o contador). Las dos quedan en la bitácora.
-- Qué NO cambia: los asientos, la doble partida, los cierres, el IVA, el asiento del día, las facturas y pagos a
--   proveedores, el inventario, la caja, el banco ni la nómina. Ningún registro existente se cambia ni se borra.
-- Qué ve una página anterior: accounting.html sigue funcionando igual para el dueño con código y el contador.
-- Cuándo: fuera del horario de atención, antes de publicar contabilidad.html (la página nueva avisa si falta esta migración).
-- Reversión: supabase/tools/reversion-0034.sql (vuelve a las funciones de antes y quita las nuevas; las columnas quedan).
-- =====================================================================================================
select canopy.migration_begin(34, 'contabilidad_lecturas');
set local lock_timeout = '8s';

-- 1) proveedores: lo habitual y los datos del contador ------------------------------------------------------------------
alter table public.vendors add column if not exists tax_id text;                   -- cédula física o jurídica (para el contador)
alter table public.vendors add column if not exists credit_days int;               -- plazo de crédito en días (vacío = 30, como hoy)
alter table public.vendors add column if not exists default_account text;          -- cuenta de gasto habitual
alter table public.vendors add column if not exists default_paid_from text;        -- forma de pago habitual
alter table public.vendors add column if not exists default_iva_rate numeric(5,4); -- tasa de IVA habitual (0, 0.01, 0.02, 0.04, 0.13); vacío = preguntar
alter table public.vendors add column if not exists payment_notes text;            -- cómo se le paga (cuenta, SINPE…)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'vendors_default_paid_from_check') then
    alter table public.vendors add constraint vendors_default_paid_from_check
      check (default_paid_from is null or default_paid_from in ('cash', 'petty', 'bank', 'credit', 'payout'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vendors_default_iva_rate_check') then
    alter table public.vendors add constraint vendors_default_iva_rate_check
      check (default_iva_rate is null or default_iva_rate in (0, 0.01, 0.02, 0.04, 0.13));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vendors_credit_days_check') then
    alter table public.vendors add constraint vendors_credit_days_check check (credit_days is null or (credit_days >= 0 and credit_days <= 180));
  end if;
end $$;

-- 2) quién registra gastos: el dueño con código o el contador (nunca una tableta con PIN) -------------------------------
create or replace function public._expense_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(acct.can_read(), false);
$$;
revoke all on function public._expense_allowed() from public, anon;
grant execute on function public._expense_allowed() to authenticated;
-- the receipts folder follows the same rule (its two Storage policies call this function by name)
create or replace function public._receipts_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(acct.can_read(), false);
$$;
-- what is still owed on an expense (0034: a credit expense owes all of it; 0035 subtracts its payments)
create or replace function public._expense_open(p_id uuid) returns numeric language sql stable security definer set search_path = public as $$
  select case when e.paid_from = 'credit' and e.voided_at is null then e.amount_crc else 0::numeric end from public.expenses e where e.id = p_id;
$$;
revoke all on function public._expense_open(uuid) from public, anon, authenticated;

create or replace function public.expense_save(p_expense jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; a acct.accounts; amt numeric; iva numeric; src text; inv text; vid uuid; vname text; eid bigint; who text; po uuid;
        v_acc text; v_src text; v_rate numeric; acc text; descr text;
begin
  if not public._expense_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into x from public.expenses where id = p_request_id;
  if x.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'id', x.id); end if;
  amt := round(nullif(p_expense->>'amount_crc', '')::numeric, 2);
  inv := nullif(left(trim(coalesce(p_expense->>'invoice_no', '')), 40), '');
  vid := nullif(p_expense->>'vendor_id', '')::uuid;
  vname := nullif(left(trim(coalesce(p_expense->>'vendor_name', '')), 80), '');
  if vid is not null then
    select name, default_account, default_paid_from, default_iva_rate into vname, v_acc, v_src, v_rate from public.vendors where id = vid;
    if vname is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  end if;
  -- what the request does not say comes from the supplier's confirmed habits; nothing is guessed
  acc := coalesce(nullif(p_expense->>'account', ''), v_acc);
  if acc is null then return jsonb_build_object('ok', false, 'error', 'needs_account'); end if;
  select * into a from acct.accounts where code = acc;
  if a.code is null or not a.active or a.type <> 'expense' then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  src := coalesce(nullif(p_expense->>'paid_from', ''), v_src);
  if src is null then return jsonb_build_object('ok', false, 'error', 'needs_paid_from'); end if;
  if nullif(p_expense->>'iva_crc', '') is not null then iva := round((p_expense->>'iva_crc')::numeric, 2);
  elsif v_rate is not null and amt is not null then iva := round(amt - amt / (1 + v_rate), 2);
  else return jsonb_build_object('ok', false, 'error', 'needs_iva'); end if;
  descr := coalesce(nullif(left(trim(coalesce(p_expense->>'description', '')), 200), ''), vname);
  po := nullif(p_expense->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if amt is null or amt <= 0 or iva < 0 or iva >= amt or src not in ('cash', 'petty', 'bank', 'credit', 'payout')
     or descr is null or nullif(p_expense->>'date', '') is null then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if (p_expense->>'date')::date > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'future_date'); end if;
  if inv is not null and exists (select 1 from public.expenses e where e.voided_at is null and lower(e.invoice_no) = lower(inv)
                                    and coalesce(e.vendor_id::text, lower(e.vendor_name)) = coalesce(vid::text, lower(vname))) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_invoice'); end if;
  who := acct.actor();
  begin
    eid := acct.post((p_expense->>'date')::date, 'Gasto: ' || descr || coalesce(' · ' || vname, '') || coalesce(' · fact. ' || inv, ''),
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
    values (p_request_id, (p_expense->>'date')::date, vid, vname, descr, a.code, amt, iva, src, inv,
            nullif(p_expense->>'invoice_date', '')::date, eid, who, case when src = 'payout' then po end);
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid, 'account', a.code, 'paid_from', src, 'iva_crc', iva);
end $$;

create or replace function public.expense_list(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._expense_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'expenses', (
    select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('account_name', a.name, 'open_crc', public._expense_open(e.id)) order by e.date desc, e.created_at desc), '[]')
      from public.expenses e join acct.accounts a on a.code = e.account where e.date between p_from and p_to),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where type = 'expense' and active));
end $$;

-- 3) proveedores: la lista con todo lo que la ficha necesita -------------------------------------------------------------
create or replace function public.vendors_list()
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare d date := public.cr_today();
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'as_of', d, 'can_edit', public.owner_with_code(),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where type = 'expense' and active),
    'vendors', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', v.id, 'name', v.name, 'active', v.active, 'contact_name', v.contact_name, 'phone', v.phone, 'whatsapp', v.whatsapp, 'email', v.email,
               'lead_days', v.lead_days, 'order_days', v.order_days, 'notes', v.notes, 'credit_days', v.credit_days,
               -- the cédula, how the supplier is paid, its habits and its expenses: only through the books' door (the café tablet sees the orders side)
               'tax_id', case when acct.can_read() then v.tax_id end,
               'default_account', case when acct.can_read() then v.default_account end,
               'default_account_name', case when acct.can_read() then (select name from acct.accounts where code = v.default_account) end,
               'default_paid_from', case when acct.can_read() then v.default_paid_from end, 'default_iva_rate', case when acct.can_read() then v.default_iva_rate end,
               'payment_notes', case when acct.can_read() then v.payment_notes end,
               'owed_invoices', coalesce((select sum(public._invoice_open(i.id)) from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null), 0),
               'owed_expenses', case when acct.can_read() then coalesce((select sum(public._expense_open(e.id)) from public.expenses e where e.vendor_id = v.id and e.paid_from = 'credit' and e.voided_at is null), 0) end,
               'overdue', exists (select 1 from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null and public._invoice_open(i.id) > 0
                                     and coalesce(i.due_date, i.date + coalesce(v.credit_days, 30)) < d),
               'last_purchase', greatest((select max((r.received_at at time zone 'America/Costa_Rica')::date) from public.purchase_receipts r where r.vendor_id = v.id),
                                         (select max(i.date) from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null),
                                         case when acct.can_read() then (select max(e.date) from public.expenses e where e.vendor_id = v.id and e.voided_at is null) end),
               'bought_12m', coalesce((select sum(r.total_crc) from public.purchase_receipts r where r.vendor_id = v.id and r.received_at >= public.cr_day_start(d - 365)), 0)
                           + coalesce((select sum(i.net_crc) from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null and i.account is not null and i.date > d - 365), 0)
                           + case when acct.can_read() then coalesce((select sum(e.amount_crc - e.iva_crc) from public.expenses e where e.vendor_id = v.id and e.voided_at is null and e.date > d - 365), 0) else 0 end,
               'deliveries_12m', (select count(*) from public.purchase_receipts r where r.vendor_id = v.id and r.received_at >= public.cr_day_start(d - 365)),
               'expenses_12m', case when acct.can_read() then (select count(*) from public.expenses e where e.vendor_id = v.id and e.voided_at is null and e.date > d - 365) end)
             order by v.active desc, v.name), '[]')
        from public.vendors v));
end $$;

create or replace function public.vendor_save(p_vendor jsonb)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare v public.vendors; vid uuid; nm text; lead int; cd int;
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  vid := nullif(p_vendor->>'id', '')::uuid;
  nm := nullif(left(trim(coalesce(p_vendor->>'name', '')), 80), '');
  lead := coalesce(nullif(p_vendor->>'lead_days', '')::int, 2);
  cd := nullif(p_vendor->>'credit_days', '')::int;
  if nm is null then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  if lead < 0 or lead > 60 or (cd is not null and (cd < 0 or cd > 180)) then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if vid is not null then
    select * into v from public.vendors where id = vid for update;
    if v.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  if exists (select 1 from public.vendors y where lower(y.name) = lower(nm) and y.active and y.id is distinct from vid) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name'); end if;
  if vid is null then
    insert into public.vendors (name, contact_name, phone, whatsapp, email, lead_days, order_days, notes, active, tax_id, credit_days)
      values (nm, nullif(left(trim(coalesce(p_vendor->>'contact_name', '')), 80), ''), nullif(left(trim(coalesce(p_vendor->>'phone', '')), 40), ''),
              nullif(left(trim(coalesce(p_vendor->>'whatsapp', '')), 40), ''), nullif(left(trim(coalesce(p_vendor->>'email', '')), 120), ''),
              lead, nullif(left(trim(coalesce(p_vendor->>'order_days', '')), 60), ''), nullif(left(trim(coalesce(p_vendor->>'notes', '')), 500), ''),
              coalesce((p_vendor->>'active')::boolean, true), nullif(left(trim(coalesce(p_vendor->>'tax_id', '')), 30), ''), cd)
      returning id into vid;
  else
    update public.vendors set name = nm, contact_name = nullif(left(trim(coalesce(p_vendor->>'contact_name', '')), 80), ''),
           phone = nullif(left(trim(coalesce(p_vendor->>'phone', '')), 40), ''), whatsapp = nullif(left(trim(coalesce(p_vendor->>'whatsapp', '')), 40), ''),
           email = nullif(left(trim(coalesce(p_vendor->>'email', '')), 120), ''), lead_days = lead,
           order_days = nullif(left(trim(coalesce(p_vendor->>'order_days', '')), 60), ''), notes = nullif(left(trim(coalesce(p_vendor->>'notes', '')), 500), ''),
           active = coalesce((p_vendor->>'active')::boolean, v.active), tax_id = nullif(left(trim(coalesce(p_vendor->>'tax_id', '')), 30), ''), credit_days = cd
     where id = vid;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('vendor_save', null, acct.actor(), vid::text, case when v.id is null then 'proveedor nuevo: ' else 'proveedor cambiado: ' end || nm,
            jsonb_build_object('before', case when v.id is null then null else jsonb_build_object('name', v.name, 'active', v.active, 'lead_days', v.lead_days, 'credit_days', v.credit_days) end));
  return jsonb_build_object('ok', true, 'id', vid);
end $$;

create or replace function public.vendor_defaults_save(p_vendor_id uuid, p_defaults jsonb)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare v public.vendors; acc text; src text; rate numeric;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into v from public.vendors where id = p_vendor_id for update;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  acc := nullif(p_defaults->>'account', ''); src := nullif(p_defaults->>'paid_from', ''); rate := nullif(p_defaults->>'iva_rate', '')::numeric;
  -- an active expense account, never one the day entry posts by itself (cash differences, waste, counts, price differences)
  if acc is not null and (not exists (select 1 from acct.accounts where code = acc and active and type = 'expense')
                          or exists (select 1 from acct.mappings m where m.account = acc and m.key in ('cash_over_short', 'waste', 'stock_adjust', 'price_variance'))) then
    return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  if (src is not null and src not in ('cash', 'petty', 'bank', 'credit', 'payout')) or (rate is not null and rate not in (0, 0.01, 0.02, 0.04, 0.13)) then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  update public.vendors set default_account = acc, default_paid_from = src, default_iva_rate = rate,
         payment_notes = nullif(left(trim(coalesce(p_defaults->>'payment_notes', '')), 200), '') where id = v.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('vendor_defaults', null, acct.actor(), v.id::text, 'lo habitual de ' || v.name || ': ' || coalesce(acc, '—') || ' · ' || coalesce(src, '—') || ' · IVA ' || coalesce(rate::text, '—'),
            jsonb_build_object('before', jsonb_build_object('account', v.default_account, 'paid_from', v.default_paid_from, 'iva_rate', v.default_iva_rate)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vendor_history(p_vendor_id uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare v public.vendors; d date := public.cr_today();
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  select * into v from public.vendors where id = p_vendor_id;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'vendor', jsonb_build_object('id', v.id, 'name', v.name, 'active', v.active, 'contact_name', v.contact_name, 'phone', v.phone, 'whatsapp', v.whatsapp,
                'email', v.email, 'lead_days', v.lead_days, 'order_days', v.order_days, 'notes', v.notes, 'credit_days', v.credit_days,
                'tax_id', case when acct.can_read() then v.tax_id end, 'default_account', case when acct.can_read() then v.default_account end,
                'default_paid_from', case when acct.can_read() then v.default_paid_from end, 'default_iva_rate', case when acct.can_read() then v.default_iva_rate end,
                'payment_notes', case when acct.can_read() then v.payment_notes end,
                'owed_invoices', coalesce((select sum(public._invoice_open(i.id)) from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null), 0),
                'owed_expenses', case when acct.can_read() then coalesce((select sum(public._expense_open(e.id)) from public.expenses e where e.vendor_id = v.id and e.paid_from = 'credit' and e.voided_at is null), 0) end),
    'aging', (select jsonb_build_object(
                'current', coalesce(sum(o.open) filter (where o.due >= d), 0),
                'd30', coalesce(sum(o.open) filter (where o.due < d and o.due >= d - 30), 0),
                'd60', coalesce(sum(o.open) filter (where o.due < d - 30 and o.due >= d - 60), 0),
                'older', coalesce(sum(o.open) filter (where o.due < d - 60), 0))
                from (select public._invoice_open(i.id) as open, coalesce(i.due_date, i.date + coalesce(v.credit_days, 30)) as due
                        from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null) o where o.open > 0),
    'invoices', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'number', i.number, 'date', i.date, 'due_date', coalesce(i.due_date, i.date + coalesce(v.credit_days, 30)),
                   'net', i.net_crc, 'iva', i.iva_crc, 'total', i.total_crc, 'open', public._invoice_open(i.id), 'voided', i.voided_at is not null, 'void_reason', i.void_reason,
                   'account', i.account, 'deliveries', coalesce(array_length(i.receipt_ids, 1), 0), 'entry_id', i.entry_id, 'currency', i.currency, 'created_by', i.created_by)
                   order by i.date desc, i.created_at desc), '[]')
                   from public.supplier_invoices i where i.vendor_id = v.id and i.date between p_from and p_to),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'date', p.date, 'amount', p.amount_crc, 'paid_from', p.paid_from, 'reference', p.reference,
                   'voided', p.voided_at is not null, 'entry_id', p.entry_id, 'created_by', p.created_by,
                   'invoices', (select string_agg(i.number, ', ' order by i.number) from public.supplier_payment_allocations a join public.supplier_invoices i on i.id = a.invoice_id where a.payment_id = p.id))
                   order by p.date desc, p.created_at desc), '[]')
                   from public.supplier_payments p where p.vendor_id = v.id and p.date between p_from and p_to),
    -- expenses (each one a document of the books): only through the books' door; the café tablet gets an empty list
    'expenses', (select case when not acct.can_read() then '[]'::jsonb else coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'date', e.date, 'description', e.description, 'account', e.account, 'account_name', a.name,
                   'amount_crc', e.amount_crc, 'iva_crc', e.iva_crc, 'paid_from', e.paid_from, 'invoice_no', e.invoice_no, 'invoice_date', e.invoice_date,
                   'voided_at', e.voided_at, 'receipt_path', e.receipt_path, 'open_crc', public._expense_open(e.id), 'entry_id', e.entry_id)
                   order by e.date desc, e.created_at desc), '[]') end
                   from public.expenses e join acct.accounts a on a.code = e.account where e.vendor_id = v.id and e.date between p_from and p_to),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', po.id, 'po_number', po.po_number, 'status', po.status, 'created_at', po.created_at, 'sent_at', po.sent_at,
                 'received_at', po.received_at, 'expected_on', po.expected_on,
                 'lines', (select count(*) from public.purchase_lines l where l.po_id = po.id),
                 'ordered_crc', (select coalesce(round(sum(l.qty * coalesce(l.unit_cost, 0)), 2), 0) from public.purchase_lines l where l.po_id = po.id),
                 'received_crc', (select coalesce(sum(r.total_crc), 0) from public.purchase_receipts r where r.po_id = po.id),
                 'invoice_no', (select string_agg(coalesce(i.number, r.invoice_no), ', ') from public.purchase_receipts r left join public.supplier_invoices i on i.id = r.invoice_id where r.po_id = po.id))
                 order by po.created_at desc), '[]')
                 from public.purchase_orders po where po.vendor_id = v.id and (po.created_at at time zone 'America/Costa_Rica')::date between p_from and p_to),
    'totals', jsonb_build_object(
      'invoiced', coalesce((select sum(i.total_crc) from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null and i.date between p_from and p_to), 0),
      'paid', coalesce((select sum(p.amount_crc) from public.supplier_payments p where p.vendor_id = v.id and p.voided_at is null and p.date between p_from and p_to), 0),
      'expenses', case when acct.can_read() then coalesce((select sum(e.amount_crc) from public.expenses e where e.vendor_id = v.id and e.voided_at is null and e.date between p_from and p_to), 0) end,
      'received', coalesce((select sum(r.total_crc) from public.purchase_receipts r where r.vendor_id = v.id
                              and (r.received_at at time zone 'America/Costa_Rica')::date between p_from and p_to), 0)));
end $$;

-- 4) compras: pedidos con sus entregas, facturas y pagos, en una lectura ------------------------------------------------
create or replace function public.purchases_list(p_from date, p_to date, p_vendor_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'vendors', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]') from public.vendors where active),
    'orders', (select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]') from (
      select jsonb_build_object('id', po.id, 'po_number', po.po_number, 'status', po.status, 'vendor_id', po.vendor_id, 'vendor', v.name,
               'created_at', po.created_at, 'sent_at', po.sent_at, 'expected_on', po.expected_on, 'received_at', po.received_at, 'by_name', po.by_name, 'note', po.note,
               'lines', (select count(*) from public.purchase_lines l where l.po_id = po.id),
               'items', (select string_agg(si.name, ', ') from (select s.name from public.purchase_lines l join public.stock_items s on s.id = l.item_id
                                                                 where l.po_id = po.id order by s.name limit 4) si),
               'ordered_crc', (select coalesce(round(sum(l.qty * coalesce(l.unit_cost, 0)), 2), 0) from public.purchase_lines l where l.po_id = po.id),
               'received_crc', (select coalesce(sum(r.total_crc), 0) from public.purchase_receipts r where r.po_id = po.id),
               'receipts', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'received_at', r.received_at, 'by_name', r.by_name, 'total_crc', r.total_crc,
                                                                         'invoice_status', r.invoice_status, 'invoice_id', r.invoice_id, 'invoice_no', r.invoice_no,
                                                                         'settled_at', r.settled_at, 'final', r.final) order by r.received_at), '[]')
                              from public.purchase_receipts r where r.po_id = po.id),
               'invoices', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'number', i.number, 'date', i.date, 'due_date', coalesce(i.due_date, i.date + coalesce(v.credit_days, 30)),
                                                                         'total_crc', i.total_crc, 'open_crc', public._invoice_open(i.id), 'voided', i.voided_at is not null)), '[]')
                              from (select distinct i.* from public.purchase_receipts r join public.supplier_invoices i on i.id = r.invoice_id where r.po_id = po.id) i),
               'paid_crc', (select coalesce(sum(a.amount_crc), 0) from public.supplier_payment_allocations a join public.supplier_payments sp on sp.id = a.payment_id
                              where sp.voided_at is null and a.invoice_id in (select r.invoice_id from public.purchase_receipts r where r.po_id = po.id and r.invoice_id is not null)),
               'stage', case when po.status = 'cancelled' then 'cancelled'
                             when not exists (select 1 from public.purchase_receipts r where r.po_id = po.id) then po.status
                             when exists (select 1 from public.purchase_receipts r where r.po_id = po.id and r.invoice_id is null) then 'received'
                             when exists (select 1 from public.purchase_receipts r join public.supplier_invoices i on i.id = r.invoice_id
                                           where r.po_id = po.id and i.voided_at is null and public._invoice_open(i.id) > 0) then 'invoiced'
                             else 'paid' end) as x
        from public.purchase_orders po left join public.vendors v on v.id = po.vendor_id
       where (po.created_at at time zone 'America/Costa_Rica')::date between p_from and p_to and (p_vendor_id is null or po.vendor_id = p_vendor_id)) q));
end $$;

-- 5) cobros por día y forma de pago, como los cuenta el asiento del día (acct.day_target) ------------------------------
create or replace function public.sales_by_method(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'days', (
    with pays as (
      select o.business_date as day,
             case when o.payment_method in ('cash_crc', 'cash_usd') then 'cash_crc' when o.payment_method = 'card' then 'card'
                  when o.payment_method = 'sinpe' then 'sinpe' else 'other' end as k,
             case when o.payment_method in ('cash_crc', 'cash_usd') and t.order_id is not null then t.crc_in - t.change_crc else o.total_crc end::numeric as amt
        from public.orders o left join public.cash_tenders t on t.order_id = o.id
       where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.payment_method <> 'pending'
      union all
      select o.business_date, 'cash_usd', round(t.usd_in * t.fx_rate, 2)
        from public.orders o join public.cash_tenders t on t.order_id = o.id
       where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and t.usd_in > 0)
    select coalesce(jsonb_agg(jsonb_build_object('day', q.day, 'cash_crc', q.cash_crc, 'cash_usd', q.cash_usd, 'card', q.card, 'sinpe', q.sinpe, 'other', q.other,
                                                 'total', q.cash_crc + q.cash_usd + q.card + q.sinpe + q.other) order by q.day), '[]')
      from (select day, coalesce(sum(amt) filter (where k = 'cash_crc'), 0) as cash_crc, coalesce(sum(amt) filter (where k = 'cash_usd'), 0) as cash_usd,
                   coalesce(sum(amt) filter (where k = 'card'), 0) as card, coalesce(sum(amt) filter (where k = 'sinpe'), 0) as sinpe,
                   coalesce(sum(amt) filter (where k = 'other'), 0) as other
              from pays group by day) q));
end $$;

-- 6) efectivo y bancos según los libros, con el último saldo del estado de cuenta ----------------------------------------
create or replace function public.cash_position()
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'as_of', public.cr_today(),
    'posted_through', (select max(e.date) from acct.entries e where e.source = 'day'),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name', a.name, 'balance', coalesce(b.bal, 0),
                   'bank', (select jsonb_build_object('id', k.id, 'name', k.name, 'bank', k.bank, 'last4', k.last4, 'currency', k.currency,
                                                      'statement_balance', s.balance, 'statement_day', s.date,
                                                      'open_lines', (select count(*) from public.bank_lines bl where bl.account_id = k.id and bl.status = 'open'))
                              from public.bank_accounts k
                              left join lateral (select bl.balance, bl.date from public.bank_lines bl where bl.account_id = k.id and bl.balance is not null
                                                  order by bl.date desc, bl.id desc limit 1) s on true
                             where k.gl_account = a.code and k.active order by k.created_at limit 1)) order by a.code), '[]')
                   from acct.accounts a left join lateral (select sum(l.debit - l.credit) as bal from acct.lines l where l.account = a.code) b on true
                  where a.cash and a.active),
    'payouts_open', (select coalesce(sum(m.amount_crc
                       - coalesce((select sum(e.amount_crc) from public.expenses e where e.payout_id = m.id and e.voided_at is null), 0)
                       - coalesce((select sum(p.amount_crc) from public.supplier_payments p where p.payout_id = m.id and p.voided_at is null), 0)), 0)
                       from public.cash_movements m where m.purpose = 'payout' and m.voided_at is null),
    'cards_to_settle', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = acct.map('pay_card')),
    'advances', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = acct.map('advances')),
    'ap', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = acct.map('ap')),
    'iva_net', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = acct.map('iva_out'))
             - (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = acct.map('iva_in')));
end $$;

-- 7) el período y el anterior en una llamada, con el estado de cada mes ----------------------------------------------------
create or replace function public._period_figures(p_from date, p_to date, p_labor boolean)
returns jsonb language sql stable security definer set search_path = public, acct as $$
  select jsonb_build_object('from', p_from, 'to', p_to,
    'gross', coalesce((select sum(o.total_crc) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)), 0),
    'net', coalesce((select round(sum(public._order_net(o)), 2) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)), 0),
    'orders', (select count(*) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null and o.refund_of is null),
    -- refunds, without IVA (already netted inside 'net'; shown as a memo), and the IVA of the period net of the IVA given back (as iva_report)
    'refunds', coalesce((select -sum(o.total_crc - coalesce(o.tax_crc, 0)) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.refund_of is not null), 0),
    'discounts', coalesce((select sum(o.discount_crc) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)), 0),
    'iva_out', coalesce((select sum(i.tax_crc) from public.order_items i join public.orders o on o.id = i.order_id
                          where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null), 0)
               + coalesce((select sum(o.tax_crc) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and o.refund_of is not null), 0),
    'cogs', coalesce((select round(-sum(mv.qty * coalesce(mv.unit_cost, 0)), 2) from public.stock_moves mv
                       where mv.kind in ('sale', 'void') and (mv.at at time zone 'America/Costa_Rica')::date between p_from and p_to), 0),
    'waste', coalesce((select round(-sum(mv.qty * coalesce(mv.unit_cost, 0)), 2) from public.stock_moves mv
                        where mv.kind = 'waste' and (mv.at at time zone 'America/Costa_Rica')::date between p_from and p_to), 0),
    'purchases', coalesce((select round(sum(mv.qty * coalesce(mv.unit_cost, 0)), 2) from public.stock_moves mv
                            where mv.kind = 'purchase' and (mv.at at time zone 'America/Costa_Rica')::date between p_from and p_to), 0),
    'expenses', coalesce((select sum(x.amt) from (
                   select e.amount_crc - e.iva_crc as amt from public.expenses e where e.voided_at is null and e.date between p_from and p_to
                   union all
                   select i.net_crc from public.supplier_invoices i where i.voided_at is null and i.account is not null and i.date between p_from and p_to) x), 0),
    'iva_in', coalesce((select sum(e.iva_crc) from public.expenses e where e.voided_at is null and e.date between p_from and p_to), 0)
            + coalesce((select sum(i.iva_crc) from public.supplier_invoices i where i.voided_at is null and i.date between p_from and p_to), 0),
    'labor', case when p_labor then (select sum((d->>'labor_crc')::numeric) from jsonb_array_elements(coalesce(public.labor_cost(p_from, p_to)->'days', '[]'::jsonb)) d) end,
    'days_with_sales', (select count(distinct o.business_date) from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)),
    'days_open', (select count(*) from public.register_days r where r.business_date between p_from and p_to and r.closed_at is null),
    'days_closed', (select count(*) from public.register_days r where r.business_date between p_from and p_to and r.closed_at is not null),
    'days_posted', (select count(distinct substring(e.source_key from 5 for 10)) from acct.entries e where e.source = 'day' and e.date between p_from and p_to),
    'books', case when acct.can_read() then (select jsonb_build_object('revenue', (r->>'revenue')::numeric, 'expenses', (r->>'expenses')::numeric, 'net_income', (r->>'net_income')::numeric)
                                               from public.acct_income_statement(p_from, p_to) r) end);
$$;
revoke all on function public._period_figures(date, date, boolean) from public, anon, authenticated;

create or replace function public.period_compare(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare len int; labor_ok boolean := public._pay_staff_allowed(); d date := public.cr_today();
begin
  if not public._insights_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  len := p_to - p_from + 1;
  return jsonb_build_object('ok', true, 'as_of', d, 'labor_visible', labor_ok, 'books_visible', acct.can_read(),
    'current', public._period_figures(p_from, p_to, labor_ok),
    'previous', public._period_figures(p_from - len, p_from - 1, labor_ok),
    -- each month of the range: empty (nothing happened), estimate (today or later, a register still open, or sales of a day the register
    -- never closed), final (every sales day closed by the register, some not posted yet), books (every closed day with something to post, posted)
    'months', (select coalesce(jsonb_agg(jsonb_build_object('month', to_char(m.a, 'YYYY-MM'), 'from', m.a, 'to', m.b,
                 'state', case when not exists (select 1 from public.orders o where o.business_date between m.a and m.b and o.voided_at is null and coalesce(o.paid, true))
                                    and not exists (select 1 from public.register_days r where r.business_date between m.a and m.b) then 'empty'
                               when m.b >= d or exists (select 1 from public.register_days r where r.business_date between m.a and m.b and r.closed_at is null)
                                    or exists (select 1 from public.orders o where o.business_date between m.a and m.b and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
                                                and not exists (select 1 from public.register_days r where r.business_date = o.business_date)) then 'estimate'
                               when exists (select 1 from public.register_days r where r.business_date between m.a and m.b and r.closed_at is not null
                                             and (exists (select 1 from public.orders o where o.business_date = r.business_date and o.voided_at is null and coalesce(o.paid, true))
                                                  or exists (select 1 from public.stock_moves sm where (sm.at at time zone 'America/Costa_Rica')::date = r.business_date))
                                             and not exists (select 1 from acct.entries e where e.source = 'day' and e.source_key like 'day:' || r.business_date || ':%')) then 'final'
                               else 'books' end) order by m.a), '[]')
                 from (select greatest(g::date, p_from) as a, least((g + interval '1 month' - interval '1 day')::date, p_to) as b
                         from generate_series(date_trunc('month', p_from)::date, date_trunc('month', p_to)::date, interval '1 month') g) m));
end $$;

-- 8) la bitácora contable --------------------------------------------------------------------------------------------------
create or replace function public.acct_audit(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'rows', (
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at, 'action', a.action, 'who', a.manager_name, 'target', a.target_id, 'summary', a.summary, 'details', a.details)
                              order by a.at desc, a.id desc), '[]')
      from (select l.* from public.audit_log l
             where (l.at at time zone 'America/Costa_Rica')::date between p_from and p_to
               and l.action in ('acct_period', 'acct_mapping_set', 'acct_account_save', 'compliance_confirm', 'setting_change', 'accountant_access',
                                'e_document_failed', 'fx_rate_set', 'tax_rate_save', 'payroll_rule_save', 'payroll_param_save', 'po_settle', 'po_pay',
                                'vendor_save', 'vendor_defaults', 'expense_schedule', 'expense_payment', 'timesheet_approve', 'timesheet_reopen')
             order by l.at desc, l.id desc limit 500) a));
end $$;

-- 9) permisos ------------------------------------------------------------------------------------------------------------
revoke all on function public.vendors_list(), public.vendor_save(jsonb), public.vendor_defaults_save(uuid, jsonb), public.vendor_history(uuid, date, date),
                       public.purchases_list(date, date, uuid), public.sales_by_method(date, date), public.cash_position(), public.period_compare(date, date),
                       public.acct_audit(date, date), public.expense_save(jsonb, uuid), public.expense_list(date, date) from public, anon;
grant execute on function public.vendors_list(), public.vendor_save(jsonb), public.vendor_defaults_save(uuid, jsonb), public.vendor_history(uuid, date, date),
                          public.purchases_list(date, date, uuid), public.sales_by_method(date, date), public.cash_position(), public.period_compare(date, date),
                          public.acct_audit(date, date), public.expense_save(jsonb, uuid), public.expense_list(date, date) to authenticated;

select canopy.migration_end(34, 'contabilidad_lecturas');
notify pgrst, 'reload schema';
