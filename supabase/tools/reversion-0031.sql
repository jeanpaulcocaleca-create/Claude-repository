-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0031 (ventas con la receta y el costo de su momento, devoluciones exactas)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0031 causa un problema y así lo decide el dueño, FUERA DEL HORARIO DE ATENCIÓN.
-- Antes: si la 0032 está aplicada, revierta primero la 0032 (supabase/tools/reversion-0032.sql).
--
-- Qué hace
--   * Deja exactamente como estaban antes de la 0031 (misma huella en la foto de producción): el descuento de una
--     venta (0004), el vínculo de la línea con su producto (0004), el guardado de una venta de la Caja (0010), agregar
--     y quitar productos de una cuenta y la anulación de una cuenta con pagos parciales (supabase/pos-tabs.sql), y las
--     protecciones de los ingredientes (0030).
--   * Quita las funciones nuevas y el disparador del historial de costos.
--   * Quita la 0031 del registro de migraciones (la base vuelve a la versión 30).
-- Qué NO hace: no borra las columnas nuevas ni el historial de costos (quedan, vacíos de uso), ni ningún movimiento,
--   venta o receta. Lo quitado de una cuenta con la 0031 quedó como filas 'sale' positivas: una anulación posterior de
--   esa cuenta las compensa igual que antes (0005).
-- Si más adelante se vuelve a aplicar la 0031: hágalo con las cuentas abiertas ya cobradas o anuladas. Una cuenta
--   abierta durante la 0031, con productos quitados mientras estuvo revertida, podría devolver de más al quitar otro.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 31) then
    raise exception 'La migración 0031 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 31) then
    raise exception 'Hay migraciones posteriores a la 0031: revierta primero esas (la 0032 con reversion-0032.sql). No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

drop trigger if exists stock_items_cost_log on public.stock_items;
drop function if exists public._stock_cost_log();
drop function if exists public._order_line_return(uuid, uuid, text, boolean, int, int, text);

-- 0004
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

-- 0010
create or replace function public.pos_record_sale(p_order jsonb)
returns jsonb language plpgsql set search_path = public as $$
declare oid uuid; existing boolean := false; c text; other boolean := false; op jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  oid := nullif(p_order->>'id', '')::uuid;
  if oid is null or jsonb_typeof(coalesce(p_order->'items', '[]'::jsonb)) <> 'array' then
    raise exception 'bad_payload' using errcode = 'P0001';
  end if;
  op := p_order->'operator';
  if op is not null and jsonb_typeof(op) = 'object' then
    perform set_config('canopy.operator_token', coalesce(nullif(op->>'token', ''), 'claim'), true);
    perform set_config('canopy.operator_claim', coalesce(op->>'staff_id', ''), true);
  elsif p_order ? 'operator' then
    perform set_config('canopy.operator_token', 'none', true);
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
      if not existing then raise; end if;
    when others then
      if existing and sqlerrm ~ 'order_has_lines' then other := true; else raise; end if;
  end;
  -- cash received and change; a repeated send keeps the first
  if jsonb_typeof(p_order->'tender') = 'object' then perform public._tender_insert(oid, p_order->'tender'); end if;
  perform set_config('canopy.operator_token', '', true);
  perform set_config('canopy.operator_claim', '', true);
  return jsonb_build_object('ok', true, 'already', existing, 'other_lines', other);
end $$;

-- supabase/pos-tabs.sql
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

-- 0030
create or replace function public._stock_item_in_use(p_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if pg_trigger_depth() = 0 then raise exception 'stock_item_in_use: solo desde el disparador de ingredientes'; end if;
  return exists (select 1 from public.stock_moves where item_id = p_id) or exists (select 1 from public.recipes where stock_item_id = p_id);
end $$;

create or replace function public._stock_item_history_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.stock_moves where item_id = old.id)
     or exists (select 1 from public.purchase_lines where item_id = old.id) then
    raise exception 'stock_item_has_history: % tiene movimientos; desmárquelo como Activo en vez de borrarlo', old.name
      using errcode = 'P0001';
  end if;
  if exists (select 1 from public.recipes where stock_item_id = old.id) then
    -- "history" in the code: the page published today reads it and says «it is kept; untick Active», the right advice here too
    raise exception 'stock_item_in_recipe_history: % está en una receta; quítelo de la receta o desmárquelo como Activo', old.name
      using errcode = 'P0001';
  end if;
  insert into public.audit_log (action, manager_name, target_id, summary, details)
    values ('stock_item_deleted', coalesce(public._inv_actor(), 'owner'), old.id::text, 'borró ' || old.name || ' (sin historial)', '{}'::jsonb);
  return old;
end $$;

drop function if exists public._stock_cost_at(uuid, timestamptz);
drop function if exists public._as_time(text);
drop function if exists public._sale_unit_cost(numeric, numeric, numeric);

delete from canopy.migrations where version = 31;
notify pgrst, 'reload schema';
select 'listo: la 0031 se revirtió; las columnas nuevas y el historial de costos se conservan' as resultado;
