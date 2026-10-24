-- =====================================================================================================
-- Canopy OS · migración 0005 · Inventario: historial protegido, costo en cada movimiento, recepciones seguras
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0004.
--
-- Por qué
--   * Borrar un producto del inventario borraba también todo su historial de movimientos y compras.
--   * Las existencias (on_hand) se podían cambiar directamente sin dejar un movimiento.
--   * El costo se reemplazaba con cada compra; las salidas (ventas, mermas) no guardaban su costo, así que el
--     costo de lo vendido no se podía reconstruir.
--   * Una orden de compra podía recibirse dos veces si dos personas tocaban "Recibir" a la vez (comprobado), una
--     orden cancelada podía recibirse, y se aceptaban cantidades o costos negativos.
-- Qué hace
--   * Un producto o proveedor con historial ya no se puede borrar: se archiva (desmarcar "Activo").
--   * Las existencias solo cambian con movimientos (conteo, merma, recepción, venta).
--   * stock_items.avg_cost: costo promedio ponderado por unidad (el método final lo confirma el contador).
--   * Cada movimiento guarda su costo por unidad del momento.
--   * Recepciones: una a la vez por orden, nunca de una orden cancelada, nunca negativa, y con identificador
--     de solicitud: tocar dos veces no duplica.
--   * El "inventario inicial" de un producto nuevo queda como ajuste, no como compra.
-- Qué cambia para el personal: "Eliminar" un producto con historial muestra un mensaje; use "Activo".
-- Reversión: drop trigger stock_item_history_guard / stock_items_protect / stock_move_cost / purchase_order_status.
-- =====================================================================================================
select canopy.migration_begin(5, 'inventory_integrity');

alter table public.stock_items add column if not exists avg_cost numeric;          -- colones per stock unit
update public.stock_items set avg_cost = round(cost_per_pack / nullif(pack_qty, 0), 4) where avg_cost is null;
alter table public.stock_moves add column if not exists request_id uuid;
create unique index if not exists stock_moves_request_once on public.stock_moves (request_id) where request_id is not null;

-- 1) history can never be deleted ------------------------------------------------------------------------
create or replace function public._stock_item_history_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.stock_moves where item_id = old.id)
     or exists (select 1 from public.purchase_lines where item_id = old.id) then
    raise exception 'stock_item_has_history: % tiene movimientos; desmárquelo como Activo en vez de borrarlo', old.name
      using errcode = 'P0001';
  end if;
  insert into public.audit_log (action, manager_name, target_id, summary, details)
    values ('stock_item_deleted', coalesce(public._inv_actor(), 'owner'), old.id::text, 'borró ' || old.name || ' (sin historial)', '{}'::jsonb);
  return old;
end $$;
drop trigger if exists stock_item_history_guard on public.stock_items;
create trigger stock_item_history_guard before delete on public.stock_items for each row execute function public._stock_item_history_guard();

create or replace function public._vendor_history_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.purchase_orders where vendor_id = old.id) then
    raise exception 'vendor_has_history: % tiene órdenes de compra; desmárquelo como Activo en vez de borrarlo', old.name
      using errcode = 'P0001';
  end if;
  return old;
end $$;
drop trigger if exists vendor_history_guard on public.vendors;
create trigger vendor_history_guard before delete on public.vendors for each row execute function public._vendor_history_guard();

create or replace function public._purchase_history_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'purchase_orders' then
    if old.status in ('received', 'partially_received') then
      raise exception 'purchase_order_received: una orden recibida no se borra' using errcode = 'P0001';
    end if;
  elsif coalesce(old.received_qty, 0) > 0 then
    raise exception 'purchase_line_received: una línea recibida no se borra' using errcode = 'P0001';
  end if;
  return old;
end $$;
drop trigger if exists purchase_order_history_guard on public.purchase_orders;
create trigger purchase_order_history_guard before delete on public.purchase_orders for each row execute function public._purchase_history_guard();
drop trigger if exists purchase_line_history_guard on public.purchase_lines;
create trigger purchase_line_history_guard before delete on public.purchase_lines for each row execute function public._purchase_history_guard();

-- 2) the pages cannot set stock or costs directly: only movements do -----------------------------------
create or replace function public._stock_items_protect()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.on_hand := 0;                 -- opening stock comes in as a movement (stock_receive)
      new.avg_cost := round(coalesce(new.cost_per_pack, 0) / nullif(new.pack_qty, 0), 4);
    else
      new.on_hand := old.on_hand;
      new.avg_cost := old.avg_cost;
      if new.cost_per_pack is distinct from old.cost_per_pack or new.pack_qty is distinct from old.pack_qty then
        perform public._stock_cost_edit_log(old.id, old.name, old.cost_per_pack, new.cost_per_pack, old.pack_qty, new.pack_qty);
      end if;
    end if;
  end if;
  return new;
end $$;
create or replace function public._stock_cost_edit_log(p_id uuid, p_name text, p_old numeric, p_new numeric, p_old_pack numeric, p_new_pack numeric)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (action, manager_name, target_id, summary, details)
    select 'stock_cost_edit', coalesce(public._inv_actor(), 'owner'), p_id::text, 'cambió el costo de ' || p_name,
           jsonb_build_object('cost_per_pack_before', p_old, 'cost_per_pack_after', p_new, 'pack_qty_before', p_old_pack, 'pack_qty_after', p_new_pack)
     where public.inventory_open();            -- only an open inventory can edit costs, so only it can log one
$$;
revoke all on function public._stock_cost_edit_log(uuid, text, numeric, numeric, numeric, numeric) from public, anon;
grant execute on function public._stock_cost_edit_log(uuid, text, numeric, numeric, numeric, numeric) to authenticated;
drop trigger if exists stock_items_protect on public.stock_items;
create trigger stock_items_protect before insert or update on public.stock_items for each row execute function public._stock_items_protect();

-- 3) every movement carries its unit cost; purchases keep a weighted average --------------------------------
create or replace function public._stock_move_cost()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.unit_cost is not null and new.unit_cost < 0 then raise exception 'bad_cost' using errcode = 'P0001'; end if;
  if new.unit_cost is null or (new.kind = 'purchase' and new.unit_cost = 0) then
    select coalesce(avg_cost, round(cost_per_pack / nullif(pack_qty, 0), 4)) into new.unit_cost
      from public.stock_items where id = new.item_id;
  end if;
  return new;
end $$;
drop trigger if exists stock_move_cost on public.stock_moves;
create trigger stock_move_cost before insert on public.stock_moves for each row execute function public._stock_move_cost();

create or replace function public._stock_move_applied()
returns trigger language plpgsql security definer set search_path = public as $$
declare q0 numeric; a0 numeric;
begin
  select greatest(on_hand, 0), avg_cost into q0, a0 from public.stock_items where id = new.item_id for update;
  if new.kind = 'purchase' and new.qty > 0 and new.unit_cost is not null then
    update public.stock_items set on_hand = on_hand + new.qty, updated_at = now(),
           avg_cost = case when a0 is null or q0 + new.qty <= 0 then round(new.unit_cost, 4)
                           else round((q0 * a0 + new.qty * new.unit_cost) / (q0 + new.qty), 4) end
     where id = new.item_id;
  else
    update public.stock_items set on_hand = on_hand + new.qty, updated_at = now() where id = new.item_id;
  end if;
  return new;
end $$;

-- a void or a cancelled order puts stock back at the same cost it went out with
create or replace function public._order_stock_return()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.voided_at is not null and old.voided_at is null)
     or (new.status = 'cancelled' and coalesce(old.status, '') <> 'cancelled') then
    insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, note)
      select m.item_id, 'void', -m.qty, m.unit_cost, m.order_id, m.note
        from public.stock_moves m where m.order_id = new.id and m.kind = 'sale'
        and not exists (select 1 from public.stock_moves v where v.order_id = new.id and v.kind = 'void' and v.item_id = m.item_id)
       order by m.item_id;
  end if;
  return new;
end $$;

-- 4) counts, waste and walk-in receipts: a request sent twice counts once ---------------------------------
drop function if exists public.stock_count(uuid, numeric, text);
create or replace function public.stock_count(p_item_id uuid, p_counted numeric, p_note text default null, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur numeric; diff numeric;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_request_id is not null and exists (select 1 from public.stock_moves where request_id = p_request_id) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  if p_counted is null or p_counted < 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  select on_hand into cur from public.stock_items where id = p_item_id for update;
  if cur is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  diff := p_counted - cur;
  begin
    insert into public.stock_moves (item_id, kind, qty, note, by_name, request_id)
      values (p_item_id, 'count', diff, coalesce(p_note, 'counted ' || p_counted), public._inv_actor(), p_request_id);
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'repeat', true);    -- the same request arriving at the same moment
  end;
  return jsonb_build_object('ok', true, 'diff', diff, 'on_hand', p_counted);
end $$;

drop function if exists public.stock_waste(uuid, numeric, text);
create or replace function public.stock_waste(p_item_id uuid, p_qty numeric, p_note text default null, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_request_id is not null and exists (select 1 from public.stock_moves where request_id = p_request_id) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  if coalesce(p_qty, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  if not exists (select 1 from public.stock_items where id = p_item_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  begin
    insert into public.stock_moves (item_id, kind, qty, note, by_name, request_id)
      values (p_item_id, 'waste', -p_qty, p_note, public._inv_actor(), p_request_id);
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'repeat', true);
  end;
  return jsonb_build_object('ok', true);
end $$;

drop function if exists public.stock_receive(uuid, numeric, numeric, date, text);
create or replace function public.stock_receive(p_item_id uuid, p_qty numeric, p_unit_cost numeric default null,
                                                p_expires_on date default null, p_note text default null,
                                                p_request_id uuid default null, p_opening boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare it public.stock_items; opening boolean;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_request_id is not null and exists (select 1 from public.stock_moves where request_id = p_request_id) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  if coalesce(p_qty, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  if p_unit_cost is not null and p_unit_cost < 0 then return jsonb_build_object('ok', false, 'error', 'bad_cost'); end if;
  select * into it from public.stock_items where id = p_item_id;
  if it.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  -- the stock a new item starts with is an opening balance, not a purchase (older pages say 'starting stock')
  opening := coalesce(p_opening, false) or coalesce(p_note, '') = 'starting stock';
  begin
    insert into public.stock_moves (item_id, kind, qty, unit_cost, expires_on, note, by_name, request_id)
      values (p_item_id, case when opening then 'adjust' else 'purchase' end, p_qty, p_unit_cost,
              coalesce(p_expires_on, case when it.shelf_life_days is not null then current_date + it.shelf_life_days end),
              case when opening then coalesce(p_note, 'inventario inicial') else p_note end, public._inv_actor(), p_request_id);
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'repeat', true);
  end;
  if p_unit_cost is not null and p_unit_cost > 0 then
    update public.stock_items set cost_per_pack = p_unit_cost * pack_qty where id = p_item_id;
    if opening then update public.stock_items set avg_cost = round(p_unit_cost, 4) where id = p_item_id; end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 5) receiving a purchase order: one at a time, never cancelled, never negative ---------------------------
create or replace function public.po_receive(p_po_id uuid, p_lines jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare po public.purchase_orders; ln record; l jsonb; got numeric; cost numeric; exp date; n int := 0; it public.stock_items;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select * into po from public.purchase_orders where id = p_po_id for update;
  if po.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if po.status = 'received' then return jsonb_build_object('ok', false, 'error', 'already_received'); end if;
  if po.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    if coalesce((l ->> 'received_qty')::numeric, 0) < 0 or coalesce((l ->> 'unit_cost')::numeric, 0) < 0 then
      return jsonb_build_object('ok', false, 'error', 'bad_qty');
    end if;
  end loop;
  for ln in select * from public.purchase_lines where po_id = p_po_id order by item_id loop
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

-- the pages may move a purchase order only along draft → sent → cancelled; receiving goes through po_receive
create or replace function public._purchase_order_status()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and new.status is distinct from old.status then
    if not ((old.status = 'draft' and new.status in ('sent', 'cancelled')) or (old.status = 'sent' and new.status = 'cancelled')) then
      raise exception 'po_status: no se puede pasar de % a % desde la página', old.status, new.status using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists purchase_order_status on public.purchase_orders;
create trigger purchase_order_status before update on public.purchase_orders for each row execute function public._purchase_order_status();

revoke all on function public.stock_count(uuid, numeric, text, uuid), public.stock_waste(uuid, numeric, text, uuid),
  public.stock_receive(uuid, numeric, numeric, date, text, uuid, boolean), public.po_receive(uuid, jsonb) from public, anon;
grant execute on function public.stock_count(uuid, numeric, text, uuid), public.stock_waste(uuid, numeric, text, uuid),
  public.stock_receive(uuid, numeric, numeric, date, text, uuid, boolean), public.po_receive(uuid, jsonb) to authenticated;
revoke all on function public._stock_item_history_guard(), public._vendor_history_guard(), public._purchase_history_guard(),
  public._stock_move_cost(), public._stock_move_applied(), public._order_stock_return() from public, anon, authenticated;

select canopy.migration_end(5, 'inventory_integrity');
notify pgrst, 'reload schema';
