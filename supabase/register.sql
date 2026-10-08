-- Hanging Garden Café · cash register: open the day with a cash float, close it against the card
-- terminal and the cash in the drawer.
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again (re-running upgrades).
--
-- The morning: the employee opens the register, types their PIN and the float they received
--   (₡50 000 by default). From then on the POS keeps every sale tagged cash / card / SINPE.
-- The evening: the employee types the total the card terminal (datáfono) printed for the day and
--   the cash counted in the drawer (float included), with their PIN. The function adds up that day's
--   sales on the server, stores both sides and the differences, and writes the audit log.
-- A day left open (no internet at closing time, or forgotten) is closed the next morning before a new
--   day can be opened; its sales are summed inside its own calendar day. A late sale after closing can be
--   folded in by closing the day again.
-- The owner sees every closing in Sales -> Register closings.

create extension if not exists pgcrypto;

-- Costa Rica calendar helpers (the server clock is UTC)
create or replace function public.cr_today()
returns date language sql stable as $$
  select (now() at time zone 'America/Costa_Rica')::date;
$$;
create or replace function public.cr_day_start(d date)
returns timestamptz language sql immutable as $$
  select (d::timestamp) at time zone 'America/Costa_Rica';
$$;
grant execute on function public.cr_today() to anon, authenticated;
grant execute on function public.cr_day_start(date) to anon, authenticated;

create table if not exists public.register_days (
  id uuid primary key default gen_random_uuid(),
  business_date date not null unique,                 -- Costa Rica calendar day
  opened_at timestamptz not null default now(),
  opened_by uuid references public.staff(id) on delete set null,
  opened_by_name text,
  float_crc int not null default 50000,               -- cash handed over in the morning
  closed_at timestamptz,
  closed_by uuid references public.staff(id) on delete set null,
  closed_by_name text,
  orders_count int,
  sales_cash_crc int,                                 -- cash paid in colones
  sales_cash_usd_crc int,                             -- cash paid in dollars, valued in colones
  sales_card_crc int,
  sales_sinpe_crc int,
  sales_other_crc int,
  sales_total_crc int,
  terminal_crc int,                                   -- what the card terminal's daily report says
  cash_counted_crc int,                               -- cash in the drawer at closing, float included
  expected_cash_crc int,                              -- float + cash sales (colones and dollars)
  cash_diff_crc int,                                  -- counted - expected  (+ over, - short)
  card_diff_crc int,                                  -- terminal - card sales
  notes text
);
create index if not exists register_days_date_idx on public.register_days (business_date desc);
alter table public.register_days enable row level security;
revoke all on public.register_days from anon, authenticated;
grant select on public.register_days to authenticated;
drop policy if exists "register read" on public.register_days;
-- the café login sees today and any day still open; older closings follow the same PIN gate as sales history
create policy "register read" on public.register_days for select to authenticated
  using ((select public.is_cafe()) and (business_date = public.cr_today() or closed_at is null
                                        or (select public.is_owner()) or (select public.sales_open())));
-- no insert/update policies: every write goes through the functions below

-- The register the POS should show: the oldest day still open, otherwise today's row, otherwise null.
-- 'today' carries the Costa Rica date so the page can tell a stale day from today.
create or replace function public.register_today()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_cafe() then (
    select to_jsonb(r) || jsonb_build_object('today', public.cr_today())
      from public.register_days r
      where r.closed_at is null or r.business_date = public.cr_today()
      order by (r.closed_at is null) desc, r.business_date
      limit 1) end;
$$;

-- Morning: open the register with the float received.
create or replace function public.register_open(p_staff_id uuid, p_pin text, p_float_crc int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; r public.register_days;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if p_float_crc is null or p_float_crc < 0 then return jsonb_build_object('ok', false, 'error', 'bad_float'); end if;
  select * into r from public.register_days where closed_at is null order by business_date limit 1;
  if r.id is not null and r.business_date < public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'previous_open', 'business_date', r.business_date);
  end if;
  if r.id is not null then return jsonb_build_object('ok', false, 'error', 'already_open'); end if;
  select * into r from public.register_days where business_date = public.cr_today();
  if r.id is not null then return jsonb_build_object('ok', false, 'error', 'already_closed'); end if;
  insert into public.register_days (business_date, opened_by, opened_by_name, float_crc)
    values (public.cr_today(), v.sid, v.sname, p_float_crc) returning * into r;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('register_open', v.sid, v.sname, r.id::text, 'opened the register with ' || p_float_crc || ' colones',
            jsonb_build_object('business_date', r.business_date, 'float_crc', p_float_crc));
  return jsonb_build_object('ok', true, 'register', to_jsonb(r));
end $$;

-- Evening: close the register. The day's sales are added up here, never trusted from the page.
-- Closes the oldest day still open; if everything is closed, closes today again (a late sale).
create or replace function public.register_close(p_staff_id uuid, p_pin text, p_terminal_crc int, p_cash_counted_crc int, p_notes text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; r public.register_days; prev public.register_days; s record; reclose boolean := false; d0 timestamptz; d1 timestamptz;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if p_terminal_crc is null or p_terminal_crc < 0 or p_cash_counted_crc is null or p_cash_counted_crc < 0 then
    return jsonb_build_object('ok', false, 'error', 'bad_amounts');
  end if;
  select * into r from public.register_days where closed_at is null order by business_date limit 1;
  if r.id is null then
    select * into r from public.register_days where business_date = public.cr_today();
    if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
    reclose := true; prev := r;
  end if;
  d0 := public.cr_day_start(r.business_date);
  d1 := public.cr_day_start(r.business_date + 1);
  select count(*)::int as n,
         coalesce(sum(case when o.payment_method = 'cash_crc' then o.total_crc end), 0)::int as cash,
         coalesce(sum(case when o.payment_method = 'cash_usd' then o.total_crc end), 0)::int as usd,
         coalesce(sum(case when o.payment_method = 'card'     then o.total_crc end), 0)::int as card,
         coalesce(sum(case when o.payment_method = 'sinpe'    then o.total_crc end), 0)::int as sinpe,
         coalesce(sum(case when o.payment_method not in ('cash_crc','cash_usd','card','sinpe') then o.total_crc end), 0)::int as other,
         coalesce(sum(o.total_crc), 0)::int as total
    into s
    from public.orders o
    where o.created_at >= d0 and o.created_at < d1 and o.voided_at is null and coalesce(o.paid, true);
  update public.register_days set
      closed_at = now(), closed_by = v.sid, closed_by_name = v.sname,
      orders_count = s.n, sales_cash_crc = s.cash, sales_cash_usd_crc = s.usd, sales_card_crc = s.card,
      sales_sinpe_crc = s.sinpe, sales_other_crc = s.other, sales_total_crc = s.total,
      terminal_crc = p_terminal_crc, cash_counted_crc = p_cash_counted_crc,
      expected_cash_crc = float_crc + s.cash + s.usd,
      cash_diff_crc = p_cash_counted_crc - (float_crc + s.cash + s.usd),
      card_diff_crc = p_terminal_crc - s.card,
      notes = nullif(trim(coalesce(p_notes, '')), '')
    where id = r.id returning * into r;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values (case when reclose then 'register_reclose' else 'register_close' end, v.sid, v.sname, r.id::text,
            (case when reclose then 'closed the register again: ' else 'closed the register: ' end) ||
            'cash ' || (case when r.cash_diff_crc >= 0 then '+' else '' end) || r.cash_diff_crc ||
            ', card ' || (case when r.card_diff_crc >= 0 then '+' else '' end) || r.card_diff_crc,
            case when reclose then to_jsonb(r) || jsonb_build_object('previous', to_jsonb(prev)) else to_jsonb(r) end);
  return jsonb_build_object('ok', true, 'reclosed', reclose, 'register', to_jsonb(r) || jsonb_build_object('today', public.cr_today()));
end $$;

revoke all on function public.register_today() from public, anon;
revoke all on function public.register_open(uuid, text, int) from public, anon;
revoke all on function public.register_close(uuid, text, int, int, text) from public, anon;
grant execute on function public.register_today() to authenticated;
grant execute on function public.register_open(uuid, text, int) to authenticated;
grant execute on function public.register_close(uuid, text, int, int, text) to authenticated;

notify pgrst, 'reload schema';
