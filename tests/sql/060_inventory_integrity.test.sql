-- Migration 0005: inventory history is protected, every movement carries its cost, receipts are repeat-safe.
begin;
select test.login('owner', 'aal2'); set role authenticated;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000000601', 'Tostador');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, on_hand, vendor_id)
  values ('5a000000-0000-4000-8000-000000000601', 'Leche', 'ml', 1000, 1000, 99999, '5b000000-0000-4000-8000-000000000601'),
         ('5a000000-0000-4000-8000-000000000602', 'Vasos', 'unit', 50, 2500, 0, null);
reset role;

-- 1) the pages cannot set stock or the average cost directly -----------------------------------------------
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 0::numeric,
               'a new item starts at zero (opening stock comes in as a movement)');
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 1::numeric,
               'its average cost starts at the pack cost per unit');
select test.login('owner', 'aal2'); set role authenticated;
update public.stock_items set on_hand = 500, avg_cost = 0.01 where id = '5a000000-0000-4000-8000-000000000601';
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 0::numeric,
               'editing an item cannot change its stock');
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 1::numeric,
               'nor its average cost');

-- 2) opening stock is an adjustment, not a purchase ---------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.stock_receive('5a000000-0000-4000-8000-000000000601', 2000, 0.9, null, 'starting stock')->>'ok', 'true', 'opening stock saved');
reset role;
select test.eq((select kind from public.stock_moves where item_id = '5a000000-0000-4000-8000-000000000601'), 'adjust',
               'the old page''s "starting stock" is recorded as an adjustment');
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 0.9::numeric,
               'the opening cost becomes the average');

-- 3) purchases keep a weighted average; outgoing moves carry it -----------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.stock_receive('5a000000-0000-4000-8000-000000000601', 1000, 1.2);
reset role;
-- (2000 × 0.9 + 1000 × 1.2) / 3000 = 1.0
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 1.0::numeric,
               'a purchase at a new price moves the weighted average');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 3000::numeric, 'and adds stock');
select test.eq((select cost_per_pack from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 1200::numeric,
               'the last price paid is still shown on the item');
select test.login('owner', 'aal2'); set role authenticated;
select public.stock_waste('5a000000-0000-4000-8000-000000000601', 100, 'se cortó');
reset role;
select test.eq((select unit_cost from public.stock_moves where item_id = '5a000000-0000-4000-8000-000000000601' and kind = 'waste'), 1.0::numeric,
               'waste is costed at the average');

insert into public.recipes (menu_item_id, stock_item_id, qty)
  select id, '5a000000-0000-4000-8000-000000000601', 200 from public.menu_items where name = 'Latte';
select id as latte from public.menu_items where name = 'Latte' \gset
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000601', 'total_crc', 2500, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2500, 'qty', 1, 'menu_item_id', :'latte'))));
reset role;
select test.eq((select unit_cost from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000000601' and kind = 'sale'), 1.0::numeric,
               'a sale is costed at the average (cost of goods sold can be rebuilt)');
update public.orders set voided_at = now() where id = '0d000000-0000-4000-8000-000000000601';
select test.eq((select unit_cost from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000000601' and kind = 'void'), 1.0::numeric,
               'a void puts stock back at the cost it went out with');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'), 2900::numeric, 'stock after waste, sale and void');

select test.throws($$insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('5a000000-0000-4000-8000-000000000601', 'adjust', 1, -5)$$,
                   'bad_cost', 'a negative cost is refused');
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$insert into public.stock_moves (item_id, kind, qty) values ('5a000000-0000-4000-8000-000000000601', 'adjust', 1)$$,
                   'permission denied', 'the pages cannot write movements directly');
reset role;

-- 4) a request sent twice counts once -------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.stock_receive('5a000000-0000-4000-8000-000000000602', 100, 50, null, null, '7e000000-0000-4000-8000-000000000601');
select test.eq(public.stock_receive('5a000000-0000-4000-8000-000000000602', 100, 50, null, null, '7e000000-0000-4000-8000-000000000601')->>'repeat',
               'true', 'a repeated receipt answers "repeat"');
select public.stock_waste('5a000000-0000-4000-8000-000000000602', 10, null, '7e000000-0000-4000-8000-000000000602');
select public.stock_waste('5a000000-0000-4000-8000-000000000602', 10, null, '7e000000-0000-4000-8000-000000000602');
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000602'), 90::numeric,
               'receipt and waste each counted once');
select test.login('owner', 'aal2'); set role authenticated;
select public.stock_count('5a000000-0000-4000-8000-000000000602', 80, null, '7e000000-0000-4000-8000-000000000603');
select test.eq(public.stock_count('5a000000-0000-4000-8000-000000000602', 70, null, '7e000000-0000-4000-8000-000000000603')->>'repeat',
               'true', 'a repeated count is ignored');
select test.eq(public.stock_receive('5a000000-0000-4000-8000-000000000602', -5)->>'error', 'bad_qty', 'a negative receipt is refused');
select test.eq(public.stock_receive('5a000000-0000-4000-8000-000000000602', 5, -1)->>'error', 'bad_cost', 'a negative cost is refused');
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000602'), 80::numeric, 'count applied once');

-- 5) history cannot be deleted --------------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$delete from public.stock_items where id = '5a000000-0000-4000-8000-000000000601'$$,
                   'stock_item_has_history', 'an item with movements cannot be deleted');
insert into public.stock_items (id, name, unit) values ('5a000000-0000-4000-8000-000000000603', 'Error de tipeo', 'unit');
select test.lives($$delete from public.stock_items where id = '5a000000-0000-4000-8000-000000000603'$$, 'an item with no history can be deleted');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'stock_item_deleted' and target_id = '5a000000-0000-4000-8000-000000000603'),
               'and the deletion is logged');
select test.eq((select count(*)::int from public.stock_moves where item_id = '5a000000-0000-4000-8000-000000000601'), 5, 'the history is intact');

-- cost edits from the page are logged
select test.login('owner', 'aal2'); set role authenticated;
update public.stock_items set cost_per_pack = 1500 where id = '5a000000-0000-4000-8000-000000000601';
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'stock_cost_edit' and target_id = '5a000000-0000-4000-8000-000000000601'
                       and details->>'cost_per_pack_after' = '1500'), 'a cost edit is logged with before and after');
select test.login('cafe'); set role authenticated;
select public._stock_cost_edit_log('5a000000-0000-4000-8000-000000000601', 'x', 1, 2, 1, 1);
reset role;
select test.eq((select count(*)::int from public.audit_log where action = 'stock_cost_edit'), 1, 'a locked café device cannot write cost-edit entries');

-- 6) purchase orders ------------------------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000000601', '5b000000-0000-4000-8000-000000000601', 'draft'),
                                                                 ('9a000000-0000-4000-8000-000000000602', '5b000000-0000-4000-8000-000000000601', 'draft');
insert into public.purchase_lines (id, po_id, item_id, qty, unit_cost)
  values ('9b000000-0000-4000-8000-000000000601', '9a000000-0000-4000-8000-000000000601', '5a000000-0000-4000-8000-000000000602', 100, 60),
         ('9b000000-0000-4000-8000-000000000602', '9a000000-0000-4000-8000-000000000602', '5a000000-0000-4000-8000-000000000602', 100, 60);
select test.throws($$update public.purchase_orders set status = 'received' where id = '9a000000-0000-4000-8000-000000000601'$$,
                   'po_status', 'the page cannot mark an order received without receiving it');
update public.purchase_orders set status = 'sent' where id = '9a000000-0000-4000-8000-000000000601';
update public.purchase_orders set status = 'cancelled' where id = '9a000000-0000-4000-8000-000000000602';
select test.eq(public.po_receive('9a000000-0000-4000-8000-000000000602')->>'error', 'cancelled', 'a cancelled order cannot be received');
select test.eq(public.po_receive('9a000000-0000-4000-8000-000000000601',
               '[{"line_id":"9b000000-0000-4000-8000-000000000601","received_qty":-3}]')->>'error', 'bad_qty', 'a negative quantity is refused');
select test.eq(public.po_receive('9a000000-0000-4000-8000-000000000601',
               '[{"line_id":"9b000000-0000-4000-8000-000000000601","received_qty":90}]')->>'lines', '1', 'the order is received');
select test.eq(public.po_receive('9a000000-0000-4000-8000-000000000601')->>'error', 'already_received', 'a second receive is refused');
select test.throws($$update public.purchase_orders set status = 'draft' where id = '9a000000-0000-4000-8000-000000000601'$$,
                   'po_status', 'a received order cannot go back to draft');
select test.throws($$delete from public.purchase_orders where id = '9a000000-0000-4000-8000-000000000601'$$,
                   'purchase_order_received', 'a received order cannot be deleted');
select test.throws($$delete from public.vendors where id = '5b000000-0000-4000-8000-000000000601'$$,
                   'vendor_has_history', 'a vendor with orders cannot be deleted');
select test.lives($$delete from public.purchase_orders where id = '9a000000-0000-4000-8000-000000000602'$$, 'a cancelled, never-received order can be deleted');
reset role;
-- 80 on hand at 50 + 90 at 60 → (80×50 + 90×60)/170 = 55.2941
select test.eq((select avg_cost from public.stock_items where id = '5a000000-0000-4000-8000-000000000602'), 55.2941::numeric,
               'the received order moves the weighted average');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000602'), 170::numeric, 'received quantity added once');

-- 7) a locked device cannot move stock ------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.stock_waste('5a000000-0000-4000-8000-000000000602', 1)->>'error', 'locked', 'a locked café device cannot log waste');
reset role;

select test.done();
rollback;
