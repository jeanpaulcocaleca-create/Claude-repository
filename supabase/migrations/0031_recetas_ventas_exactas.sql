-- =====================================================================================================
-- Canopy OS · migración 0031 · recetas, etapa 1B: cada venta descuenta la receta y el costo vigentes cuando se
-- registró, y lo que se quita de una cuenta devuelve exactamente lo que salió
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0030. Una sola transacción.
-- Aplicar FUERA DEL HORARIO DE ATENCIÓN: agregar columnas y disparadores a las líneas de venta, los movimientos de
-- inventario y los ingredientes toma esas tablas un instante (si algo las está usando en ese instante, el pegado se
-- detiene a los 8 segundos sin cambiar nada y se vuelve a pegar).
--
-- Qué hace
--   * Cada línea de venta guarda qué versión de la receta usó (recipe_version_id) y el momento cuya receta y costo
--     tomó (stock_time): el momento en que se registró en la caja. Una venta hecha sin internet y sincronizada horas
--     después descuenta la receta y el costo de cuando se cobró, no los de la sincronización. Si la receta no cambió
--     desde entonces (lo normal), se usa la receta de hoy, igual que antes.
--   * Cada movimiento de inventario de una venta sabe de qué línea salió (order_item_id) y para cuántas unidades
--     (line_qty). Así, quitar un producto de una cuenta devuelve exactamente lo que esa línea sacó, al mismo costo,
--     sin volver a calcular con la receta de hoy y sin devolver dos veces. (Antes se recalculaba con la receta del
--     momento de quitarlo, buscándola por el nombre.)
--   * Anular una cuenta con pagos parciales: lo pagado por producto (consumido) vuelve a salir exactamente como salió.
--   * El costo de cada ingrediente queda con historial (canopy.stock_cost_history) para valorar una venta tardía al
--     costo de su momento; un ingrediente con costo promedio 0 y precio de compra se valora al precio (no a ₡0).
--   * Lo agregado sin internet a un pedido que todavía estaba en la caja toma la receta y el costo de cuando se agregó
--     (la Caja nueva envía esa hora con el pedido o después; las páginas de antes no la envían y siguen igual).
--   * Un producto renombrado o borrado del menú mientras una caja estaba sin internet todavía descuenta su receta
--     (salvo que hoy otro producto del menú tenga ese nombre: entonces es ese, como antes).
--   * Un ingrediente que aparece en el historial de recetas ya no se puede borrar (se desactiva): las ventas viejas
--     siguen pudiendo leer su receta.
--   * Nunca rechaza una venta: si algo impide descontar el inventario, la venta se guarda igual y queda marcada
--     ('stock_not_taken' o 'recipe_item_missing'; la página Ventas lo muestra) para que el encargado la revise.
-- Qué NO cambia: la Caja, la cocina y las páginas publicadas hoy siguen igual (ningún cambio en lo que envían; la
--   hora de lo agregado es opcional).
--   Anular una venta, cancelar un pedido y devolver con reposición ya devolvían exactamente lo que salió (0005, 0006):
--   no se tocan. Las personalizaciones (etapa 1C) no están aquí.
-- Cuentas abiertas antes de la 0031: sus líneas no tienen el vínculo; al quitar una unidad se devuelve la parte que
--   sigue fuera de lo que salió con ese nombre en esa cuenta (incluye lo ya devuelto antes), sin recalcular.
-- Reversión: supabase/tools/reversion-0031.sql (después de revertir la 0032, si se aplicó). Las columnas nuevas y el
--   historial de costos se conservan.
-- =====================================================================================================
select canopy.migration_begin(31, 'recetas_ventas_exactas');

-- 1) los vínculos nuevos (columnas vacías: no cambian ningún registro existente) ------------------------------------
alter table public.order_items add column if not exists recipe_version_id bigint;   -- sin FK: el historial no se borra
alter table public.order_items add column if not exists stock_time timestamptz;      -- null: línea registrada antes de 0031
alter table public.stock_moves add column if not exists order_item_id uuid;           -- sin FK: la línea puede quitarse
alter table public.stock_moves add column if not exists line_qty numeric;             -- unidades de la línea (o devueltas)
create index if not exists stock_moves_order_item_idx on public.stock_moves (order_item_id) where order_item_id is not null;

-- 2) el costo de cada ingrediente en el tiempo ---------------------------------------------------------------------
-- el costo con que sale una venta: el promedio; sin promedio (o 0), el último precio; sin nada, la regla de 0005
create or replace function public._sale_unit_cost(p_avg numeric, p_cost_per_pack numeric, p_pack_qty numeric)
returns numeric language sql immutable set search_path = public as $$
  select coalesce(public._stock_unit_cost(p_avg, p_cost_per_pack, p_pack_qty), p_avg, round(p_cost_per_pack / nullif(p_pack_qty, 0), 4));
$$;
revoke all on function public._sale_unit_cost(numeric, numeric, numeric) from public, anon, authenticated;

create table if not exists canopy.stock_cost_history (
  id        bigint generated always as identity primary key,
  item_id   uuid not null references public.stock_items(id) on delete cascade,
  at        timestamptz not null default clock_timestamp(),
  unit_cost numeric
);
create index if not exists stock_cost_history_item_idx on canopy.stock_cost_history (item_id, at);
revoke all on canopy.stock_cost_history from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then execute 'revoke all on canopy.stock_cost_history from anon, authenticated'; end if;
end $$;

create or replace function public._stock_cost_log()
returns trigger language plpgsql security definer set search_path = public, canopy as $$
declare c numeric := public._sale_unit_cost(new.avg_cost, new.cost_per_pack, new.pack_qty);
begin
  if tg_op = 'INSERT' or c is distinct from public._sale_unit_cost(old.avg_cost, old.cost_per_pack, old.pack_qty) then
    insert into canopy.stock_cost_history (item_id, unit_cost) values (new.id, c);
  end if;
  return null;
end $$;
revoke all on function public._stock_cost_log() from public, anon, authenticated;
drop trigger if exists stock_items_cost_log on public.stock_items;
create trigger stock_items_cost_log after insert or update of avg_cost, cost_per_pack, pack_qty on public.stock_items
  for each row execute function public._stock_cost_log();
-- el punto de partida: el costo de cada ingrediente hoy (también si la 0031 se vuelve a aplicar después de revertirla:
-- un costo que cambió mientras estuvo revertida queda anotado)
insert into canopy.stock_cost_history (item_id, at, unit_cost)
  select s.id, now(), public._sale_unit_cost(s.avg_cost, s.cost_per_pack, s.pack_qty) from public.stock_items s
   where not exists (select 1 from canopy.stock_cost_history h where h.item_id = s.id)
      or public._sale_unit_cost(s.avg_cost, s.cost_per_pack, s.pack_qty) is distinct from
         (select h.unit_cost from canopy.stock_cost_history h where h.item_id = s.id order by h.at desc, h.id desc limit 1);

-- el costo de un ingrediente en un momento: si no cambió desde entonces, el de hoy (como siempre)
create or replace function public._stock_cost_at(p_item_id uuid, p_at timestamptz)
returns numeric language plpgsql stable security definer set search_path = public, canopy as $$
declare c numeric;
begin
  if exists (select 1 from canopy.stock_cost_history h where h.item_id = p_item_id and h.at > p_at) then
    select h.unit_cost into c from canopy.stock_cost_history h
     where h.item_id = p_item_id and h.at <= p_at order by h.at desc, h.id desc limit 1;
    if not found then   -- el historial empezó después: el primer costo conocido
      select h.unit_cost into c from canopy.stock_cost_history h where h.item_id = p_item_id order by h.at, h.id limit 1;
    end if;
    if c is not null then return c; end if;
  end if;
  select public._sale_unit_cost(s.avg_cost, s.cost_per_pack, s.pack_qty) into c from public.stock_items s where s.id = p_item_id;
  return c;
end $$;
revoke all on function public._stock_cost_at(uuid, timestamptz) from public, anon, authenticated;

-- 3) un producto renombrado o borrado mientras una caja estaba sin internet sigue siendo el mismo producto -------------
-- igual que en la 0004, más: el id enviado se conserva si el historial de recetas de ese producto tiene ese nombre, y
-- el producto todavía existía cuando se cobró o ningún producto del menú se llama así hoy (uno borrado y vuelto a
-- crear con el mismo nombre es el de hoy para lo cobrado después, como antes)
create or replace function public._order_item_menu_id()
returns trigger language plpgsql security definer set search_path = public as $$
declare t timestamptz;
begin
  -- an id is kept only when it names this same product; otherwise the name decides (as before)
  if new.menu_item_id is not null
     and not exists (select 1 from public.menu_items where id = new.menu_item_id and lower(name) = lower(new.item_name)) then
    -- when the line was rung (the till's time; a clock ahead is now)
    select o.created_at into t from public.orders o where o.id = new.order_id;
    if t is null or t >= now() then t := clock_timestamp(); end if;
    if not exists (select 1 from public.recipe_versions where menu_item_id = new.menu_item_id
                                                         and lower(menu_item_name) = lower(new.item_name))
       or (exists (select 1 from public.menu_items where lower(name) = lower(new.item_name))
           and not exists (select 1 from public.recipe_versions where menu_item_id = new.menu_item_id and at > t)) then
      new.menu_item_id := null;
    end if;
  end if;
  if new.menu_item_id is null then
    select id into new.menu_item_id from public.menu_items where lower(name) = lower(new.item_name) order by available desc limit 1;
  end if;
  return new;
end $$;

-- 4) la venta descuenta la receta de su momento -------------------------------------------------------------------
-- El momento de una línea es added_at: la hora de la caja para una venta (también la guardada sin internet) y la
-- hora en que se agregó para lo que se suma a una cuenta. Si la receta no cambió desde ese momento, la receta de hoy
-- (como siempre); si cambió, la versión vigente entonces; si el producto todavía no tenía receta, nada.
-- Lo agregado sin internet a un pedido que todavía estaba en la caja trae su propia hora (stock_time: la Caja nueva la
-- envía con el pedido o después, por tab_add_items); se toma entre la hora del pedido y ahora. La caja ya elige la hora
-- del pedido, así que esto no le da nada nuevo; las páginas de antes no la envían.
create or replace function public._order_item_stock()
returns trigger language plpgsql security definer set search_path = public as $$
declare mid uuid; t timestamptz; ts timestamptz; v public.recipe_versions; live boolean := false; ver bigint; missing int := 0;
begin
  mid := new.menu_item_id;
  if mid is null then
    select id into mid from public.menu_items where lower(name) = lower(new.item_name) order by available desc limit 1;
  end if;
  -- a line of now (online, or added to a bill now) takes this very instant, so a change made just before it in the same
  -- transaction counts; a line rung earlier (a sale kept on the device without internet) takes its own time
  t := case when new.added_at is null or new.added_at >= now() then clock_timestamp() else new.added_at end;
  -- an item added on the device to an order that was still there: the time it was added, never before the order and
  -- never later than now (then it is now)
  if new.stock_time is not null then
    ts := greatest(new.stock_time, (select o.created_at from public.orders o where o.id = new.order_id));
    if ts < now() then t := ts; end if;
  end if;
  begin
    if mid is not null then
      -- one snapshot for the latest version and the live recipe: a save made meanwhile is seen by both or by neither
      with lv as (select id, at from public.recipe_versions where menu_item_id = mid order by version desc limit 1),
           ins as (insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, order_item_id, line_qty, note)
                     select r.stock_item_id, 'sale', -(r.qty * greatest(new.qty, 0)), public._stock_cost_at(r.stock_item_id, t),
                            new.order_id, new.id, new.qty, new.item_name
                       from public.recipes r
                      where r.menu_item_id = mid and r.qty * greatest(new.qty, 0) <> 0
                        and not exists (select 1 from lv where lv.at > t)
                      order by r.stock_item_id   -- same lock order everywhere: two sales at once never deadlock
                   returning 1)
      select lv.id, coalesce(lv.at <= t, true) into ver, live from (select 1) one left join lv on true;
      if not live then
        select * into v from public.recipe_versions where menu_item_id = mid and at <= t order by version desc limit 1;
        if v.id is null then
          -- the history began after the line was rung: the starting version was already in force; any other first
          -- version means the product had no recipe yet then
          select * into v from public.recipe_versions where menu_item_id = mid order by version limit 1;
          if v.source is distinct from 'baseline' then v := null; end if;
        end if;
        ver := v.id;
      end if;
      -- the recipe changed since then: the version in force at that time (the live recipe was left untouched above)
      if not live and v.id is not null then
        insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, order_item_id, line_qty, note)
          select s.id, 'sale', -((l->>'qty')::numeric * greatest(new.qty, 0)), public._stock_cost_at(s.id, t),
                 new.order_id, new.id, new.qty, new.item_name
            from jsonb_array_elements(v.lines) l
            join public.stock_items s on s.id = (l->>'stock_item_id')::uuid and s.unit = coalesce(l->>'unit', s.unit)
           where (l->>'qty')::numeric * greatest(new.qty, 0) <> 0
           order by s.id;
        -- an ingredient of that version that no longer exists (or is counted in another unit now) is left out, never refused
        select count(*) into missing from jsonb_array_elements(v.lines) l
         where not exists (select 1 from public.stock_items s where s.id = (l->>'stock_item_id')::uuid and s.unit = coalesce(l->>'unit', s.unit));
      end if;
    end if;
    update public.order_items set recipe_version_id = ver, stock_time = t where id = new.id;
    if missing > 0 then
      update public.orders set flags = array_append(coalesce(flags, '{}'), 'recipe_item_missing')
       where id = new.order_id and not ('recipe_item_missing' = any(coalesce(flags, '{}')));
    end if;
  exception
    when deadlock_detected or lock_not_available or serialization_failure or query_canceled then raise;   -- the till retries
    when others then
      -- money already taken is never refused: the sale stays, marked for a manager
      raise warning 'stock_not_taken: % (%): %', new.item_name, new.order_id, sqlerrm;
      update public.orders set flags = array_append(coalesce(flags, '{}'), 'stock_not_taken')
       where id = new.order_id and not ('stock_not_taken' = any(coalesce(flags, '{}')));
      -- the line still counts as rung under 0031: nothing of it went out, so nothing of it comes back later
      begin
        update public.order_items set stock_time = t where id = new.id;
      exception when others then null;
      end;
  end;
  return new;
end $$;
revoke all on function public._order_item_stock() from public, anon, authenticated;

-- una hora enviada por la caja, leída sin riesgo: si no se entiende, ninguna (nunca rechaza la venta)
create or replace function public._as_time(p text)
returns timestamptz language plpgsql stable set search_path = public as $$
begin
  return p::timestamptz;
exception when others then
  return null;
end $$;
revoke all on function public._as_time(text) from public, anon;
grant execute on function public._as_time(text) to authenticated;

-- pos_record_sale (0010) igual, salvo la hora de cada producto agregado en la caja al pedido antes de enviarlo: "at",
-- opcional (la Caja nueva la envía; las páginas de antes no, y nada cambia para ellas)
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
    insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id, stock_time)
      select coalesce(nullif(l->>'id', '')::uuid, gen_random_uuid()), oid, l->>'item_name', (l->>'price_crc')::int, (l->>'qty')::int,
             nullif(l->>'menu_item_id', '')::uuid, public._as_time(l->>'at')
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

-- tab_add_items (supabase/pos-tabs.sql) igual, salvo la hora de cada producto agregado: "at", opcional (la Caja
-- nueva la envía para lo agregado sin internet; las páginas de antes no la envían y nada cambia para ellas)
create or replace function public.tab_add_items(p_order_id uuid, p_items jsonb, p_add_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; it jsonb; mi record; n int; kitchen boolean := false; added int := 0; rnd int;
        open_value int; used int; s_new int; d_new int; t_new int; res jsonb; t_at timestamptz;
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
    -- 0031: when it was added on the device (an order still there without internet), for the recipe of that time;
    -- a time that does not read is left out, never refused (the sale trigger keeps it between the order and now)
    t_at := null;
    begin t_at := (it->>'at')::timestamptz; exception when others then t_at := null; end;
    insert into public.order_items (order_id, item_name, price_crc, qty, round, stock_time)
      values (o.id, mi.name, mi.price_crc, n, rnd, t_at);
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

-- 5) lo que se quita de una cuenta vuelve exactamente --------------------------------------------------------------
-- Devuelve, de lo que la línea todavía tiene fuera (por ingrediente), la parte de las unidades quitadas, al costo con
-- que salió. Al quitar la última unidad devuelve exactamente lo que queda: nunca queda un residuo ni se devuelve dos
-- veces. Las filas son 'sale' positivas, como antes (una anulación posterior de la cuenta las compensa igual: 0005).
-- Una línea registrada antes de 0031 no tiene vínculo: se usa lo que sigue fuera con ese nombre en esa cuenta.
create or replace function public._order_line_return(p_order_id uuid, p_line_id uuid, p_item_name text, p_linked boolean,
                                                     p_qty_before int, p_units int, p_by text)
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; units numeric;
begin
  if p_units is null or p_units < 1 or p_qty_before is null or p_qty_before < 1 then return 0; end if;
  if p_linked then
    insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, order_item_id, line_qty, note, by_name)
      select g.item_id, 'sale',
             case when p_units >= p_qty_before then g.still_out else trim_scale(g.still_out * p_units / p_qty_before) end,
             g.cost, p_order_id, p_line_id, p_units, p_item_name, p_by
        from (select m.item_id, -sum(m.qty) as still_out,
                     coalesce((array_agg(m.unit_cost order by m.id) filter (where m.qty < 0))[1], 0) as cost
                from public.stock_moves m
               where m.order_id = p_order_id and m.order_item_id = p_line_id and m.kind in ('sale', 'void')
               group by m.item_id) g
       where g.still_out > 0
       order by g.item_id;
    get diagnostics n = row_count;
  else
    select p_qty_before + coalesce(sum(i.qty), 0) into units from public.order_items i
     where i.order_id = p_order_id and i.id <> p_line_id and i.stock_time is null and lower(i.item_name) = lower(p_item_name);
    insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, line_qty, note, by_name)
      select g.item_id, 'sale',
             case when p_units >= units then g.still_out else trim_scale(g.still_out * p_units / units) end,
             g.cost, p_order_id, p_units, p_item_name, p_by
        from (select m.item_id, -sum(m.qty) as still_out,
                     coalesce(round(sum(m.qty * coalesce(m.unit_cost, 0)) filter (where m.qty < 0)
                                    / nullif(sum(m.qty) filter (where m.qty < 0), 0), 4), 0) as cost
                from public.stock_moves m
               where m.order_id = p_order_id and m.order_item_id is null and m.kind in ('sale', 'void')
                 and lower(m.note) in (lower(p_item_name), lower(p_item_name || ' · taken off the bill'))
               group by m.item_id) g
       where g.still_out > 0
       order by g.item_id;
    get diagnostics n = row_count;
  end if;
  return n;
end $$;
revoke all on function public._order_line_return(uuid, uuid, text, boolean, int, int, text) from public, anon, authenticated;

-- tab_remove_item (supabase/pos-tabs.sql) igual, salvo la devolución del inventario
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
  -- the stock it took goes back, exactly (0031): before the line changes, while its units are known
  if to_regclass('public.stock_moves') is not null then
    perform public._order_line_return(o.id, li.id, li.item_name, li.stock_time is not null, li.qty, p_qty, who);
  end if;
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
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('tab_item_removed', by_id, who, o.id::text,
            p_qty || '× ' || li.item_name || ' · ' || public._tab_label(o) || case when why <> '' then ' · ' || why else '' end,
            jsonb_build_object('qty', p_qty, 'item', li.item_name, 'value_crc', val, 'bill_cut_crc', cut, 'reason', why,
                               'bill', public._tab_label(o), 'station', nullif(trim(coalesce(p_station, '')), ''),
                               'approved', by_id is not null));
  return jsonb_build_object('ok', true, 'total', t_new, 'closed', closes);
end $$;

-- 6) una cuenta con pagos por producto, anulada: lo consumido vuelve a salir exactamente como salió -------------------
-- (pos-tabs.sql igual, salvo esa parte; una línea registrada antes de 0031 vuelve a sacar su parte de lo que salió con su
-- nombre en esa cuenta, al costo con que salió: tampoco se recalcula con la receta de hoy)
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
    -- the void of the bill returns all its stock (0005); the items paid in parts were eaten: what each of those
    -- lines took per unit, at the cost it went out with
    insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, order_item_id, line_qty, note)
      select s.item_id, 'sale', trim_scale(s.qty * e.units / s.line_qty), coalesce(s.unit_cost, 0), null, e.item_id, e.units,
             s.note || ' · paid in part, bill voided'
        from (select l.item_id, sum(l.qty) as units
                from public.order_part_lines l
                join public.orders p on p.id = l.part_id and p.part_of = new.id and p.voided_at is null
               group by l.item_id) e
        join public.order_items i on i.id = e.item_id and i.stock_time is not null
        join public.stock_moves s on s.order_item_id = i.id and s.order_id = new.id and s.kind = 'sale' and s.qty < 0 and s.line_qty > 0
       order by s.item_id;
    -- lines rung before 0031 (no link): the eaten units' share of what still went out under their name in this bill
    -- before the void, at the cost it went out with (as _order_line_return shares it), never today's recipe
    insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, line_qty, note)
      select g.item_id, 'sale',
             -(case when e.units >= u.units then g.still_out else trim_scale(g.still_out * e.units / u.units) end),
             g.cost, null, e.units, e.name || ' · paid in part, bill voided'
        from (select lower(i.item_name) as k, min(i.item_name) as name, sum(l.qty) as units
                from public.order_part_lines l
                join public.orders p on p.id = l.part_id and p.part_of = new.id and p.voided_at is null
                join public.order_items i on i.id = l.item_id and i.order_id = new.id and i.stock_time is null
               group by lower(i.item_name)) e
        join (select lower(i.item_name) as k, sum(i.qty) as units from public.order_items i
               where i.order_id = new.id and i.stock_time is null group by lower(i.item_name)) u on u.k = e.k and u.units > 0
        join lateral (select x.item_id, -sum(x.qty) as still_out,
                             coalesce(round(sum(x.qty * coalesce(x.unit_cost, 0)) filter (where x.qty < 0)
                                            / nullif(sum(x.qty) filter (where x.qty < 0), 0), 4), 0) as cost
                        from public.stock_moves x
                       where x.order_id = new.id and x.order_item_id is null and x.kind = 'sale'
                         and lower(x.note) in (e.k, e.k || ' · taken off the bill')
                       group by x.item_id) g on g.still_out > 0
       order by g.item_id;
  end if;
  return new;
end $$;

-- 7) un ingrediente que aparece en el historial de recetas no se borra (se desactiva) -----------------------------
-- igual que en la 0030, más el historial
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
  -- 0031: a recipe of the past names it, and a sale rung then may still arrive (or be returned) with that recipe
  if exists (select 1 from public.recipe_versions where lines @> jsonb_build_array(jsonb_build_object('stock_item_id', old.id))) then
    raise exception 'stock_item_in_old_recipe_history: % aparece en el historial de recetas; desmárquelo como Activo en vez de borrarlo', old.name
      using errcode = 'P0001';
  end if;
  insert into public.audit_log (action, manager_name, target_id, summary, details)
    values ('stock_item_deleted', coalesce(public._inv_actor(), 'owner'), old.id::text, 'borró ' || old.name || ' (sin historial)', '{}'::jsonb);
  return old;
end $$;

-- y su unidad tampoco cambia (igual que en la 0030, más el historial): una venta tardía de esa receta descuenta en la
-- unidad con que se escribió
create or replace function public._stock_item_in_use(p_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if pg_trigger_depth() = 0 then raise exception 'stock_item_in_use: solo desde el disparador de ingredientes'; end if;
  return exists (select 1 from public.stock_moves where item_id = p_id) or exists (select 1 from public.recipes where stock_item_id = p_id)
      or exists (select 1 from public.recipe_versions where lines @> jsonb_build_array(jsonb_build_object('stock_item_id', p_id)));
end $$;

-- 8) el historial de recetas al día antes de que las ventas lo lean (una receta cambiada sin historial queda anotada)
select canopy.recipe_baseline();

select canopy.migration_end(31, 'recetas_ventas_exactas');
notify pgrst, 'reload schema';
