-- Migration 0031: a sale takes the recipe and the cost in force when it was rung (also when it reaches the server
-- later), and what is taken off a bill goes back exactly as it went out.
begin;
-- products of this test (a category of the seed), and ingredients at a known price (no average yet: the last price)
insert into public.menu_items (id, category_id, name, price_crc) values
  ('1b000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003', 'Batido 1B', 3000),
  ('1b000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'Te 1B', 1500),
  ('1b000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000002', 'Chai 1B', 2000),
  ('1b000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000002', 'Renombrar 1B', 1800),
  ('1b000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000002', 'Borrar 1B', 1800),
  ('1b000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000002', 'Canela 1B', 1800),
  ('1b000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000002', 'Sin historia 1B', 1800);
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values
  ('5a000000-0000-4000-8000-0000000b0001', 'Fresa 1B', 'g', 1000, 4000),     -- ₡4 per g
  ('5a000000-0000-4000-8000-0000000b0002', 'Leche 1B', 'ml', 1000, 1000),    -- ₡1 per ml
  ('5a000000-0000-4000-8000-0000000b0003', 'Canela 1B', 'g', 100, 500),      -- ₡5 per g
  ('5a000000-0000-4000-8000-0000000b0004', 'Té 1B', 'g', 100, 1000);         -- ₡10 per g
-- the net of what an order took per ingredient (minus = out of stock)
create function pg_temp.net(p_order uuid) returns text language sql as $$
  select coalesce(string_agg(s.name || '=' || trim_scale(x.q)::text, ' ' order by s.name), '')
    from (select item_id, sum(qty) as q from public.stock_moves where order_id = p_order group by item_id) x
    join public.stock_items s on s.id = x.item_id where x.q <> 0;
$$;
create function pg_temp.moves(p_order uuid) returns text language sql as $$
  select coalesce(string_agg(s.name || ':' || trim_scale(m.qty)::text || '@' || trim_scale(m.unit_cost)::text, ' ' order by m.id), '')
    from public.stock_moves m join public.stock_items s on s.id = m.item_id where m.order_id = p_order;
$$;
-- move a product's history (and the ingredients' costs) back in time, as if saved hours ago (tests only)
create function pg_temp.age(p_menu uuid, p_version int, p_hours int) returns void language sql as $$
  update public.recipe_versions set at = now() - make_interval(hours => p_hours) where menu_item_id = p_menu and version = p_version;
$$;

-- 1) a sale kept on the device and sent later takes the recipe and the cost of when it was rung ---------------------
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000001',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0001", "qty": 120, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 100, "unit": "ml"}]',
  0, test.staff('ana'), '4826', null, gen_random_uuid()) \gset r1_
reset role;
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-000000000001', 1, 3);
update canopy.stock_cost_history set at = now() - interval '3 hours';
set local session_replication_role = origin;
-- an hour ago the recipe changed (150 g of strawberries) and dearer strawberries arrived
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000001',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0001", "qty": 150, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 100, "unit": "ml"}]',
  1, test.staff('ana'), '4826', null, gen_random_uuid()) \gset r2_
reset role;
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-000000000001', 2, 1);
set local session_replication_role = origin;
insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('5a000000-0000-4000-8000-0000000b0001', 'purchase', 5000, 6);
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-0000000b0001'), 6.0000, 'strawberries now cost ₡6 per g');
-- rung two hours ago without internet, sent now
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0101', 'created_at', now() - interval '2 hours',
       'total_crc', 6000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0101', 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 2,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0101'), 'Fresa 1B:-240@4 Leche 1B:-200@1',
               'two smoothies rung before the change: 120 g each at ₡4, not 150 g at ₡6');
select test.eq((select v.version from public.order_items i join public.recipe_versions v on v.id = i.recipe_version_id
                 where i.id = '0e000000-0000-4000-8000-0000000b0101'), 1, 'the line says which version it took');
select test.ok((select abs(extract(epoch from i.stock_time - o.created_at)) < 1 from public.order_items i join public.orders o on o.id = i.order_id
                 where i.id = '0e000000-0000-4000-8000-0000000b0101'), 'and the moment: when it was rung, not when it arrived');
select test.eq((select count(*) from public.stock_moves where order_id = '0d000000-0000-4000-8000-0000000b0101'
                 and order_item_id = '0e000000-0000-4000-8000-0000000b0101' and line_qty = 2)::int, 2, 'each movement names its line and its units');
-- the same sale through an older page's two-step save (the order, then its lines without the product id)
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method) values ('0d000000-0000-4000-8000-0000000b0102', now() - interval '2 hours', 3000, 'card');
-- (a moment of its own for the line is never before its order: ten hours ago is the order's time)
insert into public.order_items (id, order_id, item_name, price_crc, qty, stock_time)
  values ('0e000000-0000-4000-8000-0000000b0102', '0d000000-0000-4000-8000-0000000b0102', 'Batido 1B', 3000, 1, now() - interval '10 hours');
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0102'), 'Fresa 1B:-120@4 Leche 1B:-100@1', 'an older page''s two-step save too');
select test.ok((select i.stock_time = o.created_at from public.order_items i join public.orders o on o.id = i.order_id
                 where i.id = '0e000000-0000-4000-8000-0000000b0102'), 'at the time of its order');
-- rung now: today's recipe at today's cost (as before 0031)
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0103', 'total_crc', 3000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0103', 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0103'), 'Fresa 1B:-150@6 Leche 1B:-100@1', 'a sale rung now: 150 g at ₡6');
select test.eq((select v.version from public.order_items i join public.recipe_versions v on v.id = i.recipe_version_id
                 where i.id = '0e000000-0000-4000-8000-0000000b0103'), 2, 'version 2');
-- a device whose clock is ahead is taken as now
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0104', 'created_at', now() + interval '30 minutes',
       'total_crc', 3000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0104'), 'Fresa 1B:-150@6 Leche 1B:-100@1', 'a clock ahead counts as now');
select test.ok((select bool_and(i.stock_time <= clock_timestamp() and i.stock_time < o.created_at) from public.order_items i join public.orders o on o.id = i.order_id
                 where i.order_id = '0d000000-0000-4000-8000-0000000b0104'), 'its moment is now, not the device''s time ahead');
-- items added on the device to an order before it was ever sent go up with it (pos_record_sale), each with its time
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0106', 'created_at', now() - interval '2 hours',
       'total_crc', 9000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001'),
                                  jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 2,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001', 'at', now() - interval '30 minutes'),
                                  jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 3,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001', 'at', 'no es una hora'),
                                  jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 4,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001', 'at', now() + interval '1 hour'))));
reset role;
select test.eq((select string_agg(trim_scale(m.qty)::text || '@' || trim_scale(m.unit_cost)::text, ' ' order by i.qty, m.item_id)
                  from public.stock_moves m join public.order_items i on i.id = m.order_item_id
                 where m.order_id = '0d000000-0000-4000-8000-0000000b0106'),
               '-120@4 -100@1 -300@4 -200@1 -360@4 -300@1 -600@6 -400@1',
               'rung 2 h ago: 120 g; added 30 min ago: the new recipe (150 g) at the cost then (₡4); an unreadable time: the order''s; a clock ahead: now (₡6); and the sale is kept');
select test.ok((select bool_and(stock_time >= now()) from public.order_items where order_id = '0d000000-0000-4000-8000-0000000b0106' and qty = 4),
               'the item added with the clock ahead has the moment of its arrival');
-- items added on the device to an order that was still there, sent after it (tab_add_items with the time of each):
-- the recipe and cost of when they were added; never before the order, never after now; a time that does not read is now
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0105', 'created_at', now() - interval '2 hours',
       'total_crc', 1500, 'payment_method', 'cash_crc', 'paid', false, 'status', 'preparing', 'source', 'front',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000002'))));
select test.eq(public.tab_add_items('0d000000-0000-4000-8000-0000000b0105', jsonb_build_array(
         jsonb_build_object('menu_item_id', '1b000000-0000-4000-8000-000000000001', 'qty', 1, 'at', now() - interval '90 minutes'),
         jsonb_build_object('menu_item_id', '1b000000-0000-4000-8000-000000000001', 'qty', 2, 'at', now() - interval '5 hours'),
         jsonb_build_object('menu_item_id', '1b000000-0000-4000-8000-000000000001', 'qty', 3, 'at', 'ayer'),
         jsonb_build_object('menu_item_id', '1b000000-0000-4000-8000-000000000001', 'qty', 4, 'at', now() + interval '1 hour')), gen_random_uuid())->>'ok',
               'true', 'four items added, each with its time');
reset role;
select test.eq((select string_agg(trim_scale(m.qty)::text || '@' || trim_scale(m.unit_cost)::text, ' ' order by i.qty, m.item_id)
                  from public.stock_moves m join public.order_items i on i.id = m.order_item_id
                 where m.order_id = '0d000000-0000-4000-8000-0000000b0105'),
               '-120@4 -100@1 -240@4 -200@1 -450@6 -300@1 -600@6 -400@1',
               'added 90 min ago: 120 g at ₡4; before the order: the order''s time; unreadable or ahead: now (150 g at ₡6)');
-- an add whose reply was lost and is sent again days later (the device was offline): still the same add, not a second one
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_add_items('0d000000-0000-4000-8000-0000000b0105', '[{"menu_item_id": "1b000000-0000-4000-8000-000000000002", "qty": 1}]',
                                    'ad000000-0000-4000-8000-0000000b0105')->>'ok', 'true', 'an add with its own id');
reset role;
update public.tab_adds set at = now() - interval '3 days' where id = 'ad000000-0000-4000-8000-0000000b0105';
select count(*) as lines_before from public.order_items where order_id = '0d000000-0000-4000-8000-0000000b0105' \gset
select test.login('cafe'); set role authenticated;
select public.tab_add_items('0d000000-0000-4000-8000-0000000b0105', '[{"menu_item_id": "1b000000-0000-4000-8000-000000000002", "qty": 1}]', gen_random_uuid())->>'ok';
select test.eq(public.tab_add_items('0d000000-0000-4000-8000-0000000b0105', '[{"menu_item_id": "1b000000-0000-4000-8000-000000000002", "qty": 1}]',
                                    'ad000000-0000-4000-8000-0000000b0105')->>'repeat', 'true', 'the same add sent again three days later is recognised');
reset role;
select test.eq((select count(*) from public.order_items where order_id = '0d000000-0000-4000-8000-0000000b0105')::int, :lines_before + 1, 'only the other add went in');

-- 2) rung before the history began: the starting version; a product whose first recipe came later: nothing ----------
set local session_replication_role = replica;     -- a recipe from before 0030
insert into public.recipes (menu_item_id, stock_item_id, qty) values ('1b000000-0000-4000-8000-000000000002', '5a000000-0000-4000-8000-0000000b0004', 2);
set local session_replication_role = origin;
select canopy.recipe_baseline();
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-000000000002', 1, 1);
set local session_replication_role = origin;
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000002', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 3, "unit": "g"}]',
                          1, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
select public.recipe_save('1b000000-0000-4000-8000-000000000003', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 5, "unit": "g"}]',
                          0, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0201', 'created_at', now() - interval '3 hours',
       'total_crc', 3500, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0201', 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000002'),
                                  jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0202', 'item_name', 'Chai 1B', 'price_crc', 2000, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000003'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0201'), 'Té 1B:-2@10',
               'rung before the history began: the starting version (2 g); the chai had no recipe yet: nothing');
select test.eq((select string_agg(coalesce(recipe_version_id::text, 'none') || ':' || (stock_time is not null)::text, ' ' order by item_name)
                  from public.order_items where order_id = '0d000000-0000-4000-8000-0000000b0201'),
               'none:true ' || (select id from public.recipe_versions where menu_item_id = '1b000000-0000-4000-8000-000000000002' and version = 1) || ':true',
               'the chai line has no version, the tea line the starting one; both have their moment');
select test.ok((select 'stock_not_taken' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-0000000b0201'),
               'the chai has a recipe today but had none then: nothing taken, and the sale is marked for a manager');
-- a product with no history at all: today's recipe (as before)
set local session_replication_role = replica;
insert into public.recipes (menu_item_id, stock_item_id, qty) values ('1b000000-0000-4000-8000-000000000007', '5a000000-0000-4000-8000-0000000b0004', 4);
set local session_replication_role = origin;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0203', 'created_at', now() - interval '3 hours',
       'total_crc', 1800, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Sin historia 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000007'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0203'), 'Té 1B:-4@10', 'a product with no history: today''s recipe');
select test.ok((select not ('stock_not_taken' = any(flags)) from public.orders where id = '0d000000-0000-4000-8000-0000000b0203'), 'and nothing to check');

-- 3) a product renamed, or deleted from the menu, while the device was offline -------------------------------------
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000004', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 6, "unit": "g"}]',
                          0, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
select public.recipe_save('1b000000-0000-4000-8000-000000000005', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 7, "unit": "g"}]',
                          0, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-000000000004', 1, 3);
select pg_temp.age('1b000000-0000-4000-8000-000000000005', 1, 3);
set local session_replication_role = origin;
update public.menu_items set name = 'Renombrado 1B' where id = '1b000000-0000-4000-8000-000000000004';
delete from public.menu_items where id = '1b000000-0000-4000-8000-000000000005';
select test.eq((select source from public.recipe_versions where menu_item_id = '1b000000-0000-4000-8000-000000000005' order by version desc limit 1), 'deleted',
               'the deleted product left its last version');
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0301', 'created_at', now() - interval '2 hours',
       'total_crc', 3600, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0301', 'item_name', 'Renombrar 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000004'),
                                  jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0302', 'item_name', 'Borrar 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000005'))));
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0301'), 'Té 1B=-13', 'both still take their recipe (6 g + 7 g)');
select test.eq((select count(*) from public.order_items where order_id = '0d000000-0000-4000-8000-0000000b0301' and menu_item_id is not null)::int, 2,
               'and keep their product');
-- an id that never had that name still falls back to the name (as in 0004)
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0303', 'total_crc', 1500, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0303', 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000004'))));
reset role;
select test.eq((select menu_item_id::text from public.order_items where id = '0e000000-0000-4000-8000-0000000b0303'), '1b000000-0000-4000-8000-000000000002',
               'an id naming another product is still dropped');
-- deleted and made again with the same name: what is rung after that is the new product; what was rung before, the old one
insert into public.menu_items (id, category_id, name, price_crc) values
  ('1b000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000002', 'Borrar 1B', 1800);
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000008', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 9, "unit": "g"}]',
                          0, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0304', 'total_crc', 1800, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0304', 'item_name', 'Borrar 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000005'))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0305', 'created_at', now() - interval '2 hours',
       'total_crc', 1800, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0305', 'item_name', 'Borrar 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000005'))));
reset role;
select test.eq((select string_agg(right(i.menu_item_id::text, 1) || ':' || pg_temp.net(i.order_id), ' ' order by i.order_id)
                  from public.order_items i where i.id in ('0e000000-0000-4000-8000-0000000b0304', '0e000000-0000-4000-8000-0000000b0305')),
               '8:Té 1B=-9 5:Té 1B=-7',
               'a till with the old menu, now: the new product and its recipe (9 g); rung before the delete: the old one (7 g)');
-- items added on the device, with the old id, to an order rung before the delete: decided at the time each was added
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0306', 'created_at', now() - interval '2 hours',
       'total_crc', 5400, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Borrar 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000005', 'at', now() + interval '5 minutes'),
                                  jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Borrar 1B', 'price_crc', 1800, 'qty', 2,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000005', 'at', now() - interval '10 minutes'))));
reset role;
select test.eq((select string_agg(right(i.menu_item_id::text, 1) || ':' || trim_scale(x.q)::text, ' ' order by i.qty)
                  from public.order_items i join lateral (select coalesce(sum(m.qty), 0) as q from public.stock_moves m where m.order_item_id = i.id) x on true
                 where i.order_id = '0d000000-0000-4000-8000-0000000b0306'),
               '8:-9 5:-14', 'added after the product was made again: the new one (9 g); added before: the old one (7 g each)');
-- renamed before its first version (a sale kept on a device across the activation): the menu log remembers the old name
insert into public.menu_items (id, category_id, name, price_crc) values ('1b000000-0000-4000-8000-00000000000c', 'a0000000-0000-4000-8000-000000000002', 'Viejo 1B', 1700);
set local session_replication_role = replica;
insert into public.recipes (menu_item_id, stock_item_id, qty) values ('1b000000-0000-4000-8000-00000000000c', '5a000000-0000-4000-8000-0000000b0004', 3);
set local session_replication_role = origin;
update public.menu_items set name = 'Nuevo 1B' where id = '1b000000-0000-4000-8000-00000000000c';
select test.eq((select count(*) from public.audit_log where action = 'menu_change' and target_id = '1b000000-0000-4000-8000-00000000000c'
                 and details->'before'->>'name' = 'Viejo 1B')::int, 1, 'the rename is in the menu log');
select canopy.recipe_baseline();
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0307', 'created_at', now() - interval '2 hours',
       'total_crc', 1700, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Viejo 1B', 'price_crc', 1700, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-00000000000c'))));
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0307'), 'Té 1B=-3', 'a sale kept under the old name still takes its recipe (the starting version)');

-- 4) an ingredient of an older version no longer exists: the sale is saved and marked, never refused ----------------
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000006',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0003", "qty": 5, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 50, "unit": "ml"}]',
  0, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-000000000006', 1, 3);
set local session_replication_role = origin;
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000006', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 50, "unit": "ml"}]',
                          1, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
-- cinnamon is in no recipe now, but in the history: it is not deleted (the delete guard)
select test.login('owner', 'aal2'); set role authenticated;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-0000000b0005', 'Nada 1B', 'g', 1, 1);
select test.throws($$delete from public.stock_items where id = '5a000000-0000-4000-8000-0000000b0003'$$, 'stock_item_in_old_recipe_history',
                   'an ingredient in the recipe history is not deleted');
select test.lives($$delete from public.stock_items where id = '5a000000-0000-4000-8000-0000000b0005'$$, 'one that never was in a recipe still is');
reset role;
-- even if it were (removed with the triggers off), a late sale of the old version is saved
set local session_replication_role = replica;
delete from public.stock_items where id = '5a000000-0000-4000-8000-0000000b0003';
set local session_replication_role = origin;
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0401', 'created_at', now() - interval '2 hours',
       'total_crc', 1800, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Canela 1B', 'price_crc', 1800, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000006'))))->>'ok', 'true', 'the sale is saved');
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0401'), 'Leche 1B:-50@1', 'with the ingredients that exist');
select test.ok((select 'recipe_item_missing' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-0000000b0401'), 'and marked for a manager');

-- 5) taking a product off a bill gives back exactly what it took, even after the recipe and the cost changed ---------
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0501', 'total_crc', 10500, 'payment_method', 'cash_crc',
       'paid', false, 'status', 'preparing', 'source', 'front', 'needs_kitchen', false,
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0501', 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 3,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001'),
                                  jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0502', 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000002'))));
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0501'), 'Fresa 1B=-450 Leche 1B=-300 Té 1B=-3', 'a bill: 3 smoothies and a tea');
-- then the recipe changes (200 g) and strawberries cost ₡10
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000001',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0001", "qty": 200, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 100, "unit": "ml"}]',
  2, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
insert into public.stock_moves (item_id, kind, qty, unit_cost)       -- as much again as is on the shelf, at ₡14: the average becomes ₡10
  select id, 'purchase', on_hand, 14 from public.stock_items where id = '5a000000-0000-4000-8000-0000000b0001';
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-0000000b0001'), 10.0000, 'strawberries now average ₡10');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_remove_item('0e000000-0000-4000-8000-0000000b0501', 1, 'equivocado', 'Caja', null, null, 1)->>'error', 'changed',
               'a device with an old total is refused');
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0501'), 'Fresa 1B=-450 Leche 1B=-300 Té 1B=-3', 'and nothing comes back');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_remove_item('0e000000-0000-4000-8000-0000000b0501', 1, 'equivocado', 'Caja', null, null,
               (select total_crc from public.orders where id = '0d000000-0000-4000-8000-0000000b0501'))->>'ok', 'true', 'one smoothie taken off');
reset role;
select test.eq((select string_agg(trim_scale(qty)::text || '@' || trim_scale(unit_cost)::text || ':' || kind || ':' || note || ':' || line_qty, ' ' order by item_id)
                  from public.stock_moves where order_id = '0d000000-0000-4000-8000-0000000b0501' and qty > 0),
               '150@6:sale:Batido 1B:1 100@1:sale:Batido 1B:1', 'what it took comes back: 150 g at ₡6 (not 200 g at ₡10), named after the product');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_remove_item('0e000000-0000-4000-8000-0000000b0501', 1, 'equivocado', 'Caja', null, null,
               (select total_crc from public.orders where id = '0d000000-0000-4000-8000-0000000b0501'))->>'ok', 'true', 'a second one');
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0501'), 'Fresa 1B=-150 Leche 1B=-100 Té 1B=-3', 'one smoothie and the tea are still out');
select test.eq((select audit.c from (select count(*)::int as c from public.audit_log where action = 'tab_item_removed'
                  and target_id = '0d000000-0000-4000-8000-0000000b0501') audit), 2, 'both are in the approvals log');
-- voiding the bill now returns only what is still out
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-0000000b0501', 'se fue')->>'ok', 'true', 'the bill is voided');
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0501'), '', 'and the bill nets to zero: nothing returned twice');
select test.eq((select sum(qty * coalesce(unit_cost, 0)) from public.stock_moves where order_id = '0d000000-0000-4000-8000-0000000b0501'), 0::numeric,
               'at the same costs');
-- a bill's line added later takes the recipe of when it was added, and comes back the same way
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0502', 'total_crc', 1500, 'payment_method', 'cash_crc',
       'paid', false, 'status', 'preparing', 'source', 'front',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000002'))));
select test.eq(public.tab_add_items('0d000000-0000-4000-8000-0000000b0502', '[{"menu_item_id": "1b000000-0000-4000-8000-000000000001", "qty": 1}]', gen_random_uuid())->>'ok',
               'true', 'a smoothie added to the bill');
reset role;
select id as added_line from public.order_items where order_id = '0d000000-0000-4000-8000-0000000b0502' and item_name = 'Batido 1B' \gset
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0502'), 'Fresa 1B=-200 Leche 1B=-100 Té 1B=-3', 'it takes today''s recipe');
-- the recipe changes before it is taken off (230 g), and back afterwards
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000001',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0001", "qty": 230, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 100, "unit": "ml"}]',
  3, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_remove_item(:'added_line', 1, '', 'Caja', null, null,
               (select total_crc from public.orders where id = '0d000000-0000-4000-8000-0000000b0502'))->>'ok', 'true', 'and is taken off again');
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0502'), 'Té 1B=-3', 'exactly what it took (200 g), not the 230 g of now');
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000001',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0001", "qty": 200, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 100, "unit": "ml"}]',
  4, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;

-- 6) a bill opened before 0031 (lines without the link, one unit taken off the old way) -----------------------------
set local session_replication_role = replica;      -- as the old code left it
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, source)
  values ('0d000000-0000-4000-8000-0000000b0601', now() - interval '1 hour', 7500, 'cash_crc', false, 'preparing', 'front');
insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id) values
  ('0e000000-0000-4000-8000-0000000b0601', '0d000000-0000-4000-8000-0000000b0601', 'Batido 1B', 3000, 2, '1b000000-0000-4000-8000-000000000001'),
  ('0e000000-0000-4000-8000-0000000b0602', '0d000000-0000-4000-8000-0000000b0601', 'Te 1B', 1500, 1, '1b000000-0000-4000-8000-000000000002');
set local session_replication_role = origin;
insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, note) values      -- 3 smoothies at 120 g, 1 tea
  ('5a000000-0000-4000-8000-0000000b0001', 'sale', -360, 4, '0d000000-0000-4000-8000-0000000b0601', 'Batido 1B'),
  ('5a000000-0000-4000-8000-0000000b0002', 'sale', -300, 1, '0d000000-0000-4000-8000-0000000b0601', 'Batido 1B'),
  ('5a000000-0000-4000-8000-0000000b0004', 'sale', -3, 10, '0d000000-0000-4000-8000-0000000b0601', 'Te 1B'),
  -- one smoothie taken off before 0031, recalculated with the recipe of then (150 g) at the cost of then
  ('5a000000-0000-4000-8000-0000000b0001', 'sale', 150, 6, '0d000000-0000-4000-8000-0000000b0601', 'Batido 1B · taken off the bill'),
  ('5a000000-0000-4000-8000-0000000b0002', 'sale', 100, 1, '0d000000-0000-4000-8000-0000000b0601', 'Batido 1B · taken off the bill');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_remove_item('0e000000-0000-4000-8000-0000000b0601', 1, '', 'Caja', null, null, 7500)->>'ok', 'true',
               'one more smoothie taken off after 0031');
reset role;
select test.eq((select string_agg(trim_scale(qty)::text || '@' || trim_scale(unit_cost)::text, ' ' order by item_id)
                  from public.stock_moves where order_id = '0d000000-0000-4000-8000-0000000b0601' and note = 'Batido 1B' and qty > 0),
               '105@4 100@1', 'half of what is still out with that name (210 g, 200 ml), at the cost it went out with');
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-0000000b0601', 'se fue')->>'ok', 'true', 'the old bill is voided');
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b0601'), '', 'and nets to zero');

-- 7) a bill with an item paid by part, then voided: the eaten item goes out again exactly as it went out -----------
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0701', 'total_crc', 7500, 'payment_method', 'cash_crc',
       'paid', false, 'status', 'preparing', 'source', 'front',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0701', 'item_name', 'Batido 1B', 'price_crc', 3000, 'qty', 2,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000001'),
                                  jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b0702', 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000002'))));
select test.eq(public.tab_pay('0d000000-0000-4000-8000-0000000b0701', 'card', '[{"item_id": "0e000000-0000-4000-8000-0000000b0701", "qty": 1}]', null, 'Caja', 7500)->>'ok',
               'true', 'one smoothie paid by item');
reset role;
-- the recipe changes again before the void
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-000000000001',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0001", "qty": 250, "unit": "g"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0002", "qty": 100, "unit": "ml"}]',
  5, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-0000000b0701', 'pleito')->>'ok', 'true', 'the bill is voided');
reset role;
select test.eq((select string_agg(trim_scale(qty)::text || '@' || trim_scale(unit_cost)::text || ':' || line_qty, ' ' order by item_id)
                  from public.stock_moves where order_item_id = '0e000000-0000-4000-8000-0000000b0701' and order_id is null),
               '-200@10:1 -100@1:1', 'the eaten smoothie: 200 g at ₡10 as rung (not 250 g)');
select test.eq((select string_agg(s.name || '=' || trim_scale(x.q)::text, ' ' order by s.name)
                  from (select item_id, sum(qty) as q from public.stock_moves
                         where order_id = '0d000000-0000-4000-8000-0000000b0701' or order_item_id = '0e000000-0000-4000-8000-0000000b0701'
                         group by item_id) x join public.stock_items s on s.id = x.item_id where x.q <> 0),
               'Fresa 1B=-200 Leche 1B=-100', 'all told, only the eaten smoothie stays out');

-- 9) a sale rung before the cost history began: the first cost known, not today's ---------------------------------
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-0000000b0006', 'Miel 1B', 'g', 1000, 2000);
insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('5a000000-0000-4000-8000-0000000b0006', 'purchase', 1000, 8);
select test.eq((select string_agg(trim_scale(unit_cost)::text, ' ' order by at, id) from canopy.stock_cost_history
                 where item_id = '5a000000-0000-4000-8000-0000000b0006'), '2 8', 'honey: ₡2 when it was entered, then ₡8');
insert into public.menu_items (id, category_id, name, price_crc) values ('1b000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000002', 'Miel 1B', 1000);
set local session_replication_role = replica;
insert into public.recipes (menu_item_id, stock_item_id, qty) values ('1b000000-0000-4000-8000-000000000009', '5a000000-0000-4000-8000-0000000b0006', 10);
set local session_replication_role = origin;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b0901', 'created_at', now() - interval '2 hours',
       'total_crc', 1000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Miel 1B', 'price_crc', 1000, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000009'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b0901'), 'Miel 1B:-10@2', 'rung before the history began: the first cost known (₡2), not ₡8');

-- 10) an ingredient only in an old recipe keeps its unit; a late sale of that recipe never takes it in another unit ---
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-0000000b0007', 'Sirope 1B', 'ml', 1000, 5000);
insert into public.menu_items (id, category_id, name, price_crc) values ('1b000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000002', 'Te dulce 1B', 1600);
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-00000000000a',
  '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0007", "qty": 30, "unit": "ml"}, {"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 2, "unit": "g"}]',
  0, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-00000000000a', 1, 3);
set local session_replication_role = origin;
select test.login('cafe'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.recipe_save('1b000000-0000-4000-8000-00000000000a', '[{"stock_item_id": "5a000000-0000-4000-8000-0000000b0004", "qty": 2, "unit": "g"}]',
                          1, test.staff('ana'), '4826', null, gen_random_uuid()) is not null;
reset role;
set local session_replication_role = replica;
select pg_temp.age('1b000000-0000-4000-8000-00000000000a', 2, 1);
set local session_replication_role = origin;
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$update public.stock_items set unit = 'L' where id = '5a000000-0000-4000-8000-0000000b0007'$$, 'unit_locked',
                   'the syrup is in no recipe now, but in the history: its unit stays');
reset role;
-- even if it had changed (before 0031, or by hand), the late sale leaves it out and says so
set local session_replication_role = replica;
update public.stock_items set unit = 'L', pack_qty = 1 where id = '5a000000-0000-4000-8000-0000000b0007';
set local session_replication_role = origin;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b1001', 'created_at', now() - interval '2 hours',
       'total_crc', 1600, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Te dulce 1B', 'price_crc', 1600, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-00000000000a'))));
reset role;
select test.eq(pg_temp.moves('0d000000-0000-4000-8000-0000000b1001'), 'Té 1B:-2@10', 'the tea of that version goes out; 30 ml are never taken as 30 L');
select test.ok((select 'recipe_item_missing' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-0000000b1001'), 'and the sale is marked for a manager');

-- 11) a bill opened before 0031, one item paid by item, then voided: the eaten item goes out again as it went out -----
set local session_replication_role = replica;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, source)
  values ('0d000000-0000-4000-8000-0000000b1101', now() - interval '1 hour', 6000, 'cash_crc', false, 'preparing', 'front');
insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id) values
  ('0e000000-0000-4000-8000-0000000b1101', '0d000000-0000-4000-8000-0000000b1101', 'Batido 1B', 3000, 2, '1b000000-0000-4000-8000-000000000001');
set local session_replication_role = origin;
insert into public.stock_moves (item_id, kind, qty, unit_cost, order_id, note) values      -- 2 smoothies at 120 g, as the old code took them
  ('5a000000-0000-4000-8000-0000000b0001', 'sale', -240, 4, '0d000000-0000-4000-8000-0000000b1101', 'Batido 1B'),
  ('5a000000-0000-4000-8000-0000000b0002', 'sale', -200, 1, '0d000000-0000-4000-8000-0000000b1101', 'Batido 1B');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_pay('0d000000-0000-4000-8000-0000000b1101', 'card', '[{"item_id": "0e000000-0000-4000-8000-0000000b1101", "qty": 1}]', null, 'Caja', 6000)->>'ok',
               'true', 'one old smoothie paid by item');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-0000000b1101', 'pleito')->>'ok', 'true', 'the old bill is voided');
reset role;
select test.eq((select string_agg(trim_scale(qty)::text || '@' || trim_scale(unit_cost)::text || ':' || line_qty, ' ' order by item_id)
                  from public.stock_moves where order_id is null and order_item_id is null and note = 'Batido 1B · paid in part, bill voided'),
               '-120@4:1 -100@1:1', 'the eaten smoothie: its share of what went out (120 g at ₡4), not today''s 250 g');

-- 12) a line whose stock could not be taken keeps its link: nothing of it went out, so nothing of it comes back -------
create function public.t_1b_fail() returns trigger language plpgsql as $f$
begin if new.note = 'Falla 1B' then raise exception 'boom'; end if; return new; end $f$;
create trigger t_1b_fail before insert on public.stock_moves for each row execute function public.t_1b_fail();
insert into public.menu_items (id, category_id, name, price_crc) values ('1b000000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-000000000002', 'Falla 1B', 1000);
set local session_replication_role = replica;
insert into public.recipes (menu_item_id, stock_item_id, qty) values ('1b000000-0000-4000-8000-00000000000b', '5a000000-0000-4000-8000-0000000b0004', 1);
set local session_replication_role = origin;
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-0000000b1201', 'total_crc', 3500, 'payment_method', 'cash_crc',
       'paid', false, 'status', 'preparing', 'source', 'front',
       'items', jsonb_build_array(jsonb_build_object('id', '0e000000-0000-4000-8000-0000000b1201', 'item_name', 'Falla 1B', 'price_crc', 1000, 'qty', 2,
                                                     'menu_item_id', '1b000000-0000-4000-8000-00000000000b'),
                                  jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Te 1B', 'price_crc', 1500, 'qty', 1,
                                                     'menu_item_id', '1b000000-0000-4000-8000-000000000002'))))->>'ok', 'true', 'the sale is kept');
reset role;
drop trigger t_1b_fail on public.stock_moves;
select test.ok((select 'stock_not_taken' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-0000000b1201'), 'marked for a manager');
select test.eq((select coalesce(count(m.id), 0) || ':' || (i.stock_time is not null)::text from public.order_items i
                  left join public.stock_moves m on m.order_item_id = i.id where i.id = '0e000000-0000-4000-8000-0000000b1201' group by i.stock_time),
               '0:true', 'nothing went out for that line, and it is still a line of 0031');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_remove_item('0e000000-0000-4000-8000-0000000b1201', 1, '', 'Caja', null, null, 3500)->>'ok', 'true', 'one taken off');
reset role;
select test.eq(pg_temp.net('0d000000-0000-4000-8000-0000000b1201'), 'Té 1B=-3', 'nothing comes back for it; the tea stays out');

-- 8) never a zero movement; the new helpers are not for the pages ---------------------------------------------------
insert into public.order_items (order_id, item_name, price_crc, qty, menu_item_id)
  values ('0d000000-0000-4000-8000-0000000b0103', 'Batido 1B', 0, 0, '1b000000-0000-4000-8000-000000000001');
select test.eq((select count(*) from public.stock_moves where order_id = '0d000000-0000-4000-8000-0000000b0103' and qty = 0)::int, 0, 'a line of 0 takes nothing');
select test.ok(not has_function_privilege('authenticated', 'public._order_line_return(uuid, uuid, text, boolean, int, int, text)', 'execute')
               and not has_function_privilege('anon', 'public._order_line_return(uuid, uuid, text, boolean, int, int, text)', 'execute')
               and not has_function_privilege('authenticated', 'public._stock_cost_at(uuid, timestamptz)', 'execute')
               and not has_function_privilege('authenticated', 'public._sale_unit_cost(numeric, numeric, numeric)', 'execute')
               and not has_function_privilege('authenticated', 'public._stock_cost_log()', 'execute')
               and not has_function_privilege('anon', 'public._as_time(text)', 'execute'), 'the pages cannot call the new helpers');
select test.ok(not has_table_privilege('authenticated', 'canopy.stock_cost_history', 'select')
               and has_table_privilege('canopy_backup', 'canopy.stock_cost_history', 'select'), 'the cost history: not for the pages, in the backup');
select test.eq((select count(*) from pg_proc where proname = 'tab_remove_item' and pronamespace = 'public'::regnamespace)::int, 1, 'tab_remove_item has one signature');

select test.done();
rollback;
