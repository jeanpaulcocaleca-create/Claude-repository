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
--   * A bill left open past midnight still shows the next day until it is paid.
-- Split payments
--   * A person pays only their items, an equal part, or an amount, each with their own payment method.
--     Each payment is its own sale (so the register closing and the sales by method stay right) and is
--     taken off the bill. The last payment closes the bill.
--   * Each person pays their items less the bill's discount; whoever pays the last items pays what is left.
--   * Voiding one of those payments (Orders, with a manager PIN) puts its amount back on the bill while
--     the bill is still open.

create extension if not exists pgcrypto;

-- 1) Bills and payments -------------------------------------------------------------------------------
alter table public.orders add column if not exists part_of uuid references public.orders(id) on delete set null;
alter table public.orders add column if not exists parts_crc int not null default 0;     -- paid so far in parts
alter table public.orders add column if not exists kitchen_round int not null default 1; -- items added later
alter table public.order_items add column if not exists round int not null default 1;
alter table public.order_items add column if not exists paid_qty int not null default 0;
alter table public.order_items add column if not exists added_at timestamptz not null default now();
create index if not exists orders_part_of_idx on public.orders (part_of) where part_of is not null;

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

-- 2) Only the functions below keep these numbers: a sale typed at the till always starts clean ---------
create or replace function public._order_tab_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.part_of := null; new.parts_crc := 0; new.kitchen_round := 1;
  end if;
  return new;
end $$;
drop trigger if exists order_tab_defaults on public.orders;
create trigger order_tab_defaults before insert on public.orders
  for each row execute function public._order_tab_defaults();

create or replace function public._order_item_tab_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.round := 1; new.paid_qty := 0; new.added_at := now();
  end if;
  return new;
end $$;
drop trigger if exists order_item_tab_defaults on public.order_items;
create trigger order_item_tab_defaults before insert on public.order_items
  for each row execute function public._order_item_tab_defaults();

-- the discount stays frozen for the till; adding or taking off items keeps the bill's subtotal right
create or replace function public._order_discount_frozen()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and (
       new.discount_crc is distinct from old.discount_crc or new.discount_id is distinct from old.discount_id
       or new.subtotal_crc is distinct from old.subtotal_crc) then
    raise exception 'discount_frozen' using errcode = 'P0001';
  end if;
  return new;
end $$;

create or replace function public._tab_label(o public.orders)
returns text language sql stable as $$
  select case when o.pickup_number is not null then '#' || o.pickup_number
              when coalesce(o.guest_name, '') <> '' then o.guest_name
              else 'order ' || to_char(o.created_at at time zone 'America/Costa_Rica', 'HH24:MI') end;
$$;

-- what each item really costs on this bill: its price less the bill's discount, in proportion
-- (subtotal_crc and discount_crc are set only when the bill has a discount)
create or replace function public._tab_net(o public.orders, p_value int)
returns int language sql stable set search_path = public as $$
  select case when o.subtotal_crc is null or o.subtotal_crc <= 0 or coalesce(o.discount_crc, 0) <= 0 then p_value
              else round(p_value::numeric * (o.subtotal_crc - o.discount_crc) / o.subtotal_crc)::int end;
$$;

-- 3) Add items to a bill that is not paid yet -----------------------------------------------------------
-- p_items: [{"menu_item_id": "...", "qty": 1}, ...]. Names and prices come from the menu.
create or replace function public.tab_add_items(p_order_id uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; it jsonb; mi record; n int; kitchen boolean := false; added int := 0; rnd int;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if jsonb_array_length(p_items) > 40 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  -- check every line before writing anything
  for it in select * from jsonb_array_elements(p_items) loop
    if coalesce(it->>'qty', '') !~ '^[0-9]{1,3}$' or coalesce(it->>'menu_item_id', '') !~* '^[0-9a-f-]{36}$' then
      return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
    n := (it->>'qty')::int;
    if n < 1 or n > 50 then return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
    select m.id, coalesce(c.kitchen, false) as kitchen into mi
      from public.menu_items m left join public.menu_categories c on c.id = m.category_id
      where m.id = (it->>'menu_item_id')::uuid;
    if mi.id is null then return jsonb_build_object('ok', false, 'error', 'unknown_item'); end if;
    kitchen := kitchen or mi.kitchen;
  end loop;
  -- kitchen items on a bill the kitchen already finished start a new round: the kitchen sees only those
  rnd := o.kitchen_round;
  if kitchen and o.status not in ('new', 'preparing') then
    rnd := o.kitchen_round + 1;
    update public.orders set kitchen_round = rnd, status = 'preparing', needs_kitchen = true,
                             accepted_at = now(), ready_at = null
      where id = o.id;
  elsif kitchen and not coalesce(o.needs_kitchen, false) then
    update public.orders set needs_kitchen = true where id = o.id;
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    n := (it->>'qty')::int;
    select m.name, m.price_crc into mi from public.menu_items m where m.id = (it->>'menu_item_id')::uuid;
    insert into public.order_items (order_id, item_name, price_crc, qty, round)
      values (o.id, mi.name, mi.price_crc, n, rnd);
    added := added + mi.price_crc * n;
  end loop;
  update public.orders set total_crc = total_crc + added,
                           subtotal_crc = case when subtotal_crc is null then null else subtotal_crc + added end
    where id = o.id;
  return jsonb_build_object('ok', true, 'added', added, 'total', o.total_crc + added, 'kitchen', kitchen, 'round', rnd);
end $$;

-- 4) Take an item off a bill that is not paid yet (logged) ---------------------------------------------
-- Before the bill was delivered, or within 10 minutes of adding the item, the till can do it alone.
-- After that it needs the PIN of a manager, GM or owner, like cancelling a delivered order.
drop function if exists public.tab_remove_item(uuid, int, text, text);
create or replace function public.tab_remove_item(p_item_id uuid, p_qty int, p_reason text, p_station text,
                                                  p_staff_id uuid default null, p_pin text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; li record; v record; open_value int; open_left int; val int; cut int; mid uuid; why text;
        who text; by_id uuid; last_method text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select order_id into li from public.order_items where id = p_item_id;
  if li.order_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into o from public.orders where id = li.order_id for update;
  if o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  select * into li from public.order_items where id = p_item_id for update;
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
  select coalesce(sum((qty - paid_qty) * price_crc), 0)::int into open_value from public.order_items where order_id = o.id;
  val := li.price_crc * p_qty;
  open_left := open_value - val;
  if open_left <= 0 and coalesce(o.parts_crc, 0) = 0 then return jsonb_build_object('ok', false, 'error', 'use_cancel'); end if;
  -- the bill goes down by what the item cost on it (its price less the bill's discount)
  cut := case when open_left <= 0 then o.total_crc else least(o.total_crc, greatest(0, public._tab_net(o, val))) end;
  if li.qty - p_qty = 0 then delete from public.order_items where id = li.id;
  else update public.order_items set qty = qty - p_qty where id = li.id; end if;
  update public.orders set
      total_crc = total_crc - cut,
      subtotal_crc = case when subtotal_crc is null then null else subtotal_crc - val end,
      discount_crc = case when subtotal_crc is null then discount_crc
                          else greatest(0, (subtotal_crc - val) - (total_crc - cut) - parts_crc) end
    where id = o.id;
  -- nothing left to pay: what was paid in parts covered the rest
  if open_left <= 0 then
    select payment_method into last_method from public.orders
      where part_of = o.id and voided_at is null order by created_at desc limit 1;
    update public.orders set paid = true, payment_method = coalesce(last_method, 'other'), total_crc = 0 where id = o.id;
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
  return jsonb_build_object('ok', true, 'total', o.total_crc - cut, 'closed', open_left <= 0);
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
create or replace function public.tab_pay(p_order_id uuid, p_method text, p_lines jsonb, p_amount int, p_station text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; open_value int; val int := 0; amt int; ln jsonb; li record; part uuid; what text := '';
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if o.total_crc <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;
  select coalesce(sum((qty - paid_qty) * price_crc), 0)::int into open_value from public.order_items where order_id = o.id;

  if p_lines is not null and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then
    for ln in select * from jsonb_array_elements(p_lines) loop
      if coalesce(ln->>'qty', '') !~ '^[0-9]{1,3}$' or coalesce(ln->>'item_id', '') !~* '^[0-9a-f-]{36}$' then
        return jsonb_build_object('ok', false, 'error', 'changed'); end if;
    end loop;
    for li in select i.id, i.item_name, i.price_crc, i.qty - i.paid_qty as open_qty, p.qty as pick
                from public._tab_pick(p_lines) p left join public.order_items i on i.id = p.item_id and i.order_id = o.id loop
      if li.id is null or li.pick > li.open_qty then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
      val := val + li.price_crc * li.pick;
      what := what || case when what = '' then '' else ', ' end || li.pick || '× ' || li.item_name;
    end loop;
    if val <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;
    -- this person pays their items less the bill's discount; whoever pays the last items pays what is left
    -- (so an amount paid earlier "on account" comes off the end of the bill)
    amt := case when val >= open_value then o.total_crc else least(o.total_crc, public._tab_net(o, val)) end;
  elsif p_amount is not null then
    if p_amount < 1 or p_amount > o.total_crc then return jsonb_build_object('ok', false, 'error', 'bad_amount'); end if;
    amt := p_amount;
  else
    amt := o.total_crc;
  end if;
  if amt < 1 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;

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
      update public.orders set created_at = now() where id = o.id;
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
  update public.orders set total_crc = total_crc - amt, parts_crc = parts_crc + amt where id = o.id;
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

-- 8) Voids and split bills ------------------------------------------------------------------------------
--   * voiding a partial payment while the bill is still open puts its amount back on the bill;
--   * voiding the bill itself gives back the stock of what is left on it, not of what the other people paid for
create or replace function public._order_tab_voided()
returns trigger language plpgsql security definer set search_path = public as $$
declare m public.orders;
begin
  if new.voided_at is null or old.voided_at is not null then return new; end if;
  if new.part_of is not null then
    select * into m from public.orders where id = new.part_of for update;
    if m.id is not null and not coalesce(m.paid, false) and m.voided_at is null and m.status <> 'cancelled' then
      update public.orders set total_crc = total_crc + new.total_crc, parts_crc = greatest(0, parts_crc - new.total_crc)
        where id = m.id;
      update public.order_items i set paid_qty = greatest(0, i.paid_qty - l.qty)
        from public.order_part_lines l where l.part_id = new.id and l.item_id = i.id;
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

-- 9) A bill left open past midnight can still be read (and charged) the next days ---------------------------
drop policy if exists "orders read" on public.orders;
create policy "orders read" on public.orders for select to authenticated
  using ((select public.is_cafe()) and (created_at >= public.cr_today_start() or (select public.sales_open())
         or (paid = false and voided_at is null and status <> 'cancelled' and created_at >= public.cr_today_start() - interval '3 days')));

-- 10) Who may call what ------------------------------------------------------------------------------------
revoke all on function public.tab_add_items(uuid, jsonb), public.tab_remove_item(uuid, int, text, text, uuid, text),
  public.tab_pay(uuid, text, jsonb, int, text), public.tab_rename(uuid, text), public.cancel_unpaid_order(uuid),
  public._tab_label(public.orders), public._tab_pick(jsonb), public._tab_net(public.orders, int) from public, anon;
grant execute on function public.tab_add_items(uuid, jsonb), public.tab_remove_item(uuid, int, text, text, uuid, text),
  public.tab_pay(uuid, text, jsonb, int, text), public.tab_rename(uuid, text), public.cancel_unpaid_order(uuid)
  to authenticated;

notify pgrst, 'reload schema';
