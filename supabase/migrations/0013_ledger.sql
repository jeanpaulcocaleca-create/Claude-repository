-- =====================================================================================================
-- Canopy OS · migración 0013 · Contabilidad: catálogo de cuentas, libro diario de partida doble, periodos,
--                             asientos automáticos del día, reportes y acceso del contador
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0012.
--
-- Qué hace
--   * Esquema acct (no visible por el API): catálogo de cuentas (propuesta para el contador, editable),
--     periodos mensuales, asientos y líneas. Cada asiento cuadra (debe = haber) o no se guarda; nunca se
--     edita ni se borra: un error se corrige con un asiento de reversión. Un asiento automático no se
--     duplica (clave de origen).
--   * Asiento del día: ventas sin IVA, IVA por pagar, cobros por forma de pago (efectivo en colones y en
--     dólares según lo recibido, tarjeta, SINPE), anticipos de cuentas abiertas, faltantes/sobrantes de caja,
--     costo de ventas, mermas, ajustes y compras de inventario. Si llegan ventas después del cierre, solo se
--     asienta la diferencia.
--   * Periodos: abierto → cerrado (el contador puede reabrir) → bloqueado (definitivo).
--   * Reportes: balanza de comprobación, estado de resultados, balance general, flujo de efectivo, diario y
--     mayor, para exportar.
--   * Acceso del contador: un ingreso de tipo 'accountant' (el dueño lo asigna) ve y trabaja la contabilidad,
--     y no abre la caja ni el inventario.
--   * Los asientos automáticos están APAGADOS (ledger_auto_post) hasta que el contador apruebe el catálogo
--     ('chart_of_accounts_approved'). Antes de eso se puede asentar a mano un día para revisarlo.
-- Qué cambia para el personal: nada.
-- Reversión: update public.settings set value = 'false' where key = 'ledger_auto_post';
-- =====================================================================================================
select canopy.migration_begin(13, 'ledger');

create schema if not exists acct;
revoke all on schema acct from public;

-- 1) the accountant login ---------------------------------------------------------------------------------------
do $c$
declare n text;
begin
  for n in select conname from pg_constraint where conrelid = 'public.app_accounts'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%kind%' loop
    execute format('alter table public.app_accounts drop constraint %I', n);
  end loop;
end $c$;
alter table public.app_accounts add constraint app_accounts_kind_check check (kind in ('cafe', 'owner', 'accountant'));

create or replace function public.account_kind()
returns text language sql stable security definer set search_path = public as $$
  select case when a.kind = 'owner' and public.mfa_ok() then 'owner'
              when a.kind = 'owner' then 'owner_needs_code'
              when a.kind = 'accountant' and public.mfa_ok() then 'accountant'
              when a.kind = 'accountant' then 'accountant_needs_code'
              else a.kind end
  from public.app_accounts a where a.user_id = auth.uid();
$$;

create or replace function acct.can_read()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_true_owner() or public.account_kind() = 'accountant', false);
$$;
create or replace function acct.actor()
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if public.account_kind() = 'accountant' then
    return coalesce((select 'contador · ' || coalesce(a.label, '') from public.app_accounts a where a.user_id = auth.uid()), 'contador');
  end if;
  return coalesce(public._owner_label(), 'owner');
end $$;
grant usage on schema acct to authenticated;
grant execute on function acct.can_read(), acct.actor() to authenticated;
revoke execute on function acct.can_read(), acct.actor() from public;   -- owner-rights functions: signed-in only

-- the owner gives an existing login (created in Supabase → Authentication) the accountant role
create or replace function public.accountant_grant(p_email text, p_on boolean default true)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare uid uuid;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email));
  if uid is null then return jsonb_build_object('ok', false, 'error', 'no_such_login'); end if;
  if exists (select 1 from public.app_accounts where user_id = uid and kind = 'owner') then
    return jsonb_build_object('ok', false, 'error', 'is_owner'); end if;
  if coalesce(p_on, true) then
    insert into public.app_accounts (user_id, kind, label) values (uid, 'accountant', lower(trim(p_email)))
      on conflict (user_id) do update set kind = 'accountant', label = excluded.label;
  else
    delete from public.app_accounts where user_id = uid and kind = 'accountant';
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('accountant_access', null, public._owner_label(), uid::text,
            case when coalesce(p_on, true) then 'acceso de contador para ' else 'quitó el acceso de contador de ' end || lower(trim(p_email)), '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.accountant_grant(text, boolean) from public, anon;
grant execute on function public.accountant_grant(text, boolean) to authenticated;

-- 2) chart of accounts -------------------------------------------------------------------------------------------
create table if not exists acct.accounts (
  code      text primary key check (code ~ '^[0-9]{4,8}$'),
  name      text not null,
  type      text not null check (type in ('asset', 'liability', 'equity', 'revenue', 'expense')),
  cash      boolean not null default false,          -- cash and bank: the cash-flow report reads these
  active    boolean not null default true,
  system    boolean not null default false,          -- used by the automatic entries (can be renamed, not removed)
  created_at timestamptz not null default now()
);
insert into acct.accounts (code, name, type, cash, system) values
  ('1101', 'Caja general colones', 'asset', true, true),
  ('1102', 'Caja general dólares (valorada en colones)', 'asset', true, true),
  ('1103', 'Caja chica', 'asset', true, false),
  ('1110', 'Bancos · cuenta principal', 'asset', true, true),
  ('1111', 'Bancos · cuenta en dólares', 'asset', true, false),
  ('1120', 'Tarjetas por liquidar (datáfono)', 'asset', false, true),
  ('1130', 'Otros medios de pago por cobrar', 'asset', false, true),
  ('1140', 'IVA crédito fiscal', 'asset', false, true),
  ('1150', 'Inventario de alimentos, bebidas y empaques', 'asset', false, true),
  ('1160', 'Anticipos a proveedores', 'asset', false, false),
  ('1170', 'Retenciones de tarjetas por cobrar', 'asset', false, false),
  ('1201', 'Mobiliario y equipo', 'asset', false, false),
  ('1209', 'Depreciación acumulada', 'asset', false, false),
  ('2101', 'Cuentas por pagar a proveedores', 'liability', false, true),
  ('2110', 'IVA por pagar', 'liability', false, true),
  ('2120', 'Anticipos de clientes (cuentas abiertas)', 'liability', false, true),
  ('2130', 'Salarios por pagar', 'liability', false, false),
  ('2131', 'Cargas sociales por pagar', 'liability', false, false),
  ('2140', 'Impuesto sobre la renta por pagar', 'liability', false, false),
  ('3101', 'Capital', 'equity', false, false),
  ('3201', 'Utilidades acumuladas', 'equity', false, true),
  ('4101', 'Ventas de alimentos y bebidas', 'revenue', false, true),
  ('4102', 'Devoluciones sobre ventas', 'revenue', false, true),
  ('4201', 'Otros ingresos', 'revenue', false, false),
  ('4202', 'Diferencial cambiario · ganancia', 'revenue', false, false),
  ('5101', 'Costo de ventas', 'expense', false, true),
  ('5102', 'Mermas', 'expense', false, true),
  ('5103', 'Ajustes de inventario', 'expense', false, true),
  ('6101', 'Salarios', 'expense', false, false),
  ('6102', 'Cargas sociales', 'expense', false, false),
  ('6201', 'Alquiler', 'expense', false, false),
  ('6202', 'Electricidad y agua', 'expense', false, false),
  ('6203', 'Internet y teléfono', 'expense', false, false),
  ('6204', 'Suministros de limpieza', 'expense', false, false),
  ('6205', 'Empaques y desechables', 'expense', false, false),
  ('6206', 'Mantenimiento y reparaciones', 'expense', false, false),
  ('6207', 'Publicidad', 'expense', false, false),
  ('6208', 'Comisiones bancarias y de tarjetas', 'expense', false, false),
  ('6209', 'Honorarios profesionales', 'expense', false, false),
  ('6210', 'Diferencial cambiario · pérdida', 'expense', false, false),
  ('6211', 'Faltantes y sobrantes de caja', 'expense', false, true),
  ('6299', 'Otros gastos', 'expense', false, false)
on conflict (code) do nothing;

-- which account each automatic line uses (the accountant can point them elsewhere)
create table if not exists acct.mappings (
  key     text primary key,
  account text not null references acct.accounts(code),
  label   text not null
);
insert into acct.mappings (key, account, label) values
  ('pay_cash_crc', '1101', 'Cobros en efectivo (colones)'),
  ('pay_cash_usd', '1102', 'Cobros en efectivo (dólares)'),
  ('pay_card', '1120', 'Cobros con tarjeta'),
  ('pay_sinpe', '1110', 'Cobros por SINPE Móvil'),
  ('pay_other', '1130', 'Otros cobros'),
  ('revenue', '4101', 'Ventas (sin IVA)'),
  ('returns', '4102', 'Devoluciones (sin IVA)'),
  ('iva_out', '2110', 'IVA de las ventas'),
  ('iva_in', '1140', 'IVA de las compras y gastos'),
  ('advances', '2120', 'Cuentas abiertas pagadas en parte'),
  ('cash_over_short', '6211', 'Diferencias del cierre de caja'),
  ('inventory', '1150', 'Inventario'),
  ('cogs', '5101', 'Costo de lo vendido'),
  ('waste', '5102', 'Mermas'),
  ('stock_adjust', '5103', 'Conteos y ajustes de inventario'),
  ('ap', '2101', 'Compras a proveedores por pagar')
on conflict (key) do nothing;

-- 3) periods, entries, lines -------------------------------------------------------------------------------------
create table if not exists acct.periods (
  id         int primary key,                          -- yyyymm
  starts_on  date not null,
  ends_on    date not null,
  status     text not null default 'open' check (status in ('open', 'closed', 'locked')),
  changed_at timestamptz,
  changed_by text
);
create sequence if not exists acct.entry_no;
create table if not exists acct.entries (
  id         bigint generated always as identity primary key,
  entry_no   bigint not null unique default nextval('acct.entry_no'),
  date       date not null,
  period_id  int not null references acct.periods(id),
  memo       text not null,
  source     text not null check (source in ('manual', 'day', 'expense', 'reversal', 'opening', 'payroll', 'ap', 'bank')),
  source_key text unique,                              -- an automatic entry is never made twice
  reverses   bigint references acct.entries(id),
  created_at timestamptz not null default now(),
  created_by text not null
);
create table if not exists acct.lines (
  id       bigint generated always as identity primary key,
  entry_id bigint not null references acct.entries(id),
  account  text not null references acct.accounts(code),
  debit    numeric(14,2) not null default 0 check (debit >= 0),
  credit   numeric(14,2) not null default 0 check (credit >= 0),
  memo     text,
  check (debit = 0 or credit = 0),
  check (debit > 0 or credit > 0)
);
create index if not exists acct_lines_entry_idx on acct.lines (entry_id);
create index if not exists acct_lines_account_idx on acct.lines (account);
create index if not exists acct_entries_date_idx on acct.entries (date);
revoke all on all tables in schema acct from public, anon, authenticated;

-- nothing in the ledger is ever edited or deleted
create or replace function acct._immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'ledger_immutable: los asientos no se modifican ni se borran; registre un asiento de reversión' using errcode = 'P0001';
end $$;
drop trigger if exists entries_immutable on acct.entries;
create trigger entries_immutable before update or delete on acct.entries for each row execute function acct._immutable();
drop trigger if exists lines_immutable on acct.lines;
create trigger lines_immutable before update or delete on acct.lines for each row execute function acct._immutable();

-- every entry balances, with at least two lines (checked when the transaction commits)
-- checked at commit, when the session is back to the caller's role: definer, so the check can read the lines
create or replace function acct._balanced()
returns trigger language plpgsql security definer set search_path = acct as $$
declare d numeric; c numeric; n int;
begin
  select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*) into d, c, n from acct.lines where entry_id = new.entry_id;
  if n < 2 or d <> c then
    raise exception 'ledger_unbalanced: asiento % · debe % · haber % · líneas %', new.entry_id, d, c, n using errcode = 'P0001';
  end if;
  return null;
end $$;
drop trigger if exists lines_balanced on acct.lines;
create constraint trigger lines_balanced after insert on acct.lines deferrable initially deferred
  for each row execute function acct._balanced();
create or replace function acct._entry_has_lines()
returns trigger language plpgsql security definer set search_path = acct as $$
begin
  if not exists (select 1 from acct.lines where entry_id = new.id) then
    raise exception 'ledger_unbalanced: el asiento % no tiene líneas', new.id using errcode = 'P0001';
  end if;
  return null;
end $$;
drop trigger if exists entries_have_lines on acct.entries;
create constraint trigger entries_have_lines after insert on acct.entries deferrable initially deferred
  for each row execute function acct._entry_has_lines();

-- the period of a date, created when first needed
create or replace function acct.period_of(p_date date)
returns acct.periods language plpgsql security definer set search_path = acct, public as $$
declare p acct.periods; pid int := extract(year from p_date)::int * 100 + extract(month from p_date)::int;
begin
  insert into acct.periods (id, starts_on, ends_on) values (pid, date_trunc('month', p_date)::date, (date_trunc('month', p_date) + interval '1 month - 1 day')::date)
    on conflict (id) do nothing;
  select * into p from acct.periods where id = pid;
  return p;
end $$;

-- the one way to write an entry: lines = [{account, debit, credit, memo}] (amounts > 0, zero lines dropped)
create or replace function acct.post(p_date date, p_memo text, p_source text, p_source_key text, p_lines jsonb,
                                     p_reverses bigint default null, p_by text default null)
returns bigint language plpgsql security definer set search_path = acct, public as $$
declare p acct.periods; eid bigint; l jsonb; d numeric; c numeric;
begin
  if p_source_key is not null then
    select id into eid from acct.entries where source_key = p_source_key;
    if eid is not null then return eid; end if;
  end if;
  p := acct.period_of(p_date);
  if p.status <> 'open' then raise exception 'period_closed: el periodo % está %', p.id, p.status using errcode = 'P0001'; end if;
  insert into acct.entries (date, period_id, memo, source, source_key, reverses, created_by)
    values (p_date, p.id, left(coalesce(nullif(trim(p_memo), ''), p_source), 300), p_source, p_source_key, p_reverses, coalesce(p_by, 'sistema'))
    returning id into eid;
  for l in select * from jsonb_array_elements(p_lines) loop
    d := round(coalesce((l->>'debit')::numeric, 0), 2); c := round(coalesce((l->>'credit')::numeric, 0), 2);
    if d < 0 then c := c - d; d := 0; end if;          -- a negative debit is a credit
    if c < 0 then d := d - c; c := 0; end if;
    if d > 0 and c > 0 then
      if d >= c then d := d - c; c := 0; else c := c - d; d := 0; end if;
    end if;
    if d > 0 or c > 0 then
      if not exists (select 1 from acct.accounts where code = l->>'account' and active) then
        raise exception 'unknown_account: %', l->>'account' using errcode = 'P0001';
      end if;
      insert into acct.lines (entry_id, account, debit, credit, memo) values (eid, l->>'account', d, c, nullif(left(l->>'memo', 200), ''));
    end if;
  end loop;
  return eid;
end $$;
revoke all on function acct.post(date, text, text, text, jsonb, bigint, text), acct.period_of(date) from public, anon, authenticated;

-- 4) settings -----------------------------------------------------------------------------------------------------
insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('ledger_auto_post', 'boolean', null, 'false', 'chart_of_accounts_approved',
   'Asientos automáticos: al cerrar la caja, el día se asienta solo en el libro diario. Se activa cuando el contador apruebe el catálogo de cuentas.'),
  ('ledger_start_date', 'text', null, '""', null,
   'Primer día que la contabilidad asienta (AAAA-MM-DD). Los días anteriores van en el asiento de apertura del contador.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

-- 5) the day's entry ------------------------------------------------------------------------------------------------
create or replace function acct.map(p_key text)
returns text language sql stable security definer set search_path = acct as $$
  select account from acct.mappings where key = p_key;
$$;

-- what the ledger should hold for a day, per account (debit positive, credit negative)
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
    -- inventory: sold and given back at cost, waste, counts and adjustments, purchases
    union all select acct.map('cogs'), -cost, 'costo de lo vendido' from stock where kind in ('sale', 'void')
    union all select acct.map('waste'), -cost, 'mermas' from stock where kind = 'waste'
    union all select acct.map('stock_adjust'), -cost, 'conteos y ajustes' from stock where kind in ('count', 'adjust')
    union all select acct.map('ap'), -cost, 'compras de inventario' from stock where kind = 'purchase'
    union all select acct.map('inventory'), coalesce(sum(cost), 0), 'movimientos de inventario' from stock
  )
  select account, round(sum(amount), 2), string_agg(distinct memo, ' · ') from rows where amount is not null group by account having round(sum(amount), 2) <> 0;
$$;

-- post the day: only what is missing compared to what was already posted for it (late sales, a re-close)
create or replace function acct.post_day(p_day date, p_by text default null)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare lines jsonb; n int; per acct.periods; d date; eid bigint; k text;
begin
  perform pg_advisory_xact_lock(hashtext('acct.post_day'), (p_day - date '2000-01-01'));
  with posted as (
    select l.account, sum(l.debit - l.credit) as amount from acct.lines l join acct.entries e on e.id = l.entry_id
     where e.source = 'day' and e.source_key like 'day:' || p_day || ':%' group by l.account),
  target as (select account, amount from acct.day_target(p_day)),
  delta as (
    select coalesce(t.account, po.account) as account, coalesce(t.amount, 0) - coalesce(po.amount, 0) as amount
      from target t full join posted po on po.account = t.account)
  select jsonb_agg(jsonb_build_object('account', account, 'debit', greatest(amount, 0), 'credit', greatest(-amount, 0)) order by account), count(*)
    into lines, n from delta where amount <> 0;
  if coalesce(n, 0) = 0 then return jsonb_build_object('ok', true, 'posted', false); end if;
  select count(*) into n from acct.entries where source = 'day' and source_key like 'day:' || p_day || ':%';
  k := 'day:' || p_day || ':' || (n + 1);
  per := acct.period_of(p_day);
  d := case when per.status = 'open' then p_day else public.cr_today() end;    -- a closed month is never touched
  eid := acct.post(d, case when n = 0 then 'Ventas y movimientos del ' else 'Ajuste tardío del ' end || to_char(p_day, 'DD/MM/YYYY'),
                   'day', k, lines, null, coalesce(p_by, 'sistema'));
  return jsonb_build_object('ok', true, 'posted', true, 'entry_id', eid, 'date', d);
end $$;
revoke all on function acct.day_target(date), acct.post_day(date, text), acct.map(text) from public, anon, authenticated;

-- after a register close (or re-close), the day is posted when the owner switched it on
create or replace function acct._register_closed_post()
returns trigger language plpgsql security definer set search_path = acct, public as $$
declare start text;
begin
  if new.closed_at is null or (old.closed_at is not distinct from new.closed_at) then return new; end if;
  if (public.setting('ledger_auto_post') #>> '{}') is distinct from 'true' then return new; end if;
  start := nullif(public.setting('ledger_start_date') #>> '{}', '');
  if start is not null and new.business_date < start::date then return new; end if;
  begin
    perform acct.post_day(new.business_date, 'cierre de caja');
  exception when others then
    -- the register close always goes through; the accountant sees the day as pending
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('ledger_post_failed', null, 'sistema', new.business_date::text, left(sqlerrm, 200), '{}'::jsonb);
  end;
  return new;
end $$;
drop trigger if exists register_closed_post on public.register_days;
create trigger register_closed_post after update of closed_at on public.register_days
  for each row execute function acct._register_closed_post();

-- 6) what the accountant and the owner use ---------------------------------------------------------------------
create or replace function public.acct_overview()
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'kind', public.account_kind(),
    'accounts', (select coalesce(jsonb_agg(to_jsonb(a) order by a.code), '[]') from acct.accounts a),
    'mappings', (select coalesce(jsonb_agg(to_jsonb(m) order by m.key), '[]') from acct.mappings m),
    'periods', (select coalesce(jsonb_agg(to_jsonb(p) order by p.id desc), '[]') from acct.periods p),
    'auto_post', public.setting('ledger_auto_post'), 'start_date', public.setting('ledger_start_date'),
    'approved', exists (select 1 from public.compliance_confirmations where key = 'chart_of_accounts_approved'),
    -- closed register days not yet (fully) in the ledger
    'pending_days', (select coalesce(jsonb_agg(r.business_date order by r.business_date), '[]') from public.register_days r
                      where r.closed_at is not null and r.business_date >= coalesce(nullif(public.setting('ledger_start_date') #>> '{}', '')::date, r.business_date)
                        and not exists (select 1 from acct.entries e where e.source = 'day' and e.source_key like 'day:' || r.business_date || ':%')));
end $$;

create or replace function public.acct_account_save(p_code text, p_name text, p_type text, p_cash boolean default false, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare a acct.accounts;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(p_code, '') !~ '^[0-9]{4,8}$' or coalesce(trim(p_name), '') = '' or p_type not in ('asset', 'liability', 'equity', 'revenue', 'expense') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into a from acct.accounts where code = p_code;
  if a.code is not null and a.type <> p_type and exists (select 1 from acct.lines where account = p_code) then
    return jsonb_build_object('ok', false, 'error', 'type_in_use'); end if;
  if a.code is not null and a.system and not coalesce(p_active, true) then return jsonb_build_object('ok', false, 'error', 'system_account'); end if;
  if a.code is null then
    insert into acct.accounts (code, name, type, cash, active) values (p_code, trim(p_name), p_type, coalesce(p_cash, false), coalesce(p_active, true));
  else
    update acct.accounts set name = trim(p_name), type = p_type, cash = coalesce(p_cash, false), active = coalesce(p_active, true) where code = p_code;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('acct_account_save', null, acct.actor(), p_code, p_code || ' ' || trim(p_name), jsonb_build_object('before', to_jsonb(a), 'type', p_type));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.acct_mapping_set(p_key text, p_account text)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from acct.accounts where code = p_account and active) then return jsonb_build_object('ok', false, 'error', 'unknown_account'); end if;
  update acct.mappings set account = p_account where key = p_key;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_key'); end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('acct_mapping_set', null, acct.actor(), p_key, p_key || ' → ' || p_account, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

-- a manual entry (opening balances, accruals, corrections); p_request_id makes a double tap harmless
create or replace function public.acct_entry_post(p_date date, p_memo text, p_lines jsonb, p_request_id uuid, p_opening boolean default false)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare eid bigint; d numeric; c numeric;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_date is null or p_request_id is null or coalesce(trim(p_memo), '') = '' or jsonb_typeof(p_lines) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select coalesce(sum(round(coalesce((l->>'debit')::numeric, 0), 2)), 0), coalesce(sum(round(coalesce((l->>'credit')::numeric, 0), 2)), 0)
    into d, c from jsonb_array_elements(p_lines) l;
  if d <> c or d = 0 then return jsonb_build_object('ok', false, 'error', 'unbalanced', 'debit', d, 'credit', c); end if;
  begin
    eid := acct.post(p_date, p_memo, case when coalesce(p_opening, false) then 'opening' else 'manual' end, 'manual:' || p_request_id, p_lines, null, acct.actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    if sqlerrm ~ 'unknown_account' then return jsonb_build_object('ok', false, 'error', 'unknown_account'); end if;
    raise;
  end;
  return jsonb_build_object('ok', true, 'entry_id', eid, 'entry_no', (select entry_no from acct.entries where id = eid));
end $$;

-- a mistake is corrected by its mirror image, dated when the correction is made
create or replace function public.acct_entry_reverse(p_entry_id bigint, p_date date, p_memo text)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare e acct.entries; lines jsonb; eid bigint;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into e from acct.entries where id = p_entry_id;
  if e.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if exists (select 1 from acct.entries where reverses = e.id) then return jsonb_build_object('ok', false, 'error', 'already_reversed'); end if;
  if e.source = 'reversal' then return jsonb_build_object('ok', false, 'error', 'is_reversal'); end if;
  select jsonb_agg(jsonb_build_object('account', account, 'debit', credit, 'credit', debit, 'memo', memo)) into lines from acct.lines where entry_id = e.id;
  begin
    eid := acct.post(coalesce(p_date, public.cr_today()), 'Reversión del asiento ' || e.entry_no || ': ' || coalesce(nullif(trim(p_memo), ''), e.memo),
                     'reversal', 'reverse:' || e.id, lines, e.id, acct.actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

create or replace function public.acct_post_days(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare d date; r jsonb; n int := 0;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 or p_to > public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    r := acct.post_day(d, acct.actor());
    if (r->>'posted')::boolean then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'entries', n);
end $$;

create or replace function public.acct_period_set(p_period int, p_status text)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare p acct.periods;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_status not in ('open', 'closed', 'locked') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into p from acct.periods where id = p_period for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status = 'locked' then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  -- months close in order: no open month before a closed one
  if p_status <> 'open' and exists (select 1 from acct.periods where id < p.id and status = 'open'
                                     and exists (select 1 from acct.entries where period_id = acct.periods.id)) then
    return jsonb_build_object('ok', false, 'error', 'earlier_open'); end if;
  if p_status = 'open' and exists (select 1 from acct.periods where id > p.id and status = 'locked') then
    return jsonb_build_object('ok', false, 'error', 'later_locked'); end if;
  update acct.periods set status = p_status, changed_at = now(), changed_by = acct.actor() where id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('acct_period', null, acct.actor(), p.id::text, 'periodo ' || p.id || ': ' || p.status || ' → ' || p_status, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

-- the journal and ledger lines of a range (for the screens and the CSV exports)
create or replace function public.acct_journal(p_from date, p_to date, p_account text default null)
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_to - p_from > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'entries', (
    select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'entry_no', e.entry_no, 'date', e.date, 'memo', e.memo, 'source', e.source,
             'reverses', e.reverses, 'reversed', exists (select 1 from acct.entries x where x.reverses = e.id), 'created_by', e.created_by,
             'lines', (select jsonb_agg(jsonb_build_object('account', l.account, 'name', a.name, 'debit', l.debit, 'credit', l.credit, 'memo', l.memo) order by l.id)
                         from acct.lines l join acct.accounts a on a.code = l.account where l.entry_id = e.id))
           order by e.date, e.entry_no), '[]')
      from acct.entries e
     where e.date between p_from and p_to
       and (p_account is null or exists (select 1 from acct.lines l where l.entry_id = e.id and l.account = p_account))));
end $$;

-- balances by account: opening (before p_from), movement in the range, closing
create or replace function public.acct_trial_balance(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'rows', (
    select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name', a.name, 'type', a.type,
             'opening', x.opening, 'debit', x.debit, 'credit', x.credit, 'closing', x.opening + x.debit - x.credit) order by a.code), '[]')
      from acct.accounts a
      join lateral (
        select coalesce(sum(case when e.date < p_from and a.type in ('asset', 'liability', 'equity') then l.debit - l.credit else 0 end), 0) as opening,
               coalesce(sum(case when e.date between p_from and p_to then l.debit else 0 end), 0) as debit,
               coalesce(sum(case when e.date between p_from and p_to then l.credit else 0 end), 0) as credit
          from acct.lines l join acct.entries e on e.id = l.entry_id where l.account = a.code and e.date <= p_to) x on true
     where x.opening <> 0 or x.debit <> 0 or x.credit <> 0));
end $$;

create or replace function public.acct_income_statement(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
declare rows jsonb; rev numeric; exp numeric;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'amount', amount) order by code), '[]'),
         coalesce(sum(amount) filter (where type = 'revenue'), 0), coalesce(sum(amount) filter (where type = 'expense'), 0)
    into rows, rev, exp
    from (select a.code, a.name, a.type,
                 case when a.type = 'revenue' then sum(l.credit - l.debit) else sum(l.debit - l.credit) end as amount
            from acct.lines l join acct.entries e on e.id = l.entry_id join acct.accounts a on a.code = l.account
           where e.date between p_from and p_to and a.type in ('revenue', 'expense')
           group by a.code, a.name, a.type having sum(l.debit - l.credit) <> 0) s;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'rows', rows, 'revenue', rev, 'expenses', exp, 'net_income', rev - exp);
end $$;

create or replace function public.acct_balance_sheet(p_as_of date)
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
declare rows jsonb; earnings numeric; a numeric; li numeric; eq numeric;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'amount', amount) order by code), '[]'),
         coalesce(sum(amount) filter (where type = 'asset'), 0), coalesce(sum(amount) filter (where type = 'liability'), 0),
         coalesce(sum(amount) filter (where type = 'equity'), 0)
    into rows, a, li, eq
    from (select ac.code, ac.name, ac.type,
                 case when ac.type = 'asset' then sum(l.debit - l.credit) else sum(l.credit - l.debit) end as amount
            from acct.lines l join acct.entries e on e.id = l.entry_id join acct.accounts ac on ac.code = l.account
           where e.date <= p_as_of and ac.type in ('asset', 'liability', 'equity')
           group by ac.code, ac.name, ac.type having sum(l.debit - l.credit) <> 0) s;
  -- results not yet carried to retained earnings
  select coalesce(sum(l.credit - l.debit), 0) into earnings
    from acct.lines l join acct.entries e on e.id = l.entry_id join acct.accounts ac on ac.code = l.account
   where e.date <= p_as_of and ac.type in ('revenue', 'expense');
  return jsonb_build_object('ok', true, 'as_of', p_as_of, 'rows', rows, 'assets', a, 'liabilities', li, 'equity', eq,
                            'current_earnings', earnings, 'balanced', a = li + eq + earnings);
end $$;

-- direct method: the cash and bank accounts' movement, by what caused it
create or replace function public.acct_cash_flow(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'opening', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l join acct.entries e on e.id = l.entry_id
                  join acct.accounts a on a.code = l.account where a.cash and e.date < p_from),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('group', g, 'amount', amt) order by g), '[]') from (
               select case e.source when 'day' then 'Cobros a clientes y diferencias de caja'
                                    when 'expense' then 'Pagos de gastos'
                                    when 'ap' then 'Pagos a proveedores'
                                    when 'payroll' then 'Pagos de planilla'
                                    when 'bank' then 'Movimientos bancarios'
                                    when 'opening' then 'Saldos iniciales'
                                    else 'Otros movimientos' end as g,
                      sum(l.debit - l.credit) as amt
                 from acct.lines l join acct.entries e on e.id = l.entry_id join acct.accounts a on a.code = l.account
                where a.cash and e.date between p_from and p_to group by 1 having sum(l.debit - l.credit) <> 0) s),
    'closing', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l join acct.entries e on e.id = l.entry_id
                  join acct.accounts a on a.code = l.account where a.cash and e.date <= p_to));
end $$;

do $g$
declare f text;
begin
  foreach f in array array['acct_overview()', 'acct_account_save(text, text, text, boolean, boolean)', 'acct_mapping_set(text, text)',
                           'acct_entry_post(date, text, jsonb, uuid, boolean)', 'acct_entry_reverse(bigint, date, text)',
                           'acct_post_days(date, date)', 'acct_period_set(int, text)', 'acct_journal(date, date, text)',
                           'acct_trial_balance(date, date)', 'acct_income_statement(date, date)', 'acct_balance_sheet(date)',
                           'acct_cash_flow(date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $g$;

-- the backup account reads the books too (tables and sequences, also those later migrations add to acct)
grant usage on schema acct to canopy_backup;
grant select on all tables in schema acct to canopy_backup;
grant select on all sequences in schema acct to canopy_backup;
alter default privileges in schema acct grant select on tables to canopy_backup;
alter default privileges in schema acct grant select on sequences to canopy_backup;

select canopy.migration_end(13, 'ledger');
notify pgrst, 'reload schema';
