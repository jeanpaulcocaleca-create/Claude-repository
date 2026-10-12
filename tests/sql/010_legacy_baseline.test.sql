-- Regression baseline: behaviour that works in production today and must keep working.
begin;

-- fixtures (as the database owner)
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, on_hand)
  values ('5a000000-0000-4000-8000-000000000001', 'Leche', 'ml', 1000, 1200, 10000);
insert into public.recipes (menu_item_id, stock_item_id, qty)
  select id, '5a000000-0000-4000-8000-000000000001', 150 from public.menu_items where name = 'Latte' limit 1;

-- 1) the café tablet records a sale; recipes take stock out ---------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, station)
  values ('0d000000-0000-4000-8000-000000000001', now(), 4400, 'cash_crc', true, 'done', 'Caja');
insert into public.order_items (id, order_id, item_name, price_crc, qty)
  values (gen_random_uuid(), '0d000000-0000-4000-8000-000000000001', 'Latte', 2200, 2);
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000001'), 9700::numeric,
               'a sale of 2 lattes takes 300 ml of milk');

-- a second set of lines on the same sale is refused (pos-tabs)
select test.login('cafe'); set role authenticated;
select test.throws($$insert into public.order_items (order_id, item_name, price_crc, qty)
                     values ('0d000000-0000-4000-8000-000000000001', 'Latte', -2200, 1)$$, 'order_has_lines',
                   'lines cannot be added to a saved sale directly');
-- the till cannot rewrite money columns
select test.throws($$update public.orders set total_crc = 1 where id = '0d000000-0000-4000-8000-000000000001'$$,
                   'permission denied', 'the till cannot change a sale total');
reset role;

-- anonymous visitors cannot record sales
select test.login('anon'); set role anon;
select test.throws($$insert into public.orders (total_crc, payment_method) values (100, 'cash_crc')$$, 'permission denied|row-level security',
                   'anonymous visitors cannot insert orders');
reset role;

-- 2) time clock with PIN and lockout ----------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.clock_punch(test.staff('luis'), '5284')->>'action', 'in', 'Luis clocks in with his PIN');
select test.eq(public.clock_punch(test.staff('luis'), '0000')->>'error', 'bad_pin', 'a wrong PIN is refused');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('luis')), 1, 'the wrong PIN is counted');
select test.login('cafe'); set role authenticated;
select public.clock_punch(test.staff('luis'), '0000') from generate_series(1, 4);
select test.eq(public.clock_punch(test.staff('luis'), '5284')->>'error', 'locked', 'five wrong PINs lock the person out');
reset role;

-- 3) discounts need a manager and are single-use ----------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.approve_discount(test.staff('marta'), '6173', 'percent', 10, 5000, 'cliente frecuente', 'Caja')->>'error',
               'not_manager', 'a team member cannot approve a discount');
create temp table t_disc as select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'cliente frecuente', 'Caja') as r;
select test.eq((select r->>'ok' from t_disc), 'true', 'a manager approves a 10% discount');
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, subtotal_crc, discount_crc, discount_id)
  select '0d000000-0000-4000-8000-000000000002', now(), 4500, 'card', true, 'done', 5000, 500, (r->>'id')::uuid from t_disc;
select test.throws($$insert into public.orders (id, created_at, total_crc, payment_method, paid, status, subtotal_crc, discount_crc, discount_id)
                     select gen_random_uuid(), now(), 4500, 'card', true, 'done', 5000, 500, (r->>'id')::uuid from t_disc$$,
                   'discount_used|duplicate', 'the same approval cannot be used twice');
select test.throws($$insert into public.orders (id, created_at, total_crc, payment_method, paid, status, subtotal_crc, discount_crc)
                     values (gen_random_uuid(), now(), 4000, 'card', true, 'done', 5000, 1000)$$,
                   'discount_not_approved', 'a discount without approval is refused');
reset role;

-- 4) open bill, split payment, closing payment -------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, station, guest_name)
  values ('0d000000-0000-4000-8000-000000000003', now(), 6000, 'pending', false, 'ready', 'Caja', 'Mesa 2');
insert into public.order_items (order_id, item_name, price_crc, qty)
  values ('0d000000-0000-4000-8000-000000000003', 'Americano', 1500, 4);
select test.eq((public.tab_pay('0d000000-0000-4000-8000-000000000003', 'cash_crc', null, 2000, 'Caja', 6000))->>'amount', '2000',
               'a guest pays ₡2 000 of the bill');
select test.eq((public.tab_pay('0d000000-0000-4000-8000-000000000003', 'card', null, null, 'Caja', 4000))->>'closed', 'true',
               'the last payment closes the bill');
reset role;
select test.eq((select count(*)::int from public.orders where part_of = '0d000000-0000-4000-8000-000000000003'), 1,
               'the part payment is its own sale row');
select test.eq((select sum(total_crc)::int from public.orders
                 where (id = '0d000000-0000-4000-8000-000000000003' or part_of = '0d000000-0000-4000-8000-000000000003')
                   and paid and voided_at is null), 6000, 'money received on the bill adds up to the bill, counted once');

-- 5) register closing sums the day on the server -----------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.register_open(test.staff('marta'), '6173', 50000)->>'ok', 'true', 'the register opens with a float');
create temp table t_close as select public.register_close(test.staff('marta'), '6173', 8500, 52000 + 4400, null) as r;
reset role;
select test.eq((select (r->'register'->>'sales_total_crc')::int from t_close), 4400 + 4500 + 6000,
               'register close totals today''s paid sales');
select test.eq((select (r->'register'->>'sales_card_crc')::int from t_close), 4500 + 4000, 'card total by method');
select test.eq((select (r->'register'->>'cash_diff_crc')::int from t_close), 0, 'cash difference computed on the server');

-- 6) voids need a manager PIN and a reason, and never delete ----------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_void_order(test.staff('marta'), '6173', '0d000000-0000-4000-8000-000000000001', 'error')->>'error',
               'not_manager', 'a team member cannot void');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000001', '')->>'error',
               'missing_reason', 'a void needs a reason');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000001', 'cliente se fue')->>'ok',
               'true', 'a manager voids with PIN and reason');
reset role;
select test.ok((select voided_at is not null from public.orders where id = '0d000000-0000-4000-8000-000000000001'),
               'the voided sale stays on record');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000000001'), 10000::numeric,
               'the void puts the milk back');
select test.ok(exists (select 1 from public.audit_log where action = 'order_void'), 'the void is in the approvals log');

-- 7) the owner sees the approvals log, the café login does not --------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq((select count(*)::int from public.audit_log), 0, 'café login cannot read the approvals log');
reset role;

select test.done();
rollback;
