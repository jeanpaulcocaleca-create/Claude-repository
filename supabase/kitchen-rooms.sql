-- Canopy OS · The Hanging Garden Café
-- Kitchen tickets, pickup numbers and room ordering.
-- Run ONCE in Supabase (SQL Editor -> New query -> paste -> Run). Safe to re-run.
-- Run supabase/authorization.sql before this one.
--
-- What it adds:
--   * Every order now has a status (new -> preparing -> ready -> done), an optional
--     pickup number, and a "needs the kitchen" flag taken from the category switches.
--   * A settings row (how many number stands, room ordering hours).
--   * Ten rooms, each with a private code for its QR card.
--   * Guest functions the room page uses with the public key: look up a room,
--     place an order (prices always come from the menu, never from the phone),
--     and follow the order's status.
--   * Staff functions to finish or cancel a room order. Voids still need a manager.

create extension if not exists pgcrypto;

-- 1) Settings ------------------------------------------------------------------
create table if not exists public.app_settings (
  id int primary key,
  pickup_numbers int not null default 12,          -- physical number stands, 1..N
  numbers_out int[] not null default '{}',         -- stands out of service
  room_orders_enabled boolean not null default true,
  room_open time not null default '07:00',
  room_close time not null default '16:00',
  updated_at timestamptz not null default now()
);
insert into public.app_settings (id) values (1) on conflict (id) do nothing;
alter table public.app_settings enable row level security;
drop policy if exists "settings public read" on public.app_settings;
create policy "settings public read" on public.app_settings for select to anon, authenticated using (true);
drop policy if exists "settings staff write" on public.app_settings;
create policy "settings staff write" on public.app_settings for all to authenticated using (true) with check (true);
grant select on public.app_settings to anon, authenticated;
grant insert, update on public.app_settings to authenticated;

-- 2) Which categories the kitchen prepares -------------------------------------
alter table public.menu_categories add column if not exists kitchen boolean not null default false;
update public.menu_categories set kitchen = true
  where name in ('Sandwiches', 'Savory', 'Costa Rican Favorites', 'Adventure Box')
    and not exists (select 1 from public.menu_categories where kitchen);
drop policy if exists "categories kitchen switch for signed-in" on public.menu_categories;
create policy "categories kitchen switch for signed-in" on public.menu_categories
  for update to authenticated using (true) with check (true);
grant update (kitchen) on public.menu_categories to authenticated;

-- 3) Rooms ----------------------------------------------------------------------
create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  number int not null unique,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.rooms (number, code)
  select n, n || '-' || lower(substr(md5(gen_random_uuid()::text), 1, 6))
  from generate_series(1, 10) as n
  where not exists (select 1 from public.rooms);
alter table public.rooms enable row level security;
-- Codes are secrets: only the café login can read them (to print the cards).
drop policy if exists "rooms read for signed-in" on public.rooms;
create policy "rooms read for signed-in" on public.rooms for select to authenticated using (true);
drop policy if exists "rooms write for signed-in" on public.rooms;
create policy "rooms write for signed-in" on public.rooms for all to authenticated using (true) with check (true);
revoke all on public.rooms from anon;
grant select, insert, update on public.rooms to authenticated;

-- 4) Orders: status, pickup number, room and guest fields -----------------------
alter table public.orders add column if not exists source text not null default 'front';   -- front | room
alter table public.orders add column if not exists status text not null default 'done';    -- new | preparing | ready | done | cancelled
alter table public.orders add column if not exists needs_kitchen boolean not null default false;
alter table public.orders add column if not exists pickup_number int;
alter table public.orders add column if not exists notes text;
alter table public.orders add column if not exists paid boolean not null default true;
alter table public.orders add column if not exists room_id uuid references public.rooms(id) on delete set null;
alter table public.orders add column if not exists guest_name text;
alter table public.orders add column if not exists guest_phone text;
alter table public.orders add column if not exists guest_lang text;
alter table public.orders add column if not exists track_token text;
alter table public.orders add column if not exists accepted_at timestamptz;
alter table public.orders add column if not exists ready_at timestamptz;
alter table public.orders add column if not exists done_at timestamptz;
create index if not exists orders_open_idx on public.orders (status) where status in ('new', 'preparing', 'ready');
create unique index if not exists orders_track_idx on public.orders (track_token) where track_token is not null;

-- The till may move an order along (status, number, timestamps) but nothing else:
-- totals, payment and voids stay protected.
grant update (status, pickup_number, accepted_at, ready_at, done_at) on public.orders to authenticated;
drop policy if exists "orders progress for signed-in" on public.orders;
create policy "orders progress for signed-in" on public.orders
  for update to authenticated using (true) with check (true);

-- 5) Guest functions (public key) -----------------------------------------------
create or replace function public._room_is_open(out is_open boolean, out opens text, out closes text)
language plpgsql security definer set search_path = public as $$
declare s public.app_settings; t time;
begin
  select * into s from public.app_settings where id = 1;
  t := (now() at time zone 'America/Costa_Rica')::time;
  opens := to_char(s.room_open, 'HH24:MI'); closes := to_char(s.room_close, 'HH24:MI');
  is_open := s.room_orders_enabled and t >= s.room_open and t < s.room_close;
end $$;
revoke all on function public._room_is_open() from public, anon, authenticated;

create or replace function public.room_lookup(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.rooms; o record;
begin
  select * into r from public.rooms where code = p_code and active;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown_room'); end if;
  select * into o from public._room_is_open();
  return jsonb_build_object('ok', true, 'room', r.number, 'open', o.is_open, 'opens', o.opens, 'closes', o.closes);
end $$;

create or replace function public.place_room_order(p_code text, p_name text, p_phone text, p_lang text,
                                                   p_notes text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.rooms; o record; it jsonb; mi record; total int := 0; kitchen boolean := false;
        n int; oid uuid; tok text; phone text; lines jsonb := '[]'::jsonb;
begin
  select * into r from public.rooms where code = p_code and active;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown_room'); end if;
  select * into o from public._room_is_open();
  if not o.is_open then return jsonb_build_object('ok', false, 'error', 'closed', 'opens', o.opens, 'closes', o.closes); end if;
  if coalesce(trim(p_name), '') = '' or length(p_name) > 60 then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if length(phone) < 7 or length(phone) > 15 then return jsonb_build_object('ok', false, 'error', 'bad_phone'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 30 then
    return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if exists (select 1 from public.orders where room_id = r.id and status in ('new', 'preparing', 'ready') and voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'room_busy'); end if;

  for it in select * from jsonb_array_elements(p_items) loop
    n := least(greatest(coalesce((it->>'qty')::int, 1), 1), 20);
    select i.name, i.price_crc, c.kitchen into mi
      from public.menu_items i join public.menu_categories c on c.id = i.category_id
      where i.id = (it->>'id')::uuid and i.available;
    if mi.name is null then return jsonb_build_object('ok', false, 'error', 'item_unavailable'); end if;
    total := total + mi.price_crc * n;
    kitchen := kitchen or coalesce(mi.kitchen, false);
    lines := lines || jsonb_build_object('item_name', mi.name, 'price_crc', mi.price_crc, 'qty', n);
  end loop;

  tok := encode(gen_random_bytes(16), 'hex');
  insert into public.orders (total_crc, payment_method, source, status, needs_kitchen, paid, room_id,
                             guest_name, guest_phone, guest_lang, notes, track_token)
    values (total, 'pending', 'room', 'new', kitchen, false, r.id,
            trim(p_name), phone, case when p_lang = 'es' then 'es' else 'en' end,
            nullif(left(trim(coalesce(p_notes, '')), 200), ''), tok)
    returning id into oid;
  insert into public.order_items (order_id, item_name, price_crc, qty)
    select oid, l->>'item_name', (l->>'price_crc')::int, (l->>'qty')::int from jsonb_array_elements(lines) l;
  return jsonb_build_object('ok', true, 'token', tok, 'total', total, 'room', r.number);
end $$;

create or replace function public.order_status(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; items jsonb; rn int;
begin
  select * into o from public.orders where track_token = p_token;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select jsonb_agg(jsonb_build_object('name', item_name, 'qty', qty, 'price_crc', price_crc)) into items
    from public.order_items where order_id = o.id;
  select number into rn from public.rooms where id = o.room_id;
  return jsonb_build_object('ok', true,
    'status', case when o.voided_at is not null then 'cancelled' else o.status end,
    'room', rn, 'total', o.total_crc, 'pickup_number', o.pickup_number,
    'created_at', o.created_at, 'ready_at', o.ready_at, 'items', coalesce(items, '[]'::jsonb));
end $$;

revoke all on function public.room_lookup(text) from public;
revoke all on function public.place_room_order(text, text, text, text, text, jsonb) from public;
revoke all on function public.order_status(text) from public;
grant execute on function public.room_lookup(text) to anon, authenticated;
grant execute on function public.place_room_order(text, text, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.order_status(text) to anon, authenticated;

-- 6) Staff functions for room orders (café login, no PIN needed) ----------------
-- The guest pays at the window: this records the payment and closes the order.
create or replace function public.finish_room_order(p_order_id uuid, p_payment_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select * into o from public.orders where id = p_order_id;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.source <> 'room' or o.paid then return jsonb_build_object('ok', false, 'error', 'not_room_order'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if p_payment_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  update public.orders set paid = true, payment_method = p_payment_method, status = 'done',
    done_at = now(), guest_phone = null where id = p_order_id;
  return jsonb_build_object('ok', true);
end $$;

-- A guest who never shows up: the order was never paid, so no manager PIN is needed.
create or replace function public.cancel_room_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select * into o from public.orders where id = p_order_id;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.source <> 'room' or o.paid then return jsonb_build_object('ok', false, 'error', 'not_room_order'); end if;
  update public.orders set status = 'cancelled', done_at = now(), guest_phone = null where id = p_order_id;
  return jsonb_build_object('ok', true);
end $$;

-- New code for a room's QR card (if a card leaks). Café login only.
create or replace function public.room_new_code(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.rooms;
begin
  update public.rooms set code = number || '-' || lower(substr(md5(gen_random_uuid()::text), 1, 6))
    where id = p_room_id returning * into r;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'code', r.code);
end $$;

revoke all on function public.finish_room_order(uuid, text) from public, anon;
revoke all on function public.cancel_room_order(uuid) from public, anon;
revoke all on function public.room_new_code(uuid) from public, anon;
grant execute on function public.finish_room_order(uuid, text) to authenticated;
grant execute on function public.cancel_room_order(uuid) to authenticated;
grant execute on function public.room_new_code(uuid) to authenticated;

notify pgrst, 'reload schema';
