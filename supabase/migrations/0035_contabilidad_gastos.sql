-- =====================================================================================================
-- Canopy OS · migración 0035 · Contabilidad nueva (2 de 2): gastos que se repiten y pago de los gastos a crédito
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0034. Una sola transacción.
--
-- Qué hace (rediseño de Contabilidad aprobado por el dueño el 2026-10-26, docs/CONTABILIDAD-REDISENO.md)
--   * Gastos que se repiten (alquiler, luz, internet…): una tabla de plantillas (expense_schedules) con el proveedor, la
--     cuenta, el monto, el IVA, la forma de pago y cada cuánto vence. NUNCA se asienta nada solo: la página avisa «vence
--     esta semana», prellena «Nuevo gasto» y una persona lo confirma. Cada registro lleva un id determinista (plantilla +
--     período + intento), así un doble toque no duplica y un gasto anulado sí se puede volver a registrar.
--   * Gastos a crédito: hasta hoy un gasto «a crédito» (2101, cuentas por pagar) no se podía pagar desde su pantalla
--     (D-037). Ahora expense_pay registra el pago (debe 2101, haber la cuenta de donde salió el dinero) y lo guarda en
--     expense_payments, conservando el gasto con su comprobante, su categoría y su historial; la antigüedad de
--     proveedores (ap_aging) descuenta lo pagado, así la cuenta 2101 sigue cuadrando con los documentos. No se crea una
--     segunda cuenta por pagar: el pago va contra la misma 2101 que el gasto acreditó.
--   * Los retiros de la caja (1104) cuentan también los pagos de gastos a crédito hechos con ese dinero.
-- Quién: dueño con el código del teléfono o contador (la regla de la 0034). Todo queda en la bitácora.
-- Qué NO cambia: los gastos ya registrados, los asientos, los cierres, el IVA ni las facturas de proveedor. Las dos tablas
--   nuevas nacen vacías; a expenses solo se le agregan dos columnas opcionales (schedule_id, period_key).
-- Qué ve una página anterior: accounting.html sigue igual; los pagos de gastos a crédito solo se ven en la página nueva.
-- Cuándo: fuera del horario de atención, junto con la 0034 o después.
-- Reversión: supabase/tools/reversion-0035.sql (vuelve a las funciones de la 0034 y quita las nuevas; las tablas y columnas
--   quedan, con lo que tengan).
-- =====================================================================================================
select canopy.migration_begin(35, 'contabilidad_gastos');
set local lock_timeout = '8s';

-- 1) tablas ---------------------------------------------------------------------------------------------------------------
create table if not exists public.expense_schedules (
  id           uuid primary key default gen_random_uuid(),
  vendor_id    uuid references public.vendors(id),
  description  text not null,
  account      text not null,
  amount_crc   numeric(14,2) not null check (amount_crc > 0),
  iva_crc      numeric(14,2) not null default 0 check (iva_crc >= 0),
  paid_from    text not null check (paid_from in ('cash', 'petty', 'bank', 'credit', 'payout')),
  every        text not null check (every in ('week', 'month')),
  day_of       int not null check (day_of between 1 and 31),     -- week: 1 = lunes … 7 = domingo; month: día del mes (se recorta al último día)
  next_due     date not null,
  active       boolean not null default true,
  created_by   text not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  location_id  uuid not null default '10ca7100-0000-4000-8000-000000000001' references public.locations(id),
  check (iva_crc < amount_crc)
);
alter table public.expense_schedules enable row level security;
revoke all on public.expense_schedules from anon, authenticated;

create table if not exists public.expense_payments (
  id            uuid primary key,                      -- the page's request id
  expense_id    uuid not null references public.expenses(id),
  date          date not null,
  amount_crc    numeric(14,2) not null check (amount_crc > 0),
  paid_from     text not null check (paid_from in ('cash', 'petty', 'bank', 'payout', 'card_debit', 'card_credit')),
  reference     text,
  payout_id     uuid references public.cash_movements(id),
  entry_id      bigint,
  void_entry_id bigint,
  voided_at     timestamptz,
  void_reason   text,
  created_at    timestamptz not null default now(),
  created_by    text not null
);
create index if not exists expense_payments_expense_idx on public.expense_payments (expense_id);
alter table public.expense_payments enable row level security;
revoke all on public.expense_payments from anon, authenticated;

alter table public.expenses add column if not exists schedule_id uuid references public.expense_schedules(id);
alter table public.expenses add column if not exists period_key text;
create index if not exists expenses_schedule_idx on public.expenses (schedule_id, period_key) where schedule_id is not null;

-- the backup account reads the new tables too (it already has the default privileges of 0013 on acct; public is explicit)
grant select on public.expense_schedules, public.expense_payments to canopy_backup;

-- 2) lo que todavía se debe de un gasto a crédito -------------------------------------------------------------------------
create or replace function public._expense_open(p_id uuid) returns numeric language sql stable security definer set search_path = public as $$
  select case when e.paid_from = 'credit' and e.voided_at is null
              then e.amount_crc - coalesce((select sum(p.amount_crc) from public.expense_payments p where p.expense_id = e.id and p.voided_at is null), 0)
              else 0::numeric end
    from public.expenses e where e.id = p_id;
$$;

-- 3) la próxima fecha de una plantilla, estrictamente después de p_after -------------------------------------------------
-- the accounts the day entry posts by itself (cash differences, waste, counts and adjustments, price differences): never typed by hand
create or replace function public._expense_account_ok(p_code text)
returns boolean language sql stable security definer set search_path = public, acct as $$
  select exists (select 1 from acct.accounts a where a.code = p_code and a.active and a.type = 'expense')
     and not exists (select 1 from acct.mappings m where m.account = p_code and m.key in ('cash_over_short', 'waste', 'stock_adjust', 'price_variance'));
$$;
revoke all on function public._expense_account_ok(text) from public, anon, authenticated;

create or replace function public._schedule_next(p_every text, p_day_of int, p_after date)
returns date language plpgsql immutable set search_path = pg_catalog as $$
declare c date; m date;
begin
  if p_every = 'week' then
    return p_after + ((p_day_of - extract(isodow from p_after)::int + 6) % 7 + 1);
  end if;
  m := date_trunc('month', p_after)::date;
  c := m + (least(p_day_of, extract(day from (m + interval '1 month' - interval '1 day'))::int) - 1);
  if c > p_after then return c; end if;
  m := (m + interval '1 month')::date;
  return m + (least(p_day_of, extract(day from (m + interval '1 month' - interval '1 day'))::int) - 1);
end $$;
revoke all on function public._schedule_next(text, int, date) from public, anon, authenticated;

-- 4) registrar un gasto: igual que en la 0034, más la plantilla de la que viene -------------------------------------------
create or replace function public.expense_save(p_expense jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; a acct.accounts; amt numeric; iva numeric; src text; inv text; vid uuid; vname text; eid bigint; who text; po uuid;
        v_acc text; v_src text; v_rate numeric; acc text; descr text; sch public.expense_schedules; pk text;
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
  -- a scheduled bill: the template must exist and be active, and the request names the period it covers
  if nullif(p_expense->>'schedule_id', '') is not null then
    if p_expense->>'schedule_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return jsonb_build_object('ok', false, 'error', 'bad_schedule'); end if;
    select * into sch from public.expense_schedules where id = (p_expense->>'schedule_id')::uuid for update;
    pk := nullif(p_expense->>'period_key', '');
    -- the period is the one the reminder offered (its due date): a client cannot move the template forward or backward
    if sch.id is null or not sch.active or pk is null or pk <> sch.next_due::text then return jsonb_build_object('ok', false, 'error', 'bad_schedule'); end if;
  end if;
  -- what the request does not say comes from the supplier's confirmed habits; nothing is guessed
  acc := coalesce(nullif(p_expense->>'account', ''), v_acc);
  if acc is null then return jsonb_build_object('ok', false, 'error', 'needs_account'); end if;
  select * into a from acct.accounts where code = acc;
  if a.code is null or not public._expense_account_ok(a.code) then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  src := coalesce(nullif(p_expense->>'paid_from', ''), v_src);
  if src is null then return jsonb_build_object('ok', false, 'error', 'needs_paid_from'); end if;
  if nullif(p_expense->>'iva_crc', '') is not null then iva := round((p_expense->>'iva_crc')::numeric, 2);
  elsif v_rate is not null and amt is not null then iva := round(amt - amt / (1 + v_rate), 2);
  else return jsonb_build_object('ok', false, 'error', 'needs_iva'); end if;
  descr := coalesce(nullif(left(trim(coalesce(p_expense->>'description', '')), 200), ''), vname);
  po := nullif(p_expense->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if amt is null or amt = 'NaN' or iva = 'NaN' or amt <= 0 or iva < 0 or iva >= amt or src not in ('cash', 'petty', 'bank', 'credit', 'payout')
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
    if sqlerrm ~ 'unknown_account' then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
    raise;
  end;
  insert into public.expenses (id, date, vendor_id, vendor_name, description, account, amount_crc, iva_crc, paid_from, invoice_no, invoice_date, entry_id, created_by, payout_id,
                               schedule_id, period_key)
    values (p_request_id, (p_expense->>'date')::date, vid, vname, descr, a.code, amt, iva, src, inv,
            nullif(p_expense->>'invoice_date', '')::date, eid, who, case when src = 'payout' then po end, sch.id, pk);
  -- the template moves on to the next due date (a person confirmed this one; nothing is ever posted on its own)
  if sch.id is not null then
    update public.expense_schedules set next_due = public._schedule_next(every, day_of, next_due), updated_at = now() where id = sch.id;
  end if;
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid, 'account', a.code, 'paid_from', src, 'iva_crc', iva,
                            'next_due', (select next_due from public.expense_schedules where id = sch.id));
end $$;

create or replace function public.expense_list(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._expense_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'expenses', (
    select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('account_name', a.name, 'open_crc', public._expense_open(e.id),
             'paid_crc', coalesce((select sum(p.amount_crc) from public.expense_payments p where p.expense_id = e.id and p.voided_at is null), 0),
             'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'date', p.date, 'amount_crc', p.amount_crc, 'paid_from', p.paid_from, 'reference', p.reference,
                                                                        'voided_at', p.voided_at, 'void_reason', p.void_reason, 'entry_id', p.entry_id) order by p.date, p.created_at), '[]')
                            from public.expense_payments p where p.expense_id = e.id))
           order by e.date desc, e.created_at desc), '[]')
      from public.expenses e join acct.accounts a on a.code = e.account where e.date between p_from and p_to),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where type = 'expense' and active));
end $$;

-- 5) pagar un gasto a crédito ---------------------------------------------------------------------------------------------
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

create or replace function public.expense_payment_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare p public.expense_payments; r jsonb;
begin
  if not public._expense_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into p from public.expense_payments where id = p_id for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  r := public.acct_entry_reverse(p.entry_id, public.cr_today(), 'pago de gasto anulado: ' || trim(p_reason));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  update public.expense_payments set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('expense_payment', null, acct.actor(), p.expense_id::text, 'pago anulado: ' || left(trim(p_reason), 200), jsonb_build_object('payment_id', p.id, 'amount_crc', p.amount_crc));
  return jsonb_build_object('ok', true);
end $$;

-- 6) gastos que se repiten: plantillas, lo que vence, nunca un asiento solo ----------------------------------------------
create or replace function public.expense_schedule_save(p_schedule jsonb)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare s public.expense_schedules; sid uuid; vid uuid; vname text; acc text; amt numeric; iva numeric; src text; ev text; dof int; nd date; descr text;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  sid := nullif(p_schedule->>'id', '')::uuid;
  if sid is not null then
    select * into s from public.expense_schedules where id = sid for update;
    if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  vid := nullif(p_schedule->>'vendor_id', '')::uuid;
  if vid is not null then
    select name into vname from public.vendors where id = vid;
    if vname is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  end if;
  acc := nullif(p_schedule->>'account', ''); amt := round(nullif(p_schedule->>'amount_crc', '')::numeric, 2);
  iva := round(coalesce(nullif(p_schedule->>'iva_crc', '')::numeric, 0), 2); src := nullif(p_schedule->>'paid_from', '');
  ev := nullif(p_schedule->>'every', ''); dof := nullif(p_schedule->>'day_of', '')::int;
  descr := coalesce(nullif(left(trim(coalesce(p_schedule->>'description', '')), 200), ''), vname);
  if not public._expense_account_ok(acc) then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  if amt is null or amt = 'NaN' or iva = 'NaN' or amt <= 0 or iva < 0 or iva >= amt or src is null or src not in ('cash', 'petty', 'bank', 'credit', 'payout') or descr is null
     or ev is null or ev not in ('week', 'month') or dof is null or dof < 1 or dof > (case when ev = 'week' then 7 else 31 end) then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  nd := nullif(p_schedule->>'next_due', '')::date;
  -- without a date (a template born from the bill just paid): the next occurrence strictly after today, never today again
  if nd is null or nd < public.cr_today() then nd := public._schedule_next(ev, dof, public.cr_today()); end if;
  if sid is null then
    insert into public.expense_schedules (vendor_id, description, account, amount_crc, iva_crc, paid_from, every, day_of, next_due, active, created_by)
      values (vid, descr, acc, amt, iva, src, ev, dof, nd, coalesce((p_schedule->>'active')::boolean, true), acct.actor()) returning id into sid;
  else
    update public.expense_schedules set vendor_id = vid, description = descr, account = acc, amount_crc = amt, iva_crc = iva, paid_from = src, every = ev, day_of = dof,
           next_due = nd, active = coalesce((p_schedule->>'active')::boolean, s.active), updated_at = now() where id = sid;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('expense_schedule', null, acct.actor(), sid::text, (case when s.id is null then 'plantilla nueva: ' else 'plantilla cambiada: ' end) || descr || ' · ' || amt || ' · cada ' || ev,
            jsonb_build_object('before', case when s.id is null then null else jsonb_build_object('amount_crc', s.amount_crc, 'account', s.account, 'paid_from', s.paid_from, 'every', s.every, 'day_of', s.day_of, 'active', s.active) end));
  return jsonb_build_object('ok', true, 'id', sid, 'next_due', nd);
end $$;

create or replace function public.expense_schedule_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare s public.expense_schedules;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into s from public.expense_schedules where id = p_id for update;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not s.active then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  update public.expense_schedules set active = false, updated_at = now() where id = s.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('expense_schedule', null, acct.actor(), s.id::text, 'plantilla desactivada: ' || s.description || ' · ' || left(trim(p_reason), 200), '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.expense_schedules_list()
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'as_of', public.cr_today(), 'schedules', (
    select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'vendor_id', s.vendor_id, 'vendor', v.name, 'description', s.description, 'account', s.account, 'account_name', a.name,
             'amount_crc', s.amount_crc, 'iva_crc', s.iva_crc, 'paid_from', s.paid_from, 'every', s.every, 'day_of', s.day_of, 'next_due', s.next_due, 'active', s.active,
             'created_by', s.created_by, 'created_at', s.created_at,
             'last_registered', (select max(e.date) from public.expenses e where e.schedule_id = s.id and e.voided_at is null),
             'registered', (select count(*) from public.expenses e where e.schedule_id = s.id and e.voided_at is null))
           order by s.active desc, s.next_due, s.description), '[]')
      from public.expense_schedules s left join public.vendors v on v.id = s.vendor_id left join acct.accounts a on a.code = s.account));
end $$;

-- what is due within p_days (and what is overdue), each with the request id its registration must use
create or replace function public.expense_due(p_days int default 7)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare d date := public.cr_today();
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'as_of', d, 'days', least(greatest(coalesce(p_days, 7), 0), 60), 'due', (
    select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'vendor_id', s.vendor_id, 'vendor', v.name, 'description', s.description, 'account', s.account, 'account_name', a.name,
             'amount_crc', s.amount_crc, 'iva_crc', s.iva_crc, 'paid_from', s.paid_from, 'every', s.every, 'next_due', s.next_due, 'overdue', s.next_due < d,
             'period_key', s.next_due::text,
             'request_id', md5(s.id::text || ':' || s.next_due::text || ':' ||
                               (1 + (select count(*) from public.expenses e where e.schedule_id = s.id and e.period_key = s.next_due::text))::text)::uuid)
           order by s.next_due, s.description), '[]')
      from public.expense_schedules s left join public.vendors v on v.id = s.vendor_id left join acct.accounts a on a.code = s.account
     where s.active and s.next_due <= d + least(greatest(coalesce(p_days, 7), 0), 60)));
end $$;

-- 7) la antigüedad de proveedores descuenta los pagos de gastos a crédito (la 2101 sigue cuadrando) ----------------------
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
      'expenses_on_credit', (select coalesce(sum(e.amount_crc), 0) from public.expenses e where e.paid_from = 'credit' and e.voided_at is null and e.date <= d)
                          - (select coalesce(sum(p.amount_crc), 0) from public.expense_payments p join public.expenses e on e.id = p.expense_id
                              where p.voided_at is null and e.voided_at is null and p.date <= d)));
end $$;

-- 8) los retiros de la caja cuentan también los pagos de gastos a crédito hechos con ese dinero ----------------------------
create or replace function public.cash_payouts(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'payouts', (
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'date', m.business_date, 'at', m.at, 'currency', m.currency, 'amount', m.amount,
             'amount_crc', m.amount_crc, 'reason', m.reason, 'staff_name', m.staff_name,
             'documented_crc', coalesce((select sum(e.amount_crc) from public.expenses e where e.payout_id = m.id and e.voided_at is null), 0)
                             + coalesce((select sum(p.amount_crc) from public.supplier_payments p where p.payout_id = m.id and p.voided_at is null), 0)
                             + coalesce((select sum(x.amount_crc) from public.expense_payments x where x.payout_id = m.id and x.voided_at is null), 0))
           order by m.at desc), '[]')
      from public.cash_movements m
     where m.purpose = 'payout' and m.voided_at is null and m.business_date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, public.cr_today())));
end $$;

-- 9) la posición de efectivo descuenta de cada retiro también los pagos de gastos a crédito hechos con él (cash_position de la 0034 + una línea)
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
                       - coalesce((select sum(p.amount_crc) from public.supplier_payments p where p.payout_id = m.id and p.voided_at is null), 0)
                       - coalesce((select sum(x.amount_crc) from public.expense_payments x where x.payout_id = m.id and x.voided_at is null), 0)), 0)
                       from public.cash_movements m where m.purpose = 'payout' and m.voided_at is null),
    'cards_to_settle', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = acct.map('pay_card')),
    'advances', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = acct.map('advances')),
    'ap', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = acct.map('ap')),
    'iva_net', (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = acct.map('iva_out'))
             - (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = acct.map('iva_in')));
end $$;

-- 10) anular un gasto a crédito con pagos vigentes: primero se anulan los pagos (como supplier_invoice_void), así 2101 sigue cuadrando
create or replace function public.expense_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into x from public.expenses where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  -- a credit expense with payments standing is not voided: void (reverse) its payments first, so 2101 stays tied out
  if exists (select 1 from public.expense_payments p where p.expense_id = x.id and p.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'has_payments'); end if;
  r := public.acct_entry_reverse(x.entry_id, public.cr_today(), 'gasto anulado: ' || trim(p_reason));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  update public.expenses set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = x.id;
  -- a bill registered from a reminder and then voided: the reminder offers that period again (a new deterministic id, attempt 2)
  if x.schedule_id is not null and x.period_key ~ '^\d{4}-\d{2}-\d{2}$' then
    update public.expense_schedules set next_due = least(next_due, x.period_key::date), updated_at = now() where id = x.schedule_id and active;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 11) interruptor: fotos de recibos desde la página nueva (apagado hasta verificar el respaldo de los archivos privados, E-17) ----
-- contabilidad.html muestra «Tomar foto» y «Adjuntar» solo con este ajuste en true; accounting.html no cambia.
insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('expense_receipt_photos', 'boolean', null, 'false', null,
   'Fotos y archivos de recibos desde la página nueva de Contabilidad. Actívelo cuando el respaldo de los archivos privados (E-17) esté verificado; mientras tanto los recibos se adjuntan desde la página anterior.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value, guard = excluded.guard, description = excluded.description;

-- 12) permisos -----------------------------------------------------------------------------------------------------------
revoke all on function public.expense_save(jsonb, uuid), public.expense_list(date, date), public.expense_pay(jsonb, uuid), public.expense_payment_void(uuid, text),
                       public.expense_schedule_save(jsonb), public.expense_schedule_void(uuid, text), public.expense_schedules_list(), public.expense_due(int),
                       public.ap_aging(date), public.cash_payouts(date, date), public.cash_position(), public.expense_void(uuid, text) from public, anon;
grant execute on function public.expense_save(jsonb, uuid), public.expense_list(date, date), public.expense_pay(jsonb, uuid), public.expense_payment_void(uuid, text),
                          public.expense_schedule_save(jsonb), public.expense_schedule_void(uuid, text), public.expense_schedules_list(), public.expense_due(int),
                          public.ap_aging(date), public.cash_payouts(date, date), public.cash_position(), public.expense_void(uuid, text) to authenticated;

select canopy.migration_end(35, 'contabilidad_gastos');
notify pgrst, 'reload schema';
