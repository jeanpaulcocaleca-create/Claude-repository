-- =====================================================================================================
-- Canopy OS · REVISIÓN DE CONSISTENCIA (SOLO LECTURA: no cambia nada)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Resultado: UNA celda ("consistency").
-- Ejecútela ANTES y DESPUÉS de aplicar migraciones (y en una copia restaurada): los valores de "kept" deben salir
-- IGUALES. Muestra cantidades y huellas (md5), nunca montos, nombres ni PINs.
--   kept      lo que ninguna migración puede cambiar: ventas, partes de cuentas, anulaciones, descuentos, caja,
--             inventario, horas, personal, bitácora (huellas de lo que ya existía)
--   problems  cosas que deberían ser 0 (filas huérfanas, inventario que no cuadra con sus movimientos, etc.).
--             Si ya eran distintas de 0 antes, deben seguir IGUALES después (la migración no las crea).
--   after     revisiones que solo existen después de las migraciones (asientos cuadrados, recibos únicos…); desde la
--             0039/0040 también Proveedores (entregas que no suman sus movimientos, pagos SINPE sin número, pagos
--             aplicados de más, la 1160 contra los pagos sin aplicar, pagos sin aplicar de hace más de 30 días, días
--             asentados con compras recibidas después): todas deben ser 0
-- =====================================================================================================
with
d as (select (o.created_at at time zone 'America/Costa_Rica')::date as day, o.* from public.orders o),
kept as (select jsonb_build_object(
  'orders', (select count(*) from public.orders),
  'orders_paid_not_voided', (select count(*) from public.orders where paid and voided_at is null),
  'orders_open_bills', (select count(*) from public.orders where not paid and voided_at is null and coalesce(status, '') <> 'cancelled'),
  'orders_voided', (select count(*) from public.orders where voided_at is not null),
  'sales_by_day_md5', (select md5(coalesce(string_agg(day || ':' || n || ':' || t, ',' order by day), '')) from
                        (select day, count(*) n, sum(total_crc) t from d where paid and voided_at is null group by day) q),
  'sales_by_method_md5', (select md5(coalesce(string_agg(payment_method || ':' || t, ',' order by payment_method), '')) from
                           (select payment_method, sum(total_crc) t from public.orders where paid and voided_at is null group by 1) q),
  'items', (select count(*) from public.order_items),
  'items_md5', (select md5(coalesce(string_agg(order_id || ':' || item_name || ':' || qty || ':' || price_crc || ':' || paid_qty, ',' order by order_id, id), ''))
                  from public.order_items),
  'bill_parts', (select count(*) from public.orders where part_of is not null),
  'bill_parts_md5', (select md5(coalesce(string_agg(part_of || ':' || total_crc || ':' || payment_method, ',' order by part_of, id), ''))
                       from public.orders where part_of is not null),
  'part_lines', (select count(*) from public.order_part_lines),
  'discounts_md5', (select md5(coalesce(string_agg(id || ':' || discount_crc || ':' || coalesce(discount_id::text, ''), ',' order by id), ''))
                      from public.orders where discount_crc <> 0),
  'voids_md5', (select md5(coalesce(string_agg(id || ':' || coalesce(voided_by::text, '') || ':' || coalesce(void_reason, ''), ',' order by id), ''))
                  from public.orders where voided_at is not null),
  'register_days', (select count(*) from public.register_days),
  'register_md5', (select md5(coalesce(string_agg(business_date || ':' || coalesce(closed_at::text, 'open') || ':' || coalesce(sales_total_crc, -1) || ':' ||
                                                  coalesce(cash_counted_crc, -1) || ':' || coalesce(cash_diff_crc, 0), ',' order by business_date), ''))
                     from public.register_days),
  'stock_items', (select count(*) from public.stock_items),
  'stock_on_hand_md5', (select md5(coalesce(string_agg(id || ':' || round(on_hand, 3), ',' order by id), '')) from public.stock_items),
  'stock_moves', (select count(*) from public.stock_moves),
  'stock_moves_md5', (select md5(coalesce(string_agg(id || ':' || item_id || ':' || kind || ':' || round(qty, 3), ',' order by id), '')) from public.stock_moves),
  'purchase_orders', (select count(*) from public.purchase_orders),
  'time_entries', (select count(*) from public.time_entries),
  'time_md5', (select md5(coalesce(string_agg(staff_id || ':' || extract(epoch from clock_in) || ':' || coalesce(extract(epoch from clock_out)::text, 'open'), ',' order by id), ''))
                 from public.time_entries),
  'staff', (select count(*) from public.staff),
  'staff_md5', (select md5(coalesce(string_agg(id || ':' || name || ':' || role || ':' || active, ',' order by id), '')) from public.staff),
  'logins', (select count(*) from public.app_accounts),
  'audit_log', (select count(*) from public.audit_log),
  'menu_md5', (select md5(coalesce(string_agg(id || ':' || name || ':' || price_crc || ':' || available, ',' order by id), '')) from public.menu_items)
) as v),
problems as (select jsonb_build_object(
  'items_without_order', (select count(*) from public.order_items i where not exists (select 1 from public.orders o where o.id = i.order_id)),
  'parts_without_bill', (select count(*) from public.orders p where p.part_of is not null and not exists (select 1 from public.orders o where o.id = p.part_of)),
  'bills_parts_total_differs', (select count(*) from public.orders o
                                   left join (select part_of, sum(total_crc) as s from public.orders where part_of is not null and given_back_at is null group by 1) p
                                     on p.part_of = o.id
                                  where o.part_of is null and o.parts_crc <> coalesce(p.s, 0)),
  'paid_without_method', (select count(*) from public.orders where paid and coalesce(payment_method, '') in ('', 'pending') and part_of is null and total_crc > 0),
  'orders_total_vs_items', (select count(*) from public.orders o
                               left join (select order_id, sum(qty * price_crc) as s from public.order_items group by 1) i on i.order_id = o.id
                              where o.part_of is null and o.voided_at is null and o.total_crc + o.parts_crc + coalesce(o.discount_crc, 0) <> coalesce(i.s, 0)),
  'stock_on_hand_vs_moves', (select count(*) from public.stock_items s
                                left join (select item_id, sum(qty) as q from public.stock_moves group by 1) m on m.item_id = s.id
                               where round(s.on_hand, 3) <> round(coalesce(m.q, 0), 3)),
  'shifts_negative', (select count(*) from public.time_entries where clock_out < clock_in),
  'shifts_open_before_today', (select count(*) from public.time_entries where clock_out is null and clock_in < now() - interval '20 hours'),
  'registers_open_before_today', (select count(*) from public.register_days where closed_at is null
                                    and business_date < (now() at time zone 'America/Costa_Rica')::date)
) as v),
after as (select jsonb_strip_nulls(jsonb_build_object(
  'migrations', case when to_regclass('canopy.migrations') is not null then
      (xpath('/row/j/text()', query_to_xml('select coalesce(max(version), -1)::text as j from canopy.migrations', false, true, '')))[1]::text end,
  'ledger_unbalanced', case when to_regclass('acct.lines') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u', false, true, '')))[1]::text end,
  'ledger_entries', case when to_regclass('acct.entries') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from acct.entries', false, true, '')))[1]::text end,
  'receipt_numbers_repeated', case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'orders' and column_name = 'receipt_no') then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from (select receipt_no from public.orders where receipt_no is not null group by 1 having count(*) > 1) r', false, true, '')))[1]::text end,
  'paid_orders_without_business_date', case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'orders' and column_name = 'business_date') then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.orders where business_date is null and paid', false, true, '')))[1]::text end,
  'orders_business_date_not_sale_day', case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'orders' and column_name = 'business_date') then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.orders where business_date <> (created_at at time zone ''America/Costa_Rica'')::date', false, true, '')))[1]::text end,
  'orders_before_reset', case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'orders' and column_name = 'flags') then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.orders where ''before_reset'' = any(flags)', false, true, '')))[1]::text end,
  'rows_without_location', case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'orders' and column_name = 'location_id') then
      (xpath('/row/j/text()', query_to_xml('select ((select count(*) from public.orders where location_id is null) + (select count(*) from public.stock_moves where location_id is null) + (select count(*) from public.time_entries where location_id is null))::text as j', false, true, '')))[1]::text end,
  -- Proveedores (0039/0040): each should be 0
  'receipts_total_vs_moves', case when to_regclass('public.purchase_receipt_lines') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.purchase_receipts r where abs(r.total_crc - coalesce((select sum(m.qty * coalesce(m.unit_cost, 0)) from public.stock_moves m where m.receipt_id = r.id and m.kind = ''purchase''), 0)) >= 0.01', false, true, '')))[1]::text end,
  'sinpe_payments_without_reference', case when to_regclass('public.supplier_advances') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.supplier_advances where method = ''sinpe'' and voided_at is null and (coalesce(reference, '''') = '''' or coalesce(ref_key, '''') = '''')', false, true, '')))[1]::text end,
  'payments_applied_above_amount', case when to_regclass('public.supplier_advances') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.supplier_advances a where (select coalesce(sum(p.amount_crc), 0) from public.supplier_payments p where p.advance_id = a.id and p.voided_at is null) > a.amount_crc + 0.005', false, true, '')))[1]::text end,
  'advances_ledger_vs_unapplied', case when to_regclass('public.supplier_advances') is not null then
      (xpath('/row/j/text()', query_to_xml('select trim_scale(round(coalesce((select sum(l.debit - l.credit) from acct.lines l join acct.entries e on e.id = l.entry_id where l.account = (select account from acct.mappings where key = ''supplier_advance'') and (e.source_key like ''supadv:%'' or e.source_key like ''suppay:%'' or e.reverses in (select x.id from acct.entries x where x.source_key like ''supadv:%'' or x.source_key like ''suppay:%''))), 0) - coalesce((select sum(a.amount_crc - coalesce((select sum(p.amount_crc) from public.supplier_payments p where p.advance_id = a.id and p.voided_at is null), 0)) from public.supplier_advances a where a.voided_at is null), 0), 2))::text as j', false, true, '')))[1]::text end,
  'vendors_unapplied_with_open_invoices', case when to_regclass('public.supplier_advances') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.vendors v where exists (select 1 from public.supplier_advances a where a.vendor_id = v.id and a.voided_at is null and a.amount_crc > (select coalesce(sum(p.amount_crc), 0) from public.supplier_payments p where p.advance_id = a.id and p.voided_at is null)) and exists (select 1 from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null and i.total_crc > (select coalesce(sum(al.amount_crc), 0) from public.supplier_payment_allocations al join public.supplier_payments p on p.id = al.payment_id where al.invoice_id = i.id and p.voided_at is null))', false, true, '')))[1]::text end,
  'advances_unapplied_over_30_days', case when to_regclass('public.supplier_advances') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.supplier_advances a where a.voided_at is null and a.created_at < now() - interval ''30 days'' and a.amount_crc > (select coalesce(sum(p.amount_crc), 0) from public.supplier_payments p where p.advance_id = a.id and p.voided_at is null)', false, true, '')))[1]::text end,
  'purchase_moves_at_zero_cost', case when to_regclass('public.purchase_receipt_lines') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from public.stock_moves where kind = ''purchase'' and coalesce(unit_cost, 0) = 0', false, true, '')))[1]::text end,
  'posted_days_with_purchases_not_posted', case when to_regclass('public.purchase_receipt_lines') is not null then
      (xpath('/row/j/text()', query_to_xml('select count(*)::text as j from (select (m.at at time zone ''America/Costa_Rica'')::date as d, sum(m.qty * coalesce(m.unit_cost, 0)) as c from public.stock_moves m where m.kind = ''purchase'' group by 1) x where exists (select 1 from acct.entries e where e.source = ''day'' and e.source_key like ''day:'' || x.d || '':%'') and x.c - coalesce((select sum(l.credit - l.debit) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = ''day'' and e.source_key like ''day:'' || x.d || '':%'' and l.account = (select account from acct.mappings where key = ''ap'')), 0) > 0.01', false, true, '')))[1]::text end
)) as v)
select jsonb_pretty(jsonb_build_object('checked_at', now(), 'kept', kept.v, 'problems', problems.v, 'after', after.v)) as consistency
  from kept, problems, after;
