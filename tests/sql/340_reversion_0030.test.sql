-- supabase/tools/reversion-0030.sql: undoes migration 0030 and leaves every changed function exactly as it was
-- (same fingerprint as in supabase/tools/production-snapshot.sql); the recipe history stays and sales keep working.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
select test.login('owner', 'aal2'); set role authenticated;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003401', 'Leche rev', 'ml', 1000, 1000);
reset role;
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003401", "qty": 200}]', 0,
                                  test.staff('ana'), '4826', null, gen_random_uuid())->>'ok', 'true', 'a recipe saved with 0030');
reset role;
select count(*) as versions_before from public.recipe_versions \gset

-- after 0030 come 0031, 0032 and 0033: they are reverted first (newest first)
\o /dev/null
\ir ../../supabase/tools/reversion-0033.sql
\ir ../../supabase/tools/reversion-0032.sql
\ir ../../supabase/tools/reversion-0031.sql
\o
\ir ../../supabase/tools/reversion-0030.sql

select test.eq(public.canopy_schema_version(), 29, 'the database is back at version 29');
select test.ok(to_regprocedure('public.recipe_save(uuid, jsonb, integer, uuid, text, text, uuid)') is null
               and to_regprocedure('public.recipes_autolink_pin(uuid, text)') is null, 'recipe_save and the PIN autolink are gone');
select test.eq((select count(*) from pg_trigger where tgrelid = 'public.recipes'::regclass and not tgisinternal)::int, 0, 'no history trigger is left on recipes');
select test.eq((select left(md5(prosrc), 12) from pg_proc where oid = 'public._stock_items_protect()'::regprocedure), 'cbdd30f782c8',
               '_stock_items_protect is exactly the 0005 version');
select test.eq((select left(md5(prosrc), 12) from pg_proc where oid = 'public._stock_item_history_guard()'::regprocedure), '5bbc67df2530',
               '_stock_item_history_guard is exactly the 0005 version');
select test.eq((select left(md5(prosrc), 12) from pg_proc where oid = 'public.inventory_food_cost(integer)'::regprocedure), '25617b0ee225',
               'inventory_food_cost is exactly the version before 0030');
select test.eq((select count(*) from public.recipe_versions), :versions_before::bigint, 'the recipe history is kept');
select test.throws('delete from public.recipe_versions', 'recipe_versions_immutable', 'and still cannot be deleted');
select test.eq((select qty from public.recipes where menu_item_id = :'latte'), 200::numeric, 'the recipe itself is untouched');

-- sales keep working, and a direct write no longer adds a version
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003401', 'total_crc', 2200, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))));
reset role;
select test.eq((select qty from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000003401'), -200::numeric, 'a sale still takes its recipe');
update public.recipes set qty = 210 where menu_item_id = :'latte';
select test.eq((select count(*) from public.recipe_versions), :versions_before::bigint, 'after the rollback a recipe write adds no version');
select test.login('owner', 'aal2'); set role authenticated;
select test.lives($$update public.stock_items set unit = 'L' where id = '5a000000-0000-4000-8000-000000003401'$$, 'the unit guard is gone again');
reset role;

select test.done();
rollback;
