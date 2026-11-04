-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0038 (Descuentos de Caja)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo por una falla de una función de la 0038, así lo decide el dueño, fuera del horario de atención, y solo
-- DESPUÉS de volver a publicar las páginas anteriores (v2026.11.03-1). La vuelta normal es otra: el ajuste
-- pos_free_discount en «on» y las páginas anteriores (docs/ACTIVACION-DESCUENTOS.md §6). ANTES de esta reversión,
-- deje pos_free_discount en «on» (supabase/tools/descuento-libre-encender.sql): sin la 0038 nadie lo lee, y al
-- aplicar la 0038 otra vez vale lo que quedó.
--
-- Qué hace
--   * Deja exactamente como estaban antes de la 0038 (misma huella en la foto de producción, mismos permisos):
--     approve_discount y _order_discount_check (supabase/pos-stations.sql) y tab_set_discount (supabase/pos-tabs.sql).
--   * Quita los tres disparadores nuevos de orders (order_zz_discount, order_zz_discount_lock, order_zz_discount_after)
--     y todas las funciones nuevas de la 0038 (descuentos por categoría, cajas registradas, el informe y las
--     herramientas del dueño).
--   * Quita la 0038 del registro de migraciones (la base vuelve a la versión 37).
-- Qué NO hace: no borra ningún dato. Las columnas nuevas de discount_approvals (categoría, empleado, empresa, día…),
--   su regla, sus índices, la tabla discount_tills (las cajas registradas, que quedan sin uso), la tabla
--   discount_pin_shared (quién comparte un código), la columna till_id, los índices del registro y los dos ajustes
--   (pos_free_discount, pos_discount_guia) quedan como están. Las aprobaciones de categoría que ya existan quedan
--   guardadas; una venta que llegue después con una de ellas se revisa como una aprobación de la ventana anterior (su
--   porcentaje fijo, 30 minutos).
-- Se niega si la 0038 no está aplicada o si hay una migración posterior aplicada (revierta esa primero).
-- Después: release-check.sql dice migrations_missing = [38]; production-snapshot.sql, migrations_applied termina en 37
--   y functions_changed = [] (las tres funciones vuelven a contar como «legacy»).
-- =====================================================================================================
do $$
begin
  if not exists (select 1 from canopy.migrations where version = 38) then
    raise exception 'La migración 0038 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 38) then
    raise exception 'Hay una migración posterior a la 0038 aplicada (%): revierta esa primero. No se cambió nada.',
      (select string_agg(version::text, ', ' order by version) from canopy.migrations where version > 38);
  end if;
end $$;
set local lock_timeout = '8s';

-- 1) los disparadores nuevos ---------------------------------------------------------------------------------------------
drop trigger if exists order_zz_discount on public.orders;
drop trigger if exists order_zz_discount_lock on public.orders;
drop trigger if exists order_zz_discount_after on public.orders;

-- 2) las tres funciones de antes, con su texto exacto (supabase/pos-stations.sql, supabase/pos-tabs.sql) --------------
create or replace function public.approve_discount(p_staff_id uuid, p_pin text, p_kind text, p_value int,
                                                   p_subtotal int, p_reason text, p_station text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; a public.discount_approvals; amt int; why text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  why := left(trim(coalesce(p_reason, '')), 160);
  if why = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  if p_kind not in ('percent', 'amount') or p_value is null or p_value <= 0
     or (p_kind = 'percent' and p_value > 100) then
    return jsonb_build_object('ok', false, 'error', 'bad_discount'); end if;
  if p_subtotal is null or p_subtotal <= 0 then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if p_kind = 'amount' and p_value > p_subtotal then return jsonb_build_object('ok', false, 'error', 'too_big'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  amt := case when p_kind = 'percent' then round(p_subtotal * p_value / 100.0)::int else p_value end;
  insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, station, subtotal_crc, amount_crc)
    values (v.sid, v.sname, p_kind, p_value, why, nullif(left(trim(coalesce(p_station, '')), 40), ''), p_subtotal, amt)
    returning * into a;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_approved', v.sid, v.sname, a.id::text, why,
            jsonb_build_object('kind', p_kind, 'value', p_value, 'subtotal_crc', p_subtotal, 'discount_crc', amt,
                               'station', a.station));
  return jsonb_build_object('ok', true, 'id', a.id, 'amount', amt, 'name', v.sname, 'reason', why, 'at', a.created_at);
end $$;
revoke all on function public.approve_discount(uuid, text, text, int, int, text, text) from public, anon;
grant execute on function public.approve_discount(uuid, text, text, int, int, text, text) to authenticated;

create or replace function public._order_discount_check()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare a public.discount_approvals; allowed int;
begin
  if coalesce(new.discount_crc, 0) < 0 then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  if coalesce(new.discount_crc, 0) = 0 then
    -- no discount: a subtotal, when sent, must be the total
    if new.subtotal_crc is not null and new.total_crc <> new.subtotal_crc then
      raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
    new.discount_crc := 0; new.discount_id := null; new.discount_reason := null; new.discount_by := null;
    return new;
  end if;
  if new.discount_id is null then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  select * into a from public.discount_approvals where id = new.discount_id for update;
  if a.id is null then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  if a.order_id is not null and a.order_id <> new.id then raise exception 'discount_used' using errcode = '23505'; end if;
  -- the sale must be rung within 30 minutes of the approval (the order's own time, so an offline sale still counts)
  if new.created_at > a.created_at + interval '30 minutes' or new.created_at < a.created_at - interval '10 minutes' then
    raise exception 'discount_expired' using errcode = 'P0001'; end if;
  if new.subtotal_crc is null or new.subtotal_crc <= 0 then raise exception 'discount_no_subtotal' using errcode = 'P0001'; end if;
  -- never more than the manager saw: a percentage follows the order down, not up
  allowed := case when a.kind = 'percent' then round(new.subtotal_crc * a.value / 100.0)::int
                  else least(a.value, new.subtotal_crc) end;
  if a.amount_crc is not null then allowed := least(allowed, a.amount_crc); end if;
  if new.discount_crc > allowed + (case when a.kind = 'percent' then 1 else 0 end)
     or new.discount_crc > new.subtotal_crc then raise exception 'discount_too_big' using errcode = 'P0001'; end if;
  if new.total_crc <> new.subtotal_crc - new.discount_crc or new.total_crc < 0 then
    raise exception 'discount_total' using errcode = 'P0001'; end if;
  new.discount_reason := a.reason;
  new.discount_by := a.approved_name;
  update public.discount_approvals set used_at = now(), order_id = new.id where id = a.id;
  return new;
end $$;
-- the trigger order_discount_check stays as it is (same name, same function)

create or replace function public.tab_set_discount(p_order_id uuid, p_discount_id uuid, p_expect int default null,
                                                   p_station text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; a public.discount_approvals; s int; paid_value int; open_value int; used int; d int; t int;
        st text := nullif(left(trim(coalesce(p_station, '')), 40), '');
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if p_expect is not null and p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  select coalesce(sum(qty * price_crc), 0)::int, coalesce(sum(paid_qty * price_crc), 0)::int
    into s, paid_value from public.order_items where order_id = o.id;
  open_value := s - paid_value;
  used := greatest(0, paid_value - o.parts_items_crc);
  -- the bill's value from its own books (a sale whose discount could not be verified keeps what it charged)
  s := coalesce(o.subtotal_crc, o.total_crc + o.parts_crc);
  if p_discount_id is null then
    d := case when o.subtotal_crc is null then 0 else used end;
    t := s - d - o.parts_crc;
    if t < 0 then return jsonb_build_object('ok', false, 'error', 'refund_first'); end if;
    update public.orders set subtotal_crc = case when d > 0 then s else null end, discount_crc = d, discount_id = null,
                             discount_reason = case when d > 0 then discount_reason else null end,
                             discount_by = case when d > 0 then discount_by else null end, total_crc = t
      where id = o.id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('tab_discount_removed', null, coalesce(st, o.station, 'POS'), o.id::text, public._tab_label(o),
              jsonb_build_object('discount_crc', coalesce(o.discount_crc, 0) - d, 'total_crc', t, 'bill', public._tab_label(o),
                                 'reason', o.discount_reason, 'station', st));
    return jsonb_build_object('ok', true, 'total', t, 'discount', d);
  end if;
  select * into a from public.discount_approvals where id = p_discount_id for update;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'discount_not_approved'); end if;
  if a.order_id is not null and a.order_id <> o.id then return jsonb_build_object('ok', false, 'error', 'discount_used'); end if;
  if now() > a.created_at + interval '30 minutes' then return jsonb_build_object('ok', false, 'error', 'discount_expired'); end if;
  -- it covers the items not paid yet: those paid by item keep their value and the discount they got
  update public.discount_approvals set base_crc = paid_value, base_used_crc = used where id = a.id;
  o.subtotal_crc := s; o.discount_id := a.id; o.discount_crc := 0;
  d := public._tab_discount(o, s, used, open_value);
  t := s - d - o.parts_crc;
  if t < 0 then
    update public.discount_approvals set base_crc = a.base_crc, base_used_crc = a.base_used_crc where id = a.id;
    return jsonb_build_object('ok', false, 'error', 'refund_first');
  end if;
  update public.orders set subtotal_crc = s, discount_crc = d, discount_id = a.id, discount_reason = a.reason,
                           discount_by = a.approved_name, total_crc = t
    where id = o.id;
  update public.discount_approvals set used_at = now(), order_id = o.id where id = a.id;
  return jsonb_build_object('ok', true, 'total', t, 'discount', d);
end $$;

revoke all on function public.tab_set_discount(uuid, uuid, int, text) from public, anon;
grant execute on function public.tab_set_discount(uuid, uuid, int, text) to authenticated;

-- 3) lo que solo existía por la 0038 -------------------------------------------------------------------------------------
drop function if exists public.descuento_estado(text);
drop function if exists public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text);
drop function if exists public.descuento_liberar(uuid, uuid);
drop function if exists public.descuento_quitar_cuenta(uuid, int, text, uuid, text, text, uuid);
drop function if exists public.descuento_cupo_devolver(uuid, uuid, text, text);
drop function if exists public.descuentos_informe(date, date);
drop function if exists public.descuento_caja_registrar(text, uuid);
drop function if exists public.descuento_caja_volver(text, text);
drop function if exists public.descuento_cajas();
drop function if exists public.descuento_caja_reanudar(int, uuid, text, text);
drop function if exists public.descuento_caja_quitar(uuid, uuid, text, text);
drop function if exists public._discount_tills_resume_all(text);
drop function if exists public._discount_tills_end_all(text);
drop function if exists public._pin_locks_clear_all(text);
drop function if exists public._discount_places_summary();
drop function if exists public._order_discount_flags();
drop function if exists public._order_discount_after();
drop function if exists public._discount_freeable(public.discount_approvals);
drop function if exists public._discount_answer(public.discount_approvals);
drop function if exists public._discount_bill_problem(uuid, int, int, boolean);
drop function if exists public._discount_retake_day(uuid, date);
drop function if exists public._discount_wrong(public.discount_tills, text, text, text, text, uuid, text);
drop function if exists public._discount_till_unknown(text, text);
drop function if exists public._discount_places(uuid);
drop function if exists public._discount_person(uuid);
drop function if exists public._discount_staff_state(uuid);
drop function if exists public._discount_take_staff(uuid);
drop function if exists public._discount_slot_state(int);
drop function if exists public._discount_till_mine();
drop function if exists public._discount_new_key();
drop function if exists public._discount_key_hash(text);
drop function if exists public._discount_station(text);
drop function if exists public._discount_tag(text);
drop function if exists public._discount_session();
drop function if exists public._discount_till_limits();
drop function if exists public._staff_by_code(text);
drop function if exists public._discount_reserved(text);
drop function if exists public._discount_company(text);
drop function if exists public._discount_clean(text);
drop function if exists public._discount_label(text);
drop function if exists public._discount_rate(text);
-- (columns, constraints, indexes, the tables discount_tills and discount_pin_shared and the two settings stay: additive, unused)

-- 4) el libro ------------------------------------------------------------------------------------------------------------
delete from canopy.migrations where version = 38;
notify pgrst, 'reload schema';
