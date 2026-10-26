-- Migration 0017: the period's IVA for the accountant, inventory at average cost, profit by product.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
update public.menu_items set price_crc = 2260 where id = :'latte';
insert into public.stock_items (id, name, category, unit, pack_qty, cost_per_pack, on_hand) values
  ('5a000000-0000-4000-8000-000000001801', 'Leche', 'dairy', 'ml', 1000, 1000, 10000),
  ('5a000000-0000-4000-8000-000000001802', 'Café en grano', 'coffee', 'g', 1000, 10000, 2000);
delete from public.recipes where menu_item_id = :'latte';
insert into public.recipes (menu_item_id, stock_item_id, qty) values (:'latte', '5a000000-0000-4000-8000-000000001801', 200),
                                                                    (:'latte', '5a000000-0000-4000-8000-000000001802', 18);

-- a sale of 2 lattes and one of 1 latte that is given back
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001801', 'total_crc', 4520, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2260, 'qty', 2, 'menu_item_id', :'latte'))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001802', 'total_crc', 2260, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2260, 'qty', 1, 'menu_item_id', :'latte'))));
select test.eq(public.iva_report(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'a locked café device cannot see the IVA');
select test.eq(public.product_profitability(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'nor the profit by product');
reset role;
insert into public.orders (id, total_crc, payment_method, paid, status, refund_of)
  values ('0d000000-0000-4000-8000-000000001803', -2260, 'card', true, 'done', '0d000000-0000-4000-8000-000000001802');
update public.orders set refunded_at = now() where id = '0d000000-0000-4000-8000-000000001802';

-- purchases with IVA: an expense and a supplier invoice
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000001801', 'Lácteos Monteverde');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Jabón', 'vendor_name', 'Súper', 'account', '6204',
       'amount_crc', 11300, 'iva_crc', 1300, 'paid_from', 'cash', 'invoice_no', 'E-1'), gen_random_uuid())->>'ok', 'true', 'an expense with IVA');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001801', 'number', 'L-5', 'date', public.cr_today(),
       'net_crc', 2000, 'iva_crc', 260, 'account', '6206'), gen_random_uuid())->>'ok', 'true', 'a supplier invoice with IVA');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Pan', 'vendor_name', 'Panadería', 'account', '6299',
       'amount_crc', 3000, 'iva_crc', 0, 'paid_from', 'cash'), gen_random_uuid())->>'ok', 'true', 'a purchase without IVA (said so: since 0034 the server never assumes the IVA)');

-- 1) IVA: 4520 × 13/113 = 520 and 2260 → 260, given back: −260 ; credits 1300 + 260
select public.iva_report(public.cr_today(), public.cr_today()) as iv \gset
select test.eq(((:'iv'::jsonb)#>>'{sales,by_rate,0,tax_crc}')::numeric, 780::numeric, 'sales IVA at 13 %: both sales');
select test.eq(((:'iv'::jsonb)#>>'{sales,refunds_tax_crc}')::numeric, -260::numeric, 'the refund gives back its IVA');
select test.eq(((:'iv'::jsonb)#>>'{sales,tax_crc}')::numeric, 520::numeric, 'IVA charged on sales, net of refunds');
select test.eq(((:'iv'::jsonb)#>>'{credits,iva_crc}')::numeric, 1560::numeric, 'creditable IVA: expense + supplier invoice');
select test.eq(jsonb_array_length((:'iv'::jsonb)#>'{credits,documents}'), 3, 'every purchase document is listed');
select test.eq(((:'iv'::jsonb)#>>'{credits,without_iva}')::int, 1, 'and those without IVA are counted');
select test.eq(((:'iv'::jsonb)#>>'{net_crc}')::numeric, -1040::numeric, 'net: a credit balance this period');
select test.eq(((:'iv'::jsonb)#>>'{ledger,iva_in_crc}')::numeric, 1560::numeric, 'the books hold the same creditable IVA');
select test.eq(((:'iv'::jsonb)#>>'{ledger,iva_out_crc}')::numeric, 0::numeric, 'sales IVA reaches the books when the day is posted');
select test.eq(public.iva_report(public.cr_today() - 100, public.cr_today())->>'error', 'bad_range', 'at most a quarter at a time');

-- 2) inventory: milk 10 000 − 600 ml at ₡1, coffee 2 000 − 54 g at ₡10
select public.inventory_valuation() as inv \gset
select test.eq(((:'inv'::jsonb)->>'total_crc')::numeric, (9400 * 1 + 1946 * 10)::numeric, 'stock valued at average cost');
select test.eq(jsonb_array_length((:'inv'::jsonb)->'items') >= 2, true, 'each item listed');

-- 3) profit by product: the refunded sale does not count
select public.product_profitability(public.cr_today(), public.cr_today()) as pp \gset
select test.eq((select x->>'units' from jsonb_array_elements((:'pp'::jsonb)->'rows') x where x->>'name' = 'Latte'), '2', 'units that stand: 2');
select test.eq((select (x->>'net_crc')::numeric from jsonb_array_elements((:'pp'::jsonb)->'rows') x where x->>'name' = 'Latte'), 4000::numeric, 'sold net of IVA');
select test.eq((select (x->>'cost_crc')::numeric from jsonb_array_elements((:'pp'::jsonb)->'rows') x where x->>'name' = 'Latte'), 760::numeric,
               'cost of what went out: 2 × (200 ml × ₡1 + 18 g × ₡10)');
select test.eq((select (x->>'food_cost_pct')::numeric from jsonb_array_elements((:'pp'::jsonb)->'rows') x where x->>'name' = 'Latte'), 19.0::numeric, 'food cost 19 %');
select test.eq((select (x->>'recipe_cost_crc')::numeric || '|' || (x->>'unit_margin_crc') from jsonb_array_elements((:'pp'::jsonb)->'rows') x where x->>'name' = 'Latte'),
               '380.00|1620.00', 'recipe cost today and the margin at today''s price net of IVA');
select test.ok((select bool_and((x->>'has_recipe')::boolean = false) from jsonb_array_elements((:'pp'::jsonb)->'rows') x where x->>'name' = 'Tea'), 'products without a recipe are flagged');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.inventory_valuation()->>'ok', 'true', 'the accountant sees the valuation');
reset role;
select test.done();
rollback;
