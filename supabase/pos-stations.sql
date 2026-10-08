-- Hanging Garden Café · POS: discounts approved by a manager, and connected stations (front register + iPad)
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
-- Run after supabase/manager-mode.sql.
--
-- Discounts
--   * A discount needs the PIN of a manager, GM or owner and a reason. The approval is checked in the
--     database, written to the approvals log, and can be used for one order only.
--   * Percent (1-100 %) or a fixed amount in colones. The order keeps the subtotal, the discount, who
--     approved it and why; the total is what the customer paid.
-- Stations
--   * Every order records which device took it (front register, iPad...).
--   * An order taken on the iPad can be sent to the register unpaid: it shows on every station, the front
--     charges it, and any station marks it delivered.

create extension if not exists pgcrypto;

-- 1) Orders: station, optional name or table, subtotal and discount ------------------------------
alter table public.orders add column if not exists station text;
alter table public.orders add column if not exists subtotal_crc int;
alter table public.orders add column if not exists discount_crc int not null default 0;
alter table public.orders add column if not exists discount_reason text;
alter table public.orders add column if not exists discount_by text;
alter table public.orders add column if not exists discount_id uuid;
create unique index if not exists orders_discount_once on public.orders (discount_id) where discount_id is not null;
create index if not exists orders_unpaid_idx on public.orders (created_at) where paid = false;

-- 2) Discount approvals ------------------------------------------------------------------------------
create table if not exists public.discount_approvals (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  approved_by uuid references public.staff(id) on delete set null,
  approved_name text,
  kind text not null check (kind in ('percent', 'amount')),
  value int not null check (value > 0),
  reason text not null,
  station text,
  order_id uuid,
  used_at timestamptz
);
alter table public.discount_approvals enable row level security;
revoke all on public.discount_approvals from anon, authenticated;
grant select on public.discount_approvals to authenticated;
drop policy if exists "discounts read" on public.discount_approvals;
create policy "discounts read" on public.discount_approvals for select to authenticated using ((select public.is_owner()));

create or replace function public.approve_discount(p_staff_id uuid, p_pin text, p_kind text, p_value int,
                                                   p_subtotal int, p_reason text, p_station text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; a public.discount_approvals; amt int; why text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  why := left(trim(coalesce(p_reason, '')), 160);
  if why = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  if p_kind not in ('percent', 'amount') or p_value is null or p_value <= 0
     or (p_kind = 'percent' and p_value > 100) then
    return jsonb_build_object('ok', false, 'error', 'bad_discount'); end if;
  if p_subtotal is null or p_subtotal <= 0 then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if p_kind = 'amount' and p_value > p_subtotal then return jsonb_build_object('ok', false, 'error', 'too_big'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  amt := case when p_kind = 'percent' then round(p_subtotal * p_value / 100.0)::int else p_value end;
  insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, station)
    values (v.sid, v.sname, p_kind, p_value, why, nullif(left(trim(coalesce(p_station, '')), 40), ''))
    returning * into a;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_approved', v.sid, v.sname, a.id::text, why,
            jsonb_build_object('kind', p_kind, 'value', p_value, 'subtotal_crc', p_subtotal, 'discount_crc', amt,
                               'station', a.station));
  return jsonb_build_object('ok', true, 'id', a.id, 'amount', amt, 'name', v.sname, 'reason', why);
end $$;
revoke all on function public.approve_discount(uuid, text, text, int, int, text, text) from public, anon;
grant execute on function public.approve_discount(uuid, text, text, int, int, text, text) to authenticated;

-- 3) Every order with a discount must carry an unused approval that covers it -----------------------
create or replace function public._order_discount_check()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare a public.discount_approvals; allowed int;
begin
  if coalesce(new.discount_crc, 0) <= 0 then
    new.discount_crc := 0; new.discount_id := null; new.discount_reason := null; new.discount_by := null;
    return new;
  end if;
  if new.discount_id is null then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  select * into a from public.discount_approvals where id = new.discount_id for update;
  if a.id is null then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  if a.order_id is not null and a.order_id <> new.id then raise exception 'discount_used' using errcode = '23505'; end if;
  if new.subtotal_crc is null or new.subtotal_crc <= 0 then raise exception 'discount_no_subtotal' using errcode = 'P0001'; end if;
  allowed := case when a.kind = 'percent' then round(new.subtotal_crc * a.value / 100.0)::int
                  else least(a.value, new.subtotal_crc) end;
  if new.discount_crc > allowed + 1 then raise exception 'discount_too_big' using errcode = 'P0001'; end if;
  if new.total_crc <> new.subtotal_crc - new.discount_crc then raise exception 'discount_total' using errcode = 'P0001'; end if;
  new.discount_reason := a.reason;
  new.discount_by := a.approved_name;
  update public.discount_approvals set used_at = now(), order_id = new.id where id = a.id;
  return new;
end $$;
drop trigger if exists order_discount_check on public.orders;
create trigger order_discount_check before insert on public.orders
  for each row execute function public._order_discount_check();
-- discounts can never be added or changed after the sale
create or replace function public._order_discount_frozen()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.discount_crc is distinct from old.discount_crc or new.discount_id is distinct from old.discount_id
     or new.subtotal_crc is distinct from old.subtotal_crc then
    raise exception 'discount_frozen' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists order_discount_frozen on public.orders;
create trigger order_discount_frozen before update on public.orders
  for each row execute function public._order_discount_frozen();

-- 4) Orders sent to the register unpaid: charge them at any station, or cancel before payment --------
create or replace function public.finish_order(p_order_id uuid, p_payment_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if p_payment_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  if o.source = 'room' then
    update public.orders set paid = true, payment_method = p_payment_method, status = 'done', done_at = now(),
                             guest_phone = null where id = p_order_id;
  else
    update public.orders set paid = true, payment_method = p_payment_method where id = p_order_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cancel_unpaid_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  -- handed over but never paid: charge it, or a manager voids it with a PIN and a reason
  if o.status = 'done' then return jsonb_build_object('ok', false, 'error', 'delivered'); end if;
  update public.orders set status = 'cancelled', done_at = now(), guest_phone = null where id = p_order_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('unpaid_cancelled', null, coalesce(o.station, 'POS'), o.id::text,
            coalesce(nullif(o.guest_name, ''), case when o.pickup_number is not null then '#' || o.pickup_number end, ''),
            jsonb_build_object('total_crc', o.total_crc, 'station', o.station, 'source', o.source));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.finish_order(uuid, text), public.cancel_unpaid_order(uuid) from public, anon;
grant execute on function public.finish_order(uuid, text), public.cancel_unpaid_order(uuid) to authenticated;

notify pgrst, 'reload schema';
