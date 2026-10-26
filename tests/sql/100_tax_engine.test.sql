-- Migration 0009: IVA per product, stored on every line at sale time.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
select id as tea from public.menu_items where name = 'Tea' limit 1 \gset

-- 1) rates: only the general 13 % comes built in; others need who and which document ------------------------
select test.eq((select string_agg(code || ':' || rate, ',') from public.tax_rates), 'IVA13:0.1300', 'only the general rate is built in');
select test.eq((select count(*)::int from public.menu_items where tax_code <> 'IVA13'), 0, 'every product starts at the general rate (as the POS today)');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.tax_rate_save('IVA4', 'Tarifa reducida 4 %', 0.04, '', '')->>'error', 'missing_reference', 'a rate needs who confirmed it');
select test.eq(public.tax_rate_save('IVA4', 'Tarifa reducida 4 %', 0.04, 'Contadora M. Rojas', 'Consulta 2026-17')->>'ok', 'true', 'the owner adds a confirmed rate');
update public.menu_items set tax_code = 'IVA4' where id = :'tea';
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(public.tax_rate_save('IVA2', 'x', 0.02, 'a', 'b')->>'error', 'owner_only', 'the café login cannot add rates');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$update public.menu_items set cabys = '12345' where name = 'Latte'$$, 'cabys', 'CABYS must be 13 digits');
select test.lives($$update public.menu_items set cabys = '2399999009900' where name = 'Latte'$$, 'a 13-digit CABYS is kept');
reset role;

-- 2) a sale: the server works out the IVA of each line --------------------------------------------------------
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001001', 'total_crc', 5400, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 2, 'menu_item_id', :'latte'),
                                  jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 1, 'menu_item_id', :'tea'))));
reset role;
-- 4400 × 13/113 = 506.19 → 506 ; 1000 × 4/104 = 38.46 → 38
select test.eq((select tax_crc || '|' || net_crc || '|' || tax_code from public.order_items where order_id = '0d000000-0000-4000-8000-000000001001' and item_name = 'Latte'),
               '506|3894|IVA13', 'Latte: IVA 13 % included');
select test.eq((select tax_crc || '|' || net_crc || '|' || tax_code from public.order_items where order_id = '0d000000-0000-4000-8000-000000001001' and item_name = 'Tea'),
               '38|962|IVA4', 'Tea: its own 4 % rate');
select test.eq((select tax_crc from public.orders where id = '0d000000-0000-4000-8000-000000001001'), 544, 'the sale keeps its total IVA');

-- the till cannot choose the rate or the tax
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, tax_crc) values ('0d000000-0000-4000-8000-000000001002', now(), 2200, 'card', true, 'done', 1);
insert into public.order_items (order_id, item_name, price_crc, qty, menu_item_id, tax_code, tax_rate, tax_crc)
  values ('0d000000-0000-4000-8000-000000001002', 'Latte', 2200, 1, :'latte', 'IVA4', 0.04, 0);
reset role;
select test.eq((select tax_code || '|' || tax_crc from public.order_items where order_id = '0d000000-0000-4000-8000-000000001002'), 'IVA13|253',
               'rate and tax come from the product, not from the till');

-- 3) a discount is shared across the lines before IVA -----------------------------------------------------------
select test.login('cafe'); set role authenticated;
select public.approve_discount(test.staff('ana'), '4826', 'amount', 320, 3200, 'cortesía', 'Caja') as d \gset
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001003', 'total_crc', 2880, 'subtotal_crc', 3200,
       'discount_crc', 320, 'discount_id', (:'d'::jsonb)->>'id', 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'),
                                  jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 1, 'menu_item_id', :'tea'))));
reset role;
select test.eq((select sum(discount_alloc_crc)::int from public.order_items where order_id = '0d000000-0000-4000-8000-000000001003'), 320,
               'the shares add up to the discount exactly');
-- Latte: 2200 − 220 = 1980 → 227.79 → 228 ; Tea: 1000 − 100 = 900 → 34.6 → 35
select test.eq((select tax_crc from public.orders where id = '0d000000-0000-4000-8000-000000001003'), 263, 'IVA on the discounted amounts');
select test.eq((select sum(net_crc + tax_crc)::int from public.order_items where order_id = '0d000000-0000-4000-8000-000000001003'), 2880,
               'net + IVA = what was charged');

-- 4) a bill: items added and taken off move the IVA -------------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, guest_name) values ('0d000000-0000-4000-8000-000000001004', now(), 2200, 'pending', false, 'ready', 'Mesa 5');
insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id) values ('1e000000-0000-4000-8000-000000001004', '0d000000-0000-4000-8000-000000001004', 'Latte', 2200, 1, :'latte');
select public.tab_add_items('0d000000-0000-4000-8000-000000001004', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte')));
reset role;
select test.eq((select tax_crc from public.orders where id = '0d000000-0000-4000-8000-000000001004'), 506, 'two lattes on the bill: IVA 506');
select test.login('cafe'); set role authenticated;
select public.tab_remove_item('1e000000-0000-4000-8000-000000001004', 1, 'error', 'Caja');
reset role;
select test.eq((select tax_crc from public.orders where id = '0d000000-0000-4000-8000-000000001004'), 253, 'one taken off: IVA 253');

-- 5) a refund gives the IVA back ------------------------------------------------------------------------------------
insert into public.register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name)
  values (public.cr_today(), 'Ana', 50000, now(), 'Ana');
select test.login('cafe'); set role authenticated;
select public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000001001', 'devolución') as rf \gset
reset role;
select test.eq((select tax_crc from public.orders where id = ((:'rf'::jsonb)->>'refund_id')::uuid), -544, 'the refund carries the IVA back');

-- 6) the IVA summary --------------------------------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.tax_summary(public.cr_today(), public.cr_today()) as ts \gset
reset role;
select test.eq((select (x->>'tax_crc')::int from jsonb_array_elements((:'ts'::jsonb)->'by_rate') x where x->>'code' = 'IVA4'), 38 + 35, 'IVA at 4 % for the day');
select test.eq(((:'ts'::jsonb)->>'refunds_tax_crc')::int, -544, 'refunded IVA reported apart');

-- 7) a rate used on sales is never rewritten; tax-exclusive prices stay locked ------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.tax_rate_save('IVA4', 'x', 0.05, 'a', 'b')->>'error', 'rate_in_use', 'a used rate cannot change (add a new code)');
select test.eq(public.setting_set('price_mode', '"exclusive"')->>'error', 'needs_confirmation', 'tax-exclusive prices are locked');
reset role;

select test.done();
rollback;
