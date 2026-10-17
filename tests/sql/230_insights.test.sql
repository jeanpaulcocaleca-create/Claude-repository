-- Migrations 0023 and 0024: the day (estimate or final), patterns, monthly trends, suppliers, stock forecast; one location.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
-- last week's same weekday: one sale early in the day; today: two sales and a void
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values
  ('0d000000-0000-4000-8000-000000002301', public.cr_day_start(public.cr_today() - 7) + interval '1 minute', 1130, 'card', true, 'done');
select test.login('cafe'); set role authenticated;
select test.eq(public.dashboard_today()->>'error', 'not_allowed', 'a locked café device does not see the numbers');
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000002302', 'total_crc', 4520, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2260, 'qty', 2, 'menu_item_id', :'latte'))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000002303', 'total_crc', 2260, 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2260, 'qty', 1, 'menu_item_id', :'latte'))));
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000002303', 'error')->>'ok', 'true', 'one voided');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select public.dashboard_today() as dt \gset
select test.eq((:'dt'::jsonb)->>'state', 'no_register', 'no register today: neither estimate nor final');
select test.eq(((:'dt'::jsonb)#>>'{today,gross}')::numeric || '|' || ((:'dt'::jsonb)#>>'{today,net}')::numeric || '|' || ((:'dt'::jsonb)#>>'{today,orders}'),
               '4520|4000.00|1', 'today: with IVA, without IVA, orders (the void left out)');
select test.eq(((:'dt'::jsonb)#>>'{voided,total}')::numeric, 2260::numeric, 'voids shown apart');
select test.eq(((:'dt'::jsonb)#>>'{last_week,gross_day}')::numeric, 1130::numeric, 'the same weekday last week');
reset role;
-- a register opened today: an estimate; closed: final
select test.login('cafe'); set role authenticated;
select public.register_open(test.staff('ana'), '4826', 50000);
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.dashboard_today()->>'state', 'estimate', 'an estimate while the register is open');
reset role;
select test.login('cafe'); set role authenticated;
select public.register_close(test.staff('ana'), '4826', 4520, 50000, null);
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.dashboard_today()->>'state', 'final', 'final once it is closed');

-- patterns
select public.sales_patterns(public.cr_today() - 7, public.cr_today()) as sp \gset
select test.eq(jsonb_array_length((:'sp'::jsonb)->'days'), 2, 'two days with sales');
select test.eq((select (x->>'units')::numeric from jsonb_array_elements((:'sp'::jsonb)->'categories') x where (x->>'gross')::numeric = 4520), 2::numeric,
               'sales by category');
select test.eq((:'sp'::jsonb)#>>'{leaks,voids_n}', '1', 'voids counted');
select test.ok((select sum((x->>'avg_gross')::numeric) > 0 from jsonb_array_elements((:'sp'::jsonb)->'week_hours') x), 'by weekday and hour');
-- months: this month's sales without IVA
select public.trends_monthly(3) as tm \gset
select test.eq(jsonb_array_length((:'tm'::jsonb)->'months'), 3, 'three months');
select test.ok(((:'tm'::jsonb)#>>'{months,2,net}')::numeric >= 4000, 'this month: at least today''s sales without IVA');
select test.eq((:'tm'::jsonb)->>'labor_visible', 'true', 'the owner sees labor');
reset role;
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.trends_monthly(3)->>'error', 'not_allowed', 'a manager PIN alone does not open the numbers');
reset role;
update public.staff set can_see_sales = true where id = test.staff('ana');
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.trends_monthly(3)->>'labor_visible', 'false', 'a manager allowed to see sales sees the trends, without labor (pay rates are the owner''s)');
reset role;

-- stock forecast: milk used 1 000 ml a day for a week; 3 000 left; vendor delivers in 2 days
insert into public.vendors (id, name, lead_days) values ('5b000000-0000-4000-8000-000000002301', 'Lácteos', 2);
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, on_hand, par_level, vendor_id)
  values ('5a000000-0000-4000-8000-000000002301', 'Leche', 'ml', 1000, 1000, 10000, 8000, '5b000000-0000-4000-8000-000000002301');
insert into public.stock_moves (item_id, kind, qty, at)
  select '5a000000-0000-4000-8000-000000002301', 'sale', -1000, now() - make_interval(days => g) from generate_series(1, 7) g;
select on_hand as milk_left from public.stock_items where id = '5a000000-0000-4000-8000-000000002301' \gset
select test.eq(:'milk_left'::numeric, 3000::numeric, '3 000 ml left');
select test.login('owner', 'aal2'); set role authenticated;
select public.stock_forecast() as sf \gset
select test.eq((select x->>'status' || '|' || (x->>'days_left') from jsonb_array_elements((:'sf'::jsonb)->'items') x where x->>'name' = 'Leche'), 'soon|4.8',
               '625 ml a day (the week weighs as much as the month): 4.8 days left, order within 3 days');
select test.ok((select (x->>'suggest_packs')::int > 0 from jsonb_array_elements((:'sf'::jsonb)->'items') x where x->>'name' = 'Leche'), 'packs to order suggested');
select test.eq(public.supplier_insights(public.cr_today() - 30, public.cr_today())->>'ok', 'true', 'supplier insights');
reset role;

-- one location: everything belongs to today's café
select test.eq((select count(*)::int from public.locations), 1, 'one location');
select test.eq((select count(distinct location_id)::int from public.orders), 1, 'every sale in it');
select test.eq((select location_id::text from public.orders where id = '0d000000-0000-4000-8000-000000002302'), '10ca7100-0000-4000-8000-000000000001', 'new sales too');
select test.done();
rollback;
