-- =====================================================================================================
-- Canopy OS · migración 0023 · Información del negocio: el día (estimado o final), tendencias, patrones,
-- proveedores y pronóstico de inventario
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0022.
--
-- Qué hace (solo lectura: no cambia ningún dato)
--   * dashboard_today: ventas de hoy con y sin IVA, pedidos, ticket promedio, cómo pagaron, comparado con el
--     mismo día de la semana pasada a la misma hora; "estimado" mientras la caja está abierta, "final" al cerrar.
--   * sales_patterns: ventas por día, por día de la semana y hora, por categoría; descuentos, anulaciones y devoluciones.
--   * trends_monthly: mes a mes: ventas sin IVA, costo de lo vendido, mermas, mano de obra (si se puede ver),
--     gastos, margen bruto, costo primo (costo de alimentos + mano de obra) y su porcentaje.
--   * supplier_insights: compras por proveedor, entregas a tiempo, lo que se debe y cambios de precio de cada insumo.
--   * stock_forecast: cuándo se acaba cada insumo según su uso reciente, considerando lo pedido que aún no llega
--     y los días de entrega del proveedor: cuándo pedir y cuánto.
--   * Lo ven el dueño y quien tenga el permiso de ventas (el pronóstico, también quien abrió el inventario).
--     La mano de obra solo el dueño (con el código del teléfono) y el contador.
-- Qué cambia para el personal: nada.
-- Reversión: drop function dashboard_today, sales_patterns, trends_monthly, supplier_insights, stock_forecast.
-- =====================================================================================================
select canopy.migration_begin(23, 'insights');

create or replace function public._insights_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_owner() or public.sales_open() or acct.can_read(), false);
$$;
revoke all on function public._insights_allowed() from public, anon;
grant execute on function public._insights_allowed() to authenticated;

-- an order's sales without IVA: its lines as stamped (0009). A bill paid partly in parts counts only what it
-- still carries (the parts are orders of their own), at the bill's own IVA ratio; older sales, estimated at 13 %.
create or replace function public._order_net(o public.orders) returns numeric language sql stable security definer set search_path = public as $$
  with x as (select sum(i.net_crc) as net, sum(i.price_crc * i.qty - coalesce(i.discount_alloc_crc, 0)) as gross, bool_and(i.net_crc is not null) as full
               from public.order_items i where i.order_id = o.id)
  select case when x.full and coalesce(o.parts_crc, 0) = 0 then x.net
              when x.full and x.gross > 0 then round(o.total_crc * x.net / x.gross, 2)
              when o.tax_crc is not null and coalesce(o.parts_crc, 0) = 0 then o.total_crc - o.tax_crc
              else round(o.total_crc / 1.13, 2) end
    from x;
$$;
revoke all on function public._order_net(public.orders) from public, anon, authenticated;

-- 1) today ----------------------------------------------------------------------------------------------------------
create or replace function public.dashboard_today()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d date := public.cr_today(); r public.register_days; t0 timestamptz; t1 timestamptz; now_tod interval;
begin
  if not public._insights_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  t0 := public.cr_day_start(d); t1 := public.cr_day_start(d + 1); now_tod := now() - t0;
  select * into r from public.register_days where business_date = d;
  return jsonb_build_object('ok', true, 'day', d,
    'state', case when r.id is null then 'no_register' when r.closed_at is null then 'estimate' else 'final' end,
    'register', case when r.id is not null then jsonb_build_object('opened_at', r.opened_at, 'closed_at', r.closed_at, 'cash_diff_crc', r.cash_diff_crc,
                                                                    'card_diff_crc', r.card_diff_crc, 'closed_by', r.closed_by_name) end,
    'today', (select jsonb_build_object('gross', coalesce(sum(o.total_crc), 0), 'net', coalesce(round(sum(public._order_net(o)), 2), 0),
                       'orders', count(*) filter (where o.part_of is null and o.refund_of is null),
                       'refunds', coalesce(-sum(o.total_crc) filter (where o.refund_of is not null), 0),
                       'by_method', (select coalesce(jsonb_object_agg(m, s), '{}') from (select payment_method as m, sum(total_crc) as s from public.orders x
                                      where x.created_at >= t0 and x.created_at < t1 and x.voided_at is null and coalesce(x.paid, true) group by payment_method) q))
                from public.orders o where o.created_at >= t0 and o.created_at < t1 and o.voided_at is null and coalesce(o.paid, true)),
    'voided', (select jsonb_build_object('n', count(*), 'total', coalesce(sum(total_crc), 0)) from public.orders where created_at >= t0 and created_at < t1 and voided_at is not null),
    'unpaid', (select jsonb_build_object('n', count(*), 'total', coalesce(sum(total_crc), 0)) from public.orders
                where created_at >= t0 and created_at < t1 and voided_at is null and paid = false and coalesce(status, '') <> 'cancelled' and part_of is null),
    -- the same weekday last week: up to this time of day, and the whole day
    'last_week', (select jsonb_build_object('gross_so_far', coalesce(sum(total_crc) filter (where created_at < t0 - interval '7 days' + now_tod), 0),
                                            'gross_day', coalesce(sum(total_crc), 0),
                                            'orders_so_far', count(*) filter (where created_at < t0 - interval '7 days' + now_tod and part_of is null and refund_of is null))
                   from public.orders where created_at >= t0 - interval '7 days' and created_at < t1 - interval '7 days' and voided_at is null and coalesce(paid, true)));
end $$;

-- 2) patterns over a range ------------------------------------------------------------------------------------------
create or replace function public.sales_patterns(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._insights_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'days', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'gross', gross, 'net', net, 'orders', n, 'avg_ticket', case when n > 0 then round(gross / n) end) order by d), '[]')
               from (select o.business_date as d, sum(o.total_crc) as gross, round(sum(public._order_net(o)), 2) as net,
                            count(*) filter (where o.part_of is null and o.refund_of is null) as n
                       from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)
                      group by o.business_date) q),
    -- average sales of each weekday (1 = Monday) and hour, over the weekdays in the range
    'week_hours', (select coalesce(jsonb_agg(jsonb_build_object('dow', dow, 'hour', h, 'orders', n,
                       'avg_gross', round(gross / greatest((select count(*) from generate_series(p_from, p_to, interval '1 day') g where extract(isodow from g)::int = q.dow), 1)))
                     order by dow, h), '[]')
                     from (select extract(isodow from o.created_at at time zone 'America/Costa_Rica')::int as dow,
                                  extract(hour from o.created_at at time zone 'America/Costa_Rica')::int as h,
                                  sum(o.total_crc) as gross, count(*) filter (where o.part_of is null and o.refund_of is null) as n
                             from public.orders o where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)
                            group by 1, 2) q),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('category', c, 'units', u, 'gross', g) order by g desc), '[]')
                     from (select coalesce((select mc.name from public.menu_items mi join public.menu_categories mc on mc.id = mi.category_id
                                             where lower(mi.name) = lower(i.item_name) order by mi.available desc limit 1), 'Other') as c,
                                  sum(i.qty) as u, sum(i.price_crc * i.qty - coalesce(i.discount_alloc_crc, 0)) as g
                             from public.order_items i join public.orders o on o.id = i.order_id
                            where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.refund_of is null
                            group by 1) q),
    'leaks', (select jsonb_build_object(
                'discounts', coalesce((select sum(discount_crc) from public.orders where business_date between p_from and p_to and voided_at is null and coalesce(paid, true)), 0),
                'voids_n', (select count(*) from public.orders where business_date between p_from and p_to and voided_at is not null),
                'voids_total', coalesce((select sum(total_crc) from public.orders where business_date between p_from and p_to and voided_at is not null), 0),
                'refunds_n', (select count(*) from public.orders where business_date between p_from and p_to and refund_of is not null and voided_at is null),
                'refunds_total', coalesce((select -sum(total_crc) from public.orders where business_date between p_from and p_to and refund_of is not null and voided_at is null), 0))));
end $$;

-- 3) month by month -------------------------------------------------------------------------------------------------
create or replace function public.trends_monthly(p_months int default 12)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare m0 date := date_trunc('month', public.cr_today())::date; labor_ok boolean := public._pay_staff_allowed(); rows jsonb;
begin
  if not public._insights_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_months is null or p_months < 1 or p_months > 24 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  with months as (select (m0 - make_interval(months => g))::date as m from generate_series(0, p_months - 1) g),
  s as (select date_trunc('month', o.business_date)::date as m, round(sum(public._order_net(o)), 2) as net, sum(o.total_crc) as gross,
               count(*) filter (where o.part_of is null and o.refund_of is null) as n
          from public.orders o where o.business_date >= m0 - make_interval(months => p_months - 1) and o.voided_at is null and coalesce(o.paid, true)
         group by 1),
  st as (select date_trunc('month', (mv.at at time zone 'America/Costa_Rica'))::date as m,
                round(-sum(mv.qty * coalesce(mv.unit_cost, 0)) filter (where mv.kind in ('sale', 'void')), 2) as cogs,
                round(-sum(mv.qty * coalesce(mv.unit_cost, 0)) filter (where mv.kind = 'waste'), 2) as waste,
                round(sum(mv.qty * coalesce(mv.unit_cost, 0)) filter (where mv.kind = 'purchase'), 2) as purchases
           from public.stock_moves mv where mv.at >= public.cr_day_start((m0 - make_interval(months => p_months - 1))::date)
          group by 1),
  ex as (select date_trunc('month', x.date)::date as m, sum(x.amt) as expenses from (
           select e.date, e.amount_crc - e.iva_crc as amt from public.expenses e where e.voided_at is null
           union all
           select i.date, i.net_crc from public.supplier_invoices i where i.voided_at is null and i.account is not null) x
         group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('month', to_char(mo.m, 'YYYY-MM'), 'net', coalesce(s.net, 0), 'gross', coalesce(s.gross, 0), 'orders', coalesce(s.n, 0),
           'avg_ticket', case when s.n > 0 then round(s.gross / s.n) end,
           'cogs', coalesce(st.cogs, 0), 'waste', coalesce(st.waste, 0), 'purchases', coalesce(st.purchases, 0), 'expenses', coalesce(ex.expenses, 0),
           'labor', case when labor_ok then (select sum((d->>'labor_crc')::numeric) from jsonb_array_elements(
                        public.labor_cost(mo.m, least((mo.m + interval '1 month' - interval '1 day')::date, public.cr_today()))->'days') d) end,
           'food_cost_pct', case when s.net > 0 then round(100 * coalesce(st.cogs, 0) / s.net, 1) end,
           'gross_margin', coalesce(s.net, 0) - coalesce(st.cogs, 0)) order by mo.m), '[]')
    into rows
    from months mo left join s on s.m = mo.m left join st on st.m = mo.m left join ex on ex.m = mo.m;
  -- prime cost: food cost + labor, against sales without IVA
  return jsonb_build_object('ok', true, 'labor_visible', labor_ok, 'months', (
    select coalesce(jsonb_agg(x || jsonb_build_object(
             'labor_pct', case when (x->>'net')::numeric > 0 and x->>'labor' is not null then round(100 * (x->>'labor')::numeric / (x->>'net')::numeric, 1) end,
             'prime_pct', case when (x->>'net')::numeric > 0 and x->>'labor' is not null
                               then round(100 * ((x->>'cogs')::numeric + (x->>'labor')::numeric) / (x->>'net')::numeric, 1) end)), '[]')
      from jsonb_array_elements(rows) x));
end $$;

-- 4) suppliers ------------------------------------------------------------------------------------------------------
create or replace function public.supplier_insights(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not (public._insights_allowed() or public.inventory_open()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'vendors', (
    select coalesce(jsonb_agg(x order by (x->>'received')::numeric desc nulls last), '[]') from (
      select jsonb_build_object('vendor_id', v.id, 'name', v.name, 'lead_days', v.lead_days,
        'received', coalesce((select sum(r.total_crc) from public.purchase_receipts r where r.vendor_id = v.id
                               and (r.received_at at time zone 'America/Costa_Rica')::date between p_from and p_to), 0),
        'deliveries', (select count(*) from public.purchase_receipts r where r.vendor_id = v.id and (r.received_at at time zone 'America/Costa_Rica')::date between p_from and p_to),
        -- days from sending the order to its first delivery, against the vendor's usual days
        'avg_days', (select round(avg(extract(epoch from (fr.first_at - po.sent_at)) / 86400)::numeric, 1)
                       from public.purchase_orders po
                       join lateral (select min(r.received_at) as first_at from public.purchase_receipts r where r.po_id = po.id) fr on fr.first_at is not null
                      where po.vendor_id = v.id and po.sent_at is not null and (po.sent_at at time zone 'America/Costa_Rica')::date between p_from and p_to),
        'late', (select count(*) from public.purchase_orders po
                  join lateral (select min(r.received_at) as first_at from public.purchase_receipts r where r.po_id = po.id) fr on fr.first_at is not null
                 where po.vendor_id = v.id and po.sent_at is not null and (po.sent_at at time zone 'America/Costa_Rica')::date between p_from and p_to
                   and fr.first_at > po.sent_at + make_interval(days => coalesce(v.lead_days, 2) + 1)),
        'owed', coalesce((select sum(public._invoice_open(i.id)) from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null), 0),
        -- each item's cost per unit at its first and last delivery in the range
        'prices', (select coalesce(jsonb_agg(jsonb_build_object('item', p.name, 'unit', p.unit, 'first', p.first_cost, 'last', p.last_cost,
                                    'change_pct', case when p.first_cost > 0 then round(100 * (p.last_cost - p.first_cost) / p.first_cost, 1) end) order by p.name), '[]')
                     from (select si.name, si.unit,
                                  (array_agg(mv.unit_cost order by mv.at))[1] as first_cost, (array_agg(mv.unit_cost order by mv.at desc))[1] as last_cost
                             from public.stock_moves mv join public.purchase_orders po on po.id = mv.po_id join public.stock_items si on si.id = mv.item_id
                            where mv.kind = 'purchase' and po.vendor_id = v.id and mv.unit_cost is not null
                              and (mv.at at time zone 'America/Costa_Rica')::date between p_from and p_to
                            group by si.name, si.unit) p)) as x
        from public.vendors v
       where v.active or exists (select 1 from public.purchase_receipts r where r.vendor_id = v.id)) q));
end $$;

-- 5) when each item runs out (a count below zero, from sales without a count, is taken as nothing left) -----------
create or replace function public.stock_forecast()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d date := public.cr_today();
begin
  if not (public.inventory_open() or public._insights_allowed()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'day', d, 'items', (
    with use as (
      select m.item_id,
             -sum(m.qty) filter (where m.at >= public.cr_day_start(d - 28)) / 28.0 as u28,
             -sum(m.qty) filter (where m.at >= public.cr_day_start(d - 7)) / 7.0 as u7
        from public.stock_moves m where m.kind in ('sale', 'void', 'waste') and m.at >= public.cr_day_start(d - 28)
       group by m.item_id),
    incoming as (
      select l.item_id, sum(greatest(l.qty - coalesce(l.received_qty, 0), 0)) as qty
        from public.purchase_lines l join public.purchase_orders po on po.id = l.po_id
       where po.status in ('sent', 'partially_received') group by l.item_id),
    f as (
      select s.id, s.name, s.unit, s.category, greatest(s.on_hand, 0) as on_hand, s.on_hand < 0 as below_zero, s.par_level, s.reorder_point, s.pack_qty, s.pack_label, v.name as vendor, coalesce(v.lead_days, 2) as lead_days,
             coalesce(i.qty, 0) as incoming,
             -- recent days weigh as much as the month: a busier week shows sooner
             greatest(coalesce(0.5 * u.u7 + 0.5 * u.u28, 0), 0) as rate
        from public.stock_items s left join use u on u.item_id = s.id left join incoming i on i.item_id = s.id left join public.vendors v on v.id = s.vendor_id
       where s.active)
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'unit', unit, 'category', category, 'vendor', vendor, 'lead_days', lead_days,
             'on_hand', on_hand, 'below_zero', below_zero, 'incoming', incoming, 'per_day', round(rate::numeric, 3),
             'days_left', case when rate > 0 then round(((on_hand + incoming) / rate)::numeric, 1) end,
             'runs_out', case when rate > 0 then d + floor((on_hand + incoming) / rate)::int end,
             'order_by', case when rate > 0 then d + floor((on_hand + incoming) / rate)::int - lead_days end,
             'status', case when rate <= 0 then 'no_use'
                            when d + floor((on_hand + incoming) / rate)::int - lead_days <= d then 'order_now'
                            when d + floor((on_hand + incoming) / rate)::int - lead_days <= d + 3 then 'soon' else 'ok' end,
             -- enough to reach the par level after the delivery days, in whole packs
             'suggest_packs', case when rate > 0 then greatest(ceil((greatest(par_level, rate * (lead_days + 7)) + rate * lead_days - on_hand - incoming) / nullif(pack_qty, 0)), 0) end,
             'pack_label', pack_label)
           order by case when rate <= 0 then 9999 else floor((on_hand + incoming) / rate) - lead_days end, name), '[]')
      from f));
end $$;

revoke all on function public.dashboard_today(), public.sales_patterns(date, date), public.trends_monthly(int), public.supplier_insights(date, date), public.stock_forecast() from public, anon;
grant execute on function public.dashboard_today(), public.sales_patterns(date, date), public.trends_monthly(int), public.supplier_insights(date, date), public.stock_forecast() to authenticated;

select canopy.migration_end(23, 'insights');
notify pgrst, 'reload schema';
