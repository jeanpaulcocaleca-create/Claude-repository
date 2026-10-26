-- Migration 0032: no page can write the recipes table directly any more (old Inventory pages, a direct query); the only
-- way is the editor with a manager's or the owner's PIN. Reading, the POS and the kitchen are unchanged.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003601', 'Leche 0032', 'ml', 1000, 1000);
insert into public.menu_items (id, category_id, name, price_crc) values
  ('1b000000-0000-4000-8000-000000003601', 'a0000000-0000-4000-8000-000000000002', 'Borrar 0032', 1000);
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003601", "qty": 200, "unit": "ml"}]', 0,
                                  test.staff('ana'), '4826', null, gen_random_uuid())->>'ok', 'true', 'the editor with a PIN saves');
select test.eq(public.recipe_save('1b000000-0000-4000-8000-000000003601', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003601", "qty": 50, "unit": "ml"}]', 0,
                                  test.staff('ana'), '4826', null, gen_random_uuid())->>'ok', 'true', 'and a second product');
-- a café device with the manager's unlock, as an older Inventory page would write
select test.eq((select count(*) from public.recipes where menu_item_id = :'latte')::int, 1, 'it still reads recipes');
select test.throws($$delete from public.recipes where menu_item_id = (select id from public.menu_items where name = 'Latte')$$, 'permission denied',
                   'an older page''s delete is refused (it shows «could not save» and changes nothing)');
select test.throws($$insert into public.recipes (menu_item_id, stock_item_id, qty) select id, '5a000000-0000-4000-8000-000000003601', 1 from public.menu_items where name = 'Espresso'$$,
                   'permission denied', 'an insert too');
select test.throws($$update public.recipes set qty = 999 where menu_item_id = (select id from public.menu_items where name = 'Latte')$$, 'permission denied',
                   'an update too');
select test.throws($$select public.recipes_autolink()$$, 'permission denied', 'the old «link same-name items» without a PIN is gone');
select test.eq(public.recipes_autolink_pin(test.staff('ana'), '4826')->>'ok', 'true', 'the one with a PIN works');
reset role;
-- the owner with the phone code is no exception
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$update public.recipes set qty = 999 where menu_item_id = (select id from public.menu_items where name = 'Latte')$$, 'permission denied',
                   'the owner''s login cannot write it directly either');
select test.eq((select count(*) from public.recipes where menu_item_id = (select id from public.menu_items where name = 'Latte'))::int, 1, 'and reads it');
reset role;
select test.eq((select qty from public.recipes where menu_item_id = :'latte'), 200::numeric, 'the recipe is as the editor saved it');
select test.eq((select count(*) from public.recipe_versions where menu_item_id = :'latte')::int, 1, 'and nothing else was recorded');
-- deleting a product from the menu still takes its recipe with it, and the history keeps it
select test.login('owner', 'aal2'); set role authenticated;
select test.lives($$delete from public.menu_items where id = '1b000000-0000-4000-8000-000000003601'$$, 'the owner deletes a product with a recipe');
reset role;
select test.eq((select count(*) from public.recipes where menu_item_id = '1b000000-0000-4000-8000-000000003601')::int, 0, 'its recipe goes');
select test.eq((select source from public.recipe_versions where menu_item_id = '1b000000-0000-4000-8000-000000003601' order by version desc limit 1), 'deleted',
               'and the history says so');
-- the POS sells as before, without any unlock
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003601', 'total_crc', 2200, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))))->>'ok',
       'true', 'a sale is saved');
reset role;
select test.eq((select qty from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000003601'), -200::numeric, 'and takes its recipe');
select test.ok(not has_table_privilege('authenticated', 'public.recipes', 'insert') and not has_table_privilege('authenticated', 'public.recipes', 'update')
               and not has_table_privilege('authenticated', 'public.recipes', 'delete') and not has_table_privilege('authenticated', 'public.recipes', 'truncate')
               and has_table_privilege('authenticated', 'public.recipes', 'select') and not has_table_privilege('anon', 'public.recipes', 'select'),
               'the rights: read only, for signed-in pages');

-- the rollback gives the old rights back (and only that)
\o /dev/null
\ir ../../supabase/tools/reversion-0035.sql
\ir ../../supabase/tools/reversion-0034.sql
\ir ../../supabase/tools/reversion-0033.sql
\ir ../../supabase/tools/reversion-0032.sql
\o
select test.eq(public.canopy_schema_version(), 31, 'back at version 31');
select test.login('owner', 'aal2'); set role authenticated;
select test.lives($$update public.recipes set qty = 210 where menu_item_id = (select id from public.menu_items where name = 'Latte')$$,
                  'direct writes work again (as before 0032)');
reset role;
select test.eq((select source from public.recipe_versions where menu_item_id = :'latte' order by version desc limit 1), 'direct', 'and are recorded as direct');
select test.ok(has_function_privilege('authenticated', 'public.recipes_autolink()', 'execute'), 'the old link is back');
select test.done();
rollback;
