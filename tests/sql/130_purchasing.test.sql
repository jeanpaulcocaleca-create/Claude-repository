-- Migration 0012: PO numbers, partial deliveries with the supplier's invoice, duplicate-safe.
begin;
select test.login('owner', 'aal2'); set role authenticated;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000001301', 'Lácteos Monteverde');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000001301', 'Leche', 'ml', 1000, 1000),
                                                                              ('5a000000-0000-4000-8000-000000001302', 'Crema', 'ml', 500, 1500);
insert into public.purchase_orders (id, vendor_id, status, po_number) values ('9a000000-0000-4000-8000-000000001301', '5b000000-0000-4000-8000-000000001301', 'draft', 999999),
                                                                            ('9a000000-0000-4000-8000-000000001302', '5b000000-0000-4000-8000-000000001301', 'draft', null);
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost)
  values ('9b000000-0000-4000-8000-000000001301', '9a000000-0000-4000-8000-000000001301', '5a000000-0000-4000-8000-000000001301', 10, 10000, 1),
         ('9b000000-0000-4000-8000-000000001302', '9a000000-0000-4000-8000-000000001301', '5a000000-0000-4000-8000-000000001302', 4, 2000, 3),
         ('9b000000-0000-4000-8000-000000001303', '9a000000-0000-4000-8000-000000001302', '5a000000-0000-4000-8000-000000001301', 2, 2000, 1);
reset role;
select test.ok((select po_number <> 999999 and po_number is not null from public.purchase_orders where id = '9a000000-0000-4000-8000-000000001301'),
               'the server numbers the order');
select test.ok((select b.po_number > a.po_number from public.purchase_orders a, public.purchase_orders b
                 where a.id = '9a000000-0000-4000-8000-000000001301' and b.id = '9a000000-0000-4000-8000-000000001302'), 'numbers go up');

select test.login('owner', 'aal2'); set role authenticated;
update public.purchase_orders set status = 'sent' where id = '9a000000-0000-4000-8000-000000001301';
-- first delivery: 6 of 10 packs of milk, no cream; invoice F-100
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001301',
        '[{"line_id":"9b000000-0000-4000-8000-000000001301","qty":6000}]', '7e000000-0000-4000-8000-000000001301', 'F-100', current_date)->>'status',
        'partially_received', 'part of the order arrived');
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001301',
        '[{"line_id":"9b000000-0000-4000-8000-000000001301","qty":6000}]', '7e000000-0000-4000-8000-000000001301', 'F-100', current_date)->>'repeat',
        'true', 'the same delivery sent twice is saved once');
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001301',
        '[{"line_id":"9b000000-0000-4000-8000-000000001302","qty":2000}]', '7e000000-0000-4000-8000-000000001302', 'f-100', current_date)->>'error',
        'duplicate_invoice', 'the same supplier invoice cannot be entered twice');
select test.eq(public.po_receive('9a000000-0000-4000-8000-000000001301')->>'error', 'use_delivery', 'the one-step receive of older pages stops on a partly received order');
select test.throws($$update public.purchase_orders set status = 'received' where id = '9a000000-0000-4000-8000-000000001301'$$, 'po_status', 'the page cannot close it by editing');
-- second delivery: the rest of the milk and all the cream
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001301',
        '[{"line_id":"9b000000-0000-4000-8000-000000001301","qty":4000},{"line_id":"9b000000-0000-4000-8000-000000001302","qty":2000,"unit_cost":3.2}]',
        '7e000000-0000-4000-8000-000000001303', 'F-117', current_date)->>'status', 'received', 'everything arrived: received');
-- the other order: half arrives and nothing more is coming
select public.po_receive_delivery('9a000000-0000-4000-8000-000000001302',
        '[{"line_id":"9b000000-0000-4000-8000-000000001303","qty":1000}]', '7e000000-0000-4000-8000-000000001304', null, null, true) as fin \gset
select test.eq((:'fin'::jsonb)->>'status', 'received', 'closed with less than ordered when nothing more is coming');
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001302', '[]', '7e000000-0000-4000-8000-000000001305')->>'error', 'already_received', 'a closed order takes no more deliveries');
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001301', '[{"line_id":"9b000000-0000-4000-8000-000000001303","qty":1}]', '7e000000-0000-4000-8000-000000001306')->>'error',
               'already_received', 'a line of another order is never received here');
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000001301'), 11000::numeric, 'milk: 6 000 + 4 000 + 1 000');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000001302'), 2000::numeric, 'cream: 2 000');
select test.eq((select string_agg(coalesce(invoice_no, '-') || ':' || final, ',' order by received_at, invoice_no) from public.purchase_receipts), 'F-100:false,F-117:true,-:true',
               'every delivery is kept with its invoice');
select test.eq((select count(distinct receipt_id)::int from public.stock_moves where receipt_id is not null), 3, 'stock moves point to their delivery');
select test.login('cafe'); set role authenticated;
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000001301', '[]', gen_random_uuid())->>'error', 'locked', 'a locked café device cannot receive');
reset role;
select test.done();
rollback;
