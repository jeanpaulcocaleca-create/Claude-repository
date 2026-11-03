-- =====================================================================================================
-- Canopy OS · migración 0011 · Número de recibo, búsqueda de ventas anteriores y reimpresión (COPIA)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0010.
--
-- Qué hace
--   * Cada venta, pago o devolución nueva recibe un número de recibo del servidor (orders.receipt_no), en orden.
--     Las ventas anteriores no se modifican (no tienen número).
--   * order_search: busca ventas por fecha, número de recibo, producto, nombre, monto o forma de pago, con sus
--     líneas, IVA, efectivo recibido y pagos parciales. Hoy: cualquier caja del café. Días anteriores: con
--     el PIN de un encargado o el ingreso del dueño (como el resto del historial de ventas).
--   * order_reprint: deja en la bitácora cada reimpresión (la copia dice COPIA).
-- Qué cambia para el personal: en Pedidos aparece "Buscar ventas anteriores" (reimprimir, devolver, anular).
-- Reversión: drop function order_search, order_reprint; drop trigger order_receipt_no.
-- =====================================================================================================
select canopy.migration_begin(11, 'history_receipts');

create sequence if not exists canopy.receipt_seq;
alter table public.orders add column if not exists receipt_no bigint;
create unique index if not exists orders_receipt_no_idx on public.orders (receipt_no) where receipt_no is not null;

create or replace function public._order_receipt_no()
returns trigger language plpgsql security definer set search_path = public, canopy as $$
begin
  new.receipt_no := nextval('canopy.receipt_seq');   -- the till never chooses it
  return new;
end $$;
drop trigger if exists order_receipt_no on public.orders;
create trigger order_receipt_no before insert on public.orders for each row execute function public._order_receipt_no();

-- the day a sale belongs to: its business day, or the day it was rung (bills not paid yet)
create or replace function public._order_day(o public.orders)
returns date language sql immutable as $$
  select coalesce(o.business_date, (o.created_at at time zone 'America/Costa_Rica')::date);
$$;

create or replace function public.order_search(p_from date, p_to date, p_text text default null, p_receipt bigint default null,
                                               p_amount int default null, p_method text default null, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q text; res jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  -- earlier days are sales history: a manager's PIN (or the owner) opens them, as on the sales page
  if p_from < public.cr_today() and not (public.is_owner() or public.sales_open()) then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;
  q := nullif(trim(coalesce(p_text, '')), '');
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb) into res from (
    select jsonb_build_object(
      'id', o.id, 'receipt_no', o.receipt_no, 'created_at', o.created_at, 'day', public._order_day(o),
      'total_crc', o.total_crc, 'payment_method', o.payment_method, 'paid', o.paid, 'status', o.status,
      'voided_at', o.voided_at, 'void_reason', o.void_reason, 'refunded_at', o.refunded_at, 'refund_of', o.refund_of,
      'guest_name', o.guest_name, 'station', o.station, 'operator_name', o.operator_name, 'pickup_number', o.pickup_number,
      'subtotal_crc', o.subtotal_crc, 'discount_crc', o.discount_crc, 'discount_reason', o.discount_reason, 'tax_crc', o.tax_crc,
      'parts_crc', o.parts_crc, 'notes', o.notes,
      'items', (select coalesce(jsonb_agg(jsonb_build_object('name', i.item_name, 'qty', i.qty, 'price', i.price_crc,
                                                             'tax_rate', i.tax_rate, 'tax', i.tax_crc) order by i.added_at, i.id), '[]'::jsonb)
                  from public.order_items i where i.order_id = o.id),
      'tender', (select jsonb_build_object('crc_in', t.crc_in, 'usd_in', t.usd_in, 'change_crc', t.change_crc, 'fx_rate', t.fx_rate)
                   from public.cash_tenders t where t.order_id = o.id),
      'parts', (select coalesce(jsonb_agg(jsonb_build_object('receipt_no', p.receipt_no, 'total_crc', p.total_crc, 'method', p.payment_method,
                                                             'at', p.created_at, 'voided', p.voided_at is not null) order by p.created_at), '[]'::jsonb)
                  from public.orders p where p.part_of = o.id),
      'can_void', o.voided_at is null and o.refunded_at is null and o.refund_of is null and o.total_crc >= 0
                  and (not coalesce(o.paid, true) or public._order_day_open(o)),
      'can_refund', o.voided_at is null and o.refunded_at is null and o.refund_of is null and o.total_crc > 0
                    and coalesce(o.paid, true) and coalesce(o.parts_crc, 0) = 0 and not public._order_day_open(o)) as x
      from public.orders o
     where o.part_of is null
       and public._order_day(o) between p_from and p_to
       and (p_receipt is null or o.receipt_no = p_receipt)
       and (p_amount is null or o.total_crc = p_amount or o.total_crc = -p_amount)
       and (p_method is null or o.payment_method = p_method)
       and (q is null or o.guest_name ilike '%' || q || '%' or o.operator_name ilike '%' || q || '%' or o.station ilike '%' || q || '%'
            or exists (select 1 from public.order_items i where i.order_id = o.id and i.item_name ilike '%' || q || '%'))
     order by o.created_at desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200)) s;
  return jsonb_build_object('ok', true, 'orders', res);
end $$;
revoke all on function public.order_search(date, date, text, bigint, int, text, int) from public, anon;
grant execute on function public.order_search(date, date, text, bigint, int, text, int) to authenticated;

-- every reprint is logged (a copy says COPIA)
create or replace function public.order_reprint(p_order_id uuid, p_station text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('receipt_reprint', null, coalesce(nullif(left(trim(coalesce(p_station, '')), 40), ''), 'POS'), o.id::text,
            'COPIA recibo ' || coalesce(o.receipt_no::text, left(o.id::text, 8)) || ' · ' || o.total_crc,
            jsonb_build_object('receipt_no', o.receipt_no, 'total_crc', o.total_crc, 'created_at', o.created_at));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.order_reprint(uuid, text) from public, anon;
grant execute on function public.order_reprint(uuid, text) to authenticated;

select canopy.migration_end(11, 'history_receipts');
notify pgrst, 'reload schema';
