-- =====================================================================================================
-- Canopy OS · migración 0006 · Anular solo mientras el día está abierto; devoluciones con fecha de hoy
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0005.
--
-- Por qué
--   * Una venta cobrada se podía anular días después. Eso cambiaba las ventas de un día que ya se había
--     contado en el cierre de caja: el cierre guardado y los reportes dejaban de coincidir.
--   * No existía una forma de registrar una devolución de dinero de una venta de otro día.
-- Qué hace
--   * Anular (manager_void_order) una venta COBRADA solo se puede mientras la caja de ese día no se ha cerrado.
--     Las cuentas sin cobrar se pueden anular siempre (no hay dinero contado).
--   * Para una venta de un día ya cerrado: manager_refund_order. Registra la devolución HOY, como un movimiento
--     negativo con el mismo medio de pago (o el que se indique), con PIN de gerente y motivo. El día original
--     queda tal como se cerró. Opcional: devolver los productos al inventario.
--   * Una venta no se anula ni se devuelve dos veces; una devolución no se anula (se registra una venta nueva).
-- Qué cambia para el personal: si la caja del día ya se cerró, el botón "Anular" ofrece "Devolver" en su lugar.
-- Reversión: volver a ejecutar la versión de manager_void_order de supabase/authorization.sql; drop function
--            manager_refund_order. Las columnas nuevas pueden quedarse.
-- =====================================================================================================
select canopy.migration_begin(6, 'voids_refunds');

alter table public.orders add column if not exists refund_of uuid;          -- this row gives back the money of that sale
alter table public.orders add column if not exists refunded_at timestamptz;  -- this sale's money was given back (on a later day)
create index if not exists orders_refund_of_idx on public.orders (refund_of) where refund_of is not null;
create unique index if not exists orders_refund_once on public.orders (refund_of) where refund_of is not null and voided_at is null;

-- the till can never write these itself
create or replace function public._order_refund_defaults()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.refund_of := null; new.refunded_at := null;
  end if;
  return new;
end $$;
drop trigger if exists order_refund_defaults on public.orders;
create trigger order_refund_defaults before insert on public.orders for each row execute function public._order_refund_defaults();

-- is the register day this paid order belongs to still open? (no register row for an earlier day = not open)
create or replace function public._order_day_open(o public.orders)
returns boolean language sql stable security definer set search_path = public as $$
  with d as (select coalesce(o.business_date, (o.created_at at time zone 'America/Costa_Rica')::date) as day)
  select case
    when exists (select 1 from public.register_days r, d where r.business_date = d.day and r.closed_at is not null) then false
    when (select day from d) >= public.cr_today() then true
    else exists (select 1 from public.register_days r, d where r.business_date = d.day and r.closed_at is null)
  end;
$$;
revoke all on function public._order_day_open(public.orders) from public, anon, authenticated;

-- 1) void: only while the money has not been counted ---------------------------------------------------
create or replace function public.manager_void_order(p_manager_id uuid, p_manager_pin text,
    p_order_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; o public.orders; items text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if o.refunded_at is not null then return jsonb_build_object('ok', false, 'error', 'refunded'); end if;
  if o.refund_of is not null or o.given_back_at is not null or o.total_crc < 0 then
    return jsonb_build_object('ok', false, 'error', 'is_refund');
  end if;
  -- money already counted at a closed register stays on its day: give it back today instead
  if coalesce(o.paid, true) and not public._order_day_open(o) then
    return jsonb_build_object('ok', false, 'error', 'closed_day',
                              'business_date', coalesce(o.business_date, (o.created_at at time zone 'America/Costa_Rica')::date));
  end if;
  update public.orders set voided_at = now(), voided_by = v.sid, void_reason = trim(p_reason) where id = p_order_id;
  select string_agg(qty || 'x ' || item_name, ', ') into items from public.order_items where order_id = p_order_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('order_void', v.sid, v.sname, p_order_id::text, trim(p_reason),
      jsonb_build_object('total_crc', o.total_crc, 'payment_method', o.payment_method,
                         'created_at', o.created_at, 'business_date', o.business_date, 'items', items));
  return jsonb_build_object('ok', true);
end $$;

-- 2) refund: the money goes back today; the original day is left as it was counted ------------------------
create or replace function public.manager_refund_order(p_manager_id uuid, p_manager_pin text, p_order_id uuid, p_reason text,
                                                       p_restock boolean default false, p_method text default null,
                                                       p_station text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; o public.orders; why text; meth text; rid uuid := gen_random_uuid(); items text; moved int := 0;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  why := left(trim(coalesce(p_reason, '')), 160);
  if why = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if o.refunded_at is not null then return jsonb_build_object('ok', false, 'error', 'refunded'); end if;
  if o.refund_of is not null or o.given_back_at is not null or o.total_crc <= 0 then
    return jsonb_build_object('ok', false, 'error', 'is_refund');
  end if;
  if not coalesce(o.paid, true) then return jsonb_build_object('ok', false, 'error', 'not_paid'); end if;
  -- a payment toward a bill still open is given back with tab_give_back; a bill paid in parts, part by part
  if o.part_of is not null or coalesce(o.parts_crc, 0) > 0 then return jsonb_build_object('ok', false, 'error', 'has_parts'); end if;
  if public._order_day_open(o) then return jsonb_build_object('ok', false, 'error', 'void_instead'); end if;
  meth := coalesce(nullif(p_method, ''), o.payment_method);
  if meth not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;

  insert into public.orders (id, created_at, total_crc, payment_method, paid, status, done_at, source, needs_kitchen,
                             pickup_number, station, guest_name, notes, refund_of)
    values (rid, now(), -o.total_crc, meth, true, 'done', now(), 'front', false, null,
            coalesce(nullif(left(trim(coalesce(p_station, '')), 40), ''), o.station), o.guest_name,
            left('Devolución · ' || why, 200), o.id);
  update public.orders set refunded_at = now() where id = o.id;
  -- what comes back to the shelf goes back at the cost it went out with
  if coalesce(p_restock, false) then
    insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, note, by_name)
      select m.item_id, 'void', -m.qty, m.unit_cost, rid, 'devolución · ' || coalesce(m.note, ''), v.sname
        from public.stock_moves m where m.order_id = o.id and m.kind = 'sale'
       order by m.item_id;
    get diagnostics moved = row_count;
  end if;
  select string_agg(qty || 'x ' || item_name, ', ') into items from public.order_items where order_id = o.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('order_refund', v.sid, v.sname, o.id::text, why,
            jsonb_build_object('total_crc', o.total_crc, 'refund_id', rid, 'method', meth, 'original_method', o.payment_method,
                               'original_day', coalesce(o.business_date, (o.created_at at time zone 'America/Costa_Rica')::date),
                               'restocked_lines', moved, 'items', items,
                               'station', nullif(trim(coalesce(p_station, '')), '')));
  return jsonb_build_object('ok', true, 'refund_id', rid, 'total', o.total_crc, 'method', meth, 'restocked', moved);
end $$;
revoke all on function public.manager_refund_order(uuid, text, uuid, text, boolean, text, text) from public, anon;
grant execute on function public.manager_refund_order(uuid, text, uuid, text, boolean, text, text) to authenticated;

select canopy.migration_end(6, 'voids_refunds');
notify pgrst, 'reload schema';
