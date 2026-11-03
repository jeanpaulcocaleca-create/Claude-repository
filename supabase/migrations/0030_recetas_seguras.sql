-- =====================================================================================================
-- Canopy OS · migración 0030 · Recetas seguras (Etapa 1A: Inventario → Recetas)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0029.
-- (No confundir con la 0030_facturas_archivo que se borró el 2026-10-15 sin llegar a producción, D-042.)
--
-- Qué hace (plan aprobado por el dueño el 2026-10-16, D-043)
--   * recipe_save: guarda la receta de un producto en UN paso (nunca queda a medias ni vacía para una venta), con el
--     PIN de un encargado o del dueño, las cantidades en g, ml o unidades (se convierten a la unidad del ingrediente),
--     y avisa si otra persona la cambió mientras tanto. Responde con la receta guardada y su costo.
--   * recipe_versions: el historial de cada receta. Cada guardado agrega una versión con quién la autorizó, cuándo,
--     el motivo, las líneas y el costo antes y después. No se puede modificar ni borrar. Al aplicar esta migración
--     cada receta que ya existe queda como «versión inicial».
--   * Si algo escribe recetas sin pasar por recipe_save (una página vieja guardada en el aparato, el botón viejo
--     «Enlazar por nombre», borrar un producto del menú o un ingrediente), el historial lo anota como «cambio
--     directo» o «producto borrado». Nunca impide ese cambio: solo lo registra.
--   * recipes_autolink_pin: «Enlazar por nombre» con PIN; solo enlaza ingredientes que se cuentan por unidad.
--   * Un costo para todo: el de las ventas (costo promedio; si es 0, el último precio). El reporte de costo de
--     ingredientes de Inventario valora lo usado y lo desperdiciado al costo con que salió, y las ventas sin IVA.
--   * Protecciones: no se cambia la unidad de un ingrediente que ya tiene movimientos o recetas (se crea uno
--     nuevo), y no se borra un ingrediente que está en una receta.
-- Qué cambia para el personal: guardar una receta pide el PIN de un encargado o del dueño. Nada cambia en la caja,
--   las ventas, los pagos ni el descuento de inventario de cada venta.
-- Reversión: supabase/tools/reversion-0030.sql (deja las funciones como estaban; el historial se conserva).
-- =====================================================================================================
select canopy.migration_begin(30, 'recetas_seguras');

-- 1) el historial de recetas ------------------------------------------------------------------------------------
create table if not exists public.recipe_versions (
  id              bigint generated always as identity primary key,
  menu_item_id    uuid not null,                     -- sin llave foránea: el historial sobrevive al borrar el producto
  menu_item_name  text,
  version         int not null check (version > 0),
  lines           jsonb not null default '[]'::jsonb, -- [{stock_item_id, name, unit, qty, unit_cost, entered_qty, entered_unit}]
  cost_crc        numeric,                            -- costo de la receta guardada, al costo de ese momento
  cost_before_crc numeric,                            -- costo de la receta anterior, al mismo costo
  missing_cost    jsonb not null default '[]'::jsonb, -- ingredientes sin costo (nombres)
  price_crc       int,
  price_net_crc   numeric,
  source          text not null check (source in ('baseline', 'editor', 'direct', 'deleted', 'autolink')),
  reason          text,
  authorized_by   uuid,                               -- staff.id del PIN (editor, autolink)
  by_name         text,
  request_id      uuid,
  at              timestamptz not null default clock_timestamp(),
  unique (menu_item_id, version)
);
create unique index if not exists recipe_versions_request_once on public.recipe_versions (request_id) where request_id is not null;
create index if not exists recipe_versions_item_idx on public.recipe_versions (menu_item_id, version desc);

alter table public.recipe_versions enable row level security;
revoke all on public.recipe_versions from anon, authenticated;
grant select on public.recipe_versions to authenticated;
drop policy if exists "recipe versions read" on public.recipe_versions;
create policy "recipe versions read" on public.recipe_versions for select to authenticated using ((select public.inventory_open()));

-- una versión no se cambia ni se borra, ni siquiera con el SQL Editor
create or replace function public._recipe_versions_immutable() returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'recipe_versions_immutable: el historial de recetas no se modifica ni se borra' using errcode = 'P0001';
end $$;
drop trigger if exists recipe_versions_immutable on public.recipe_versions;
create trigger recipe_versions_immutable before update or delete on public.recipe_versions
  for each row execute function public._recipe_versions_immutable();
drop trigger if exists recipe_versions_no_truncate on public.recipe_versions;
create trigger recipe_versions_no_truncate before truncate on public.recipe_versions
  for each statement execute function public._recipe_versions_immutable();
revoke all on function public._recipe_versions_immutable() from public, anon, authenticated;

-- 2) un costo para todo: el que se sella en cada venta (0005), con el último precio cuando el promedio es 0 ----------
create or replace function public._stock_unit_cost(p_avg numeric, p_cost_per_pack numeric, p_pack_qty numeric)
returns numeric language sql immutable set search_path = public as $$
  select coalesce(nullif(p_avg, 0), round(nullif(p_cost_per_pack, 0) / nullif(p_pack_qty, 0), 4));
$$;
revoke all on function public._stock_unit_cost(numeric, numeric, numeric) from public, anon, authenticated;

-- las líneas actuales de una receta, con nombre, unidad y costo de hoy, en un orden fijo
create or replace function public._recipe_lines(p_menu_item_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('stock_item_id', r.stock_item_id, 'name', s.name, 'unit', s.unit, 'qty', r.qty,
                                               'unit_cost', public._stock_unit_cost(s.avg_cost, s.cost_per_pack, s.pack_qty))
                            order by r.stock_item_id::text), '[]'::jsonb)
    from public.recipes r join public.stock_items s on s.id = r.stock_item_id
   where r.menu_item_id = p_menu_item_id;
$$;
-- lo que cuenta para decir que una receta cambió: ingrediente y cantidad (no el nombre ni el costo del día)
create or replace function public._recipe_key(p_lines jsonb)
returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('s', x->>'stock_item_id', 'q', (x->>'qty')::numeric) order by x->>'stock_item_id'), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x;
$$;
create or replace function public._recipe_cost(p_lines jsonb)
returns numeric language sql immutable set search_path = public as $$
  select round(coalesce(sum((x->>'qty')::numeric * (x->>'unit_cost')::numeric) filter (where x->>'unit_cost' is not null), 0), 2)
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x;
$$;
-- las mismas líneas con el costo de hoy (para comparar una versión anterior con la nueva al costo de este momento)
create or replace function public._recipe_recost(p_lines jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x || jsonb_build_object('unit_cost', public._stock_unit_cost(s.avg_cost, s.cost_per_pack, s.pack_qty)) order by x->>'stock_item_id'), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x left join public.stock_items s on s.id = (x->>'stock_item_id')::uuid;
$$;
create or replace function public._recipe_missing_cost(p_lines jsonb)
returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(x->>'name' order by x->>'name') filter (where x->>'unit_cost' is null), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x;
$$;
revoke all on function public._recipe_lines(uuid), public._recipe_key(jsonb), public._recipe_cost(jsonb), public._recipe_recost(jsonb), public._recipe_missing_cost(jsonb)
  from public, anon, authenticated;

-- 3) escribir una versión (una a la vez por producto) ------------------------------------------------------------
-- p_only_if_changed: el historial de un cambio directo solo agrega una versión si el ingrediente o la cantidad cambió
create or replace function public._recipe_version_write(p_menu_item_id uuid, p_source text, p_reason text, p_by uuid, p_by_name text,
                                                        p_request_id uuid, p_only_if_changed boolean,
                                                        p_lines jsonb default null, p_cost_before numeric default null)
returns int language plpgsql security definer set search_path = public as $$
declare last public.recipe_versions; lines jsonb; mi record; rate numeric; src text; v int;
begin
  perform pg_advisory_xact_lock(hashtextextended('canopy.recipe:' || p_menu_item_id::text, 0));
  lines := coalesce(p_lines, public._recipe_lines(p_menu_item_id));
  select * into last from public.recipe_versions where menu_item_id = p_menu_item_id order by version desc limit 1;
  if p_only_if_changed then
    if last.id is null and lines = '[]'::jsonb then return 0; end if;
    if last.id is not null and public._recipe_key(last.lines) = public._recipe_key(lines) then return 0; end if;
  end if;
  select m.id, m.name, m.price_crc, m.tax_code into mi from public.menu_items m where m.id = p_menu_item_id;
  if mi.id is not null then select t.rate into rate from public.tax_rates t where t.code = mi.tax_code; end if;
  src := coalesce(p_source, case when mi.id is null then 'deleted' else 'direct' end);
  v := coalesce(last.version, 0) + 1;
  insert into public.recipe_versions (menu_item_id, menu_item_name, version, lines, cost_crc, cost_before_crc, missing_cost, price_crc, price_net_crc,
                                      source, reason, authorized_by, by_name, request_id)
    values (p_menu_item_id, coalesce(mi.name, last.menu_item_name), v, lines, public._recipe_cost(lines),
            coalesce(p_cost_before, case when last.id is not null then public._recipe_cost(public._recipe_recost(last.lines)) end),
            public._recipe_missing_cost(lines),
            coalesce(mi.price_crc, last.price_crc),
            case when mi.id is not null then round(mi.price_crc / (1 + coalesce(rate, 0.13)), 2) else last.price_net_crc end,
            src, coalesce(p_reason, case src when 'deleted' then 'producto borrado del menú' end), p_by,
            coalesce(p_by_name, case when public.access_level() is not null then public._owner_label() else 'sistema' end),
            p_request_id);
  return v;
end $$;
revoke all on function public._recipe_version_write(uuid, text, text, uuid, text, uuid, boolean, jsonb, numeric) from public, anon, authenticated;

-- la versión inicial de cada receta que ya existe (se puede volver a ejecutar: no duplica); si una receta cambió
-- mientras el historial no corría (la 0030 revertida y aplicada otra vez), ese cambio queda anotado como directo
create or replace function canopy.recipe_baseline()
returns int language plpgsql security definer set search_path = public as $$
declare m uuid; n int := 0;
begin
  for m in select distinct r.menu_item_id from public.recipes r
            where not exists (select 1 from public.recipe_versions v where v.menu_item_id = r.menu_item_id) loop
    perform public._recipe_version_write(m, 'baseline', 'versión inicial', null, 'sistema', null, false);
    n := n + 1;
  end loop;
  for m in select distinct v.menu_item_id from public.recipe_versions v loop
    if public._recipe_version_write(m, null, 'cambio sin historial (anotado al aplicar la 0030)', null, 'sistema', null, true) > 0 then n := n + 1; end if;
  end loop;
  return n;
end $$;
revoke all on function canopy.recipe_baseline() from public;

-- 4) red de seguridad: lo que escribe recetas sin recipe_save queda en el historial ----------------------------------
-- recipe_save y recipes_autolink_pin escriben su propia versión y marcan su producto (o '*') para que esto no la repita.
-- Nunca lanza un error: una página vieja o un borrado del menú siguen funcionando igual que hoy.
create or replace function public._recipes_log_direct(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare flag text; m uuid;
begin
  flag := nullif(current_setting('canopy.recipe_save', true), '');
  if flag = '*' then return; end if;
  foreach m in array coalesce(p_ids, '{}'::uuid[]) loop
    continue when m is null or flag = m::text;
    begin
      perform public._recipe_version_write(m, null, null, null, null, null, true);
    exception
      when deadlock_detected then raise;      -- la escritura falla a la vista y se repite; nunca una versión perdida en silencio
      when others then raise warning 'recipe_versions: no se anotó el cambio directo de %: %', m, sqlerrm;
    end;
  end loop;
end $$;
create or replace function public._recipes_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._recipes_log_direct((select array_agg(distinct menu_item_id) from new_rows));
  return null;
end $$;
create or replace function public._recipes_after_update() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._recipes_log_direct((select array_agg(distinct x) from (select menu_item_id as x from old_rows union select menu_item_id from new_rows) q));
  return null;
end $$;
create or replace function public._recipes_after_delete() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._recipes_log_direct((select array_agg(distinct menu_item_id) from old_rows));
  return null;
end $$;
revoke all on function public._recipes_log_direct(uuid[]), public._recipes_after_insert(), public._recipes_after_update(), public._recipes_after_delete()
  from public, anon, authenticated;
drop trigger if exists recipes_history_insert on public.recipes;
create trigger recipes_history_insert after insert on public.recipes referencing new table as new_rows
  for each statement execute function public._recipes_after_insert();
drop trigger if exists recipes_history_update on public.recipes;
create trigger recipes_history_update after update on public.recipes referencing old table as old_rows new table as new_rows
  for each statement execute function public._recipes_after_update();
drop trigger if exists recipes_history_delete on public.recipes;
create trigger recipes_history_delete after delete on public.recipes referencing old table as old_rows
  for each statement execute function public._recipes_after_delete();
-- con los disparadores ya puestos (la tabla queda tomada hasta el final de esta transacción), la versión inicial
select canopy.recipe_baseline();

-- 5) guardar una receta: un paso, con PIN, sin pisar el cambio de otra persona ---------------------------------------
-- p_lines: [{stock_item_id, qty, unit}] con unit en 'g', 'kg', 'ml', 'L' o 'unit' (sin unit: la del ingrediente)
-- p_expected_version: la versión que la página mostró (0 si la receta no tenía ninguna)
create or replace function public.recipe_save(p_menu_item_id uuid, p_lines jsonb, p_expected_version int,
                                              p_staff_id uuid, p_pin text, p_reason text default null, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pin record; prev public.recipe_versions; mi record; cur int; x jsonb; i int := 0; sid uuid; si public.stock_items;
        q numeric; cap numeric; qs text; u text; fam_in text; fam_st text; f_in numeric; f_st numeric; conv numeric; seen uuid[] := '{}';
        old_ids uuid[]; ins jsonb := '[]'::jsonb; lines jsonb; cost_before numeric; v int; why text; vrow public.recipe_versions;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_menu_item_id is null or p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  -- el PIN va antes de todo lo demás y sin bloque de excepción: un intento equivocado queda contado
  select * into pin from public._verify_pin(p_staff_id, p_pin, true);
  if pin.err is not null then return jsonb_build_object('ok', false, 'error', pin.err, 'step', 'pin'); end if;

  perform pg_advisory_xact_lock(hashtextextended('canopy.recipe:' || p_menu_item_id::text, 0));
  -- the same request again (a lost answer, a double tap): the version it already saved
  select * into prev from public.recipe_versions where request_id = p_request_id;
  if prev.id is not null then
    if prev.menu_item_id <> p_menu_item_id then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
    return jsonb_build_object('ok', true, 'repeat', true, 'version', prev.version, 'lines', prev.lines, 'cost_crc', prev.cost_crc,
                              'cost_before_crc', prev.cost_before_crc, 'missing_cost', prev.missing_cost, 'price_net_crc', prev.price_net_crc, 'at', prev.at);
  end if;
  select m.id, m.name into mi from public.menu_items m where m.id = p_menu_item_id;
  if mi.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select coalesce(max(version), 0) into cur from public.recipe_versions where menu_item_id = p_menu_item_id;
  if p_expected_version is null or p_expected_version < 0 then return jsonb_build_object('ok', false, 'error', 'bad_version'); end if;
  if p_expected_version <> cur then return jsonb_build_object('ok', false, 'error', 'changed', 'version', cur); end if;

  -- check every line before writing anything
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if jsonb_array_length(p_lines) > 30 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  select array_agg(stock_item_id) into old_ids from public.recipes where menu_item_id = p_menu_item_id;
  -- the ingredients are held (shared) in one fixed order, by id, so a sale at the same moment never crosses this save
  -- and no unit changes under it; the hold lasts the few milliseconds of this function
  perform id from public.stock_items
    where id in (select (e->>'stock_item_id')::uuid from jsonb_array_elements(p_lines) e
                  where jsonb_typeof(e) = 'object' and coalesce(e->>'stock_item_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    order by id for share;
  for x in select value from jsonb_array_elements(p_lines) loop
    i := i + 1;
    if jsonb_typeof(x) <> 'object' or coalesce(x->>'stock_item_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('ok', false, 'error', 'bad_line', 'line', i); end if;
    sid := (x->>'stock_item_id')::uuid;
    select * into si from public.stock_items where id = sid;
    if si.id is null then return jsonb_build_object('ok', false, 'error', 'unknown_item', 'line', i); end if;
    if sid = any(seen) then return jsonb_build_object('ok', false, 'error', 'duplicate', 'line', i, 'item', si.name); end if;
    seen := seen || sid;
    if not si.active and not (sid = any(coalesce(old_ids, '{}'::uuid[]))) then
      return jsonb_build_object('ok', false, 'error', 'inactive_item', 'line', i, 'item', si.name); end if;
    qs := trim(coalesce(x->>'qty', ''));
    if qs !~ '^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]{1,3})?$' then return jsonb_build_object('ok', false, 'error', 'bad_qty', 'line', i, 'item', si.name); end if;
    q := qs::numeric;
    if q <= 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty', 'line', i, 'item', si.name); end if;
    u := coalesce(nullif(x->>'unit', ''), si.unit);
    fam_in := case u when 'g' then 'mass' when 'kg' then 'mass' when 'ml' then 'volume' when 'L' then 'volume' when 'unit' then 'count' end;
    fam_st := case si.unit when 'g' then 'mass' when 'kg' then 'mass' when 'ml' then 'volume' when 'L' then 'volume' when 'unit' then 'count' end;
    if fam_in is null or fam_st is null or fam_in <> fam_st then
      return jsonb_build_object('ok', false, 'error', 'bad_unit', 'line', i, 'item', si.name, 'unit', si.unit); end if;
    f_in := case when u in ('kg', 'L') then 1000 else 1 end;
    f_st := case when si.unit in ('kg', 'L') then 1000 else 1 end;
    -- a sane ceiling per serving: 10 kg or 10 L, or 500 units
    cap := case fam_in when 'count' then 500 else 10000 end;
    if q * f_in > cap then return jsonb_build_object('ok', false, 'error', 'too_much', 'line', i, 'item', si.name); end if;
    conv := trim_scale(q * f_in / f_st);      -- exact in numeric: no rounding, no trailing zeros
    q := trim_scale(q);
    ins := ins || jsonb_build_object('stock_item_id', sid, 'qty', conv, 'entered_qty', q, 'entered_unit', u);
  end loop;
  why := nullif(left(trim(coalesce(p_reason, '')), 200), '');
  if jsonb_array_length(ins) = 0 and why is null then return jsonb_build_object('ok', false, 'error', 'empty_needs_reason'); end if;

  -- nothing changed (same ingredients, same quantities): no new version
  if cur > 0 and public._recipe_key(ins) = public._recipe_key(public._recipe_lines(p_menu_item_id)) then
    return jsonb_build_object('ok', true, 'unchanged', true, 'version', cur);
  end if;

  -- write: this item's lines only, in the sales' lock order; the history trigger skips this item (its version comes next)
  cost_before := public._recipe_cost(public._recipe_lines(p_menu_item_id));
  perform set_config('canopy.recipe_save', p_menu_item_id::text, true);
  delete from public.recipes where menu_item_id = p_menu_item_id;
  insert into public.recipes (menu_item_id, stock_item_id, qty)
    select p_menu_item_id, (e->>'stock_item_id')::uuid, (e->>'qty')::numeric
      from jsonb_array_elements(ins) e order by (e->>'stock_item_id')::uuid;
  perform set_config('canopy.recipe_save', '', true);

  -- the saved lines with names, units and today's cost, plus what was typed
  select coalesce(jsonb_agg(l || jsonb_build_object('entered_qty', e->'entered_qty', 'entered_unit', e->'entered_unit') order by l->>'stock_item_id'), '[]'::jsonb)
    into lines
    from jsonb_array_elements(public._recipe_lines(p_menu_item_id)) l
    left join jsonb_array_elements(ins) e on e->>'stock_item_id' = l->>'stock_item_id';
  v := public._recipe_version_write(p_menu_item_id, 'editor', why, pin.sid, pin.sname, p_request_id, false, lines, cost_before);
  select * into vrow from public.recipe_versions where menu_item_id = p_menu_item_id and version = v;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('recipe_change', pin.sid, pin.sname, p_menu_item_id::text,
            mi.name || ' · versión ' || v || ' · costo ₡' || round(coalesce(cost_before, 0)) || ' → ₡' || round(coalesce(vrow.cost_crc, 0)),
            jsonb_build_object('version', v, 'version_id', vrow.id, 'reason', why, 'cost_before_crc', cost_before, 'cost_crc', vrow.cost_crc,
                               'lines', jsonb_array_length(lines)));
  return jsonb_build_object('ok', true, 'version', v, 'lines', vrow.lines, 'cost_crc', vrow.cost_crc, 'cost_before_crc', cost_before,
                            'missing_cost', vrow.missing_cost, 'price_net_crc', vrow.price_net_crc, 'at', vrow.at);
end $$;
revoke all on function public.recipe_save(uuid, jsonb, int, uuid, text, text, uuid) from public, anon;
grant execute on function public.recipe_save(uuid, jsonb, int, uuid, text, text, uuid) to authenticated;

-- 6) «Enlazar por nombre» con PIN: solo ingredientes que se cuentan por unidad (un croissant comprado = 1 croissant) --
create or replace function public.recipes_autolink_pin(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pin record; ids uuid[]; m uuid;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select * into pin from public._verify_pin(p_staff_id, p_pin, true);
  if pin.err is not null then return jsonb_build_object('ok', false, 'error', pin.err, 'step', 'pin'); end if;
  perform pg_advisory_xact_lock(hashtext('canopy.recipe_autolink'));
  select array_agg(distinct mi.id) into ids
    from public.menu_items mi join public.stock_items si on lower(si.name) = lower(mi.name)
   where si.active and si.unit = 'unit' and not exists (select 1 from public.recipes r where r.menu_item_id = mi.id);
  foreach m in array coalesce(ids, '{}'::uuid[]) loop
    perform pg_advisory_xact_lock(hashtextextended('canopy.recipe:' || m::text, 0));   -- the lock recipe_save takes
  end loop;
  perform set_config('canopy.recipe_save', '*', true);
  with x as (
    insert into public.recipes (menu_item_id, stock_item_id, qty)
      select mi.id, si.id, 1
        from public.menu_items mi join public.stock_items si on lower(si.name) = lower(mi.name)
       where si.active and si.unit = 'unit' and not exists (select 1 from public.recipes r where r.menu_item_id = mi.id)
       order by si.id
      on conflict do nothing
      returning menu_item_id)
  select array_agg(distinct menu_item_id) into ids from x;
  perform set_config('canopy.recipe_save', '', true);
  foreach m in array coalesce(ids, '{}'::uuid[]) loop
    perform public._recipe_version_write(m, 'autolink', 'enlace por nombre', pin.sid, pin.sname, null, false);
  end loop;
  if coalesce(array_length(ids, 1), 0) > 0 then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('recipe_change', pin.sid, pin.sname, null, 'enlazó ' || array_length(ids, 1) || ' productos por nombre',
              jsonb_build_object('autolink', true, 'menu_item_ids', to_jsonb(ids)));
  end if;
  return jsonb_build_object('ok', true, 'linked', coalesce(array_length(ids, 1), 0));
end $$;
revoke all on function public.recipes_autolink_pin(uuid, text) from public, anon;
grant execute on function public.recipes_autolink_pin(uuid, text) to authenticated;

-- 7) protecciones de ingredientes ------------------------------------------------------------------------------------
-- solo lo consulta el disparador de abajo: llamado directo desde la API no responde nada
create or replace function public._stock_item_in_use(p_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if pg_trigger_depth() = 0 then raise exception 'stock_item_in_use: solo desde el disparador de ingredientes'; end if;
  return exists (select 1 from public.stock_moves where item_id = p_id) or exists (select 1 from public.recipes where stock_item_id = p_id);
end $$;
revoke all on function public._stock_item_in_use(uuid) from public, anon;
grant execute on function public._stock_item_in_use(uuid) to authenticated;

-- igual que en la 0005, más: la unidad no cambia si el ingrediente ya tiene movimientos o recetas (solo desde las páginas)
create or replace function public._stock_items_protect()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.on_hand := 0;                 -- opening stock comes in as a movement (stock_receive)
      -- no price yet: no average (0 would make every sale of it cost ₡0; null lets the price typed later count)
      new.avg_cost := nullif(round(coalesce(new.cost_per_pack, 0) / nullif(new.pack_qty, 0), 4), 0);
    else
      new.on_hand := old.on_hand;
      new.avg_cost := old.avg_cost;
      -- an ingredient never received has no average yet: the price typed on the page is its cost until a delivery sets one
      if coalesce(old.avg_cost, 0) = 0 and not exists (select 1 from public.stock_moves m where m.item_id = old.id and m.kind = 'purchase') then
        new.avg_cost := nullif(round(coalesce(new.cost_per_pack, 0) / nullif(new.pack_qty, 0), 4), 0);
      end if;
      if new.unit is distinct from old.unit and new.unit in ('unit', 'g', 'kg', 'ml', 'L') and public._stock_item_in_use(old.id) then
        raise exception 'unit_locked: % ya tiene movimientos o recetas; para contarlo en otra unidad cree un ingrediente nuevo', old.name
          using errcode = 'P0001';
      end if;
      if new.cost_per_pack is distinct from old.cost_per_pack or new.pack_qty is distinct from old.pack_qty then
        perform public._stock_cost_edit_log(old.id, old.name, old.cost_per_pack, new.cost_per_pack, old.pack_qty, new.pack_qty);
      end if;
    end if;
  end if;
  return new;
end $$;

-- igual que en la 0005, más: un ingrediente que está en una receta no se borra (se quita de la receta o se desactiva)
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

-- los ingredientes creados con precio pero nunca recibidos quedaron con promedio 0 (sus ventas salían a ₡0, 0005):
-- toman su precio como promedio, igual que hará la página desde ahora; una entrega después lo promedia como siempre
update public.stock_items s set avg_cost = round(s.cost_per_pack / s.pack_qty, 4)
 where coalesce(s.avg_cost, 0) = 0 and coalesce(s.cost_per_pack, 0) > 0 and coalesce(s.pack_qty, 0) > 0
   and not exists (select 1 from public.stock_moves m where m.item_id = s.id and m.kind = 'purchase');

-- 8) costo de ingredientes de Inventario: lo usado al costo con que salió y las ventas sin IVA ------------------------
-- (un movimiento sellado sin costo, de cuando el ingrediente no tenía precio, se valora al costo de hoy, como antes)
create or replace function public.inventory_food_cost(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object(
    'ok', true,
    'usage_cost', coalesce((select round(sum(-m.qty * coalesce(nullif(m.unit_cost, 0), public._stock_unit_cost(i.avg_cost, i.cost_per_pack, i.pack_qty), 0)))
                              from public.stock_moves m join public.stock_items i on i.id = m.item_id
                             where m.kind in ('sale', 'void', 'waste') and m.at >= now() - make_interval(days => p_days)), 0),
    'waste_cost', coalesce((select round(sum(-m.qty * coalesce(nullif(m.unit_cost, 0), public._stock_unit_cost(i.avg_cost, i.cost_per_pack, i.pack_qty), 0)))
                              from public.stock_moves m join public.stock_items i on i.id = m.item_id
                             where m.kind = 'waste' and m.at >= now() - make_interval(days => p_days)), 0),
    -- 'revenue' as before (what was charged, with IVA: the page published today shows it as «Sales»); the new page
    -- compares the cost of what was used with 'revenue_net_crc', the same sales without IVA
    'revenue', case when public.sales_open() then
                 coalesce((select sum(total_crc) from public.orders
                            where created_at >= now() - make_interval(days => p_days) and voided_at is null
                              and coalesce(paid, true) and coalesce(status, 'done') <> 'cancelled'), 0) end,
    'revenue_net_crc', case when public.sales_open() then
                 coalesce((select round(sum(public._order_net(o))) from public.orders o
                            where o.created_at >= now() - make_interval(days => p_days) and o.voided_at is null
                              and coalesce(o.paid, true) and coalesce(o.status, 'done') <> 'cancelled'), 0) end,
    'stock_value', coalesce((select round(sum(on_hand * coalesce(public._stock_unit_cost(avg_cost, cost_per_pack, pack_qty), 0)))
                               from public.stock_items where active), 0));
end $$;

select canopy.migration_end(30, 'recetas_seguras');
notify pgrst, 'reload schema';
