-- Hanging Garden Café · POS: open bills (pay later) and split payments
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
-- Run after supabase/pos-stations.sql.
--
-- Open bills
--   * An order left to pay later can be opened at any device: its items, what was paid and what is left.
--   * Items can be added to it later (a dessert, another coffee). Kitchen items go to the kitchen as a new
--     round and the kitchen screen shows only what is new.
--   * An item can be taken off a bill that is not paid yet, and it is written in the approvals log. Once the
--     bill was delivered, it needs the PIN of a manager (same rule as cancelling), except for an item added
--     in the last 10 minutes (a mistake fixed right away).
--   * A bill left open past midnight still shows the next days (up to 30) until it is paid.
--   * A discount (reason and a manager's PIN) can also be given on a bill already taken, for what is still
--     to pay, and taken off again.
-- Split payments
--   * A person pays only their items, an equal part, or an amount, each with their own payment method.
--     Each payment is its own sale (so the register closing and the sales by method stay right) and is
--     taken off the bill. The last payment closes the bill.
--   * The bill's discount follows the manager's approval as items come and go (a percentage follows the bill,
--     an amount stays, never more than the manager saw). Each person paying by item pays their items less
--     their share of the discount still unused; whoever pays the last items pays what is left.
--   * Voiding one of those payments (Orders, with a manager PIN) puts its amount back on the bill while
--     the bill is still open. A payment made on an earlier day (that day is already counted at the register)
--     is given back today instead, the same way it was paid.
--   * Paying, taking an item off and adding items are refused when the bill changed on another device since
--     the screen showed it, and an add sent twice (a lost reply) counts once.

create extension if not exists pgcrypto;

-- 1) Bills and payments -------------------------------------------------------------------------------
alter table public.orders add column if not exists part_of uuid references public.orders(id) on delete set null;
alter table public.orders add column if not exists parts_crc int not null default 0;     -- paid so far in parts
alter table public.orders add column if not exists kitchen_round int not null default 1; -- items added later
alter table public.orders add column if not exists kitchen_rev int not null default 0;   -- kitchen items added, any round
alter table public.orders add column if not exists given_back_at timestamptz;              -- a payment given back on a later day
alter table public.order_items add column if not exists round int not null default 1;
alter table public.order_items add column if not exists paid_qty int not null default 0;
alter table public.order_items add column if not exists added_at timestamptz not null default now();
create index if not exists orders_part_of_idx on public.orders (part_of) where part_of is not null;
-- a discount given on a bill later (tab_set_discount) covers only the items not paid yet: the list value of the
-- items already paid by item then, and the discount they had got
alter table public.discount_approvals add column if not exists base_crc int;
alter table public.discount_approvals add column if not exists base_used_crc int;

-- which items each partial payment covered
create table if not exists public.order_part_lines (
  part_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid not null,
  qty int not null check (qty > 0),
  primary key (part_id, item_id)
);
alter table public.order_part_lines enable row level security;
revoke all on public.order_part_lines from anon, authenticated;
grant select on public.order_part_lines to authenticated;
drop policy if exists "part lines read" on public.order_part_lines;
create policy "part lines read" on public.order_part_lines for select to authenticated
  using (exists (select 1 from public.orders o where o.id = part_id));

-- of parts_crc, what was paid for picked items (the rest was paid on account). Filled in once for bills already
-- paid in part by item under the first version of this file.
do $mig$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'orders' and column_name = 'parts_items_crc') then
    alter table public.orders add column parts_items_crc int not null default 0;
    update public.orders b set parts_items_crc = coalesce((select sum(p.total_crc) from public.orders p
                                                           where p.part_of = b.id and p.voided_at is null
                                                             and exists (select 1 from public.order_part_lines l where l.part_id = p.id)), 0)
     where b.part_of is null and coalesce(b.parts_crc, 0) > 0 and not coalesce(b.paid, false);
  end if;
end $mig$;

-- items added with "Add items": the same add sent twice (the reply was lost and it was tapped again) counts once
create table if not exists public.tab_adds (
  id uuid primary key,
  order_id uuid not null,
  result jsonb not null,
  at timestamptz not null default now()
);
alter table public.tab_adds enable row level security;
revoke all on public.tab_adds from anon, authenticated;

-- 2) Only the functions below keep these numbers: a sale typed at the till always starts clean ---------
create or replace function public._order_tab_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.part_of := null; new.parts_crc := 0; new.parts_items_crc := 0; new.kitchen_round := 1; new.kitchen_rev := 0;
    new.given_back_at := null;
  end if;
  return new;
end $$;
drop trigger if exists order_tab_defaults on public.orders;
create trigger order_tab_defaults before insert on public.orders
  for each row execute function public._order_tab_defaults();

-- when an order was rung (also an old bill the till no longer reads)
create or replace function public._order_rung_at(p_order_id uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select created_at from public.orders where id = p_order_id;
$$;
revoke all on function public._order_rung_at(uuid) from public, anon;
grant execute on function public._order_rung_at(uuid) to authenticated;

-- a line the till writes belongs to its sale and is as old as the order; only "Add items" (tab_add_items, run
-- as the owner) stamps the time it was added, so only those lines can be taken off within 10 minutes without a PIN
create or replace function public._order_item_tab_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.round := 1; new.paid_qty := 0;
    new.added_at := least(now(), coalesce(public._order_rung_at(new.order_id), now()));
  end if;
  return new;
end $$;
drop trigger if exists order_item_tab_defaults on public.order_items;
create trigger order_item_tab_defaults before insert on public.order_items
  for each row execute function public._order_item_tab_defaults();

-- the till writes the lines of a sale once, all in one insert, with it; items added later go through
-- tab_add_items. A line typed into a bill that already has lines (a price below zero to empty it) is refused.
create or replace function public._order_other_lines(p_orders uuid[], p_ids uuid[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.order_items i where i.order_id = any(p_orders) and not (i.id = any(p_ids)));
$$;
revoke all on function public._order_other_lines(uuid[], uuid[]) from public, anon;
grant execute on function public._order_other_lines(uuid[], uuid[]) to authenticated;
create or replace function public._order_items_once()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if exists (select 1 from new_lines where qty < 1) then raise exception 'bad_qty' using errcode = 'P0001'; end if;
    if public._order_other_lines((select array_agg(distinct order_id) from new_lines), (select array_agg(id) from new_lines)) then
      raise exception 'order_has_lines' using errcode = 'P0001';
    end if;
  end if;
  return null;
end $$;
drop trigger if exists order_items_once on public.order_items;
create trigger order_items_once after insert on public.order_items referencing new table as new_lines
  for each statement execute function public._order_items_once();

-- the discount stays frozen for the till; adding or taking off items keeps the bill's subtotal right
-- (runs as the caller, so the functions below may change it and a direct edit from the till may not)
create or replace function public._order_discount_frozen()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and (
       new.discount_crc is distinct from old.discount_crc or new.discount_id is distinct from old.discount_id
       or new.subtotal_crc is distinct from old.subtotal_crc) then
    raise exception 'discount_frozen' using errcode = 'P0001';
  end if;
  return new;
end $$;

-- a delivered order stays delivered for the till: it decides when a manager's PIN is needed
create or replace function public._order_done_kept()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and old.done_at is not null and new.done_at is null then
    raise exception 'order_closed' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists order_done_kept on public.orders;
create trigger order_done_kept before update on public.orders
  for each row execute function public._order_done_kept();

create or replace function public._tab_label(o public.orders)
returns text language sql stable as $$
  select case when o.pickup_number is not null then '#' || o.pickup_number
              when coalesce(o.guest_name, '') <> '' then o.guest_name
              else to_char(o.created_at at time zone 'America/Costa_Rica', 'HH24:MI') end;
$$;

-- The bill's discount for what is on it now (subtotal_crc and discount_crc are set only when the bill has one):
-- the most the manager's approval allows, as at the sale (a percentage follows the bill, an amount stays, never
-- more than the manager saw); never less than what the items already paid by item got (p_used), and never more
-- than that plus what is still open (an item is at most free).
drop function if exists public._tab_net(public.orders, int);
create or replace function public._tab_discount(o public.orders, p_sub int, p_used int, p_open int)
returns int language plpgsql stable set search_path = public as $$
declare a public.discount_approvals; d int;
begin
  if o.subtotal_crc is null then return 0; end if;
  select * into a from public.discount_approvals where id = o.discount_id;
  if a.id is null then
    d := least(coalesce(o.discount_crc, 0), greatest(0, p_sub));
  else
    -- an approval given on the bill later covers the items not paid yet then (base: the items paid by item
    -- before, which keep the discount they had got)
    p_sub := greatest(0, p_sub - coalesce(a.base_crc, 0));
    d := case when a.kind = 'percent' then round(p_sub * a.value / 100.0)::int else least(a.value, p_sub) end;
    d := least(d, coalesce(a.amount_crc, o.discount_crc, 0)) + coalesce(a.base_used_crc, 0);
  end if;
  return greatest(0, p_used, least(d, p_used + greatest(0, p_open)));
end $$;

-- 3) Add items to a bill that is not paid yet -----------------------------------------------------------
-- p_items: [{"menu_item_id": "...", "qty": 1}, ...]. Names and prices come from the menu.
-- p_add_id: one id per "Add to the bill" on the device; the same add sent again (a lost reply) is not added twice.
drop function if exists public.tab_add_items(uuid, jsonb);
create or replace function public.tab_add_items(p_order_id uuid, p_items jsonb, p_add_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; it jsonb; mi record; n int; kitchen boolean := false; added int := 0; rnd int;
        open_value int; used int; s_new int; d_new int; t_new int; res jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if jsonb_array_length(p_items) > 40 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_add_id is not null then
    select result into res from public.tab_adds where id = p_add_id and order_id = o.id;
    if res is not null then return res || jsonb_build_object('repeat', true); end if;
  end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  -- check every line before writing anything
  for it in select * from jsonb_array_elements(p_items) loop
    if coalesce(it->>'qty', '') !~ '^[0-9]{1,3}$' or coalesce(it->>'menu_item_id', '') !~* '^[0-9a-f-]{36}$' then
      return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
    n := (it->>'qty')::int;
    if n < 1 or n > 50 then return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
    select m.id, m.price_crc, coalesce(c.kitchen, false) as kitchen into mi
      from public.menu_items m left join public.menu_categories c on c.id = m.category_id
      where m.id = (it->>'menu_item_id')::uuid;
    if mi.id is null then return jsonb_build_object('ok', false, 'error', 'unknown_item'); end if;
    kitchen := kitchen or mi.kitchen;
    added := added + mi.price_crc * n;
  end loop;
  -- what the bill comes to: items added later are at full price; the discount follows the approval
  select coalesce(sum((qty - paid_qty) * price_crc), 0)::int, coalesce(sum(paid_qty * price_crc), 0)::int - o.parts_items_crc
    into open_value, used from public.order_items where order_id = o.id;
  if o.subtotal_crc is not null then
    s_new := o.subtotal_crc + added;
    d_new := public._tab_discount(o, s_new, used, open_value + added);
    t_new := s_new - d_new - o.parts_crc;
  else
    t_new := o.total_crc + added;
  end if;
  -- a line below zero (a combo discount) cannot take the bill below what was already paid
  if t_new < 0 then
    return jsonb_build_object('ok', false, 'error', case when o.parts_crc > 0 then 'refund_first' else 'below_zero' end); end if;
  -- kitchen items on a bill the kitchen already finished start a new round: the kitchen sees only those
  -- (also on a ticket left over from an earlier day, which the kitchen screen no longer shows)
  rnd := o.kitchen_round;
  if kitchen and (o.status not in ('new', 'preparing') or coalesce(o.accepted_at, o.created_at) < public.cr_today_start()) then
    rnd := o.kitchen_round + 1;
    -- its number stand may be with another guest by now: then the bill goes by its name or table
    update public.orders set kitchen_round = rnd, status = 'preparing', needs_kitchen = true,
                             accepted_at = now(), ready_at = null,
                             pickup_number = case when o.pickup_number is not null and exists (
                                 select 1 from public.orders x
                                  where x.id <> o.id and x.pickup_number = o.pickup_number
                                    and x.part_of is null and x.voided_at is null
                                    and x.status in ('new', 'preparing', 'ready'))
                               then null else pickup_number end
      where id = o.id;
  elsif kitchen and not coalesce(o.needs_kitchen, false) then
    update public.orders set needs_kitchen = true where id = o.id;
  end if;
  -- the kitchen screen notices anything added, also while it is still making the rest
  if kitchen then update public.orders set kitchen_rev = kitchen_rev + 1 where id = o.id; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    n := (it->>'qty')::int;
    select m.name, m.price_crc into mi from public.menu_items m where m.id = (it->>'menu_item_id')::uuid;
    insert into public.order_items (order_id, item_name, price_crc, qty, round)
      values (o.id, mi.name, mi.price_crc, n, rnd);
  end loop;
  update public.orders set total_crc = t_new,
                           subtotal_crc = case when subtotal_crc is null then null else s_new end,
                           discount_crc = case when subtotal_crc is null then discount_crc else d_new end
    where id = o.id;
  res := jsonb_build_object('ok', true, 'added', added, 'total', t_new, 'kitchen', kitchen, 'round', rnd);
  if p_add_id is not null then
    delete from public.tab_adds where at < now() - interval '2 days';
    insert into public.tab_adds (id, order_id, result) values (p_add_id, o.id, res) on conflict (id) do nothing;
  end if;
  return res;
end $$;

-- 4) Take an item off a bill that is not paid yet (logged) ---------------------------------------------
-- Before the bill was delivered, or within 10 minutes of adding the item, the till can do it alone.
-- After that it needs the PIN of a manager, GM or owner, like cancelling a delivered order.
-- p_expect: the bill's total the screen showed; when it changed meanwhile (on another device, or this same take-off
-- already went through and its reply was lost) nothing is taken off.
drop function if exists public.tab_remove_item(uuid, int, text, text);
drop function if exists public.tab_remove_item(uuid, int, text, text, uuid, text);
create or replace function public.tab_remove_item(p_item_id uuid, p_qty int, p_reason text, p_station text,
                                                  p_staff_id uuid default null, p_pin text default null,
                                                  p_expect int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; li record; v record; open_value int; open_left int; open_units int; used int; val int; cut int;
        s_new int; d_new int; t_new int; mid uuid; why text; who text; by_id uuid; last_method text; closes boolean;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select order_id into li from public.order_items where id = p_item_id;
  if li.order_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into o from public.orders where id = li.order_id for update;
  if o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if p_expect is not null and p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  select * into li from public.order_items where id = p_item_id for update;
  -- another device took it off meanwhile
  if li.id is null or li.order_id is distinct from o.id then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  if p_qty is null or p_qty < 1 or p_qty > li.qty - li.paid_qty then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  why := left(trim(coalesce(p_reason, '')), 120);
  who := coalesce(nullif(left(trim(coalesce(p_station, '')), 40), ''), o.station, 'POS');
  -- delivered already, and not a mistake fixed right away: a manager approves it
  if (o.status = 'done' or o.done_at is not null) and li.added_at < now() - interval '10 minutes' then
    if p_staff_id is null or coalesce(p_pin, '') = '' then return jsonb_build_object('ok', false, 'error', 'needs_pin'); end if;
    if why = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
    select * into v from public._verify_pin(p_staff_id, p_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    who := v.sname; by_id := v.sid;
  end if;
  select coalesce(sum((qty - paid_qty) * price_crc), 0)::int, coalesce(sum(qty - paid_qty), 0)::int,
         coalesce(sum(paid_qty * price_crc), 0)::int - o.parts_items_crc
    into open_value, open_units, used from public.order_items where order_id = o.id;
  val := li.price_crc * p_qty;
  open_left := open_value - val;
  -- nothing would be left on the bill: cancel it instead
  if open_units - p_qty <= 0 and coalesce(o.parts_crc, 0) = 0 then return jsonb_build_object('ok', false, 'error', 'use_cancel'); end if;
  -- what the bill comes to without it; the discount follows the manager's approval (see _tab_discount)
  if o.subtotal_crc is not null then
    s_new := o.subtotal_crc - val;
    d_new := public._tab_discount(o, s_new, used, open_left);
    t_new := s_new - d_new - o.parts_crc;
  else
    t_new := o.total_crc - val;
  end if;
  if t_new < 0 then
    -- money paid on account already covers it: a manager voids that payment first (it goes back on the bill),
    -- then the item comes off and the rest is charged again. Or what stays is a combo discount line alone.
    return jsonb_build_object('ok', false, 'error', case when open_left < 0 then 'combo_first' else 'refund_first' end);
  end if;
  -- what was paid in parts covers everything that stays: the bill closes
  closes := coalesce(o.parts_crc, 0) > 0 and (open_units - p_qty <= 0 or t_new = 0);
  cut := o.total_crc - t_new;
  if li.qty - p_qty = 0 then delete from public.order_items where id = li.id;
  else update public.order_items set qty = qty - p_qty where id = li.id; end if;
  update public.orders set total_crc = t_new,
                           subtotal_crc = case when subtotal_crc is null then null else s_new end,
                           discount_crc = case when subtotal_crc is null then discount_crc else d_new end
    where id = o.id;
  -- nothing for the kitchen is left in a new round: the bill goes back to where it was. Only lines that are
  -- surely not for the kitchen may stay (a line whose name is no longer on the menu counts as kitchen food).
  -- The round number stays, so a late "Ready" on the old ticket cannot finish a newer round.
  if o.kitchen_round > 1 and o.status <> 'done'
     and not exists (select 1 from public.order_items i
                      where i.order_id = o.id and i.round = o.kitchen_round
                        and not exists (select 1 from public.menu_items m join public.menu_categories c on c.id = m.category_id
                                         where lower(m.name) = lower(i.item_name) and not coalesce(c.kitchen, false))) then
    update public.orders set status = case when done_at is not null then 'done' else 'ready' end,
                             ready_at = coalesce(ready_at, now())
      where id = o.id;
  end if;
  -- nothing left to pay: what was paid in parts covered the rest
  if closes then
    select payment_method into last_method from public.orders
      where part_of = o.id and voided_at is null order by created_at desc limit 1;
    update public.order_items set paid_qty = qty where order_id = o.id;
    update public.orders set paid = true, payment_method = coalesce(last_method, 'other'), total_crc = 0 where id = o.id;
    -- left open past closing and settled on a later day: it belongs to today, where the till and the kitchen see it
    if (o.created_at at time zone 'America/Costa_Rica')::date < (now() at time zone 'America/Costa_Rica')::date then
      update public.orders set created_at = now(),
             -- a kitchen ticket left over from an earlier day is not brought back to the kitchen screen
             status = case when status in ('new', 'preparing', 'ready') and coalesce(accepted_at, created_at) < public.cr_today_start()
                           then 'done' else status end,
             done_at = case when status in ('new', 'preparing', 'ready') and coalesce(accepted_at, created_at) < public.cr_today_start()
                            then coalesce(done_at, now()) else done_at end
        where id = o.id;
    end if;
  end if;
  -- the stock it used goes back (a returned sale, so a later void of the bill still balances)
  if to_regclass('public.stock_moves') is not null then
    select id into mid from public.menu_items where lower(name) = lower(li.item_name) order by available desc limit 1;
    if mid is not null then
      insert into public.stock_moves (item_id, kind, qty, order_id, note)
        select r.stock_item_id, 'sale', r.qty * p_qty, o.id, li.item_name || ' · taken off the bill'
          from public.recipes r where r.menu_item_id = mid;
    end if;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('tab_item_removed', by_id, who, o.id::text,
            p_qty || '× ' || li.item_name || ' · ' || public._tab_label(o) || case when why <> '' then ' · ' || why else '' end,
            jsonb_build_object('qty', p_qty, 'item', li.item_name, 'value_crc', val, 'bill_cut_crc', cut, 'reason', why,
                               'bill', public._tab_label(o), 'station', nullif(trim(coalesce(p_station, '')), ''),
                               'approved', by_id is not null));
  return jsonb_build_object('ok', true, 'total', t_new, 'closed', closes);
end $$;

-- 5) Pay a bill: all of it, some items, or an amount ---------------------------------------------------
-- the items picked for one payment, one row per item (the lines were checked before this is called)
create or replace function public._tab_pick(p_lines jsonb)
returns table (item_id uuid, qty int) language sql immutable as $$
  select (x->>'item_id')::uuid, sum((x->>'qty')::int)::int
    from jsonb_array_elements(p_lines) x
   where (x->>'qty')::int > 0
   group by 1;
$$;

-- p_lines: [{"item_id": "...", "qty": 1}, ...] for the items one person pays; or p_amount; or neither = all.
-- p_expect: the bill's total the screen showed; when it changed on another device meanwhile nothing is charged.
drop function if exists public.tab_pay(uuid, text, jsonb, int, text);
create or replace function public.tab_pay(p_order_id uuid, p_method text, p_lines jsonb, p_amount int, p_station text,
                                          p_expect int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; open_value int; val int := 0; amt int; ln jsonb; li record; part uuid; what text := ''; onacc int;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if p_expect is not null and p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  -- a bill at 0 (a courtesy) is closed as a whole
  if o.total_crc <= 0 and (p_lines is not null or p_amount is not null) then
    return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;
  select coalesce(sum((qty - paid_qty) * price_crc), 0)::int into open_value from public.order_items where order_id = o.id;

  if p_lines is not null and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then
    for ln in select * from jsonb_array_elements(p_lines) loop
      if coalesce(ln->>'qty', '') !~ '^[0-9]{1,3}$' or coalesce(ln->>'item_id', '') !~* '^[0-9a-f-]{36}$' then
        return jsonb_build_object('ok', false, 'error', 'changed'); end if;
    end loop;
    for li in select i.id, i.item_name, i.price_crc, i.qty - i.paid_qty as open_qty, p.qty as pick
                from public._tab_pick(p_lines) p left join public.order_items i on i.id = p.item_id and i.order_id = o.id
               order by i.round, i.added_at, i.item_name loop
      if li.id is null or li.pick > li.open_qty then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
      val := val + li.price_crc * li.pick;
      what := what || case when what = '' then '' else ', ' end || li.pick || '× ' || li.item_name;
    end loop;
    if val <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;
    -- this person pays their items less their share of the discount still unused (what is left to pay for the
    -- open items, counting what was paid on account, spread over them); whoever pays the last items pays what is left
    onacc := greatest(0, o.parts_crc - o.parts_items_crc);
    amt := case when val >= open_value then o.total_crc
                else least(o.total_crc, round(val::numeric * (o.total_crc + onacc) / open_value)::int) end;
  elsif p_amount is not null then
    if p_amount < 1 or p_amount > o.total_crc then return jsonb_build_object('ok', false, 'error', 'bad_amount'); end if;
    amt := p_amount;
  else
    amt := o.total_crc;
  end if;
  if amt < 1 and o.total_crc > 0 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;

  if amt >= o.total_crc then
    -- the last payment closes the bill on the bill itself
    update public.order_items set paid_qty = qty where order_id = o.id;
    if o.source = 'room' and o.status not in ('new', 'preparing') then
      update public.orders set paid = true, payment_method = p_method, status = 'done', done_at = now(), guest_phone = null
        where id = o.id;
    else
      update public.orders set paid = true, payment_method = p_method where id = o.id;
    end if;
    -- left unpaid past closing and paid on a later day: it belongs to the day the money came in
    if (o.created_at at time zone 'America/Costa_Rica')::date < (now() at time zone 'America/Costa_Rica')::date then
      update public.orders set created_at = now(),
             -- a kitchen ticket left over from an earlier day is not brought back to the kitchen screen
             status = case when status in ('new', 'preparing', 'ready') and coalesce(accepted_at, created_at) < public.cr_today_start()
                           then 'done' else status end,
             done_at = case when status in ('new', 'preparing', 'ready') and coalesce(accepted_at, created_at) < public.cr_today_start()
                            then coalesce(done_at, now()) else done_at end
        where id = o.id;
    end if;
    return jsonb_build_object('ok', true, 'closed', true, 'amount', o.total_crc, 'left', 0, 'order_id', o.id);
  end if;

  -- a payment for part of the bill is a sale of its own, with its own payment method
  part := gen_random_uuid();
  insert into public.orders (id, created_at, total_crc, payment_method, paid, status, done_at, source, needs_kitchen,
                             pickup_number, station, guest_name, part_of, notes)
    values (part, now(), amt, p_method, true, 'done', now(), 'front', false,
            o.pickup_number, coalesce(nullif(left(trim(coalesce(p_station, '')), 40), ''), o.station), o.guest_name, o.id,
            left('Part of ' || public._tab_label(o) || case when what <> '' then ': ' || what else '' end, 200));
  if val > 0 then
    insert into public.order_part_lines (part_id, item_id, qty) select part, p.item_id, p.qty from public._tab_pick(p_lines) p;
    update public.order_items i set paid_qty = i.paid_qty + p.qty
      from public._tab_pick(p_lines) p where p.item_id = i.id and i.order_id = o.id;
  end if;
  update public.orders set total_crc = total_crc - amt, parts_crc = parts_crc + amt,
                           parts_items_crc = parts_items_crc + case when val > 0 then amt else 0 end where id = o.id;
  return jsonb_build_object('ok', true, 'closed', false, 'amount', amt, 'left', o.total_crc - amt, 'part_id', part, 'order_id', o.id);
end $$;

-- 6) Name or table on a bill ----------------------------------------------------------------------------
create or replace function public.tab_rename(p_order_id uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  update public.orders set guest_name = nullif(left(trim(coalesce(p_name, '')), 40), '') where id = o.id;
  return jsonb_build_object('ok', true);
end $$;

-- 6b) A discount on a bill already taken: approved with the PIN of an owner, GM or manager (approve_discount,
--     made for the value of the items not paid yet), like at the sale. It covers the items not paid yet; items
--     already paid by item keep the discount they got. p_discount_id null takes the discount off.
drop function if exists public.tab_set_discount(uuid, uuid, int);
create or replace function public.tab_set_discount(p_order_id uuid, p_discount_id uuid, p_expect int default null,
                                                   p_station text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; a public.discount_approvals; s int; paid_value int; open_value int; used int; d int; t int;
        st text := nullif(left(trim(coalesce(p_station, '')), 40), '');
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if p_expect is not null and p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  select coalesce(sum(qty * price_crc), 0)::int, coalesce(sum(paid_qty * price_crc), 0)::int
    into s, paid_value from public.order_items where order_id = o.id;
  open_value := s - paid_value;
  used := greatest(0, paid_value - o.parts_items_crc);
  -- the bill's value from its own books (a sale whose discount could not be verified keeps what it charged)
  s := coalesce(o.subtotal_crc, o.total_crc + o.parts_crc);
  if p_discount_id is null then
    d := case when o.subtotal_crc is null then 0 else used end;
    t := s - d - o.parts_crc;
    if t < 0 then return jsonb_build_object('ok', false, 'error', 'refund_first'); end if;
    update public.orders set subtotal_crc = case when d > 0 then s else null end, discount_crc = d, discount_id = null,
                             discount_reason = case when d > 0 then discount_reason else null end,
                             discount_by = case when d > 0 then discount_by else null end, total_crc = t
      where id = o.id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('tab_discount_removed', null, coalesce(st, o.station, 'POS'), o.id::text, public._tab_label(o),
              jsonb_build_object('discount_crc', coalesce(o.discount_crc, 0) - d, 'total_crc', t, 'bill', public._tab_label(o),
                                 'reason', o.discount_reason, 'station', st));
    return jsonb_build_object('ok', true, 'total', t, 'discount', d);
  end if;
  select * into a from public.discount_approvals where id = p_discount_id for update;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'discount_not_approved'); end if;
  if a.order_id is not null and a.order_id <> o.id then return jsonb_build_object('ok', false, 'error', 'discount_used'); end if;
  if now() > a.created_at + interval '30 minutes' then return jsonb_build_object('ok', false, 'error', 'discount_expired'); end if;
  -- it covers the items not paid yet: those paid by item keep their value and the discount they got
  update public.discount_approvals set base_crc = paid_value, base_used_crc = used where id = a.id;
  o.subtotal_crc := s; o.discount_id := a.id; o.discount_crc := 0;
  d := public._tab_discount(o, s, used, open_value);
  t := s - d - o.parts_crc;
  if t < 0 then
    update public.discount_approvals set base_crc = a.base_crc, base_used_crc = a.base_used_crc where id = a.id;
    return jsonb_build_object('ok', false, 'error', 'refund_first');
  end if;
  update public.orders set subtotal_crc = s, discount_crc = d, discount_id = a.id, discount_reason = a.reason,
                           discount_by = a.approved_name, total_crc = t
    where id = o.id;
  update public.discount_approvals set used_at = now(), order_id = o.id where id = a.id;
  return jsonb_build_object('ok', true, 'total', t, 'discount', d);
end $$;

-- a discount taken off (tab_set_discount) leaves only what items already paid by item got; when one of those
-- payments is voided or given back, its items are to pay again in full
create or replace function public._tab_removed_discount(p_bill uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b public.orders; used int; t int;
begin
  select * into b from public.orders where id = p_bill;
  if b.id is null or b.discount_id is not null or b.subtotal_crc is null or coalesce(b.paid, false) then return; end if;
  select greatest(0, coalesce(sum(paid_qty * price_crc), 0)::int - b.parts_items_crc) into used from public.order_items where order_id = b.id;
  used := least(used, coalesce(b.discount_crc, 0));
  t := b.subtotal_crc - used - b.parts_crc;
  if t < 0 or used = coalesce(b.discount_crc, 0) then return; end if;
  update public.orders set discount_crc = used, total_crc = t,
                           subtotal_crc = case when used > 0 then subtotal_crc end,
                           discount_reason = case when used > 0 then discount_reason end,
                           discount_by = case when used > 0 then discount_by end
    where id = b.id;
end $$;
revoke all on function public._tab_removed_discount(uuid) from public, anon, authenticated;

-- 7) A bill already partly paid cannot be cancelled whole: take items off one by one instead ------------
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
  if o.status = 'done' or o.done_at is not null then return jsonb_build_object('ok', false, 'error', 'delivered'); end if;
  if coalesce(o.parts_crc, 0) > 0 then return jsonb_build_object('ok', false, 'error', 'has_parts'); end if;
  update public.orders set status = 'cancelled', done_at = now(), guest_phone = null where id = p_order_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('unpaid_cancelled', null, coalesce(o.station, 'POS'), o.id::text,
            coalesce(nullif(o.guest_name, ''), case when o.pickup_number is not null then '#' || o.pickup_number end, ''),
            jsonb_build_object('total_crc', o.total_crc, 'station', o.station, 'source', o.source));
  return jsonb_build_object('ok', true);
end $$;

-- 7b) Money paid on an earlier day for a bill still open is given back today ---------------------------------
-- That day was already counted at the register, so its payment is not voided. The money goes back out today,
-- the same way it came in (a payment below zero, today), and its amount goes back on the bill. A manager approves.
create or replace function public.tab_give_back(p_manager_id uuid, p_manager_pin text, p_part_id uuid, p_reason text,
                                                p_station text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; p public.orders; b public.orders; bill_id uuid; why text; had_lines boolean;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  why := left(trim(coalesce(p_reason, '')), 160);
  if why = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select part_of into bill_id from public.orders where id = p_part_id;
  if bill_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  -- the bill first, then the payment (the same order the other bill functions lock in)
  select * into b from public.orders where id = bill_id for update;
  select * into p from public.orders where id = p_part_id for update;
  if p.voided_at is not null or p.given_back_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if not coalesce(p.paid, false) or p.total_crc <= 0 then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.created_at >= public.cr_today_start() then return jsonb_build_object('ok', false, 'error', 'same_day'); end if;
  if b.id is null or b.voided_at is not null or b.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if b.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  had_lines := exists (select 1 from public.order_part_lines where part_id = p.id);
  insert into public.orders (id, created_at, total_crc, payment_method, paid, status, done_at, source, needs_kitchen,
                             pickup_number, station, guest_name, part_of, notes)
    values (gen_random_uuid(), now(), -p.total_crc, p.payment_method, true, 'done', now(), 'front', false,
            b.pickup_number, coalesce(nullif(left(trim(coalesce(p_station, '')), 40), ''), b.station), b.guest_name, b.id,
            left('Given back · ' || coalesce(p.notes, public._tab_label(b)), 200));
  update public.orders set total_crc = total_crc + p.total_crc, parts_crc = greatest(0, parts_crc - p.total_crc),
                           parts_items_crc = case when had_lines then greatest(0, parts_items_crc - p.total_crc) else parts_items_crc end
    where id = b.id;
  -- the items it paid for are to pay again
  if had_lines then
    update public.order_items i set paid_qty = greatest(0, i.paid_qty - l.qty)
      from public.order_part_lines l where l.part_id = p.id and l.item_id = i.id;
    delete from public.order_part_lines where part_id = p.id;
    perform public._tab_removed_discount(b.id);
  end if;
  update public.orders set given_back_at = now() where id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('payment_given_back', v.sid, v.sname, b.id::text, why || ' · ' || public._tab_label(b),
            jsonb_build_object('total_crc', p.total_crc, 'payment_method', p.payment_method, 'paid_at', p.created_at,
                               'bill', public._tab_label(b), 'part_id', p.id,
                               'station', nullif(trim(coalesce(p_station, '')), '')));
  return jsonb_build_object('ok', true, 'given_back', p.total_crc, 'method', p.payment_method, 'total', b.total_crc + p.total_crc);
end $$;

-- 8) Voids and split bills ------------------------------------------------------------------------------
--   * voiding a partial payment while the bill is still open puts its amount back on the bill;
--   * voiding the bill itself gives back the stock of what is left on it, not of what the other people paid for
create or replace function public._order_tab_voided()
returns trigger language plpgsql security definer set search_path = public as $$
declare m public.orders;
begin
  if new.voided_at is null or old.voided_at is not null then return new; end if;
  -- a payment already given back is no longer on the bill
  if new.part_of is not null and new.given_back_at is not null then return new; end if;
  if new.part_of is not null then
    select * into m from public.orders where id = new.part_of for update;
    if m.id is not null and not coalesce(m.paid, false) and m.voided_at is null and m.status <> 'cancelled' then
      update public.orders set total_crc = total_crc + new.total_crc, parts_crc = greatest(0, parts_crc - new.total_crc),
                               parts_items_crc = case when exists (select 1 from public.order_part_lines where part_id = new.id)
                                                      then greatest(0, parts_items_crc - new.total_crc) else parts_items_crc end
        where id = m.id;
      update public.order_items i set paid_qty = greatest(0, i.paid_qty - l.qty)
        from public.order_part_lines l where l.part_id = new.id and l.item_id = i.id;
      perform public._tab_removed_discount(m.id);
    end if;
  elsif coalesce(new.parts_crc, 0) > 0 and to_regclass('public.stock_moves') is not null then
    -- the void of the bill returns all its stock (inventory.sql); the items paid in parts were eaten
    insert into public.stock_moves (item_id, kind, qty, order_id, note)
      select r.stock_item_id, 'sale', -(r.qty * l.qty), null, i.item_name || ' · paid in part, bill voided'
        from public.order_part_lines l
        join public.orders p on p.id = l.part_id and p.part_of = new.id and p.voided_at is null
        join public.order_items i on i.id = l.item_id
        join lateral (select id from public.menu_items where lower(name) = lower(i.item_name) order by available desc limit 1) mi on true
        join public.recipes r on r.menu_item_id = mi.id;
  end if;
  return new;
end $$;
drop trigger if exists order_part_voided on public.orders;
drop trigger if exists order_tab_voided on public.orders;
create trigger order_tab_voided after update of voided_at on public.orders
  for each row execute function public._order_tab_voided();
drop function if exists public._order_part_voided();

-- 9) A bill left open past midnight can still be read (and charged) the next 30 days, with the payments already
--    made on it (so a manager can void one from Orders) ----------------------------------------------------------
-- is that bill still open? (runs as the owner, so the read rule below does not call itself)
create or replace function public._tab_open(p_bill uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.orders where id = p_bill and paid = false and voided_at is null and status <> 'cancelled');
$$;
revoke all on function public._tab_open(uuid) from public, anon;
grant execute on function public._tab_open(uuid) to authenticated;
drop policy if exists "orders read" on public.orders;
create policy "orders read" on public.orders for select to authenticated
  using ((select public.is_cafe()) and (created_at >= public.cr_today_start() or (select public.sales_open())
         or (created_at >= public.cr_today_start() - interval '30 days'
             and ((paid = false and voided_at is null and status <> 'cancelled')
                  or (part_of is not null and public._tab_open(part_of))))));

-- 10) Who may call what ------------------------------------------------------------------------------------
revoke all on function public.tab_add_items(uuid, jsonb, uuid), public.tab_remove_item(uuid, int, text, text, uuid, text, int),
  public.tab_give_back(uuid, text, uuid, text, text), public.tab_set_discount(uuid, uuid, int, text),
  public.tab_pay(uuid, text, jsonb, int, text, int), public.tab_rename(uuid, text), public.cancel_unpaid_order(uuid),
  public._tab_label(public.orders), public._tab_pick(jsonb), public._tab_discount(public.orders, int, int, int) from public, anon;
grant execute on function public.tab_add_items(uuid, jsonb, uuid), public.tab_remove_item(uuid, int, text, text, uuid, text, int),
  public.tab_give_back(uuid, text, uuid, text, text), public.tab_set_discount(uuid, uuid, int, text),
  public.tab_pay(uuid, text, jsonb, int, text, int), public.tab_rename(uuid, text), public.cancel_unpaid_order(uuid)
  to authenticated;

notify pgrst, 'reload schema';
