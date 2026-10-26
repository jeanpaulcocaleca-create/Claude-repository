-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0035 (Contabilidad nueva, 2 de 2: gastos que se repiten y pago de gastos a crédito)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0035 causa un problema y así lo decide el dueño, fuera del horario de atención.
--
-- Qué hace
--   * Deja como estaban en la 0034: registrar y listar gastos (sin plantillas), lo que se debe de un gasto a crédito
--     (todo su monto), la antigüedad de proveedores (ap_aging de la 0016) y los retiros de la caja (cash_payouts de la 0019).
--   * Deja cash_position como en la 0034 (no descuenta de los retiros los pagos de gastos a crédito) y expense_void como en
--     la 0014 (anula un gasto a crédito aunque tenga pagos vigentes). El interruptor expense_receipt_photos queda (sin uso).
--   * Quita las funciones nuevas: expense_pay, expense_payment_void, expense_schedule_save, expense_schedule_void,
--     expense_schedules_list, expense_due y la interna _schedule_next.
--   * Quita la 0035 del registro de migraciones (la base vuelve a la versión 34).
-- Qué NO hace: no borra las tablas expense_schedules ni expense_payments (quedan con lo que tengan, sin uso) ni las dos
--   columnas nuevas de expenses, y no borra ninguna fila. AVISO: si ya se pagó algún gasto a crédito con expense_pay, su
--   asiento (debe 2101) sigue en los libros y ap_aging vuelve a contar ese gasto por su monto completo, así que la
--   cuenta 2101 mostrará una diferencia igual a lo pagado hasta que se vuelva a aplicar la 0035.
-- Después: contabilidad.html avisa que falta la migración 0035 en Gastos (plantillas y pagos de crédito); lo demás sigue.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 35) then
    raise exception 'La migración 0035 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 35) then
    raise exception 'Hay migraciones posteriores a la 0035: revierta primero esas. No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

drop function if exists public.expense_pay(jsonb, uuid);
drop function if exists public.expense_payment_void(uuid, text);
drop function if exists public.expense_schedule_save(jsonb);
drop function if exists public.expense_schedule_void(uuid, text);
drop function if exists public.expense_schedules_list();
drop function if exists public.expense_due(int);
drop function if exists public._schedule_next(text, int, date);
drop function if exists public._expense_account_ok(text);

-- _expense_open as in 0034
create or replace function public._expense_open(p_id uuid) returns numeric language sql stable security definer set search_path = public as $$
  select case when e.paid_from = 'credit' and e.voided_at is null then e.amount_crc else 0::numeric end from public.expenses e where e.id = p_id;
$$;

-- expense_save as in 0034
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

-- expense_list as in 0034
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

-- ap_aging as in 0016
create or replace function public.ap_aging(p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare d date := coalesce(p_as_of, public.cr_today());
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'as_of', d,
    'vendor_list', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]') from public.vendors where active),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by type = 'asset', code), '[]') from acct.accounts
                  where active and not cash and type in ('expense', 'asset') and public._ap_target(code)),
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

-- cash_payouts as in 0019
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
revoke all on function public.expense_save(jsonb, uuid), public.expense_list(date, date), public.ap_aging(date), public.cash_payouts(date, date) from public, anon;
grant execute on function public.expense_save(jsonb, uuid), public.expense_list(date, date), public.ap_aging(date), public.cash_payouts(date, date) to authenticated;

-- cash_position as in 0034 (without the expense payments made with a payout)
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
-- expense_void as in 0014 (voids a credit expense even with payments standing)
create or replace function public.expense_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into x from public.expenses where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  r := public.acct_entry_reverse(x.entry_id, public.cr_today(), 'gasto anulado: ' || trim(p_reason));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  update public.expenses set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = x.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cash_position(), public.expense_void(uuid, text) from public, anon;
grant execute on function public.cash_position(), public.expense_void(uuid, text) to authenticated;

-- the switch expense_receipt_photos (canopy.setting_defs and, if the owner touched it, public.settings) stays as it is: harmless
-- without the page that reads it, and the owner's choice is not lost if the 0035 is applied again
delete from canopy.migrations where version = 35;
notify pgrst, 'reload schema';
select 'listo: la 0035 se revirtió; los gastos vuelven a la 0034 (sin plantillas ni pagos de crédito)' as resultado;
