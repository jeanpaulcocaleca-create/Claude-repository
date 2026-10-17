-- =====================================================================================================
-- Canopy OS · migración 0028 · Correcciones de la revisión independiente (caja, libros, personal, visitantes)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0027.
--
-- Qué hace (hallazgos de la revisión del 2026-10-14, D-037)
--   * Caja: una venta de la caja nunca tiene total negativo (la única venta negativa es una devolución, que hace su
--     propia función); una forma de pago o un estado desconocidos se marcan (bad_method / bad_status), no se rechazan,
--     para que la caja vieja siga funcionando.
--   * Un pedido de habitación pagado otro día pertenece al día en que entró el dinero (igual que una cuenta abierta):
--     el cierre de caja y los libros lo cuentan una sola vez.
--   * Efectivo por día (Contabilidad → Efectivo) y los días pendientes de asentar incluyen los días con ventas y sin
--     caja abierta, marcados, en vez de no verse.
--   * Diario: desde la página solo se revierte un asiento manual o de apertura (acct_journal_reverse); los de gastos,
--     proveedores, banco, planilla y del día se deshacen desde su propio documento (use_document), para que documento y
--     libro no se separen. acct_entry_reverse sigue sirviendo a esos documentos pero ya no se puede llamar desde una página.
--   * acct_post_days devuelve period_closed en vez de un error crudo; la marca "efectivo" solo en cuentas de activo.
--   * Comprobante en modo registro: una cuenta abierta cancelada por estado también cancela su documento.
--   * Costo de mano de obra: una persona que pasó de pago por hora a monto fijo no se cuenta dos veces.
--   * Equipo: un PIN ya usado por otra persona activa se rechaza (pin_in_use); el puesto de dueño solo lo da o lo
--     quita el dueño con el código del teléfono (la excepción del primer dueño en un ingreso sin código, D-027, se
--     cierra; la primera configuración sin ningún encargado sigue igual).
--   * Preguntas del sitio público: a lo sumo 500 letras y 20 preguntas por visita cada hora (antes sin límite).
-- Qué cambia para el personal: la caja avisa si un total queda negativo; un PIN repetido se rechaza al crear a alguien.
-- Reversión: drop trigger order_zz_till_guard, chat_questions_guard; volver a crear las funciones de la migración
--   anterior de cada una (0001 finish_room_order, 0019 cash_reconciliation, 0013 acct_*, 0018 trigger, 0022
--   labor_cost, manager-mode.sql manager_save_staff). No toca datos.
-- =====================================================================================================
select canopy.migration_begin(28, 'review_fixes');

-- 1) the till's sales: never a negative total; an unknown method or status is flagged -------------------------------
-- when the one-time operational reset ran (D-038): the log row is behind row security for the till, so a definer reads it
create or replace function public._reinicio_at()
returns timestamptz language sql stable security definer set search_path = public as $$
  select max(at) from public.audit_log where action = 'reinicio_operativo';
$$;
revoke all on function public._reinicio_at() from public, anon;
grant execute on function public._reinicio_at() to authenticated;   -- the till's role; a room order's definer never reaches the till branch

create or replace function public._order_till_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.refund_of is null and coalesce(new.total_crc, 0) < 0 then
      raise exception 'negative_total: una venta no puede tener total negativo (una devolución se hace con su propia función)' using errcode = 'P0001';
    end if;
    if new.payment_method is not null and new.payment_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other', 'pending') then
      new.flags := array_append(coalesce(new.flags, '{}'), 'bad_method');
    end if;
    if new.status is not null and new.status not in ('new', 'preparing', 'ready', 'done', 'delivered', 'cancelled') then
      new.flags := array_append(coalesce(new.flags, '{}'), 'bad_status');
    end if;
    -- a sale a device kept offline from before the one-time operational reset (D-038) is recorded, never refused, and
    -- flagged for the manager to void: it belongs to the test period the reset archived
    if new.created_at is not null and new.created_at < coalesce(public._reinicio_at(), '-infinity'::timestamptz) then
      new.flags := array_append(coalesce(new.flags, '{}'), 'before_reset');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists order_zz_till_guard on public.orders;
create trigger order_zz_till_guard before insert on public.orders for each row execute function public._order_till_guard();

-- 2) a room order paid on a later day belongs to the day the money came in (as tab_pay does) ---------------------------
create or replace function public.finish_room_order(p_order_id uuid, p_payment_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.source <> 'room' or o.paid then return jsonb_build_object('ok', false, 'error', 'not_room_order'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if p_payment_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method');
  end if;
  update public.orders set paid = true, payment_method = p_payment_method, status = 'done',
    done_at = now(), guest_phone = null,
    created_at = case when (o.created_at at time zone 'America/Costa_Rica')::date < (now() at time zone 'America/Costa_Rica')::date then now() else created_at end
    where id = p_order_id;
  return jsonb_build_object('ok', true);
end $$;

-- 3) cash by day and the pending days: days with sales but no register opened are shown, not skipped ------------------
create or replace function public.cash_reconciliation(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'days', (
    with days as (
      select business_date from public.register_days where business_date between p_from and p_to
      union
      select o.business_date from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
      union
      select m.business_date from public.cash_movements m where m.business_date between p_from and p_to and m.voided_at is null)
    select coalesce(jsonb_agg(jsonb_build_object(
             'date', d.business_date, 'opened', r.id is not null, 'closed', r.closed_at is not null, 'fx_rate', r.fx_rate,
             'float_crc', coalesce(r.float_crc, 0), 'float_usd', coalesce(r.float_usd, 0),
             'in_crc', coalesce(mv.in_crc, 0), 'out_crc', coalesce(mv.out_crc, 0), 'in_usd', coalesce(mv.in_usd, 0), 'out_usd', coalesce(mv.out_usd, 0),
             'sales_crc', e.cash_crc - coalesce(mv.in_crc, 0) + coalesce(mv.out_crc, 0),     -- cash taken for sales, change given back
             'sales_usd', e.usd - coalesce(mv.in_usd, 0) + coalesce(mv.out_usd, 0),
             'expected_crc', coalesce(r.expected_cash_crc, coalesce(r.float_crc, 0) + e.cash_crc), 'counted_crc', r.cash_counted_crc, 'diff_crc', r.cash_diff_crc,
             'expected_usd', coalesce(r.expected_cash_usd, coalesce(r.float_usd, 0) + e.usd), 'counted_usd', r.cash_counted_usd, 'diff_usd', r.cash_diff_usd)
           order by d.business_date), '[]')
      from days d
      left join public.register_days r on r.business_date = d.business_date
      cross join lateral public._register_expected(d.business_date) e
      left join lateral (select sum(amount) filter (where direction = 'in' and currency = 'CRC') as in_crc, sum(amount) filter (where direction = 'out' and currency = 'CRC') as out_crc,
                                sum(amount) filter (where direction = 'in' and currency = 'USD') as in_usd, sum(amount) filter (where direction = 'out' and currency = 'USD') as out_usd
                           from public.cash_movements m where m.business_date = d.business_date and m.voided_at is null) mv on true));
end $$;

create or replace function public.acct_overview()
returns jsonb language plpgsql stable security definer set search_path = acct, public as $$
declare start_on date := nullif(public.setting('ledger_start_date') #>> '{}', '')::date;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'kind', public.account_kind(),
    'accounts', (select coalesce(jsonb_agg(to_jsonb(a) order by a.code), '[]') from acct.accounts a),
    'mappings', (select coalesce(jsonb_agg(to_jsonb(m) order by m.key), '[]') from acct.mappings m),
    'periods', (select coalesce(jsonb_agg(to_jsonb(p) order by p.id desc), '[]') from acct.periods p),
    'auto_post', public.setting('ledger_auto_post'), 'start_date', public.setting('ledger_start_date'),
    'approved', exists (select 1 from public.compliance_confirmations where key = 'chart_of_accounts_approved'),
    -- days not yet (fully) in the ledger: closed register days, and past days with paid sales or stock moves and no register
    'pending_days', (
      with days as (
        select business_date, true as opened from public.register_days where closed_at is not null
        union
        select o.business_date, false from public.orders o where o.business_date < public.cr_today() and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
           and not exists (select 1 from public.register_days r where r.business_date = o.business_date)
        union
        select (m.at at time zone 'America/Costa_Rica')::date, false from public.stock_moves m where (m.at at time zone 'America/Costa_Rica')::date < public.cr_today()
           and not exists (select 1 from public.register_days r where r.business_date = (m.at at time zone 'America/Costa_Rica')::date))
      select coalesce(jsonb_agg(d.business_date order by d.business_date), '[]') from days d
       where d.business_date >= coalesce(start_on, d.business_date)
         and not exists (select 1 from acct.entries e where e.source = 'day' and e.source_key like 'day:' || d.business_date || ':%')),
    'days_without_register', (
      select coalesce(jsonb_agg(x.business_date order by x.business_date), '[]') from (
        select distinct o.business_date from public.orders o
         where o.business_date < public.cr_today() and o.business_date >= coalesce(start_on, o.business_date) and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
           and not exists (select 1 from public.register_days r where r.business_date = o.business_date)
           and not exists (select 1 from acct.entries e where e.source = 'day' and e.source_key like 'day:' || o.business_date || ':%')) x));
end $$;

-- 4) the journal reverses only what it wrote itself: a document is undone from its own screen -------------------------
-- acct_entry_reverse keeps reversing any entry for the document functions (expense_void, supplier_*_void, bank_undo call
-- it as the server), but a page can no longer call it; the page uses acct_journal_reverse, for manual and opening entries
revoke execute on function public.acct_entry_reverse(bigint, date, text) from public, anon, authenticated;
create or replace function public.acct_journal_reverse(p_entry_id bigint, p_date date, p_memo text)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare e acct.entries;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into e from acct.entries where id = p_entry_id;
  if e.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if e.source = 'reversal' then return jsonb_build_object('ok', false, 'error', 'is_reversal'); end if;
  if e.source not in ('manual', 'opening') then return jsonb_build_object('ok', false, 'error', 'use_document', 'source', e.source); end if;
  return public.acct_entry_reverse(p_entry_id, p_date, p_memo);
end $$;
revoke all on function public.acct_journal_reverse(bigint, date, text) from public, anon;
grant execute on function public.acct_journal_reverse(bigint, date, text) to authenticated;

-- 5) posting a range of days answers period_closed instead of failing; "cash" only on an asset account ------------------
create or replace function public.acct_post_days(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare d date; r jsonb; n int := 0;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 or p_to > public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    begin
      r := acct.post_day(d, acct.actor());
    exception when others then
      if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed', 'day', d, 'entries', n); end if;
      raise;
    end;
    if (r->>'posted')::boolean then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'entries', n);
end $$;

create or replace function public.acct_account_save(p_code text, p_name text, p_type text, p_cash boolean default false, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = acct, public as $$
declare a acct.accounts;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(p_code, '') !~ '^[0-9]{4,8}$' or coalesce(trim(p_name), '') = '' or p_type not in ('asset', 'liability', 'equity', 'revenue', 'expense') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if coalesce(p_cash, false) and p_type <> 'asset' then return jsonb_build_object('ok', false, 'error', 'cash_not_asset'); end if;
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

-- 6) a record-only document follows a bill cancelled by status, not only a void -----------------------------------------
create or replace function public._order_e_document_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.e_documents where order_id = new.id) then return new; end if;
  begin
    update public.e_documents d
       set total_crc = new.total_crc, tax_crc = new.tax_crc,
           missing = public._e_missing(new.id) || case when d.kind = 'NC' and d.reference_id is null then '{reference}'::text[] else '{}' end,
           status = case when (new.voided_at is not null or new.status = 'cancelled') and d.status = 'pending' then 'cancelled' else d.status end,
           updated_at = now()
     where d.order_id = new.id and d.status in ('pending', 'cancelled');
  exception when others then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('e_document_failed', null, 'sistema', new.id::text, left(sqlerrm, 200), '{}'::jsonb);
  end;
  return new;
end $$;
drop trigger if exists order_e_document_sync on public.orders;
create trigger order_e_document_sync after update of tax_crc, total_crc, voided_at, status on public.orders
  for each row execute function public._order_e_document_sync();

-- 7) labor cost: the person's latest pay rate, counted once ------------------------------------------------------------
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
    hourly as (       -- the rate in force that day, counted only when it is an hourly one (a switch to a fixed pay stops it)
      select s.day, sum(s.h) as hours,
             sum(s.h * coalesce((select case when x.kind = 'hourly' then x.rate_crc end from public.staff_pay x where x.staff_id = s.staff_id and x.effective_from <= s.day
                                   order by x.effective_from desc limit 1), 0)) as cost,
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

-- 8) the team: a PIN in use is refused; the owner role is given or taken only by the owner with the phone code ----------
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; u record; lvl text; bootstrap boolean; nid uuid; role_final text;
        old public.staff; managers_left int; msid uuid; msname text; strip_sales boolean;
begin
  lvl := public.access_level();
  bootstrap := not exists (select 1 from public.staff where active and role in ('manager', 'owner'));
  if bootstrap then
    if lvl is null and public.account_kind() is distinct from 'owner' then
      return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
    msid := null; msname := 'first setup';
  elsif lvl is null then
    return jsonb_build_object('ok', false, 'error', 'owner_only');
  elsif p_manager_id is not null or coalesce(p_manager_pin, '') <> '' then
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);   -- an extra approval, if given
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  else
    select * into u from public._unlock_staff();
    msid := u.staff_id; msname := public._owner_label();
  end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  if p_pin is not null and p_pin <> '' then
    if p_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('ok', false, 'error', 'bad_pin_format'); end if;
    if public._weak_pin(p_pin) then return jsonb_build_object('ok', false, 'error', 'weak_pin'); end if;
    -- two people never share a PIN: the clock and the till could not tell them apart
    if exists (select 1 from public.staff s where s.active and s.id is distinct from p_id and s.pin_hash = crypt(p_pin, s.pin_hash)) then
      return jsonb_build_object('ok', false, 'error', 'pin_in_use'); end if;
  end if;
  role_final := case when p_role in ('owner', 'manager') then p_role else 'staff' end;
  if bootstrap and role_final = 'staff' then role_final := 'manager'; end if;
  if p_id is not null then
    select * into old from public.staff where id = p_id;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  -- the owner role: only the owner with the phone code (D-027: the first-owner exception on a login without a code is closed)
  if (role_final = 'owner' or old.role = 'owner') and not (bootstrap or public.owner_with_code()) then
    return jsonb_build_object('ok', false, 'error', 'owner_role_only');
  end if;
  -- Another manager's PIN, role or active state: only an owner. Otherwise a GM could set a colleague's PIN
  -- and then open sales or approve voids and discounts in that colleague's name. Before the team has an
  -- owner, managers may still do it, but a PIN set by someone else switches "may open sales" off.
  strip_sales := false;
  if old.id is not null and old.role = 'manager' and old.id is distinct from msid and lvl is distinct from 'owner'
     and not bootstrap
     and ((p_pin is not null and p_pin <> '') or role_final <> old.role or coalesce(p_active, old.active) <> old.active) then
    if exists (select 1 from public.staff where active and role = 'owner') then return jsonb_build_object('ok', false, 'error', 'manager_needs_owner'); end if;
    strip_sales := p_pin is not null and p_pin <> '';
  end if;

  if p_id is null then
    if p_pin is null or p_pin = '' then return jsonb_build_object('ok', false, 'error', 'missing_pin'); end if;
    insert into public.staff (name, pin_hash, active, role)
      values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), role_final)
      returning id into nid;
  else
    if old.role in ('manager', 'owner') and old.active and (role_final = 'staff' or not coalesce(p_active, true)) then
      select count(*) into managers_left from public.staff
        where active and role in ('manager', 'owner') and id <> old.id;
      if managers_left = 0 then return jsonb_build_object('ok', false, 'error', 'last_manager'); end if;
    end if;
    update public.staff set
      name = trim(p_name),
      pin_hash = case when p_pin is not null and p_pin <> '' then crypt(p_pin, gen_salt('bf')) else pin_hash end,
      failed_pins = case when p_pin is not null and p_pin <> '' then 0 else failed_pins end,
      locked_until = case when p_pin is not null and p_pin <> '' then null else locked_until end,
      active = coalesce(p_active, active),
      role = role_final,
      can_see_sales = case when role_final = 'manager' and not strip_sales then can_see_sales else false end
      where id = p_id;
    nid := p_id;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('staff_save', msid, msname, nid::text,
      case when p_id is null then 'added ' else 'updated ' end || trim(p_name),
      jsonb_build_object('name', trim(p_name), 'active', coalesce(p_active, true), 'role', role_final,
                         'pin_changed', (p_pin is not null and p_pin <> ''), 'first_setup', bootstrap));
  return jsonb_build_object('ok', true, 'id', nid, 'role', role_final, 'first_setup', bootstrap);
end $$;

-- 9) visitors' questions: a size and a pace --------------------------------------------------------------------------------
create or replace function public._chat_questions_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(new.message, '')) > 500 then raise exception 'too_long: a lo sumo 500 letras' using errcode = 'P0001'; end if;
  new.lang := case when new.lang in ('en', 'es') then new.lang end;
  new.session := left(new.session, 64);
  if new.session is not null and (select count(*) from public.chat_questions q where q.session = new.session and q.asked_at > now() - interval '1 hour') >= 20 then
    raise exception 'too_many: espere un momento' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public._chat_questions_guard() from public, anon, authenticated;
drop trigger if exists chat_questions_guard on public.chat_questions;
create trigger chat_questions_guard before insert on public.chat_questions for each row execute function public._chat_questions_guard();

select canopy.migration_end(28, 'review_fixes');
notify pgrst, 'reload schema';
