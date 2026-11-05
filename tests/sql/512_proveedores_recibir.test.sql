-- Migration 0039 (Proveedores, D-067): receiving by management (proveedor_recibir, proveedor_recepcion_corregir). What
-- each delivery brought is kept per order line (purchase_receipt_lines) next to the stock move; 2 boxes of 12 add 24
-- units; full and partial deliveries (10 ordered, 6 then 4); a delivery never adds stock twice (a retry, a second device
-- with an older version, the published page and the new one on the same order); more than ordered only when management
-- says so; a different price is booked and listed while the catalog price stays; the delivery's total is what the moves
-- booked; a wrong delivery is corrected by a new one, nothing deleted; a delivery after the day's register close is posted.
begin;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051201', 'Lácteos Monteverde');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, avg_cost) values
  ('5a000000-0000-4000-8000-000000051201', 'Leche', 'unit', 1, 1000, null),
  ('5a000000-0000-4000-8000-000000051202', 'Queso', 'g', 500, 1750, null),
  ('5a000000-0000-4000-8000-000000051203', 'Harina', 'kg', 1, 0, null),
  ('5a000000-0000-4000-8000-000000051204', 'Azúcar', 'kg', 1, 0, 800);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051201', '5b000000-0000-4000-8000-000000051201', '5a000000-0000-4000-8000-000000051201', 'caja de 12', 12, 12000),
  ('5c000000-0000-4000-8000-000000051202', '5b000000-0000-4000-8000-000000051201', '5a000000-0000-4000-8000-000000051202', 'bloque de 2 kg', 2000, 7000);
create function test.v512(o text) returns int language sql as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.line512(o text, p int default 1) returns text language sql as $$ select id::text from public.purchase_lines where po_id = o::uuid and pos = p $$;
create function test.on_hand512(i text) returns numeric language sql as $$ select on_hand from public.stock_items where id = i::uuid $$;
select test.login('cafe'); select test.session('dev-512'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051201","packs":2}]', null,
                                     '9a000000-0000-4000-8000-000000051201') ->> 'ok' as c1 \gset
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051202","packs":10}]', null,
                                     '9a000000-0000-4000-8000-000000051202') ->> 'ok' as c2 \gset
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051201","packs":5}]', null,
                                     '9a000000-0000-4000-8000-000000051203') ->> 'ok' as c3 \gset
select test.eq(:'c1' || :'c2' || :'c3', 'truetruetrue', '0 (fixture) three orders: 2 boxes of milk, 10 blocks of cheese, 5 boxes of milk');

-- 1) «Todo recibido correctamente»: 2 boxes of 12 → +24 units --------------------------------------------------------------
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051201', '7e000000-0000-4000-8000-000000051201', test.v512('9a000000-0000-4000-8000-000000051201'),
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051201'), 'rest', true))) as r1 \gset
select test.eq((:'r1'::jsonb) - 'version' - 'short', jsonb_build_object('ok', true, 'status', 'received', 'receipt_id', '7e000000-0000-4000-8000-000000051201',
                 'total_crc', 24000.00, 'lines', 1, 'price_diffs', '[]'::jsonb, 'extra', '[]'::jsonb), '1 everything as ordered: received, ₡24 000');
reset role;
select test.eq(test.on_hand512('5a000000-0000-4000-8000-000000051201'), 24.0000, '1 2 boxes of 12 → 24 units in stock');
select test.eq((select packs || ' ' || qty || ' ' || pack_qty || ' ' || unit_cost || ' ' || pack_price || ' ' || expected_pack_price || ' ' || (move_id is not null)
                  from public.purchase_receipt_lines where receipt_id = '7e000000-0000-4000-8000-000000051201'),
               '2.0000 24.0000 12 1000.000000 12000.00 12000.00 true', '1 the delivery line: 2 boxes, 24 units, booked at ₡12 000 a box, with its move');
select test.eq((select total_crc || ' ' || final || ' ' || lines || ' ' || by_name || ' ' || origin || ' ' || coalesce(staff_id::text, '-') from public.purchase_receipts
                 where id = '7e000000-0000-4000-8000-000000051201'), '24000.00 true 1 Ana (manager) proveedores -', '1 the delivery: total, final, who');
select test.eq((select sum(qty * unit_cost) from public.stock_moves where receipt_id = '7e000000-0000-4000-8000-000000051201'),
               (select total_crc from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051201'), '1 its total is what the moves booked');

-- 2) 10 ordered: 6, then 4 --------------------------------------------------------------------------------------------------
set role authenticated;
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051202', test.v512('9a000000-0000-4000-8000-000000051202'),
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs', 6)), null, false, 'F-1001') as r2 \gset
select test.eq((:'r2'::jsonb) ->> 'status' || ' ' || ((:'r2'::jsonb) #>> '{short,0,pending_packs}'), 'partially_received 4.0000', '2 6 of 10 blocks: partially received, 4 to come');
reset role;
select test.eq(test.on_hand512('5a000000-0000-4000-8000-000000051202'), 12000.0000, '2 6 blocks of 2 kg → 12 000 g');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051202') as v2 \gset
set role authenticated;
-- the same delivery again (a lost answer): nothing more
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051202', 1,
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs', 6))),
               jsonb_build_object('ok', true, 'repeat', true, 'status', 'partially_received', 'receipt_id', '7e000000-0000-4000-8000-000000051202', 'version', :v2),
               '2 the same delivery sent again answers «repeat» and adds nothing');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051202', test.v512('9a000000-0000-4000-8000-000000051203'), '[]') ->> 'error',
               'bad_request', '2 a delivery id of another order is refused');
-- a second device that loaded the order before the first delivery
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051209', 1,
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs', 10))) as stale \gset
select test.eq((:'stale'::jsonb) ->> 'error' || ' ' || ((:'stale'::jsonb) #>> '{order,version}') || ' ' || ((:'stale'::jsonb) #>> '{order,lines,0,received_qty}')
               || ' ' || ((:'stale'::jsonb) #>> '{order,lines,0,pending_packs}'), 'changed ' || :v2 || ' 12000.0000 4.0000',
               '2 a second device with an older version is refused («changed») with what is received and pending now');
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051203', :v2,
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs', 4))) as r3 \gset
select test.eq((:'r3'::jsonb) ->> 'status' || ' ' || ((:'r3'::jsonb) ->> 'total_crc'), 'received 28000.00', '2 then the 4 (₡7 000 a block): received');
reset role;
select test.eq(test.on_hand512('5a000000-0000-4000-8000-000000051202'), 20000.0000, '2 10 blocks in all: 20 000 g, never more');
select test.eq((select count(*)::int || ' ' || sum(qty) from public.stock_moves where po_id = '9a000000-0000-4000-8000-000000051202'), '2 20000.0000', '2 two moves for two deliveries');
select test.eq((select string_agg(packs::text, ' ' order by receipt_id) from public.purchase_receipt_lines where line_id = test.line512('9a000000-0000-4000-8000-000000051202')::uuid),
               '6.0000 4.0000', '2 each delivery''s line: 6, then 4');
select test.eq((select string_agg(final::text, ' ' order by received_at, id) from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051202'), 'false true',
               '2 the second delivery completes the order');
set role authenticated;
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051204', test.v512('9a000000-0000-4000-8000-000000051202'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs', 1))) ->> 'error',
               'already_received', '2 a received order takes no more');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs', 1))) ->> 'error',
               'not_found', '2 a line of another order is refused');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 1),
                                   jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 1))) ->> 'error',
               'duplicate_line', '2 the same line twice in one delivery is refused (it would count twice)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', -1))) ->> 'error',
               'bad_qty', '2 no negative quantity');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', '1'))) ->> 'error',
               'bad_request', '2 a quantity only as a number');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 0))) ->> 'error',
               'empty', '2 nothing received is refused');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 1)), null, false, 'f-1001') ->> 'error',
               'duplicate_invoice', '2 the supplier''s invoice number of another delivery is refused (any case)');

-- 3) more than ordered, and other prices ----------------------------------------------------------------------------------
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 6))) as o1 \gset
select test.eq(:'o1'::jsonb, jsonb_build_object('ok', false, 'error', 'over_pending', 'line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'pending_packs', 5.0000),
               '3 6 boxes of 5 ordered: refused, with what is pending');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 2, 'pack_price', 120000))) ->> 'error',
               'check_price', '3 a price ten times the expected one asks «¿Seguro?»');
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051203', '7e000000-0000-4000-8000-000000051205', test.v512('9a000000-0000-4000-8000-000000051203'),
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051203'), 'packs', 6, 'pack_price', 13000)), null, false, null,
         'Vino una caja de más', true) as o2 \gset
select test.eq((:'o2'::jsonb) ->> 'status' || ' ' || ((:'o2'::jsonb) ->> 'total_crc') || ' ' || ((:'o2'::jsonb) #>> '{extra,0,packs}') || ' '
               || ((:'o2'::jsonb) #>> '{price_diffs,0,expected_pack_price}') || '>' || ((:'o2'::jsonb) #>> '{price_diffs,0,pack_price}'),
               'received 78000.00 1.0000 12000.00>13000.00', '3 with «Llegó de más (lo autorizo)»: 6 boxes booked at the new price, the extra and the difference listed');
reset role;
select test.eq(test.on_hand512('5a000000-0000-4000-8000-000000051201'), 96.0000, '3 24 + 72 units');
select test.eq((select usual_price from public.vendor_items where id = '5c000000-0000-4000-8000-000000051201'), 12000.00,
               '3 the supplier''s catalog price stays ₡12 000 (only proveedor_producto_guardar changes it)');
select test.eq((select round(cost_per_pack, 2) from public.stock_items where id = '5a000000-0000-4000-8000-000000051201'), 1083.33,
               '3 the item''s last price follows the typed one, as before (per unit: 13 000 / 12)');
select test.eq((select unit_cost || ' ' || ordered_unit_cost from public.purchase_lines where id = test.line512('9a000000-0000-4000-8000-000000051203')::uuid),
               '1000.000000 1000.000000', '3 the ordered price on the line is never overwritten by a delivery');
select test.eq((select (details -> 'extra' -> 0 ->> 'packs') || ' ' || (details -> 'lines' -> 0 ->> 'pack_price') || ' ' || (details ->> 'close')
                  from public.audit_log where action = 'stock_receive' and details ->> 'receipt_id' = '7e000000-0000-4000-8000-000000051205'),
               '1.0000 13000.00 true', '3 the log keeps the extra and the price');
select test.eq((select note from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051205'), 'Vino una caja de más', '3 with the note');

-- 4) old lines (the published page): no price, the average, the published page and this one on the same order -------------
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051204', '5b000000-0000-4000-8000-000000051201', 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values
  ('9b000000-0000-4000-8000-000000051241', '9a000000-0000-4000-8000-000000051204', '5a000000-0000-4000-8000-000000051203', 0, 10, null),
  ('9b000000-0000-4000-8000-000000051242', '9a000000-0000-4000-8000-000000051204', '5a000000-0000-4000-8000-000000051204', 0, 10, null),
  ('9b000000-0000-4000-8000-000000051243', '9a000000-0000-4000-8000-000000051204', '5a000000-0000-4000-8000-000000051201', 3, 36, 1000);
set role authenticated;
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051204', '7e000000-0000-4000-8000-000000051206', test.v512('9a000000-0000-4000-8000-000000051204'),
                 '[{"line_id":"9b000000-0000-4000-8000-000000051241","packs":10}]'),
               '{"ok":false,"error":"needs_price","line_id":"9b000000-0000-4000-8000-000000051241"}'::jsonb, '4 an item with no price at all needs one');
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051204', '7e000000-0000-4000-8000-000000051206', test.v512('9a000000-0000-4000-8000-000000051204'),
         '[{"line_id":"9b000000-0000-4000-8000-000000051241","packs":10,"pack_price":500},{"line_id":"9b000000-0000-4000-8000-000000051242","packs":10},
           {"line_id":"9b000000-0000-4000-8000-000000051243","packs":1}]') as o4 \gset
select test.eq((:'o4'::jsonb) ->> 'status' || ' ' || ((:'o4'::jsonb) ->> 'total_crc') || ' ' || ((:'o4'::jsonb) #>> '{short,0,line_id}'),
               'partially_received 25000.00 9b000000-0000-4000-8000-000000051243', '4 flour at the typed price, sugar at its average (₡800), one box of milk');
reset role;
select test.eq((select string_agg(item_id::text || '=' || qty || '@' || unit_cost, ' ' order by item_id) from public.stock_moves where receipt_id = '7e000000-0000-4000-8000-000000051206'),
               '5a000000-0000-4000-8000-000000051201=12.0000@1000 5a000000-0000-4000-8000-000000051203=10.0000@500.000000 5a000000-0000-4000-8000-000000051204=10.0000@800',
               '4 the line without a price is booked at the average; the moves go in item order');
select test.eq((select total_crc from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051206'),
               (select sum(qty * unit_cost) from public.stock_moves where receipt_id = '7e000000-0000-4000-8000-000000051206'),
               '4 the delivery''s total is what the moves booked (the average included), not 0');
set role authenticated;
-- the published page receives one more box of the same order the old way: this page''s version is now old
select test.v512('9a000000-0000-4000-8000-000000051204') as v4 \gset
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000051204', '[{"line_id":"9b000000-0000-4000-8000-000000051243","qty":12}]',
                 '7e000000-0000-4000-8000-000000051207') ->> 'status', 'partially_received', '4 (the published page receives one box)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051204', '7e000000-0000-4000-8000-000000051208', :v4,
                 '[{"line_id":"9b000000-0000-4000-8000-000000051243","rest":true}]') ->> 'error', 'changed',
               '4 the new page with the version from before that delivery is refused: the same box is never received twice');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051204', '7e000000-0000-4000-8000-000000051208', test.v512('9a000000-0000-4000-8000-000000051204'),
                 '[{"line_id":"9b000000-0000-4000-8000-000000051243","rest":true}]') ->> 'status', 'received', '4 reloaded: the last box, received');
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000051204', '[{"line_id":"9b000000-0000-4000-8000-000000051243","qty":12}]',
                 '7e000000-0000-4000-8000-000000051209') ->> 'error', 'already_received', '4 and the published page cannot add it again either');
reset role;
select test.eq((select received_qty from public.purchase_lines where id = '9b000000-0000-4000-8000-000000051243'), 36.0000, '4 36 ordered, 36 received');
select test.eq((select count(*)::int from public.purchase_receipt_lines where receipt_id = '7e000000-0000-4000-8000-000000051207'), 0,
               '4 the published page''s delivery has no delivery lines (its moves stand for them)');

-- 5) closing short, and nothing received -----------------------------------------------------------------------------------
set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051201","packs":4},
         {"vendor_item_id":"5c000000-0000-4000-8000-000000051202","packs":2}]', null, '9a000000-0000-4000-8000-000000051205') ->> 'ok' as c5 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051205', '7e000000-0000-4000-8000-000000051210', test.v512('9a000000-0000-4000-8000-000000051205'), '[]', null, true),
               '{"ok":false,"error":"no_receipts"}'::jsonb, '5 «No llega» with nothing delivered yet: nothing to close');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051205', '7e000000-0000-4000-8000-000000051210', test.v512('9a000000-0000-4000-8000-000000051205'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051205'), 'packs', 3)), null, true) ->> 'status',
               'received', '5 3 of 4 boxes and «No, cerrar el pedido»: received, the cheese and one box will not come');
reset role;
select test.eq((select final from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051210'), true, '5 the delivery is the final one');
set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051201","packs":4}]', null,
                                     '9a000000-0000-4000-8000-000000051206') ->> 'ok' as c6 \gset
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000051206', jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051206'),
                 'qty', 29)), '7e000000-0000-4000-8000-000000051213') ->> 'status', 'partially_received', '5 (the published page receives 29 loose units of the 4 boxes)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051206', '7e000000-0000-4000-8000-000000051211', test.v512('9a000000-0000-4000-8000-000000051206'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051206'), 'packs', 1.583))) ->> 'status', 'received',
               '5 then 1.583 boxes (what is pending, 19 units, written with 3 decimals): it is the rest, never «over pending»');
reset role;
select test.eq((select received_qty from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051206'), 48.0000, '5 48 of 48 units');
set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051201","packs":4}]', null,
                                     '9a000000-0000-4000-8000-000000051208') ->> 'ok' as c8 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051208', '7e000000-0000-4000-8000-000000051214', test.v512('9a000000-0000-4000-8000-000000051208'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051208'), 'packs', 1))) ->> 'status', 'partially_received', '5 (1 of 4)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051208', '7e000000-0000-4000-8000-000000051212', test.v512('9a000000-0000-4000-8000-000000051208'), '[]', null, true)
                 - 'version', '{"ok":true,"status":"received","closed":true}'::jsonb, '5 later, nothing more and «Cerrar lo pendiente»: closed without a new delivery');
reset role;
select test.eq((select count(*)::int from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051208'), 1, '5 no empty delivery row is made');

-- 6) corrections -------------------------------------------------------------------------------------------------------------
set role authenticated;
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051220',
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs_delta', -2)), 'mal') ->> 'error',
               'needs_reason', '6 a correction needs a reason');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051220',
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs_delta', -11)), 'Contamos mal') ->> 'error',
               'bad_qty', '6 never below nothing received');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051220',
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs_delta', 1)), 'Contamos mal') ->> 'error',
               'over_pending', '6 more than ordered needs extra_ok');
select public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051220',
         jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051202'), 'packs_delta', -2)), 'Eran 4 bloques, no 6') as k1 \gset
select test.eq((:'k1'::jsonb) ->> 'status' || ' ' || ((:'k1'::jsonb) ->> 'total_crc'), 'partially_received -14000.00',
               '6 two blocks taken off the first delivery: a new delivery of −2, the order is partially received again');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051220', '[]', 'otra vez') ->> 'repeat', 'true',
               '6 the same correction again: «repeat»');
reset role;
select test.eq(test.on_hand512('5a000000-0000-4000-8000-000000051202'), 16000.0000, '6 20 000 − 4 000 g');
select test.eq((select origin || ' ' || corrects || ' ' || total_crc || ' ' || note from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051220'),
               'correccion 7e000000-0000-4000-8000-000000051202 -14000.00 Eran 4 bloques, no 6', '6 the correction is a delivery of its own (origin, what it corrects, why)');
select test.eq((select kind || ' ' || qty || ' ' || unit_cost from public.stock_moves where receipt_id = '7e000000-0000-4000-8000-000000051220'), 'purchase -4000.0000 3.500000',
               '6 a signed purchase move at the corrected delivery''s cost');
select test.eq((select received_qty from public.purchase_lines where id = test.line512('9a000000-0000-4000-8000-000000051202')::uuid), 16000.0000, '6 the line: 16 000 g received');
select test.eq((select count(*)::int from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051202'), 3, '6 the first delivery is still there, unchanged');
select test.eq((select count(*)::int from public.audit_log where action = 'stock_receive_fix'), 1, '6 the correction is in the log');
-- the invoice of the corrected delivery takes its correction with it (Proveedores, 0040)
select test.login('cafe'); select test.session('dev-512'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051201', array['7e000000-0000-4000-8000-000000051202']::uuid[],
                 jsonb_build_object('date', public.cr_today(), 'net', 28000), '5e000000-0000-4000-8000-000000051202') ->> 'total_crc', '28000.00',
               '6 the supplier''s invoice for the first delivery (4 blocks, as corrected)');
reset role;
select test.eq((select received_crc || ' ' || cardinality(receipt_ids) || ' ' || ('7e000000-0000-4000-8000-000000051220' = any(receipt_ids))::text || ' ' || coalesce(entry_id::text, 'none')
                  from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051202'), '28000.00 2 true none',
               '6 it covers the delivery and its correction (₡42 000 − ₡14 000): equal to what was received, nothing to post');
select test.eq((select string_agg(coalesce(invoice_no, '-'), ' ' order by received_at, id) from public.purchase_receipts where id in ('7e000000-0000-4000-8000-000000051202', '7e000000-0000-4000-8000-000000051220')),
               'F-1001 -', '6 the number stays on the delivery that had it');
-- an invoiced delivery is corrected only after the invoice is voided
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051201', 'number', 'F-24', 'date', public.cr_today(),
                 'net_crc', 24000, 'iva_crc', 0, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051201')), '5e000000-0000-4000-8000-000000051201') ->> 'ok', 'true',
               '6 (the first milk delivery is invoiced in Contabilidad)');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051201', gen_random_uuid(),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051201'), 'packs_delta', -1)), 'Una caja venía rota') ->> 'error',
               'invoiced', '6 an invoiced delivery is not corrected («anule primero la factura»)');
reset role;

-- 7) a delivery after the day's register close is posted to the ledger (ledger_auto_post on) --------------------------------
insert into public.settings (key, value) values ('ledger_auto_post', 'true') on conflict (key) do update set value = excluded.value;
insert into public.register_days (business_date, closed_at) values (public.cr_today(), now()) on conflict (business_date) do update set closed_at = now();
select count(*) as day_before from acct.entries where source = 'day' and source_key like 'day:' || public.cr_today() || ':%' \gset
select test.login('cafe'); select test.session('dev-512'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051201', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051201","packs":1}]', null,
                                     '9a000000-0000-4000-8000-000000051207') ->> 'ok' as c7 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051207', '7e000000-0000-4000-8000-000000051230', test.v512('9a000000-0000-4000-8000-000000051207'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line512('9a000000-0000-4000-8000-000000051207'), 'rest', true))) ->> 'status', 'received',
               '7 a box of milk after the register was closed');
reset role;
select test.eq((select count(*) from acct.entries where source = 'day' and source_key like 'day:' || public.cr_today() || ':%') - :day_before, 1::bigint,
               '7 the day is posted again (only what was missing, as a re-close does)');
select test.ok(exists (select 1 from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'day' and e.source_key like 'day:' || public.cr_today() || ':%'
                         and l.account = acct.map('ap') and l.credit > 0), '7 with the purchases owed to suppliers');
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u), 0, '7 the ledger stays balanced');

select test.done();
rollback;
