-- =====================================================================================================
-- Canopy OS · migración 0001 · Corrección de seguridad: pedidos de habitación y artículos rápidos
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0000.
--
-- Por qué (encontrado el 2026-10-12, verificado en una base de pruebas)
--   * Cualquier cuenta con sesión iniciada (no solo la tableta del café o el dueño) podía cancelar un pedido
--     de habitación o marcarlo como pagado sin cobrar (cancel_room_order, finish_room_order). Si en
--     Supabase está permitido crear cuentas nuevas (la opción por defecto), un extraño podía hacerlo.
--   * room_new_code (cambiar el código QR de una habitación) y quick_items (ventas por producto) tampoco
--     revisaban quién llamaba.
--   * place_room_order (el pedido que hace el huésped desde su teléfono) usa gen_random_bytes, que en
--     Supabase vive en el esquema "extensions"; la función no lo buscaba ahí, así que el pedido desde la
--     habitación probablemente fallaba. Ahora lo encuentra.
-- Qué cambia para el personal: nada. La tableta del café y el dueño siguen pudiendo hacer todo igual.
-- Reversión: no es necesaria (solo agrega revisiones de permiso).
-- =====================================================================================================
select canopy.migration_begin(1, 'security_room_functions');

-- The guest finishes paying at the window: the café tablet (or owner) records it.
create or replace function public.finish_room_order(p_order_id uuid, p_payment_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.source <> 'room' or o.paid then return jsonb_build_object('ok', false, 'error', 'not_room_order'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if p_payment_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method');
  end if;
  update public.orders set paid = true, payment_method = p_payment_method, status = 'done',
    done_at = now(), guest_phone = null where id = p_order_id;
  return jsonb_build_object('ok', true);
end $$;

-- A guest who never shows up: the café tablet cancels the unpaid room order (logged).
create or replace function public.cancel_room_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.source <> 'room' or o.paid then return jsonb_build_object('ok', false, 'error', 'not_room_order'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  update public.orders set status = 'cancelled', done_at = now(), guest_phone = null where id = p_order_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('room_order_cancelled', null, 'café', o.id::text, coalesce(nullif(o.guest_name, ''), 'habitación'),
            jsonb_build_object('total_crc', o.total_crc, 'room_id', o.room_id));
  return jsonb_build_object('ok', true);
end $$;

-- New code for a room's QR card (if a card leaks): owner areas only (Menu Manager).
create or replace function public.room_new_code(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.rooms;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  update public.rooms set code = number || '-' || lower(substr(md5(gen_random_uuid()::text), 1, 6))
    where id = p_room_id returning * into r;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('room_code_changed', null, public._owner_label(), r.id::text, 'habitación ' || r.number, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'code', r.code);
end $$;

-- Best sellers for the POS quick tab: café and owner logins only.
create or replace function public.quick_items(p_days int default 30, p_limit int default 12)
returns table (item_name text, qty bigint)
language sql security definer set search_path = public stable as $$
  select oi.item_name, sum(oi.qty)::bigint as qty
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where public.is_cafe()
    and o.created_at >= now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
    and o.voided_at is null
    and coalesce(o.paid, true)
  group by oi.item_name
  order by qty desc, oi.item_name
  limit least(greatest(coalesce(p_limit, 12), 1), 30);
$$;

-- The guest's order from the room needs gen_random_bytes, which Supabase keeps in "extensions".
alter function public.place_room_order(text, text, text, text, text, jsonb) set search_path = public, extensions;

revoke all on function public.finish_room_order(uuid, text), public.cancel_room_order(uuid),
                       public.room_new_code(uuid), public.quick_items(int, int) from public, anon;
grant execute on function public.finish_room_order(uuid, text), public.cancel_room_order(uuid),
                          public.room_new_code(uuid), public.quick_items(int, int) to authenticated;

select canopy.migration_end(1, 'security_room_functions');
notify pgrst, 'reload schema';
