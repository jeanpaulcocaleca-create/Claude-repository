-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0030 (recetas seguras)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0030 causa un problema y así lo decide el dueño. Fuera del horario de atención: quitar los
-- disparadores de la tabla de recetas la bloquea un instante, y en ese instante una venta espera.
--
-- Qué hace
--   * Quita lo que agregó la 0030: recipe_save, recipes_autolink_pin, los tres disparadores de historial de recetas
--     y sus funciones internas.
--   * Deja exactamente como estaban antes de la 0030 (misma huella en la foto de producción):
--     _stock_items_protect y _stock_item_history_guard (0005) e inventory_food_cost (supabase/manager-mode.sql).
--   * Quita la 0030 del registro de migraciones: la base vuelve a la versión 29 y las páginas nuevas vuelven a
--     guardar recetas como antes (sin PIN), hasta que se aplique otra vez la 0030.
-- Qué NO hace: no borra el historial de recetas (recipe_versions queda, con sus versiones, y sigue sin poder
--   modificarse), no toca ninguna receta, venta, movimiento de inventario ni costo.
-- Después: supabase/tools/release-check.sql mostrará recipe_save en functions_missing; es lo esperado.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 30) then
    raise exception 'La migración 0030 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 30) then
    raise exception 'Hay migraciones posteriores a la 0030: revierta primero esas. No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

drop trigger if exists recipes_history_insert on public.recipes;
drop trigger if exists recipes_history_update on public.recipes;
drop trigger if exists recipes_history_delete on public.recipes;
drop function if exists public.recipe_save(uuid, jsonb, int, uuid, text, text, uuid);
drop function if exists public.recipes_autolink_pin(uuid, text);
drop function if exists public._recipes_after_insert();
drop function if exists public._recipes_after_update();
drop function if exists public._recipes_after_delete();
drop function if exists public._recipes_log_direct(uuid[]);
drop function if exists canopy.recipe_baseline();
drop function if exists public._recipe_version_write(uuid, text, text, uuid, text, uuid, boolean, jsonb, numeric);
drop function if exists public._recipe_lines(uuid);
drop function if exists public._recipe_key(jsonb);
drop function if exists public._recipe_cost(jsonb);
drop function if exists public._recipe_recost(jsonb);
drop function if exists public._recipe_missing_cost(jsonb);

-- como en la 0005 ------------------------------------------------------------------------------------------------
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
drop function if exists public._stock_item_in_use(uuid);

-- como en supabase/manager-mode.sql ------------------------------------------------------------------------------
create or replace function public.inventory_food_cost(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object(
    'ok', true,
    'usage_cost', coalesce((select round(sum(-m.qty * i.cost_per_pack / i.pack_qty))
                              from public.stock_moves m join public.stock_items i on i.id = m.item_id
                             where m.kind in ('sale', 'void', 'waste') and m.at >= now() - make_interval(days => p_days)), 0),
    'waste_cost', coalesce((select round(sum(-m.qty * i.cost_per_pack / i.pack_qty))
                              from public.stock_moves m join public.stock_items i on i.id = m.item_id
                             where m.kind = 'waste' and m.at >= now() - make_interval(days => p_days)), 0),
    'revenue', case when public.sales_open() then
                 coalesce((select sum(total_crc) from public.orders
                            where created_at >= now() - make_interval(days => p_days) and voided_at is null
                              and coalesce(paid, true) and coalesce(status, 'done') <> 'cancelled'), 0) end,
    'stock_value', coalesce((select round(sum(on_hand * cost_per_pack / pack_qty)) from public.stock_items where active), 0));
end $$;
drop function if exists public._stock_unit_cost(numeric, numeric, numeric);

delete from canopy.migrations where version = 30;
notify pgrst, 'reload schema';
select 'listo: la 0030 se revirtió; el historial de recetas se conserva' as resultado;
