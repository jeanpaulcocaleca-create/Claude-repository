-- supabase/tools/reversion-0031.sql (after reversion-0032.sql): every changed function exactly as it was (the production
-- snapshot's fingerprints), the history and the new columns kept, and a bill with an exact return made under 0031
-- still nets to zero when it is voided after the rollback.
begin;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003701', 'Leche 0031r', 'ml', 1000, 1000);
insert into public.menu_items (id, category_id, name, price_crc) values
  ('1b000000-0000-4000-8000-000000003701', 'a0000000-0000-4000-8000-000000000002', 'Leche fría 0031r', 1000);
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000003701', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003701", "qty": 200, "unit": "ml"}]', 0,
                          test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
-- an open bill: 3 glasses; one taken off under 0031
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003701', 'total_crc', 4000, 'payment_method', 'cash_crc',
       'paid', false, 'status', 'preparing', 'source', 'front',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-000000003701', 'item_name', 'Leche fría 0031r', 'price_crc', 1000, 'qty', 3,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000003701'),
                                  jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Espresso', 'price_crc', 1000, 'qty', 1))));
select test.eq(public.tab_remove_item('0e000000-0000-4000-8000-000000003701', 1, '', 'Caja', null, null, 4000)->>'ok', 'true', 'one glass taken off under 0031');
reset role;
select test.eq((select sum(qty) from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000003701'), -400::numeric, 'two glasses are out');

\o /dev/null
\ir ../../supabase/tools/reversion-0032.sql
\ir ../../supabase/tools/reversion-0031.sql
\o
select test.eq(public.canopy_schema_version(), 30, 'the database is back at version 30');
select test.eq((select string_agg(left(md5(p.prosrc), 12), ' ' order by p.oid::regprocedure::text) from pg_proc p
                 where p.oid in ('public._order_item_stock()'::regprocedure, 'public._order_item_menu_id()'::regprocedure,
                                 'public._order_tab_voided()'::regprocedure, 'public._stock_item_history_guard()'::regprocedure,
                                 'public.tab_remove_item(uuid, integer, text, text, uuid, text, integer)'::regprocedure,
                                 'public.tab_add_items(uuid, jsonb, uuid)'::regprocedure)),
               (select string_agg(h, ' ' order by f) from (values ('_order_item_menu_id()', 'af97466b5730'), ('_order_item_stock()', 'cbaf16f92c9e'),
                                                                   ('_order_tab_voided()', 'fd89be0c85e3'), ('_stock_item_history_guard()', '01817a884d3a'),
                                                                   ('tab_add_items(uuid,jsonb,uuid)', '490bbe32667f'),
                                                                   ('tab_remove_item(uuid,integer,text,text,uuid,text,integer)', 'a71dbc39ee31')) x(f, h)),
               'the six functions are exactly as before 0031 (0004, supabase/pos-tabs.sql, 0030)');
select test.ok(to_regprocedure('public._order_line_return(uuid, uuid, text, boolean, integer, integer, text)') is null
               and to_regprocedure('public._stock_cost_at(uuid, timestamptz)') is null
               and to_regprocedure('public._sale_unit_cost(numeric, numeric, numeric)') is null
               and to_regprocedure('public._stock_cost_log()') is null, 'the new functions are gone');
select test.eq((select count(*) from pg_trigger where tgrelid = 'public.stock_items'::regclass and tgname = 'stock_items_cost_log')::int, 0, 'and the cost trigger');
select test.ok(to_regclass('canopy.stock_cost_history') is not null
               and exists (select 1 from information_schema.columns where table_name = 'stock_moves' and column_name = 'order_item_id'),
               'the cost history and the new columns stay');
select test.ok(has_function_privilege('authenticated', 'public.recipes_autolink()', 'execute')
               and has_table_privilege('authenticated', 'public.recipes', 'delete'), 'the recipes rights are as before 0032');
-- the bill voided after the rollback: the old return mirrors every sale row, the exact return of 0031 included
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000003701', 'cerró')->>'ok', 'true', 'the bill is voided');
reset role;
select test.eq((select coalesce(sum(qty), 0) from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000003701'), 0::numeric,
               'and nets to zero: nothing returned twice, nothing left out');
-- sales keep working the old way
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003702', 'total_crc', 1000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Leche fría 0031r', 'price_crc', 1000, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000003701'))));
reset role;
select test.eq((select qty || ':' || (order_item_id is null)::text from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000003702'),
               '-200:true', 'a sale still takes its recipe (without the line link, as before 0031)');
-- and 0030's rollback is possible again
select test.eq((select count(*) from canopy.migrations where version > 30)::int, 0, 'nothing after 0030 is left');
select test.done();
rollback;
