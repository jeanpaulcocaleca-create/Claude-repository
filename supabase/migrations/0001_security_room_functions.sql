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
--   * (agregado el 2026-10-12, antes de aplicarse en producción) Cualquier cuenta con sesión iniciada podía
--     cambiar las categorías del menú (nombre, orden, si van a cocina), que se ven en el menú QR y la TV: la
--     regla "categories color for signed-in" no revisaba quién era. Se quita; el dueño (o un encargado con
--     su PIN en Administrador) las sigue editando igual.
--   * (agregado el 2026-10-12) clock_punch y manager_void_order aceptaban un PIN desde cualquier cuenta: un
--     extraño podía adivinar PINs o bloquear a una persona. Ahora solo desde la tableta del café o el dueño.
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

-- Menu categories: only the owner areas edit them ("menu categories owner write"). The old rule let any
-- signed-in account change every column (the column grant for "color" did not limit it on Supabase).
drop policy if exists "categories color for signed-in" on public.menu_categories;

-- Time clock and voids: a PIN is only tried from the café tablet or the owner's login (same bodies as before,
-- plus the account check), so a stranger's login can neither guess PINs nor lock staff out.
create or replace function public.clock_punch(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; e public.time_entries;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  select * into e from public.time_entries
    where staff_id = p_staff_id and clock_out is null order by clock_in desc limit 1;
  if e.id is not null then
    update public.time_entries set clock_out = now() where id = e.id;
    return jsonb_build_object('ok', true, 'action', 'out', 'clock_in', e.clock_in, 'clock_out', now());
  end if;
  insert into public.time_entries (staff_id, clock_in) values (p_staff_id, now()) returning * into e;
  return jsonb_build_object('ok', true, 'action', 'in', 'clock_in', e.clock_in);
end $$;

create or replace function public.manager_void_order(p_manager_id uuid, p_manager_pin text,
    p_order_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; o public.orders; items text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into o from public.orders where id = p_order_id;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  update public.orders set voided_at = now(), voided_by = v.sid, void_reason = trim(p_reason) where id = p_order_id;
  select string_agg(qty || 'x ' || item_name, ', ') into items from public.order_items where order_id = p_order_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('order_void', v.sid, v.sname, p_order_id::text, trim(p_reason),
      jsonb_build_object('total_crc', o.total_crc, 'payment_method', o.payment_method,
                         'created_at', o.created_at, 'items', items));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.clock_punch(uuid, text), public.manager_void_order(uuid, text, uuid, text) from public, anon;
grant execute on function public.clock_punch(uuid, text), public.manager_void_order(uuid, text, uuid, text) to authenticated;

revoke all on function public.finish_room_order(uuid, text), public.cancel_room_order(uuid),
                       public.room_new_code(uuid), public.quick_items(int, int) from public, anon;
grant execute on function public.finish_room_order(uuid, text), public.cancel_room_order(uuid),
                          public.room_new_code(uuid), public.quick_items(int, int) to authenticated;

select canopy.migration_end(1, 'security_room_functions');
notify pgrst, 'reload schema';
