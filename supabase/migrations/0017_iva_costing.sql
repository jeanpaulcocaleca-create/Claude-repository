-- =====================================================================================================
-- Canopy OS · migración 0017 · IVA del período, inventario valorado y rentabilidad por producto
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0016.
--
-- Qué hace (solo lectura: no cambia ningún dato)
--   * iva_report: borrador del IVA de un período para el contador: IVA de las ventas por tarifa, devoluciones,
--     IVA acreditable de gastos y facturas de proveedores (cada documento), y lo que dicen los libros
--     (cuentas de IVA). No es la declaración: el contador la revisa, aplica la proporcionalidad si hace
--     falta y la presenta.
--   * inventory_valuation: cada insumo con su existencia y costo promedio, el total, y la cuenta de
--     inventario de los libros para cuadrarlos.
--   * product_profitability: por producto del menú: unidades vendidas, venta sin IVA, costo real de lo
--     vendido (costo promedio del momento), margen; y el costo de la receta y el margen con el precio de hoy.
--   * Lo ven el dueño (con el código del teléfono), un encargado con PIN y el contador.
-- Qué cambia para el personal: nada.
-- Reversión: drop function iva_report, inventory_valuation, product_profitability.
-- =====================================================================================================
select canopy.migration_begin(17, 'iva_costing');

create or replace function public._books_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_owner() or acct.can_read(), false);
$$;
revoke all on function public._books_allowed() from public, anon;
grant execute on function public._books_allowed() to authenticated;

-- 1) the IVA of a period, as a draft for the accountant -------------------------------------------------------
create or replace function public.iva_report(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare sales jsonb; docs jsonb; refunds numeric; untaxed jsonb; out_tax numeric; credit numeric; led_out numeric; led_in numeric;
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  -- sales: each line's IVA as stamped at the moment of sale (0009); refunds give back the IVA of the sale
  select coalesce(jsonb_agg(x order by x->>'code'), '[]') into sales from (
    select jsonb_build_object('code', i.tax_code, 'rate', i.tax_rate, 'lines', count(*), 'net_crc', sum(i.net_crc), 'tax_crc', sum(i.tax_crc)) as x
      from public.order_items i join public.orders o on o.id = i.order_id
     where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null and i.tax_crc is not null
     group by i.tax_code, i.tax_rate) q;
  select coalesce(sum(tax_crc), 0) into refunds from public.orders
   where refund_of is not null and voided_at is null and business_date between p_from and p_to;
  -- sales recorded before 0009 have no IVA detail: shown apart, never guessed into the totals
  select jsonb_build_object('orders', count(*), 'total_crc', coalesce(sum(o.total_crc), 0)) into untaxed
    from public.orders o
   where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
     and o.refund_of is null and o.tax_crc is null and o.total_crc > 0;
  select coalesce(sum((x->>'tax_crc')::numeric), 0) + refunds into out_tax from jsonb_array_elements(sales) x;
  -- creditable IVA: every expense and supplier invoice of the period that is not voided, by document date
  select coalesce(jsonb_agg(d order by d->>'date', d->>'supplier'), '[]') into docs from (
    select jsonb_build_object('source', 'expense', 'id', e.id, 'date', e.date, 'supplier', e.vendor_name, 'number', e.invoice_no,
                              'base_crc', e.amount_crc - e.iva_crc, 'iva_crc', e.iva_crc, 'account', e.account) as d
      from public.expenses e where e.voided_at is null and e.date between p_from and p_to
    union all
    select jsonb_build_object('source', 'supplier_invoice', 'id', i.id, 'date', i.date, 'supplier', v.name, 'number', i.number,
                              'base_crc', i.net_crc, 'iva_crc', i.iva_crc, 'account', coalesce(i.account, acct.map('inventory')))
      from public.supplier_invoices i join public.vendors v on v.id = i.vendor_id where i.voided_at is null and i.date between p_from and p_to) q;
  select coalesce(sum((x->>'iva_crc')::numeric), 0) into credit from jsonb_array_elements(docs) x;
  -- what the books hold for the same days (only what has been posted)
  select coalesce(sum(l.credit - l.debit) filter (where l.account = acct.map('iva_out')), 0),
         coalesce(sum(l.debit - l.credit) filter (where l.account = acct.map('iva_in')), 0)
    into led_out, led_in
    from acct.lines l join acct.entries e on e.id = l.entry_id where e.date between p_from and p_to;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'draft', true,
    'sales', jsonb_build_object('by_rate', sales, 'refunds_tax_crc', refunds, 'tax_crc', out_tax, 'without_tax_detail', untaxed),
    'credits', jsonb_build_object('documents', docs, 'iva_crc', credit,
                                  'without_iva', (select count(*) from jsonb_array_elements(docs) x where (x->>'iva_crc')::numeric = 0)),
    'net_crc', out_tax - credit,
    'ledger', jsonb_build_object('iva_out_crc', led_out, 'iva_in_crc', led_in, 'net_crc', led_out - led_in,
                                 'pending_days', (select count(*) from public.register_days r where r.business_date between p_from and p_to and r.closed_at is not null
                                                     and not exists (select 1 from acct.entries e where e.source = 'day' and e.source_key like 'day:' || r.business_date || ':%'))));
end $$;

-- 2) inventory at weighted average cost, against the books -----------------------------------------------------
create or replace function public.inventory_valuation()
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare items jsonb; total numeric;
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select coalesce(jsonb_agg(x order by x->>'category', x->>'name'), '[]'), coalesce(sum((x->>'value_crc')::numeric), 0) into items, total from (
    select jsonb_build_object('id', s.id, 'name', s.name, 'category', s.category, 'unit', s.unit, 'on_hand', s.on_hand,
                              'avg_cost', coalesce(s.avg_cost, round(s.cost_per_pack / nullif(s.pack_qty, 0), 4)),
                              'value_crc', round(greatest(s.on_hand, 0) * coalesce(s.avg_cost, s.cost_per_pack / nullif(s.pack_qty, 0), 0), 2),
                              'negative', s.on_hand < 0, 'active', s.active) as x
      from public.stock_items s where s.active or s.on_hand <> 0) q;
  return jsonb_build_object('ok', true, 'items', items, 'total_crc', total,
    'ledger_crc', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = acct.map('inventory')),
    'posted', exists (select 1 from acct.entries where source = 'day'));
end $$;

-- 3) what each product leaves ----------------------------------------------------------------------------------
create or replace function public.product_profitability(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare rows jsonb;
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  with sold as (      -- lines of sales that stand (not voided, not refunded), net of IVA and of the bill discount
    select lower(i.item_name) as k, min(i.item_name) as name, sum(i.qty) as units,
           sum(coalesce(i.net_crc, round((i.price_crc * i.qty - coalesce(i.discount_alloc_crc, 0)) / 1.13, 2))) as net,
           bool_or(i.net_crc is null) as estimated
      from public.order_items i join public.orders o on o.id = i.order_id
     where o.business_date between p_from and p_to and o.voided_at is null and o.refunded_at is null and coalesce(o.paid, true)
       and o.refund_of is null and coalesce(o.status, 'done') <> 'cancelled'
     group by lower(i.item_name)),
  cost as (           -- what the stock that went out for those sales cost, at the average cost of that moment
    select lower(m.note) as k, -sum(m.qty * coalesce(m.unit_cost, 0)) as cost
      from public.stock_moves m join public.orders o on o.id = m.order_id
     where m.kind in ('sale', 'void') and o.business_date between p_from and p_to and o.voided_at is null and o.refunded_at is null
     group by lower(m.note)),
  menu as (           -- today's price net of IVA and today's recipe cost
    select distinct on (lower(mi.name)) lower(mi.name) as k, mi.id, mi.name, mi.price_crc, coalesce(t.rate, 0.13) as rate,
           (select sum(r.qty * coalesce(s.avg_cost, s.cost_per_pack / nullif(s.pack_qty, 0), 0)) from public.recipes r join public.stock_items s on s.id = r.stock_item_id
             where r.menu_item_id = mi.id) as recipe_cost,
           exists (select 1 from public.recipes r where r.menu_item_id = mi.id) as has_recipe
      from public.menu_items mi left join public.tax_rates t on t.code = mi.tax_code
     order by lower(mi.name), mi.available desc)
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', coalesce(m.name, s.name), 'units', coalesce(s.units, 0), 'net_crc', round(coalesce(s.net, 0), 2), 'estimated_tax', coalesce(s.estimated, false),
           'cost_crc', round(coalesce(c.cost, 0), 2), 'margin_crc', round(coalesce(s.net, 0) - coalesce(c.cost, 0), 2),
           'food_cost_pct', case when coalesce(s.net, 0) > 0 then round(100 * coalesce(c.cost, 0) / s.net, 1) end,
           'has_recipe', coalesce(m.has_recipe, false), 'on_menu', m.k is not null,
           'price_crc', m.price_crc, 'price_net_crc', round(m.price_crc / (1 + m.rate), 2), 'recipe_cost_crc', round(m.recipe_cost, 2),
           'unit_margin_crc', round(m.price_crc / (1 + m.rate) - coalesce(m.recipe_cost, 0), 2),
           'unit_margin_pct', case when m.price_crc > 0 then round(100 * (m.price_crc / (1 + m.rate) - coalesce(m.recipe_cost, 0)) / (m.price_crc / (1 + m.rate)), 1) end)
         order by round(coalesce(s.net, 0) - coalesce(c.cost, 0), 2) desc, coalesce(m.name, s.name)), '[]')
    into rows
    from sold s full join menu m on m.k = s.k left join cost c on c.k = coalesce(s.k, m.k)
   where s.k is not null or m.k is not null;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'rows', rows,
    'totals', (select jsonb_build_object('units', coalesce(sum((x->>'units')::numeric), 0), 'net_crc', coalesce(sum((x->>'net_crc')::numeric), 0),
                                         'cost_crc', coalesce(sum((x->>'cost_crc')::numeric), 0), 'margin_crc', coalesce(sum((x->>'margin_crc')::numeric), 0))
                 from jsonb_array_elements(rows) x));
end $$;

revoke all on function public.iva_report(date, date), public.inventory_valuation(), public.product_profitability(date, date) from public, anon;
grant execute on function public.iva_report(date, date), public.inventory_valuation(), public.product_profitability(date, date) to authenticated;

select canopy.migration_end(17, 'iva_costing');
notify pgrst, 'reload schema';
