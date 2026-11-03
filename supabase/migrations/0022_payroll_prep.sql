-- =====================================================================================================
-- Canopy OS · migración 0022 · Preparación de la planilla, costo de mano de obra, asiento revisado por el contador
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0021.
--
-- Qué hace
--   * public.staff_pay: lo que gana cada persona, por hora o un monto fijo por periodo, desde una fecha (el
--     historial queda). Solo el dueño (con el código del teléfono) y el contador lo ven y lo cambian.
--   * public.payroll_rules: las cargas y deducciones (por ejemplo, las de la CCSS) con su porcentaje. El
--     sistema NO trae ninguna: cada una se registra con quién la confirmó y el documento (DEPENDENCIES A-08).
--     Sin reglas confirmadas, la planilla solo calcula el bruto.
--   * Planilla de un periodo aprobado: horas aprobadas × tarifa (o el monto fijo), deducciones y cargas de
--     las reglas confirmadas, otras deducciones que el contador escribe (retención del impuesto, adelantos),
--     neto. El contador la revisa; luego se asienta (salarios y cargas contra lo que se debe pagar) y se
--     registra el pago. Una planilla asentada no se cambia.
--   * labor_cost: costo estimado de la mano de obra por día contra las ventas sin IVA (porcentaje).
-- Qué cambia para el personal: nada.
-- Reversión: drop function payroll_* (las tablas y los asientos quedan).
-- =====================================================================================================
select canopy.migration_begin(22, 'payroll_prep');

insert into acct.accounts (code, name, type, cash, system) values
  ('2132', 'Retenciones y otras deducciones de planilla por pagar', 'liability', false, true)
on conflict (code) do nothing;
insert into acct.mappings (key, account, label) values
  ('payroll_gross', '6101', 'Salarios brutos'),
  ('payroll_employer', '6102', 'Cargas sociales del patrono'),
  ('payroll_social', '2131', 'Cargas y deducciones de ley por pagar'),
  ('payroll_withheld', '2132', 'Otras deducciones de planilla por pagar'),
  ('payroll_net', '2130', 'Salarios netos por pagar')
on conflict (key) do nothing;

create table if not exists public.staff_pay (
  id             uuid primary key default gen_random_uuid(),
  staff_id       uuid not null references public.staff(id),
  kind           text not null check (kind in ('hourly', 'period')),
  rate_crc       numeric(12,2) not null check (rate_crc > 0),
  effective_from date not null,
  created_by     text not null,
  created_at     timestamptz not null default now(),
  unique (staff_id, effective_from)
);
create table if not exists public.payroll_rules (
  code         text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name         text not null,
  kind         text not null check (kind in ('employee', 'employer')),   -- taken from the pay, or paid on top by the business
  pct          numeric(6,3) not null check (pct >= 0 and pct < 50),
  active       boolean not null default true,
  confirmed_by text not null,
  reference    text not null,
  updated_at   timestamptz not null default now()
);
create table if not exists public.payroll_runs (
  id           uuid primary key default gen_random_uuid(),
  period_id    uuid not null unique references public.pay_periods(id),
  status       text not null default 'draft' check (status in ('draft', 'reviewed', 'posted', 'paid')),
  rules        jsonb not null default '[]',            -- the confirmed rules used, as they were
  prepared_by  text not null,
  prepared_at  timestamptz not null default now(),
  reviewed_by  text,
  reviewed_at  timestamptz,
  entry_id     bigint,
  pay_entry_id bigint
);
create table if not exists public.payroll_lines (
  run_id         uuid not null references public.payroll_runs(id),
  staff_id       uuid not null,
  staff_name     text not null,
  hours          numeric(8,2) not null default 0,
  pay_kind       text,
  rate_crc       numeric(12,2),
  gross_crc      numeric(14,2),
  deductions     jsonb not null default '[]',
  deductions_crc numeric(14,2) not null default 0,
  other_crc      numeric(14,2) not null default 0 check (other_crc >= 0),
  other_note     text,
  employer       jsonb not null default '[]',
  employer_crc   numeric(14,2) not null default 0,
  net_crc        numeric(14,2),
  primary key (run_id, staff_id)
);
alter table public.staff_pay enable row level security;
alter table public.payroll_rules enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_lines enable row level security;
revoke all on public.staff_pay, public.payroll_rules, public.payroll_runs, public.payroll_lines from anon, authenticated;

create or replace function public._pay_actor() returns text language sql stable security definer set search_path = public, acct as $$
  select case when public.account_kind() = 'accountant' then acct.actor() else public._owner_label() end;
$$;
revoke all on function public._pay_actor() from public, anon, authenticated;

-- 1) pay rates and confirmed rules ---------------------------------------------------------------------------------
create or replace function public.payroll_staff()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true,
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role, 'active', s.active,
                'pay', (select jsonb_build_object('kind', p.kind, 'rate_crc', p.rate_crc, 'effective_from', p.effective_from)
                          from public.staff_pay p where p.staff_id = s.id and p.effective_from <= public.cr_today() order by p.effective_from desc limit 1),
                'next', (select jsonb_build_object('kind', p.kind, 'rate_crc', p.rate_crc, 'effective_from', p.effective_from)
                          from public.staff_pay p where p.staff_id = s.id and p.effective_from > public.cr_today() order by p.effective_from limit 1))
              order by s.active desc, s.name), '[]') from public.staff s),
    'rules', (select coalesce(jsonb_agg(to_jsonb(r) order by r.kind, r.code), '[]') from public.payroll_rules r));
end $$;

create or replace function public.staff_pay_set(p_staff_id uuid, p_kind text, p_rate numeric, p_from date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from public.staff where id = p_staff_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_kind not in ('hourly', 'period') or p_rate is null or p_rate <= 0 or p_from is null then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  -- a rate already used by a posted payroll stays: a change starts after that period
  if exists (select 1 from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods p on p.id = r.period_id
              where l.staff_id = p_staff_id and r.status in ('posted', 'paid') and p.ends_on >= p_from) then
    return jsonb_build_object('ok', false, 'error', 'used_by_payroll'); end if;
  insert into public.staff_pay (staff_id, kind, rate_crc, effective_from, created_by)
    values (p_staff_id, p_kind, round(p_rate, 2), p_from, public._pay_actor())
    on conflict (staff_id, effective_from) do update set kind = excluded.kind, rate_crc = excluded.rate_crc, created_by = excluded.created_by, created_at = now();
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('staff_pay_set', null, public._pay_actor(), p_staff_id::text, 'tarifa desde ' || p_from,
            jsonb_build_object('kind', p_kind, 'rate_crc', p_rate, 'effective_from', p_from));
  return jsonb_build_object('ok', true);
end $$;

-- a rule is saved only with who confirmed it and the document: nothing is assumed
create or replace function public.payroll_rule_save(p_rule jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c text := lower(trim(coalesce(p_rule->>'code', ''))); pct numeric := nullif(p_rule->>'pct', '')::numeric;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_rule->>'confirmed_by'), '') = '' or coalesce(trim(p_rule->>'reference'), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_reference'); end if;
  if c !~ '^[a-z0-9_]{2,30}$' or coalesce(trim(p_rule->>'name'), '') = '' or p_rule->>'kind' not in ('employee', 'employer') or pct is null or pct < 0 or pct >= 50 then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  insert into public.payroll_rules (code, name, kind, pct, active, confirmed_by, reference)
    values (c, left(trim(p_rule->>'name'), 80), p_rule->>'kind', pct, coalesce((p_rule->>'active')::boolean, true), left(trim(p_rule->>'confirmed_by'), 80), left(trim(p_rule->>'reference'), 120))
    on conflict (code) do update set name = excluded.name, kind = excluded.kind, pct = excluded.pct, active = excluded.active,
                                     confirmed_by = excluded.confirmed_by, reference = excluded.reference, updated_at = now();
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('payroll_rule_save', null, public._pay_actor(), c, left(trim(p_rule->>'name'), 80) || ' ' || pct || ' %', p_rule);
  return jsonb_build_object('ok', true);
end $$;

-- 2) the payroll of an approved period ------------------------------------------------------------------------------
create or replace function public.payroll_prepare(p_period_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pay_periods; r public.payroll_runs; v_rules jsonb;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into p from public.pay_periods where id = p_period_id;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status = 'open' then return jsonb_build_object('ok', false, 'error', 'not_approved'); end if;
  select * into r from public.payroll_runs where period_id = p.id for update;
  if r.id is not null and r.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.kind, x.code), '[]') into v_rules from public.payroll_rules x where x.active;
  if r.id is null then
    insert into public.payroll_runs (period_id, rules, prepared_by) values (p.id, v_rules, public._pay_actor()) returning * into r;
  else
    update public.payroll_runs set rules = v_rules, prepared_by = public._pay_actor(), prepared_at = now() where id = r.id;
    delete from public.payroll_lines where run_id = r.id;          -- a draft is worked out again from the approved hours
  end if;
  with h as (       -- the hours as approved (the latest approval of the period)
    select staff_id, staff_name, hours from public.pay_period_hours
     where period_id = p.id and approved_at = (select max(approved_at) from public.pay_period_hours where period_id = p.id)),
  pay as (
    select s.id as staff_id, s.name, coalesce(h.hours, 0) as hours,
           (select x from public.staff_pay x where x.staff_id = s.id and x.effective_from <= p.ends_on order by x.effective_from desc limit 1) as sp
      from public.staff s left join h on h.staff_id = s.id
     where h.staff_id is not null
        or exists (select 1 from public.staff_pay x where x.staff_id = s.id and x.kind = 'period' and x.effective_from <= p.ends_on and s.active)),
  g as (
    select staff_id, name, hours, (sp).kind as kind, (sp).rate_crc as rate,
           case when (sp).kind = 'hourly' then round(hours * (sp).rate_crc, 2) when (sp).kind = 'period' then (sp).rate_crc end as gross
      from pay)
  insert into public.payroll_lines (run_id, staff_id, staff_name, hours, pay_kind, rate_crc, gross_crc, deductions, deductions_crc, employer, employer_crc, net_crc)
    select r.id, g.staff_id, g.name, g.hours, g.kind, g.rate, g.gross,
           coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'name', x->>'name', 'pct', (x->>'pct')::numeric,
                                                         'amount', round(g.gross * (x->>'pct')::numeric / 100, 2)))
                       from jsonb_array_elements(v_rules) x where x->>'kind' = 'employee' and g.gross is not null), '[]'),
           coalesce((select sum(round(g.gross * (x->>'pct')::numeric / 100, 2)) from jsonb_array_elements(v_rules) x where x->>'kind' = 'employee'), 0),
           coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'name', x->>'name', 'pct', (x->>'pct')::numeric,
                                                         'amount', round(g.gross * (x->>'pct')::numeric / 100, 2)))
                       from jsonb_array_elements(v_rules) x where x->>'kind' = 'employer' and g.gross is not null), '[]'),
           coalesce((select sum(round(g.gross * (x->>'pct')::numeric / 100, 2)) from jsonb_array_elements(v_rules) x where x->>'kind' = 'employer'), 0),
           null
      from g;
  update public.payroll_lines set net_crc = gross_crc - deductions_crc - other_crc where run_id = r.id and gross_crc is not null;
  return jsonb_build_object('ok', true, 'run_id', r.id);
end $$;

create or replace function public.payroll_adjust(p_run_id uuid, p_staff_id uuid, p_other numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.payroll_lines;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from public.payroll_runs where id = p_run_id and status = 'draft') then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  select * into l from public.payroll_lines where run_id = p_run_id and staff_id = p_staff_id for update;
  if l.run_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_other is null or p_other < 0 or (l.gross_crc is not null and p_other > l.gross_crc - l.deductions_crc) then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if p_other > 0 and coalesce(trim(p_note), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  update public.payroll_lines set other_crc = round(p_other, 2), other_note = nullif(left(trim(coalesce(p_note, '')), 120), ''),
         net_crc = case when gross_crc is not null then gross_crc - deductions_crc - round(p_other, 2) end
   where run_id = p_run_id and staff_id = p_staff_id;
  return jsonb_build_object('ok', true);
end $$;

-- the accountant reviews; the review is undone by preparing it again
create or replace function public.payroll_review(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs;
begin
  if public.account_kind() <> 'accountant' then return jsonb_build_object('ok', false, 'error', 'accountant_only'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and gross_crc is null) then return jsonb_build_object('ok', false, 'error', 'missing_rates'); end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id) then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  update public.payroll_runs set status = 'reviewed', reviewed_by = acct.actor(), reviewed_at = now() where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.payroll_reopen(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  update public.payroll_runs set status = 'draft', reviewed_by = null, reviewed_at = null where id = p_run_id and status = 'reviewed';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_reviewed'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- posted on the period's last day: salaries and the employer's charges against what is owed
create or replace function public.payroll_post(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs; p public.pay_periods; g numeric; e numeric; d numeric; o numeric; n numeric; eid bigint;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'reviewed' then return jsonb_build_object('ok', false, 'error', 'not_reviewed'); end if;
  select * into p from public.pay_periods where id = r.period_id;
  select sum(gross_crc), sum(employer_crc), sum(deductions_crc), sum(other_crc), sum(net_crc) into g, e, d, o, n from public.payroll_lines where run_id = r.id;
  begin
    eid := acct.post(p.ends_on, 'Planilla del ' || to_char(p.starts_on, 'DD/MM') || ' al ' || to_char(p.ends_on, 'DD/MM/YYYY'), 'payroll', 'payroll:' || r.id,
             jsonb_build_array(jsonb_build_object('account', acct.map('payroll_gross'), 'debit', g),
                               jsonb_build_object('account', acct.map('payroll_employer'), 'debit', e),
                               jsonb_build_object('account', acct.map('payroll_social'), 'credit', d + e),
                               jsonb_build_object('account', acct.map('payroll_withheld'), 'credit', o),
                               jsonb_build_object('account', acct.map('payroll_net'), 'credit', n)),
             null, public._pay_actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  update public.payroll_runs set status = 'posted', entry_id = eid where id = r.id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

create or replace function public.payroll_pay(p_run_id uuid, p_paid_from text, p_date date)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs; n numeric; eid bigint;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'posted' then return jsonb_build_object('ok', false, 'error', 'not_posted'); end if;
  if p_paid_from not in ('bank', 'cash', 'petty') or p_date is null or p_date > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select sum(net_crc) into n from public.payroll_lines where run_id = r.id;
  begin
    eid := acct.post(p_date, 'Pago de la planilla', 'payroll', 'payroll-pay:' || r.id,
             jsonb_build_array(jsonb_build_object('account', acct.map('payroll_net'), 'debit', n),
                               jsonb_build_object('account', acct.map(case p_paid_from when 'bank' then 'from_bank' when 'cash' then 'from_cash' else 'from_petty' end), 'credit', n)),
             null, public._pay_actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  update public.payroll_runs set status = 'paid', pay_entry_id = eid where id = r.id;
  update public.pay_periods set status = 'paid' where id = r.period_id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

create or replace function public.payroll_get(p_period_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where period_id = p_period_id;
  if r.id is null then return jsonb_build_object('ok', true, 'run', null); end if;
  return jsonb_build_object('ok', true, 'run', to_jsonb(r),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.staff_name), '[]') from public.payroll_lines l where l.run_id = r.id),
    'totals', (select jsonb_build_object('hours', sum(hours), 'gross', sum(gross_crc), 'deductions', sum(deductions_crc), 'other', sum(other_crc),
                                         'employer', sum(employer_crc), 'net', sum(net_crc)) from public.payroll_lines where run_id = r.id));
end $$;

-- 3) labor cost against sales, by day (an estimate: hours × today's rates; fixed pay spread over its period) --------
create or replace function public.labor_cost(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'days', (
    with days as (select d::date as day from generate_series(p_from, p_to, interval '1 day') d),
    shifts as (
      select public._shift_day(te.clock_in) as day, te.staff_id, extract(epoch from (te.clock_out - te.clock_in)) / 3600 as h
        from public.time_entries te where te.clock_out is not null and public._shift_day(te.clock_in) between p_from and p_to),
    hourly as (
      select s.day, sum(s.h) as hours,
             sum(s.h * (select x.rate_crc from public.staff_pay x where x.staff_id = s.staff_id and x.kind = 'hourly' and x.effective_from <= s.day
                          order by x.effective_from desc limit 1)) as cost,
             bool_or(not exists (select 1 from public.staff_pay x where x.staff_id = s.staff_id and x.effective_from <= s.day)) as missing
        from shifts s group by s.day),
    fixed as (     -- a fixed pay per period, spread evenly over the days of the pay period that holds the day
      select dd.day, sum(x.rate_crc / (pp.ends_on - pp.starts_on + 1)) as cost
        from days dd join public.pay_periods pp on dd.day between pp.starts_on and pp.ends_on
        join lateral (select distinct on (sp.staff_id) sp.staff_id, sp.kind, sp.rate_crc from public.staff_pay sp
                       where sp.effective_from <= dd.day order by sp.staff_id, sp.effective_from desc) x on x.kind = 'period'
       group by dd.day),
    sales as (
      select o.business_date as day,
             sum(coalesce((select sum(i.net_crc) from public.order_items i where i.order_id = o.id),
                          case when o.tax_crc is not null then o.total_crc - o.tax_crc else round(o.total_crc / 1.13, 2) end)) as net
        from public.orders o
       where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
       group by o.business_date)
    select coalesce(jsonb_agg(jsonb_build_object('day', dd.day, 'hours', round(coalesce(h.hours, 0)::numeric, 2),
             'labor_crc', round((coalesce(h.cost, 0) + coalesce(f.cost, 0))::numeric, 2), 'sales_net_crc', round(coalesce(sa.net, 0), 2),
             'pct', case when coalesce(sa.net, 0) > 0 then round(100 * (coalesce(h.cost, 0) + coalesce(f.cost, 0))::numeric / sa.net, 1) end,
             'missing_rates', coalesce(h.missing, false)) order by dd.day), '[]')
      from days dd left join hourly h on h.day = dd.day left join fixed f on f.day = dd.day left join sales sa on sa.day = dd.day));
end $$;

-- a period whose payroll is posted or paid is not reopened
create or replace function public.timesheet_reopen(p_period_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pay_periods;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into p from public.pay_periods where id = p_period_id for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status <> 'approved' then return jsonb_build_object('ok', false, 'error', 'not_approved'); end if;
  if exists (select 1 from public.payroll_runs where period_id = p.id and status in ('posted', 'paid')) then
    return jsonb_build_object('ok', false, 'error', 'payroll_posted'); end if;
  update public.pay_periods set status = 'open' where id = p.id;
  update public.payroll_runs set status = 'draft', reviewed_by = null, reviewed_at = null where period_id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('timesheet_reopen', null, public._owner_label(), p.id::text, trim(p_reason), jsonb_build_object('starts_on', p.starts_on, 'ends_on', p.ends_on));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.payroll_staff(), public.staff_pay_set(uuid, text, numeric, date), public.payroll_rule_save(jsonb), public.payroll_prepare(uuid),
                       public.payroll_adjust(uuid, uuid, numeric, text), public.payroll_review(uuid), public.payroll_reopen(uuid), public.payroll_post(uuid),
                       public.payroll_pay(uuid, text, date), public.payroll_get(uuid), public.labor_cost(date, date) from public, anon;
grant execute on function public.payroll_staff(), public.staff_pay_set(uuid, text, numeric, date), public.payroll_rule_save(jsonb), public.payroll_prepare(uuid),
                          public.payroll_adjust(uuid, uuid, numeric, text), public.payroll_review(uuid), public.payroll_reopen(uuid), public.payroll_post(uuid),
                          public.payroll_pay(uuid, text, date), public.payroll_get(uuid), public.labor_cost(date, date) to authenticated;

select canopy.migration_end(22, 'payroll_prep');
notify pgrst, 'reload schema';
