-- =====================================================================================================
-- Canopy OS · migración 0004 · Guardar cada venta completa de una sola vez, y ligar cada línea a su producto
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0003.
--
-- Por qué
--   * La caja guardaba la venta en dos pasos (la venta y luego sus líneas). Si el segundo fallaba, podía quedar
--     una venta sin líneas. Ahora pos_record_sale guarda las dos cosas juntas o ninguna, y repetir el envío
--     (internet intermitente) no la duplica.
--   * El inventario buscaba el producto vendido por su NOMBRE. Si un producto cambiaba de nombre, la receta
--     dejaba de descontar. Ahora cada línea guarda el producto exacto (menu_item_id).
--   * El servidor revisa que la suma de las líneas coincida con el total; si no, marca la venta para el gerente
--     ('total_mismatch'). Nunca rechaza dinero ya cobrado.
-- Qué cambia para el personal: nada.
-- Reversión: drop function pos_record_sale (la caja vuelve sola al guardado en dos pasos).
-- =====================================================================================================
select canopy.migration_begin(4, 'sales_save');

-- 1) every sale line knows its menu item ---------------------------------------------------------------
alter table public.order_items add column if not exists menu_item_id uuid;   -- no foreign key: history outlives menu edits
create index if not exists order_items_menu_item_idx on public.order_items (menu_item_id);

create or replace function public._order_item_menu_id()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- an id is kept only when it names this same product; otherwise the name decides (as before)
  if new.menu_item_id is not null
     and not exists (select 1 from public.menu_items where id = new.menu_item_id and lower(name) = lower(new.item_name)) then
    new.menu_item_id := null;
  end if;
  if new.menu_item_id is null then
    select id into new.menu_item_id from public.menu_items where lower(name) = lower(new.item_name) order by available desc limit 1;
  end if;
  return new;
end $$;
revoke all on function public._order_item_menu_id() from public, anon, authenticated;
drop trigger if exists order_item_menu_id on public.order_items;
create trigger order_item_menu_id before insert on public.order_items for each row execute function public._order_item_menu_id();

-- earlier lines: best effort by name (fills the new column only)
update public.order_items i set menu_item_id = m.id
  from (select distinct on (lower(name)) id, lower(name) as lname from public.menu_items order by lower(name), available desc) m
 where i.menu_item_id is null and lower(i.item_name) = m.lname;

-- stock comes out through the recipe of the exact product sold
create or replace function public._order_item_stock()
returns trigger language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  mid := new.menu_item_id;
  if mid is null then
    select id into mid from public.menu_items where lower(name) = lower(new.item_name) order by available desc limit 1;
  end if;
  if mid is null then return new; end if;
  insert into public.stock_moves (item_id, kind, qty, order_id, note)
    select r.stock_item_id, 'sale', -(r.qty * greatest(new.qty, 0)), new.order_id, new.item_name
      from public.recipes r where r.menu_item_id = mid
     order by r.stock_item_id;   -- same lock order everywhere: two sales at once never deadlock
  return new;
end $$;

-- 2) a sale whose lines do not add up to its total is flagged (never refused) -----------------------------
create or replace function public._order_check_totals(p_orders uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders o
     set flags = array_append(o.flags, case when o.notes like '%not verified%' then 'discount_not_verified' else 'total_mismatch' end)
   where o.id = any(p_orders)
     and o.part_of is null
     and not ('total_mismatch' = any(o.flags) or 'discount_not_verified' = any(o.flags))
     and coalesce(o.subtotal_crc, o.total_crc) <> (select coalesce(sum(i.price_crc * i.qty), 0) from public.order_items i where i.order_id = o.id);
end $$;
revoke all on function public._order_check_totals(uuid[]) from public, anon;
grant execute on function public._order_check_totals(uuid[]) to authenticated;

create or replace function public._order_items_totals()
returns trigger language plpgsql set search_path = public as $$
begin
  -- only sales written by the till; bill functions keep their own totals
  if current_user in ('authenticated', 'anon') then
    perform public._order_check_totals((select array_agg(distinct order_id) from new_lines));
  end if;
  return null;
end $$;
drop trigger if exists order_items_totals on public.order_items;
create trigger order_items_totals after insert on public.order_items referencing new table as new_lines
  for each statement execute function public._order_items_totals();

-- 3) one call saves the sale and its lines together -------------------------------------------------------
-- Runs with the caller's own rights: every rule a direct insert from the till meets still applies (row rules,
-- discount approval, bill protections, stock). Sending the same sale again returns already = true.
create or replace function public.pos_record_sale(p_order jsonb)
returns jsonb language plpgsql set search_path = public as $$
declare oid uuid; existing boolean := false; c text; other boolean := false;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  oid := nullif(p_order->>'id', '')::uuid;
  if oid is null or jsonb_typeof(coalesce(p_order->'items', '[]'::jsonb)) <> 'array' then
    raise exception 'bad_payload' using errcode = 'P0001';
  end if;
  begin
    insert into public.orders (id, created_at, total_crc, payment_method, paid, status, source, needs_kitchen, accepted_at,
                               pickup_number, guest_name, station, subtotal_crc, discount_crc, discount_id, notes)
    values (oid,
            coalesce((p_order->>'created_at')::timestamptz, now()),
            (p_order->>'total_crc')::int,
            coalesce(p_order->>'payment_method', 'cash_crc'),
            coalesce((p_order->>'paid')::boolean, true),
            coalesce(p_order->>'status', 'done'),
            coalesce(p_order->>'source', 'front'),
            coalesce((p_order->>'needs_kitchen')::boolean, false),
            (p_order->>'accepted_at')::timestamptz,
            (p_order->>'pickup_number')::int,
            nullif(left(p_order->>'guest_name', 60), ''),
            nullif(left(p_order->>'station', 40), ''),
            (p_order->>'subtotal_crc')::int,
            coalesce((p_order->>'discount_crc')::int, 0),
            (p_order->>'discount_id')::uuid,
            nullif(left(p_order->>'notes', 200), ''));
  exception when unique_violation then
    get stacked diagnostics c = constraint_name;
    if c = 'orders_pkey' then existing := true; else raise; end if;
  end;
  begin
    insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id)
      select coalesce(nullif(l->>'id', '')::uuid, gen_random_uuid()), oid, l->>'item_name', (l->>'price_crc')::int, (l->>'qty')::int,
             nullif(l->>'menu_item_id', '')::uuid
        from jsonb_array_elements(coalesce(p_order->'items', '[]'::jsonb)) l;
  exception
    when unique_violation then
      if not existing then raise; end if;          -- this sale's lines are already in (a repeated send)
    when others then
      if existing and sqlerrm ~ 'order_has_lines' then other := true; else raise; end if;
  end;
  return jsonb_build_object('ok', true, 'already', existing, 'other_lines', other);
end $$;
revoke all on function public.pos_record_sale(jsonb) from public, anon;
grant execute on function public.pos_record_sale(jsonb) to authenticated;

select canopy.migration_end(4, 'sales_save');
notify pgrst, 'reload schema';
