-- Migration 0030: recipes are saved in one step with a manager's PIN, every change is kept in recipe_versions,
-- writes from older pages are still recorded, and nothing in a sale changes.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
select id as espresso from public.menu_items where name = 'Espresso' \gset
select id as capu from public.menu_items where name = 'Cappuccino' \gset
select id as croissant from public.menu_items where name = 'Butter Croissant' \gset
select id as tea from public.menu_items where name = 'Tea' \gset

-- ingredients (owner with the phone code may add them, as the Stock tab does)
select test.login('owner', 'aal2'); set role authenticated;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, active) values
  ('5a000000-0000-4000-8000-000000003301', 'Café test', 'kg', 1, 10000, true),          -- ₡10 per g
  ('5a000000-0000-4000-8000-000000003302', 'Leche test', 'ml', 940, 940, true),         -- ₡1 per ml, a 940 ml carton
  ('5a000000-0000-4000-8000-000000003303', 'Butter Croissant', 'unit', 1, 600, true),   -- same name as a menu item
  ('5a000000-0000-4000-8000-000000003304', 'Sirope viejo', 'ml', 750, 3000, false),     -- inactive
  ('5a000000-0000-4000-8000-000000003305', 'Sin costo', 'g', 1000, 0, true),            -- no cost yet
  ('5a000000-0000-4000-8000-000000003306', 'Tea', 'g', 100, 1000, true),                -- same name, counted in grams
  ('5a000000-0000-4000-8000-000000003307', 'Azúcar test', 'g', 1000, 1000, true),
  ('5a000000-0000-4000-8000-000000003308', 'Leche litro', 'L', 1, 1000, true);           -- ₡1 per ml, counted in litres
reset role;

-- 1) the baseline: every recipe that exists gets version 1, once ------------------------------------------------------
set local session_replication_role = replica;      -- a recipe written before 0030 (no history trigger yet)
insert into public.recipes (menu_item_id, stock_item_id, qty) values (:'espresso', '5a000000-0000-4000-8000-000000003301', 0.018);
set local session_replication_role = origin;
select test.eq(canopy.recipe_baseline(), 1, 'the baseline records the recipe that existed');
select test.eq(canopy.recipe_baseline(), 0, 'running the baseline again adds nothing');
select test.eq((select source || ' v' || version from public.recipe_versions where menu_item_id = :'espresso'), 'baseline v1', 'it is version 1, labelled baseline');
select test.eq((select (lines->0->>'qty')::numeric from public.recipe_versions where menu_item_id = :'espresso'), 0.018::numeric, 'with the recipe''s line');

-- 2) who may save --------------------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[]', 0, test.staff('ana'), '4826', 'x', gen_random_uuid())->>'error', 'locked',
               'a café device without the manager unlock cannot save');
select test.eq((select count(*) from public.recipe_versions)::int, 0, 'and cannot read the history');
reset role;
select test.login('owner'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[]', 0, test.staff('dueno'), '7391', 'x', gen_random_uuid())->>'error', 'locked',
               'the owner login without the phone code cannot save either');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[]', 0, test.staff('ana'), '4826', 'x', gen_random_uuid())->>'error', 'locked', 'nor the accountant');
select test.eq((select count(*) from public.recipe_versions)::int, 0, 'who cannot read the history');
reset role;
select test.ok(not has_function_privilege('anon', 'public.recipe_save(uuid, jsonb, int, uuid, text, text, uuid)', 'execute'), 'anon cannot run recipe_save');
select test.ok(not has_function_privilege('anon', 'public.recipes_autolink_pin(uuid, text)', 'execute'), 'nor recipes_autolink_pin');

select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[]', 0, null, null, 'x', gen_random_uuid())->>'error', 'unknown_staff', 'unlocked, a save still needs a PIN');
select test.eq(public.recipe_save(:'latte', '[]', 0, test.staff('luis'), '5284', 'x', gen_random_uuid()) - 'x',
               '{"ok": false, "error": "not_manager", "step": "pin"}'::jsonb, 'a barista''s PIN is refused at the PIN step');
select test.eq(public.recipe_save(:'latte', '[]', 0, test.staff('ana'), '0000', 'x', gen_random_uuid())->>'error', 'bad_pin', 'a wrong PIN is refused');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 1, 'and the wrong try stays counted');
select test.eq((select count(*) from public.recipe_versions where menu_item_id = :'latte')::int, 0, 'nothing was saved by the refused tries');
select test.ok(not exists (select 1 from public.recipes where menu_item_id = :'latte'), 'and the recipe was not touched');

-- 3) a save: g on a kg item and ml on a carton item, converted to the stock unit, exact ----------------------------
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save(:'latte',
  '[{"stock_item_id": "5a000000-0000-4000-8000-000000003301", "qty": 18, "unit": "g"},
    {"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 280, "unit": "ml"}]', 0,
  test.staff('ana'), '4826', 'receta propuesta', '0f000000-0000-4000-8000-000000003301') as r1 \gset
select test.eq((:'r1'::jsonb)->>'ok', 'true', 'the manager''s PIN saves the recipe');
select test.eq(((:'r1'::jsonb)->>'version')::int, 1, 'as version 1');
select test.eq(((:'r1'::jsonb)->>'cost_crc')::numeric, 460.00, 'its cost: 18 g × ₡10 + 280 ml × ₡1');
select test.eq(((:'r1'::jsonb)->>'price_net_crc')::numeric, 1946.90, 'and the price without IVA (₡2 200 / 1.13)');
select test.eq((select count(*) from public.recipe_versions)::int, 2, 'an unlocked device reads the history');
reset role;
select test.eq((select qty from public.recipes where menu_item_id = :'latte' and stock_item_id = '5a000000-0000-4000-8000-000000003301'), 0.018::numeric,
               '18 g on an item counted in kg is stored as 0.018 kg');
select test.eq((select qty from public.recipes where menu_item_id = :'latte' and stock_item_id = '5a000000-0000-4000-8000-000000003302'), 280::numeric,
               '280 ml stays 280 ml');
select test.eq((select source || '|' || by_name || '|' || authorized_by::text || '|' || reason from public.recipe_versions where menu_item_id = :'latte' and version = 1),
               'editor|Ana|' || test.staff('ana')::text || '|receta propuesta', 'the version says who authorized it and why');
select test.eq((select (lines->0->>'entered_qty')::numeric || ' ' || (lines->0->>'entered_unit') from public.recipe_versions where menu_item_id = :'latte' and version = 1),
               '18 g', 'and what was typed');
select test.eq((select action || '|' || manager_name from public.audit_log where action = 'recipe_change' and target_id = :'latte'::text), 'recipe_change|Ana',
               'one line in the approvals log');
select test.ok(not exists (select 1 from public.audit_log where summary ~ '4826' or details::text ~ '4826') and not exists (select 1 from public.recipe_versions where lines::text ~ '4826' or coalesce(reason, '') ~ '4826'),
               'the PIN is never stored');
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 0, 'a right PIN clears the wrong tries');

-- the same request again, an old version, a missing version, nothing changed
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[]', 0, test.staff('ana'), '4826', 'x', '0f000000-0000-4000-8000-000000003301')->>'repeat', 'true',
               'a repeated request answers with what it already saved');
select test.eq(public.recipe_save(:'latte', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 300}]', 0,
                                  test.staff('ana'), '4826', null, gen_random_uuid()) - 'x', '{"ok": false, "error": "changed", "version": 1}'::jsonb,
               'a page that shows an older version is told the recipe changed');
select test.eq(public.recipe_save(:'latte', '[]', null, test.staff('ana'), '4826', 'x', gen_random_uuid())->>'error', 'bad_version', 'a save without a version is refused');
select test.eq(public.recipe_save(:'latte',
  '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 280, "unit": "ml"}, {"stock_item_id": "5a000000-0000-4000-8000-000000003301", "qty": 0.018, "unit": "kg"}]', 1,
  test.staff('ana'), '4826', null, gen_random_uuid())->>'unchanged', 'true', 'the same lines again are no new version');
reset role;
select test.eq((select count(*) from public.recipe_versions where menu_item_id = :'latte')::int, 1, 'so the Latte still has one version');

-- 4) every check, before anything is written ------------------------------------------------------------------------
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
create temp table t_bad (label text, lines jsonb, want text) on commit drop;
insert into t_bad values
  ('a duplicated ingredient', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 1}, {"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 2}]', 'duplicate'),
  ('a quantity of zero', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 0}]', 'bad_qty'),
  ('a negative quantity', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": -5}]', 'bad_qty'),
  ('a quantity that is text', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": "abc"}]', 'bad_qty'),
  ('NaN', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": "NaN"}]', 'bad_qty'),
  ('Infinity', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": "Infinity"}]', 'bad_qty'),
  ('an absurd quantity', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 20, "unit": "L"}]', 'too_much'),
  ('1e999', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": "1e999"}]', 'too_much'),
  ('ml on an item counted in kg', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003301", "qty": 18, "unit": "ml"}]', 'bad_unit'),
  ('an unknown unit', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003301", "qty": 18, "unit": "oz"}]', 'bad_unit'),
  ('an ingredient that does not exist', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000033ff", "qty": 1}]', 'unknown_item'),
  ('a line without an ingredient', '[{"qty": 1}]', 'bad_line'),
  ('a new line with an inactive ingredient', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003304", "qty": 15}]', 'inactive_item'),
  ('an empty recipe without a reason', '[]', 'empty_needs_reason'),
  ('31 lines', (select jsonb_agg(jsonb_build_object('stock_item_id', gen_random_uuid(), 'qty', 1)) from generate_series(1, 31)), 'too_many');
select test.eq(public.recipe_save(:'capu', b.lines, 0, test.staff('ana'), '4826', null, gen_random_uuid())->>'error', b.want, 'refused: ' || b.label) from t_bad b;
select test.eq(public.recipe_save(:'capu', '{"a": 1}', 0, test.staff('ana'), '4826', null, gen_random_uuid())->>'error', 'bad_request', 'refused: lines that are not a list');
reset role;
select test.ok(not exists (select 1 from public.recipes where menu_item_id = :'capu') and not exists (select 1 from public.recipe_versions where menu_item_id = :'capu'),
               'none of the refused saves wrote anything');

-- the other direction of the conversion: kg typed on an item counted in g, L typed on an item counted in ml;
-- and an empty recipe on purpose (with a reason)
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'capu',
  '[{"stock_item_id": "5a000000-0000-4000-8000-000000003307", "qty": 0.005, "unit": "kg"}, {"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 0.16, "unit": "L"},
    {"stock_item_id": "5a000000-0000-4000-8000-000000003308", "qty": 20, "unit": "ml"}, {"stock_item_id": "5a000000-0000-4000-8000-000000003305", "qty": 3}]', 0,
  test.staff('dueno'), '7391', null, gen_random_uuid())->'missing_cost', '["Sin costo"]'::jsonb, 'the owner''s PIN saves too; an ingredient without cost is named');
reset role;
select test.eq((select string_agg(s.name || '=' || r.qty::text, ' ' order by s.name) from public.recipes r join public.stock_items s on s.id = r.stock_item_id where r.menu_item_id = :'capu'),
               'Azúcar test=5 Leche litro=0.02 Leche test=160 Sin costo=3', 'kg → g ×1000, L → ml ×1000, ml → L ÷1000, exact');
select test.eq((select by_name from public.recipe_versions where menu_item_id = :'capu'), 'Dueño', 'the owner''s name is on that version');
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'capu', '[]', 1, test.staff('ana'), '4826', 'ya no se vende', gen_random_uuid())->>'version', '2', 'an empty recipe with a reason is saved');
-- an ingredient that became inactive may stay in a recipe that already has it
update public.stock_items set active = false where id = '5a000000-0000-4000-8000-000000003307';
select test.eq(public.recipe_save(:'capu', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 160}]', 2, test.staff('ana'), '4826', null, gen_random_uuid())->>'version', '3',
               'version numbers go on after refusals');
reset role;
select test.ok((select bool_and(a < b) from (select at as a, lead(at) over (order by version) as b from public.recipe_versions where menu_item_id = :'capu') q where b is not null),
               'each version has its own moment, even inside one transaction');

-- 5) sales: what was sold before keeps what it took; what is sold after takes the new recipe --------------------------
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003301', 'total_crc', 4400, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Latte', 'price_crc', 2200, 'qty', 2, 'menu_item_id', :'latte'))));
reset role;
select test.eq((select string_agg(m.qty::text || '@' || m.unit_cost::text, ' ' order by m.qty) from public.stock_moves m where m.order_id = '0d000000-0000-4000-8000-000000003301'),
               '-560@1.0000 -0.036@10000.0000', 'a sale takes 2 × the saved recipe (0.036 kg of coffee, 560 ml of milk) at the average cost');
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipe_save(:'latte', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003301", "qty": 20, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 250}]',
                                  1, test.staff('ana'), '4826', 'ajuste', gen_random_uuid())->>'version', '2', 'the recipe changes');
reset role;
select test.eq((select string_agg(m.qty::text, ' ' order by m.qty) from public.stock_moves m where m.order_id = '0d000000-0000-4000-8000-000000003301'),
               '-560 -0.036', 'the earlier sale keeps exactly what it took');
select test.eq((select cost_before_crc::text || ' → ' || cost_crc::text from public.recipe_versions where menu_item_id = :'latte' and version = 2), '460.00 → 450.00',
               'the history shows the cost before and after');
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003302', 'total_crc', 2200, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))));
reset role;
select test.eq((select string_agg(m.qty::text, ' ' order by m.qty) from public.stock_moves m where m.order_id = '0d000000-0000-4000-8000-000000003302'),
               '-250 -0.02', 'a later sale takes the new recipe');
-- a purchase moves the average cost; the version keeps the cost it had
select test.login('owner', 'aal2'); set role authenticated;
select public.stock_receive('5a000000-0000-4000-8000-000000003302', 940, 3);
reset role;
select test.eq((select cost_crc from public.recipe_versions where menu_item_id = :'latte' and version = 2), 450.00, 'a version''s cost does not move with later prices');
select test.eq((select count(*) from public.recipe_versions where menu_item_id = :'latte')::int, 2, 'and a purchase is not a recipe change');

-- 6) the history catches writes that do not go through recipe_save ------------------------------------------------
-- an older page: delete, then insert, as two requests
select test.login('owner', 'aal2'); set role authenticated;
delete from public.recipes where menu_item_id = :'espresso';
insert into public.recipes (menu_item_id, stock_item_id, qty) values (:'espresso', '5a000000-0000-4000-8000-000000003301', 0.02);
reset role;
select test.eq((select string_agg(source || ':' || jsonb_array_length(lines), ' ' order by version) from public.recipe_versions where menu_item_id = :'espresso'),
               'baseline:1 direct:0 direct:1', 'an older page''s save is recorded as two direct changes');
select test.eq((select by_name from public.recipe_versions where menu_item_id = :'espresso' and version = 3), 'owner login · owner@test.local', 'with who was signed in');
-- a write that changes nothing adds nothing
select test.login('owner', 'aal2'); set role authenticated;
update public.recipes set qty = 0.020 where menu_item_id = :'espresso';
reset role;
select test.eq((select count(*) from public.recipe_versions where menu_item_id = :'espresso')::int, 3, 'a write that changes nothing adds no version');
-- a direct write after a recipe_save in the same transaction is still recorded
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save(:'espresso', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003301", "qty": 19, "unit": "g"}]', 3, test.staff('ana'), '4826', null, gen_random_uuid());
update public.recipes set qty = 0.021 where menu_item_id = :'espresso';
reset role;
select test.eq((select string_agg(source, ' ' order by version) from public.recipe_versions where menu_item_id = :'espresso' and version > 3), 'editor direct',
               'a direct write right after a save is recorded too');
-- a line moved to another product: both products get a version
select max(id) as before_move from public.recipe_versions \gset
update public.recipes set menu_item_id = :'tea' where menu_item_id = :'espresso';
select test.eq((select count(*) from public.recipe_versions where menu_item_id in (:'tea', :'espresso') and source = 'direct' and id > :before_move)::int, 2,
               'moving a line to another product records both products');
-- the old "Link same-name items" button
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipes_autolink()->>'ok', 'true', 'the old autolink still works');
reset role;
select test.eq((select source || '|' || (lines->0->>'name') from public.recipe_versions where menu_item_id = :'croissant'), 'direct|Butter Croissant',
               'and what it linked is in the history');
-- the new one needs a PIN, links only items counted by unit, and says who did it
select test.login('owner', 'aal2'); set role authenticated;
delete from public.recipes where menu_item_id in (:'croissant', :'tea');
reset role;
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.recipes_autolink_pin(test.staff('luis'), '5284')->>'error', 'not_manager', 'the PIN autolink refuses a barista');
select test.eq(public.recipes_autolink_pin(test.staff('ana'), '4826')->>'linked', '1', 'it links the croissant only (the tea is counted in grams)');
reset role;
select test.eq((select source || '|' || by_name from public.recipe_versions where menu_item_id = :'croissant' order by version desc limit 1), 'autolink|Ana', 'recorded as Ana''s autolink');
select test.ok(not exists (select 1 from public.recipes where menu_item_id = :'tea'), 'a gram item is never linked at 1 g');

-- deleting a product from the menu: its recipe history stays, with its name
insert into public.menu_items (id, name, price_crc, category_id)
  select '3e000000-0000-4000-8000-000000003301', 'Prueba borrar', 1000, category_id from public.menu_items where id = :'latte';
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('3e000000-0000-4000-8000-000000003301', '[{"stock_item_id": "5a000000-0000-4000-8000-000000003302", "qty": 100}]', 0,
                          test.staff('ana'), '4826', null, gen_random_uuid());
reset role;
select test.login('owner', 'aal2'); set role authenticated;
delete from public.menu_items where id = '3e000000-0000-4000-8000-000000003301';
reset role;
select test.eq((select string_agg(source || ':' || menu_item_name || ':' || jsonb_array_length(lines), ' ' order by version) from public.recipe_versions
                 where menu_item_id = '3e000000-0000-4000-8000-000000003301'), 'editor:Prueba borrar:1 deleted:Prueba borrar:0',
               'deleting a product keeps its versions and adds a "deleted" one with its name');
-- renaming a product is not a recipe change
update public.menu_items set name = 'Latte' where id = :'latte';
select test.eq((select count(*) from public.recipe_versions where menu_item_id = :'latte')::int, 2, 'renaming a product adds no version');

-- 7) the history cannot be changed, and only an open inventory reads it --------------------------------------------
select test.throws('update public.recipe_versions set reason = ''x''', 'recipe_versions_immutable', 'a version cannot be changed, even by the table owner');
select test.throws('delete from public.recipe_versions', 'recipe_versions_immutable', 'nor deleted');
select test.throws('truncate public.recipe_versions', 'recipe_versions_immutable', 'nor emptied');
select test.ok(not has_table_privilege('authenticated', 'public.recipe_versions', 'insert') and not has_table_privilege('authenticated', 'public.recipe_versions', 'update')
               and not has_table_privilege('authenticated', 'public.recipe_versions', 'delete') and not has_table_privilege('authenticated', 'public.recipe_versions', 'truncate'),
               'the pages can only read the history');
select test.ok(not has_table_privilege('anon', 'public.recipe_versions', 'select'), 'anon cannot read it');
select test.ok(has_table_privilege('canopy_backup', 'public.recipe_versions', 'select'), 'the backup account reads it');

-- 8) an ingredient keeps its unit once it has moves or recipes, and is not deleted while it is in a recipe ------------
insert into public.recipes (menu_item_id, stock_item_id, qty) values (:'tea', '5a000000-0000-4000-8000-000000003305', 2);   -- in a recipe, no moves
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$update public.stock_items set unit = 'g' where id = '5a000000-0000-4000-8000-000000003301'$$, 'unit_locked', 'an item with moves keeps its unit');
select test.throws($$update public.stock_items set unit = 'kg' where id = '5a000000-0000-4000-8000-000000003305'$$, 'unit_locked', 'an item that is only in a recipe keeps its unit too');
select test.lives($$update public.stock_items set unit = 'ml', name = 'Leche test' where id = '5a000000-0000-4000-8000-000000003302'$$, 'saving an item with its same unit still works');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003309', 'Nuevo', 'g', 1, 1);
select test.lives($$update public.stock_items set unit = 'kg' where id = '5a000000-0000-4000-8000-000000003309'$$, 'a new item without moves or recipes can change unit');
select test.throws($$delete from public.stock_items where id = '5a000000-0000-4000-8000-000000003305'$$, 'stock_item_in_recipe_history', 'an item in a recipe cannot be deleted (the old page reads "history": it is kept)');
select test.lives($$delete from public.stock_items where id = '5a000000-0000-4000-8000-000000003309'$$, 'an unused item can still be deleted');
select test.throws($$select public._stock_item_in_use('5a000000-0000-4000-8000-000000003305')$$, 'solo desde el disparador', 'the in-use check answers only its trigger, not the API');
reset role;
-- the history catches up with a change made while it was not running (0030 rolled back, then applied again)
select max(version) as tea_v from public.recipe_versions where menu_item_id = :'tea' \gset
set session_replication_role = replica;      -- no triggers: like a database between the rollback and the second apply
update public.recipes set qty = 3 where menu_item_id = :'tea' and stock_item_id = '5a000000-0000-4000-8000-000000003305';
set session_replication_role = origin;
select test.eq((select max(version) from public.recipe_versions where menu_item_id = :'tea'), :tea_v, 'nothing recorded while the triggers were off');
select canopy.recipe_baseline();
select test.eq((select source || ':' || reason || ':' || (lines->0->>'qty') from public.recipe_versions where menu_item_id = :'tea' and version = :tea_v + 1),
               'direct:cambio sin historial (anotado al aplicar la 0030):3', 'applying the migration again records the change as direct');
select test.eq((select cost_before_crc from public.recipe_versions where menu_item_id = :'tea' and version = :tea_v + 1),
               (select public._recipe_cost(public._recipe_recost(lines)) from public.recipe_versions where menu_item_id = :'tea' and version = :tea_v),
               'its cost before is the previous recipe at today''s costs');
select canopy.recipe_baseline();
select test.eq((select max(version) from public.recipe_versions where menu_item_id = :'tea'), :tea_v + 1, 'running the baseline again adds nothing');
select test.login('owner', 'aal2'); set role authenticated;
reset role;

-- 9) the inventory's ingredient cost: what was used at the cost it went out with; sales without IVA ----------------
select test.login('owner', 'aal2'); set role authenticated;
select public.inventory_food_cost(30) as fc1 \gset
update public.stock_items set cost_per_pack = 94000 where id = '5a000000-0000-4000-8000-000000003302';   -- a price typed on the page
select test.eq((public.inventory_food_cost(30)->>'usage_cost')::numeric, ((:'fc1'::jsonb)->>'usage_cost')::numeric,
               'editing a price does not change what past sales cost');
reset role;
select test.eq(((:'fc1'::jsonb)->>'revenue_net_crc')::numeric, (select round(sum(public._order_net(o))) from public.orders o where o.created_at >= now() - interval '30 days'
                                                         and o.voided_at is null and coalesce(o.paid, true) and coalesce(o.status, 'done') <> 'cancelled'),
               'sales are counted without IVA');
select test.ok(((:'fc1'::jsonb)->>'revenue_net_crc')::numeric < 6600, 'so they are below the ₡6 600 charged');
select test.eq(((:'fc1'::jsonb)->>'revenue')::numeric, 6600::numeric, 'and what was charged stays as before, for the page published today');

-- 10) one cost: an ingredient priced on the page but never received sells at that price, not at ₡0 ---------------------
select test.login('owner', 'aal2'); set role authenticated;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003310', 'Mango congelado', 'g', 1000, 0);
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000003310'), null::numeric, 'created without a price: no average yet');
update public.stock_items set cost_per_pack = 3000 where id = '5a000000-0000-4000-8000-000000003310';
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000003310'), 3.0000, 'the price typed on the page becomes its cost');
insert into public.recipes (menu_item_id, stock_item_id, qty) values (:'tea', '5a000000-0000-4000-8000-000000003310', 150);
reset role;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003310', 'total_crc', 1500, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Tea', 'price_crc', 1500, 'qty', 1, 'menu_item_id', :'tea'))));
reset role;
select test.eq((select unit_cost from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000003310' and item_id = '5a000000-0000-4000-8000-000000003310'),
               3.0000, 'its sale is stamped at that cost (Insights and the books see the same)');
insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('5a000000-0000-4000-8000-000000003310', 'purchase', 1000, 5);
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000003310'), 5.0000, 'the first delivery sets the average');
select test.login('owner', 'aal2'); set role authenticated;
update public.stock_items set cost_per_pack = 9000 where id = '5a000000-0000-4000-8000-000000003310';
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000003310'), 5.0000, 'once received, a price typed later leaves the average alone');
reset role;

-- 11) five wrong PINs lock the manager out, as on every PIN screen (last: it locks Rosa) --------------------------------
insert into public.staff (id, name, role, active, pin_hash) values ('a1000000-0000-4000-8000-000000003301', 'Rosa', 'manager', true, extensions.crypt('1357', extensions.gen_salt('bf')));
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save(:'latte', '[]', 2, 'a1000000-0000-4000-8000-000000003301', '9999', 'x', gen_random_uuid()) from generate_series(1, 5);
select test.eq(public.recipe_save(:'latte', '[]', 2, 'a1000000-0000-4000-8000-000000003301', '1357', 'x', gen_random_uuid())->>'error', 'locked',
               'after five wrong PINs the right one is refused for 10 minutes');
reset role;
select test.eq((select failed_pins from public.staff where id = 'a1000000-0000-4000-8000-000000003301'), 5, 'all five tries were counted');

select test.done();
rollback;
