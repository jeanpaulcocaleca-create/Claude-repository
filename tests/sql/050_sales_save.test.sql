-- Migration 0004: one-call sale save, product id on every line, totals check.
begin;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, on_hand)
  values ('5a000000-0000-4000-8000-000000000501', 'Café molido', 'g', 1000, 9000, 5000);
insert into public.recipes (menu_item_id, stock_item_id, qty)
  select id, '5a000000-0000-4000-8000-000000000501', 18 from public.menu_items where name = 'Espresso';
select id as espresso from public.menu_items where name = 'Espresso' \gset
select price_crc as esp_price from public.menu_items where name = 'Espresso' \gset

-- 1) a sale and its lines in one call ------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object(
  'id', '0d000000-0000-4000-8000-000000000501', 'created_at', now(), 'total_crc', 2 * :esp_price, 'payment_method', 'cash_crc',
  'paid', true, 'status', 'done', 'station', 'Caja',
  'items', jsonb_build_array(jsonb_build_object('id', '1e000000-0000-4000-8000-000000000501', 'item_name', 'Espresso',
                                                'price_crc', :esp_price, 'qty', 2, 'menu_item_id', :'espresso'))))->>'already',
  'false', 'the sale is saved in one call');
reset role;
select test.eq((select count(*)::int from public.order_items where order_id = '0d000000-0000-4000-8000-000000000501'), 1, 'its line is saved');
select test.eq((select menu_item_id from public.order_items where order_id = '0d000000-0000-4000-8000-000000000501'), :'espresso'::uuid,
               'the line knows its product');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000501'), 5000 - 36::numeric, 'the recipe took 36 g');

-- 2) sending it again changes nothing -------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object(
  'id', '0d000000-0000-4000-8000-000000000501', 'created_at', now(), 'total_crc', 2 * :esp_price, 'payment_method', 'cash_crc',
  'items', jsonb_build_array(jsonb_build_object('id', '1e000000-0000-4000-8000-000000000501', 'item_name', 'Espresso',
                                                'price_crc', :esp_price, 'qty', 2))))->>'already', 'true', 'a repeated send says already saved');
reset role;
select test.eq((select count(*)::int from public.orders where id = '0d000000-0000-4000-8000-000000000501'), 1, 'still one sale');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000501'), 5000 - 36::numeric, 'stock taken once');

-- 3) all or nothing: a bad line keeps the whole sale out --------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.throws($$select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000502', 'total_crc', 1000,
                     'payment_method', 'cash_crc', 'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1000, 'qty', 0))))$$,
                   'bad_qty', 'a line with quantity 0 is refused');
reset role;
select test.eq((select count(*)::int from public.orders where id = '0d000000-0000-4000-8000-000000000502'), 0, 'and no half sale is left behind');

-- 4) a discount without approval is refused, nothing saved -----------------------------------------------
select test.login('cafe'); set role authenticated;
select test.throws($$select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000503', 'total_crc', 900,
                     'subtotal_crc', 1000, 'discount_crc', 100, 'payment_method', 'card',
                     'items', jsonb_build_array(jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 1))))$$,
                   'discount_not_approved', 'an unapproved discount is refused');
reset role;
select test.eq((select count(*)::int from public.orders where id = '0d000000-0000-4000-8000-000000000503'), 0, 'nothing saved');

-- 5) lines that do not add up to the total are flagged, not refused --------------------------------------
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000504', 'total_crc', 500, 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 1))));
reset role;
select test.ok((select 'total_mismatch' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000000504'),
               'a total that does not match its lines is flagged for the manager');
select test.ok((select not ('total_mismatch' = any(flags)) from public.orders where id = '0d000000-0000-4000-8000-000000000501'),
               'a correct sale is not flagged');

-- 6) a half-saved sale from an old page is completed by the resend ----------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000000505', now(), 1000, 'card', true, 'done');
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000505', 'total_crc', 1000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '1e000000-0000-4000-8000-000000000505', 'item_name', 'Tea', 'price_crc', 1000, 'qty', 1)))),
       '{"ok": true, "already": true, "other_lines": false}'::jsonb, 'the missing lines of a half-saved sale go in');
reset role;
select test.eq((select count(*)::int from public.order_items where order_id = '0d000000-0000-4000-8000-000000000505'), 1, 'the half sale now has its line');

-- 7) a bill that already has other lines answers other_lines ------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000505', 'total_crc', 1000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', '1e000000-0000-4000-8000-000000000599', 'item_name', 'Tea', 'price_crc', 1000, 'qty', 1))))->>'other_lines',
       'true', 'lines under other ids are reported, not duplicated');
reset role;

-- 8) the product id survives a rename; a wrong id falls back to the name ---------------------------------
update public.menu_items set name = 'Espresso doble' where id = :'espresso';
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000506', 'total_crc', :esp_price, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso doble', 'price_crc', :esp_price, 'qty', 1, 'menu_item_id', :'espresso'))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000507', 'total_crc', 1000, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 1, 'menu_item_id', :'espresso'))));
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000501'), 5000 - 54::numeric,
               'a renamed product still takes its recipe');
select test.ok((select menu_item_id <> :'espresso'::uuid from public.order_items where order_id = '0d000000-0000-4000-8000-000000000507'),
               'an id that names another product is not trusted');

-- 9) only café logins may call it ----------------------------------------------------------------------------
select test.login('anon'); set role anon;
select test.throws($$select public.pos_record_sale('{"id":"0d000000-0000-4000-8000-000000000508","total_crc":1,"items":[]}')$$,
                   'permission denied', 'anonymous visitors cannot record sales');
reset role;

select test.done();
rollback;
