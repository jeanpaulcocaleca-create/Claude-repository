-- Migration 0006: a paid sale is voided only while its register day is open; later, it is refunded today.
begin;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000000701', 'Leche', 'ml', 1000, 1000);
insert into public.stock_moves (item_id, kind, qty, note) values ('5a000000-0000-4000-8000-000000000701', 'adjust', 10000, 'test');
insert into public.recipes (menu_item_id, stock_item_id, qty)
  select id, '5a000000-0000-4000-8000-000000000701', 200 from public.menu_items where name = 'Latte';

-- yesterday: register opened and closed; a card sale with a latte
insert into public.register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name)
  values (public.cr_today() - 1, 'Ana', 50000, now() - interval '10 hours', 'Ana');
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000000701', public.cr_day_start(public.cr_today() - 1) + interval '10 hours', 2500, 'card', true, 'done');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000000701', 'Latte', 2500, 1);
-- five days ago, a day with no register at all
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000000702', public.cr_day_start(public.cr_today() - 5) + interval '10 hours', 1500, 'cash_crc', true, 'done');
-- two days ago: register still open (nobody closed it)
insert into public.register_days (business_date, opened_by_name, float_crc) values (public.cr_today() - 2, 'Ana', 50000);
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000000703', public.cr_day_start(public.cr_today() - 2) + interval '10 hours', 1800, 'sinpe', true, 'done');
-- an unpaid bill opened three days ago
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, guest_name)
  values ('0d000000-0000-4000-8000-000000000704', now() - interval '3 days', 3000, 'pending', false, 'ready', 'Mesa 2');
-- today: a cash sale
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000000705', now(), 1200, 'cash_crc', true, 'done');

-- 1) voids --------------------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000701', 'error')->>'error', 'closed_day',
               'a paid sale of a closed register day cannot be voided');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000702', 'error')->>'error', 'closed_day',
               'nor one from an earlier day that never had a register');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000703', 'error')->>'ok', 'true',
               'a sale from a day whose register is still open can be voided');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000704', 'walked out')->>'ok', 'true',
               'an unpaid bill can be voided any day');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000705', 'wrong item')->>'ok', 'true',
               'today''s sale can be voided');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000705', 'again')->>'error', 'already_voided',
               'not twice');
select test.eq(public.manager_void_order(test.staff('luis'), '5284', '0d000000-0000-4000-8000-000000000701', 'x')->>'error', 'not_manager',
               'a staff PIN cannot void');
reset role;

-- 2) refund of yesterday's sale ------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000701', '')->>'error', 'missing_reason',
               'a refund needs a reason');
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000701', 'leche cortada', true, 'tarjeta')->>'error',
               'bad_method', 'an unknown payment method is refused');
select public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000701', 'leche cortada', true) as r \gset
select test.eq((:'r'::jsonb)->>'ok', 'true', 'yesterday''s sale is refunded');
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000701', 'otra vez')->>'error', 'refunded',
               'not twice');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000701', 'x')->>'error', 'refunded',
               'a refunded sale cannot then be voided');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', ((:'r'::jsonb)->>'refund_id')::uuid, 'x')->>'error', 'is_refund',
               'the refund itself cannot be voided');
reset role;
select test.eq((select total_crc || '|' || payment_method || '|' || business_date::text || '|' || refund_of::text from public.orders
                 where id = ((:'r'::jsonb)->>'refund_id')::uuid),
               '-2500|card|' || public.cr_today()::text || '|0d000000-0000-4000-8000-000000000701', 'the money goes back today, the same way it came in');
select test.ok((select refunded_at is not null and voided_at is null from public.orders where id = '0d000000-0000-4000-8000-000000000701'),
               'the original sale stays on its day, marked refunded');
select test.eq((select qty from public.stock_moves where order_id = ((:'r'::jsonb)->>'refund_id')::uuid), 200::numeric, 'the latte''s milk went back to stock');
select test.eq((select unit_cost from public.stock_moves where order_id = ((:'r'::jsonb)->>'refund_id')::uuid),
               (select unit_cost from public.stock_moves where order_id = '0d000000-0000-4000-8000-000000000701'), 'at the cost it went out with');
select test.ok(exists (select 1 from public.audit_log where action = 'order_refund' and target_id = '0d000000-0000-4000-8000-000000000701'
                       and manager_name = 'Ana'), 'the refund is in the approvals log');

-- the other way: cash back for the five-days-ago sale, without restocking
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000702', 'cliente', false, 'cash_crc')->>'restocked',
               '0', 'a refund without restock moves no stock');
-- today's open-day sale is voided, not refunded
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000000706', now(), 900, 'cash_crc', true, 'done');
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000706', 'x')->>'error', 'void_instead',
               'a sale of a day still open is voided instead');
reset role;

-- 3) the till cannot forge a refund link -------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, refund_of, refunded_at)
  values ('0d000000-0000-4000-8000-000000000707', now(), 900, 'cash_crc', true, 'done', '0d000000-0000-4000-8000-000000000706', now());
reset role;
select test.ok((select refund_of is null and refunded_at is null from public.orders where id = '0d000000-0000-4000-8000-000000000707'),
               'refund fields from the till are ignored');

-- 4) today's register close counts the refunds today --------------------------------------------------------
insert into public.register_days (business_date, opened_by_name, float_crc) values (public.cr_today(), 'Ana', 50000);
select test.login('cafe'); set role authenticated;
select public.register_close(test.staff('ana'), '4826', 0, 50000, null) as c \gset
reset role;
-- yesterday's register stays closed and untouched; today's: 900 + 900 cash − 1500 cash refund; card −2500
select test.eq(((:'c'::jsonb)->'register'->>'business_date')::date, public.cr_today() - 2, 'the oldest open day closes first (as before)');
select test.login('cafe'); set role authenticated;
select public.register_close(test.staff('ana'), '4826', 0, 50300, null) as c2 \gset
reset role;
select test.eq(((:'c2'::jsonb)->'register'->>'sales_cash_crc')::int, 900 + 900 - 1500, 'today''s cash includes the cash refund');
select test.eq(((:'c2'::jsonb)->'register'->>'sales_card_crc')::int, -2500, 'and the card refund');
select test.eq((select sales_total_crc from public.register_days where business_date = public.cr_today() - 1), null::int,
               'yesterday''s closed register was not recalculated');

-- 5) only café devices ----------------------------------------------------------------------------------------
select test.login('f0000000-0000-4000-8000-000000000799'); set role authenticated;
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000706', 'x')->>'error', 'no_account',
               'a login that is not a café device cannot refund');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000000706', 'x')->>'error', 'no_account',
               'nor void');
reset role;

select test.done();
rollback;
