-- Migration 0011: receipt numbers, history search, logged reprints.
begin;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001201', 'total_crc', 2200, 'payment_method', 'cash_crc', 'guest_name', 'Ana María',
       'tender', jsonb_build_object('crc_in', 5000, 'change_crc', 2800),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001202', 'total_crc', 1300, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, receipt_no) values ('0d000000-0000-4000-8000-000000001203', now(), 900, 'card', true, 'done', 1);
reset role;
select test.ok((select receipt_no from public.orders where id = '0d000000-0000-4000-8000-000000001202')
             > (select receipt_no from public.orders where id = '0d000000-0000-4000-8000-000000001201'), 'receipt numbers go up');
select test.ok((select receipt_no <> 1 from public.orders where id = '0d000000-0000-4000-8000-000000001203'), 'the till cannot choose a number');
-- yesterday, its register closed
insert into public.register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name)
  values (public.cr_today() - 1, 'Ana', 50000, now() - interval '10 hours', 'Ana');
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000001204', public.cr_day_start(public.cr_today() - 1) + interval '10 hours', 2500, 'card', true, 'done');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000001204', 'Mocha', 2500, 1);

-- today, any café device ------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select public.order_search(public.cr_today(), public.cr_today()) as s \gset
select test.eq(jsonb_array_length((:'s'::jsonb)->'orders'), 3, 'today''s three sales');
select test.eq((select (x->'tender'->>'change_crc')::int from jsonb_array_elements((:'s'::jsonb)->'orders') x where x->>'id' = '0d000000-0000-4000-8000-000000001201'), 2800, 'with the cash received and change');
select test.eq(jsonb_array_length((public.order_search(public.cr_today(), public.cr_today(), 'maría'))->'orders'), 1, 'by guest name, any case');
select test.eq(jsonb_array_length((public.order_search(public.cr_today(), public.cr_today(), 'espres'))->'orders'), 1, 'by item');
select test.eq(jsonb_array_length((public.order_search(public.cr_today(), public.cr_today(), null, null, 2200))->'orders'), 1, 'by amount');
select test.eq((public.order_search(public.cr_today(), public.cr_today()))->'orders'->0->>'can_void', 'true', 'today''s sale can be voided');
-- earlier days need a manager
select test.eq(public.order_search(public.cr_today() - 1, public.cr_today())->>'error', 'locked', 'yesterday needs a manager''s PIN');
select test.unlock(test.staff('ana'), '4826');
select public.order_search(public.cr_today() - 1, public.cr_today() - 1) as y \gset
select test.eq(jsonb_array_length((:'y'::jsonb)->'orders'), 1, 'with it: yesterday''s sale');
select test.eq((:'y'::jsonb)->'orders'->0->>'can_refund', 'true', 'a closed day''s sale is offered for refund, not void');
select test.eq((:'y'::jsonb)->'orders'->0->>'can_void', 'false', 'and cannot be voided');
select test.eq(public.order_search(public.cr_today() - 200, public.cr_today())->>'error', 'bad_range', 'at most three months at a time');
-- a reprint is logged
select test.eq(public.order_reprint('0d000000-0000-4000-8000-000000001204', 'Caja')->>'ok', 'true', 'a reprint is allowed');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'receipt_reprint' and target_id = '0d000000-0000-4000-8000-000000001204'), 'and logged');
select test.login('anon'); set role anon;
select test.throws($$select public.order_search(current_date, current_date)$$, 'permission denied', 'visitors cannot search sales');
reset role;
select test.done();
rollback;
