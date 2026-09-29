-- ============================================================================
--  The Hanging Garden Café · Inventory
--  Run once in Supabase (SQL Editor → New query → paste → Run). Safe to re-run.
--  Needs timeclock.sql, authorization.sql and accounts.sql to be in place.
--
--  What it adds
--   · vendors, stock items (what you buy), stock moves (every change, signed),
--     recipes (what each menu item uses), purchase orders and their lines
--   · every sale on the POS or from a room takes stock out through the recipes;
--     a void or a cancelled room order puts it back
--   · counts, waste and receipts through small functions that also keep the
--     approvals log
--   · inventory_stats(): usage per day, days left, suggested order per item
--   · inventory_month(): ordered, sold, wasted and in stock for any month
--   · inventory_alerts(): the short list the owner home shows
--   · access: the owner login always; the café login after a manager PIN
--     (15 minutes, like the sales reports)
-- ============================================================================

create extension if not exists pgcrypto;

-- 1) Tables ------------------------------------------------------------------
create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  phone text,
  whatsapp text,
  email text,
  lead_days int not null default 2,          -- days from order to delivery
  order_days text,                           -- e.g. "Mon, Thu"
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'other',    -- coffee | dairy | bakery | sandwich | produce | drinks | packaging | cleaning | other
  unit text not null default 'unit',         -- unit | g | kg | ml | L
  pack_label text,                           -- what you buy: "bag 1 kg", "box of 24"
  pack_qty numeric not null default 1 check (pack_qty > 0),   -- units in one pack
  cost_per_pack numeric not null default 0,  -- colones
  vendor_id uuid references public.vendors(id) on delete set null,
  on_hand numeric not null default 0,
  par_level numeric not null default 0,      -- where stock should sit after an order
  reorder_point numeric not null default 0,  -- alert at or below this
  shelf_life_days int,                       -- fills the expiry date on receipts
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists stock_items_name_idx on public.stock_items (lower(name));

create table if not exists public.stock_moves (
  id bigint generated always as identity primary key,
  item_id uuid not null references public.stock_items(id) on delete cascade,
  at timestamptz not null default now(),
  kind text not null check (kind in ('purchase', 'sale', 'void', 'waste', 'count', 'adjust')),
  qty numeric not null,                      -- signed: + into stock, - out of stock
  unit_cost numeric,                         -- colones per unit (purchases)
  order_id uuid,                             -- the sale it came from
  po_id uuid,                                -- the purchase order it came from
  expires_on date,
  note text,
  by_name text
);
create index if not exists stock_moves_item_idx on public.stock_moves (item_id, at desc);
create index if not exists stock_moves_order_idx on public.stock_moves (order_id);

create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  stock_item_id uuid not null references public.stock_items(id) on delete cascade,
  qty numeric not null check (qty > 0),      -- stock units used per one sold
  unique (menu_item_id, stock_item_id)
);

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid references public.vendors(id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'sent', 'received', 'cancelled')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  received_at timestamptz,
  note text,
  by_name text
);

create table if not exists public.purchase_lines (
  id uuid primary key default gen_random_uuid(),
  po_id uuid not null references public.purchase_orders(id) on delete cascade,
  item_id uuid not null references public.stock_items(id) on delete cascade,
  packs numeric not null default 0,
  qty numeric not null default 0,            -- units ordered
  received_qty numeric,                      -- units that arrived
  unit_cost numeric,                         -- colones per unit
  expires_on date
);
create index if not exists purchase_lines_po_idx on public.purchase_lines (po_id);

create table if not exists public.inventory_unlocks (
  user_id uuid primary key,
  staff_id uuid,
  staff_name text,
  expires_at timestamptz not null
);

-- 2) Who may open it ---------------------------------------------------------
create or replace function public.inventory_open()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner()
      or exists (select 1 from public.inventory_unlocks where user_id = auth.uid() and expires_at > now());
$$;

create or replace function public.inventory_unlock(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; kind text; until timestamptz;
begin
  kind := public.account_kind();
  if kind is null then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  until := now() + interval '15 minutes';
  insert into public.inventory_unlocks (user_id, staff_id, staff_name, expires_at)
    values (auth.uid(), v.sid, v.sname, until)
    on conflict (user_id) do update set staff_id = excluded.staff_id, staff_name = excluded.staff_name,
                                        expires_at = excluded.expires_at;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('inventory_view', v.sid, v.sname, auth.uid()::text, 'opened the inventory',
            jsonb_build_object('account', kind, 'until', until));
  return jsonb_build_object('ok', true, 'until', until, 'name', v.sname);
end $$;

create or replace function public.inventory_lock()
returns void language sql security definer set search_path = public as $$
  delete from public.inventory_unlocks where user_id = auth.uid();
$$;

create or replace function public.inventory_unlocked()
returns timestamptz language sql stable security definer set search_path = public as $$
  select case when public.is_owner() then now() + interval '10 years'
              else (select expires_at from public.inventory_unlocks where user_id = auth.uid() and expires_at > now()) end;
$$;

-- who is acting, for the log lines
create or replace function public._inv_actor()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select staff_name from public.inventory_unlocks where user_id = auth.uid() and expires_at > now()),
                  case when public.is_owner() then 'owner' else 'café' end);
$$;

-- 3) Keep on_hand in step with the moves ------------------------------------
create or replace function public._stock_move_applied()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.stock_items set on_hand = on_hand + new.qty, updated_at = now() where id = new.item_id;
  return new;
end $$;
drop trigger if exists stock_move_applied on public.stock_moves;
create trigger stock_move_applied after insert on public.stock_moves
  for each row execute function public._stock_move_applied();

-- 4) Sales take stock out through the recipes --------------------------------
create or replace function public._order_item_stock()
returns trigger language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  select id into mid from public.menu_items where lower(name) = lower(new.item_name) order by available desc limit 1;
  if mid is null then return new; end if;
  insert into public.stock_moves (item_id, kind, qty, order_id, note)
    select r.stock_item_id, 'sale', -(r.qty * greatest(new.qty, 0)), new.order_id, new.item_name
      from public.recipes r where r.menu_item_id = mid;
  return new;
end $$;
drop trigger if exists order_item_stock on public.order_items;
create trigger order_item_stock after insert on public.order_items
  for each row execute function public._order_item_stock();

-- a void or a cancelled room order puts it back
create or replace function public._order_stock_return()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.voided_at is not null and old.voided_at is null)
     or (new.status = 'cancelled' and coalesce(old.status, '') <> 'cancelled') then
    insert into public.stock_moves (item_id, kind, qty, order_id, note)
      select m.item_id, 'void', -m.qty, m.order_id, m.note
        from public.stock_moves m where m.order_id = new.id and m.kind = 'sale'
        and not exists (select 1 from public.stock_moves v where v.order_id = new.id and v.kind = 'void' and v.item_id = m.item_id);
  end if;
  return new;
end $$;
drop trigger if exists order_stock_return on public.orders;
create trigger order_stock_return after update on public.orders
  for each row execute function public._order_stock_return();

-- 5) Counts, waste, receipts -------------------------------------------------
create or replace function public.stock_count(p_item_id uuid, p_counted numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur numeric; diff numeric;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select on_hand into cur from public.stock_items where id = p_item_id;
  if cur is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  diff := coalesce(p_counted, 0) - cur;
  insert into public.stock_moves (item_id, kind, qty, note, by_name)
    values (p_item_id, 'count', diff, coalesce(p_note, 'counted ' || coalesce(p_counted, 0)), public._inv_actor());
  return jsonb_build_object('ok', true, 'diff', diff, 'on_hand', coalesce(p_counted, 0));
end $$;

create or replace function public.stock_waste(p_item_id uuid, p_qty numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if coalesce(p_qty, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  if not exists (select 1 from public.stock_items where id = p_item_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.stock_moves (item_id, kind, qty, note, by_name) values (p_item_id, 'waste', -p_qty, p_note, public._inv_actor());
  return jsonb_build_object('ok', true);
end $$;

-- quick receipt without a purchase order (walked in with a bag of coffee)
create or replace function public.stock_receive(p_item_id uuid, p_qty numeric, p_unit_cost numeric default null,
                                                p_expires_on date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare it public.stock_items;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if coalesce(p_qty, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  select * into it from public.stock_items where id = p_item_id;
  if it.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.stock_moves (item_id, kind, qty, unit_cost, expires_on, note, by_name)
    values (p_item_id, 'purchase', p_qty, p_unit_cost,
            coalesce(p_expires_on, case when it.shelf_life_days is not null then current_date + it.shelf_life_days end),
            p_note, public._inv_actor());
  if p_unit_cost is not null and p_unit_cost > 0 then
    update public.stock_items set cost_per_pack = p_unit_cost * pack_qty where id = p_item_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- receiving a purchase order: p_lines = [{line_id, received_qty, unit_cost, expires_on}]
create or replace function public.po_receive(p_po_id uuid, p_lines jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare po public.purchase_orders; ln record; l jsonb; got numeric; cost numeric; exp date; n int := 0; it public.stock_items;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select * into po from public.purchase_orders where id = p_po_id;
  if po.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if po.status = 'received' then return jsonb_build_object('ok', false, 'error', 'already_received'); end if;
  for ln in select * from public.purchase_lines where po_id = p_po_id loop
    got := ln.qty; cost := ln.unit_cost; exp := ln.expires_on;
    for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
      if (l ->> 'line_id')::uuid = ln.id then
        got := coalesce((l ->> 'received_qty')::numeric, got);
        cost := coalesce((l ->> 'unit_cost')::numeric, cost);
        exp := coalesce((l ->> 'expires_on')::date, exp);
      end if;
    end loop;
    select * into it from public.stock_items where id = ln.item_id;
    if exp is null and it.shelf_life_days is not null then exp := current_date + it.shelf_life_days; end if;
    update public.purchase_lines set received_qty = got, unit_cost = cost, expires_on = exp where id = ln.id;
    if got > 0 then
      insert into public.stock_moves (item_id, kind, qty, unit_cost, po_id, expires_on, note, by_name)
        values (ln.item_id, 'purchase', got, cost, p_po_id, exp, 'received', public._inv_actor());
      if cost is not null and cost > 0 then
        update public.stock_items set cost_per_pack = cost * pack_qty where id = ln.item_id;
      end if;
      n := n + 1;
    end if;
  end loop;
  update public.purchase_orders set status = 'received', received_at = now() where id = p_po_id;
  insert into public.audit_log (action, manager_name, target_id, summary, details)
    values ('stock_receive', public._inv_actor(), p_po_id::text, 'received a purchase order', jsonb_build_object('lines', n));
  return jsonb_build_object('ok', true, 'lines', n);
end $$;

-- 6) The numbers -------------------------------------------------------------
create or replace function public.inventory_stats(p_days int default 30)
returns table (
  id uuid, name text, category text, unit text, pack_label text, pack_qty numeric, cost_per_pack numeric,
  vendor_id uuid, vendor_name text, lead_days int, on_hand numeric, par_level numeric, reorder_point numeric,
  shelf_life_days int, active boolean, notes text,
  sold_qty numeric, waste_qty numeric, received_qty numeric, avg_daily numeric, days_left numeric,
  suggested_qty numeric, suggested_packs numeric, value_on_hand numeric,
  last_count_at timestamptz, last_received_at timestamptz, expires_on date, status text
) language sql stable security definer set search_path = public as $$
  with m as (
    select item_id,
           sum(case when kind = 'sale' then -qty when kind = 'void' then -qty else 0 end) filter (where at >= now() - make_interval(days => p_days)) as sold,
           sum(case when kind = 'waste' then -qty else 0 end) filter (where at >= now() - make_interval(days => p_days)) as waste,
           sum(case when kind = 'purchase' then qty else 0 end) filter (where at >= now() - make_interval(days => p_days)) as received,
           max(at) filter (where kind = 'count') as last_count,
           max(at) filter (where kind = 'purchase') as last_recv,
           min(expires_on) filter (where kind = 'purchase' and expires_on is not null and at >= now() - interval '90 days' and expires_on >= current_date - 1) as exp
      from public.stock_moves group by item_id)
  select i.id, i.name, i.category, i.unit, i.pack_label, i.pack_qty, i.cost_per_pack,
         i.vendor_id, v.name, coalesce(v.lead_days, 2), i.on_hand, i.par_level, i.reorder_point,
         i.shelf_life_days, i.active, i.notes,
         coalesce(m.sold, 0), coalesce(m.waste, 0), coalesce(m.received, 0),
         round((coalesce(m.sold, 0) + coalesce(m.waste, 0)) / greatest(p_days, 1), 3) as avg_daily,
         case when coalesce(m.sold, 0) + coalesce(m.waste, 0) > 0
              then round(i.on_hand / ((coalesce(m.sold, 0) + coalesce(m.waste, 0)) / greatest(p_days, 1)), 1) end as days_left,
         greatest(0, i.par_level - i.on_hand + ((coalesce(m.sold, 0) + coalesce(m.waste, 0)) / greatest(p_days, 1)) * coalesce(v.lead_days, 2)) as suggested_qty,
         ceil(greatest(0, i.par_level - i.on_hand + ((coalesce(m.sold, 0) + coalesce(m.waste, 0)) / greatest(p_days, 1)) * coalesce(v.lead_days, 2)) / i.pack_qty) as suggested_packs,
         round(i.on_hand * i.cost_per_pack / i.pack_qty) as value_on_hand,
         m.last_count, m.last_recv, m.exp,
         case when i.on_hand <= 0 then 'out'
              when i.on_hand <= i.reorder_point then 'low'
              when coalesce(m.sold, 0) + coalesce(m.waste, 0) > 0
                   and i.on_hand / ((coalesce(m.sold, 0) + coalesce(m.waste, 0)) / greatest(p_days, 1)) <= coalesce(v.lead_days, 2) + 1 then 'soon'
              else 'ok' end as status
    from public.stock_items i
    left join public.vendors v on v.id = i.vendor_id
    left join m on m.item_id = i.id
   where public.inventory_open()
   order by i.name;
$$;

-- one month: what was ordered (received), sold, wasted, and what is on hand now
create or replace function public.inventory_month(p_month date default date_trunc('month', current_date - interval '1 month')::date)
returns table (id uuid, name text, category text, unit text, received_qty numeric, received_cost numeric,
               sold_qty numeric, waste_qty numeric, count_diff numeric, on_hand numeric, unit_cost numeric)
language sql stable security definer set search_path = public as $$
  with b as (select date_trunc('month', p_month)::timestamptz as s, (date_trunc('month', p_month) + interval '1 month')::timestamptz as e),
  m as (
    select item_id,
           sum(case when kind = 'purchase' then qty else 0 end) as received,
           sum(case when kind = 'purchase' then qty * coalesce(unit_cost, 0) else 0 end) as received_cost,
           sum(case when kind in ('sale', 'void') then -qty else 0 end) as sold,
           sum(case when kind = 'waste' then -qty else 0 end) as waste,
           sum(case when kind = 'count' then qty else 0 end) as count_diff
      from public.stock_moves, b where at >= b.s and at < b.e group by item_id)
  select i.id, i.name, i.category, i.unit, coalesce(m.received, 0), round(coalesce(m.received_cost, 0)),
         coalesce(m.sold, 0), coalesce(m.waste, 0), coalesce(m.count_diff, 0), i.on_hand,
         round(i.cost_per_pack / i.pack_qty, 2)
    from public.stock_items i left join m on m.item_id = i.id
   where public.inventory_open() and (i.active or m.item_id is not null)
   order by i.name;
$$;

-- the short list for the owner home
create or replace function public.inventory_alerts()
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; low int := 0; outn int := 0; soon int := 0; expn int := 0; items jsonb := '[]'::jsonb;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  for r in select * from public.inventory_stats(30) where active order by
             case status when 'out' then 0 when 'low' then 1 when 'soon' then 2 else 3 end,
             coalesce(days_left, 999), name loop
    if r.status = 'out' then outn := outn + 1; elsif r.status = 'low' then low := low + 1; elsif r.status = 'soon' then soon := soon + 1; end if;
    if r.expires_on is not null and r.expires_on <= current_date + 3 and r.on_hand > 0 then expn := expn + 1; end if;
    if jsonb_array_length(items) < 6 and (r.status <> 'ok' or (r.expires_on is not null and r.expires_on <= current_date + 3 and r.on_hand > 0)) then
      items := items || jsonb_build_object('id', r.id, 'name', r.name, 'status', r.status, 'on_hand', r.on_hand, 'unit', r.unit,
                                           'days_left', r.days_left, 'expires_on', r.expires_on, 'vendor', r.vendor_name);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'out', outn, 'low', low, 'soon', soon, 'expiring', expn, 'items', items,
                            'count', (select count(*) from public.stock_items where active));
end $$;

-- link menu items to stock items with the same name, one for one (croissant sold = croissant out)
create or replace function public.recipes_autolink()
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  insert into public.recipes (menu_item_id, stock_item_id, qty)
    select mi.id, si.id, 1
      from public.menu_items mi join public.stock_items si on lower(si.name) = lower(mi.name)
     where si.active and not exists (select 1 from public.recipes r where r.menu_item_id = mi.id)
     on conflict do nothing;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'linked', n);
end $$;

-- cost of what was used against what was sold, for a food-cost percentage
create or replace function public.inventory_food_cost(p_days int default 30)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ok', public.inventory_open(),
    'usage_cost', coalesce((select round(sum(-m.qty * i.cost_per_pack / i.pack_qty))
                              from public.stock_moves m join public.stock_items i on i.id = m.item_id
                             where m.kind in ('sale', 'void', 'waste') and m.at >= now() - make_interval(days => p_days)), 0),
    'waste_cost', coalesce((select round(sum(-m.qty * i.cost_per_pack / i.pack_qty))
                              from public.stock_moves m join public.stock_items i on i.id = m.item_id
                             where m.kind = 'waste' and m.at >= now() - make_interval(days => p_days)), 0),
    'revenue', coalesce((select sum(total_crc) from public.orders
                          where created_at >= now() - make_interval(days => p_days) and voided_at is null
                            and coalesce(paid, true) and coalesce(status, 'done') <> 'cancelled'), 0),
    'stock_value', coalesce((select round(sum(on_hand * cost_per_pack / pack_qty)) from public.stock_items where active), 0));
$$;

-- 7) Access ------------------------------------------------------------------
alter table public.vendors enable row level security;
alter table public.stock_items enable row level security;
alter table public.stock_moves enable row level security;
alter table public.recipes enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_lines enable row level security;
alter table public.inventory_unlocks enable row level security;

revoke all on public.vendors, public.stock_items, public.stock_moves, public.recipes,
              public.purchase_orders, public.purchase_lines, public.inventory_unlocks from anon, authenticated;
grant select, insert, update, delete on public.vendors, public.stock_items, public.recipes,
                                       public.purchase_orders, public.purchase_lines to authenticated;
grant select on public.stock_moves to authenticated;

do $$ declare t text; begin
  foreach t in array array['vendors', 'stock_items', 'recipes', 'purchase_orders', 'purchase_lines'] loop
    execute format('drop policy if exists "inventory all" on public.%I', t);
    execute format('create policy "inventory all" on public.%I for all to authenticated using ((select public.inventory_open())) with check ((select public.inventory_open()))', t);
  end loop;
end $$;
drop policy if exists "inventory moves read" on public.stock_moves;
create policy "inventory moves read" on public.stock_moves for select to authenticated using ((select public.inventory_open()));

revoke all on function public.inventory_open(), public.inventory_unlock(uuid, text), public.inventory_lock(), public.inventory_unlocked(),
  public._inv_actor(), public.stock_count(uuid, numeric, text), public.stock_waste(uuid, numeric, text),
  public.stock_receive(uuid, numeric, numeric, date, text), public.po_receive(uuid, jsonb), public.inventory_stats(int),
  public.inventory_month(date), public.inventory_alerts(), public.recipes_autolink(), public.inventory_food_cost(int) from public, anon;
grant execute on function public.inventory_open(), public.inventory_unlock(uuid, text), public.inventory_lock(), public.inventory_unlocked(),
  public.stock_count(uuid, numeric, text), public.stock_waste(uuid, numeric, text),
  public.stock_receive(uuid, numeric, numeric, date, text), public.po_receive(uuid, jsonb), public.inventory_stats(int),
  public.inventory_month(date), public.inventory_alerts(), public.recipes_autolink(), public.inventory_food_cost(int) to authenticated;
revoke all on function public._stock_move_applied(), public._order_item_stock(), public._order_stock_return() from public, anon, authenticated;

notify pgrst, 'reload schema';
