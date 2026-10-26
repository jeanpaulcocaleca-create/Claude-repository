-- Migration 0003: ring time, payment time and business day of every order.
begin;

-- a normal sale from the till ----------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, rung_at, paid_at, business_date, flags)
  values ('0d000000-0000-4000-8000-000000000401', now() - interval '3 minutes', 2000, 'card', true, 'done',
          '2020-01-01', '2020-01-01', '2020-01-01', '{forged}');
reset role;
select test.eq((select rung_at from public.orders where id = '0d000000-0000-4000-8000-000000000401'),
               (select created_at from public.orders where id = '0d000000-0000-4000-8000-000000000401'), 'ring time = the till''s sale time');
select test.eq((select paid_at from public.orders where id = '0d000000-0000-4000-8000-000000000401'),
               (select created_at from public.orders where id = '0d000000-0000-4000-8000-000000000401'), 'paid at the sale time');
select test.eq((select business_date from public.orders where id = '0d000000-0000-4000-8000-000000000401'), public.cr_today(), 'counts today');
select test.eq((select flags from public.orders where id = '0d000000-0000-4000-8000-000000000401'), '{}'::text[], 'the till cannot forge flags');
select test.ok((select received_at is not null from public.orders where id = '0d000000-0000-4000-8000-000000000401'), 'server receipt time recorded');

-- a bill opened yesterday and paid today ------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, guest_name)
  values ('0d000000-0000-4000-8000-000000000402', now() - interval '26 hours', 3000, 'pending', false, 'ready', 'Mesa 4');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000000402', 'Latte', 3000, 1);
reset role;
select test.ok((select paid_at is null and business_date is null from public.orders where id = '0d000000-0000-4000-8000-000000000402'),
               'an unpaid bill has no payment time and no business day yet');
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_pay('0d000000-0000-4000-8000-000000000402', 'cash_crc', null, null, 'Caja', 3000)->>'closed', 'true', 'paid today');
reset role;
select test.ok((select rung_at < now() - interval '25 hours' from public.orders where id = '0d000000-0000-4000-8000-000000000402'),
               'the original ring time is kept after a later-day payment');
select test.ok((select paid_at >= now() - interval '1 minute' from public.orders where id = '0d000000-0000-4000-8000-000000000402'),
               'the payment time is today');
select test.eq((select business_date from public.orders where id = '0d000000-0000-4000-8000-000000000402'), public.cr_today(),
               'the money counts on the payment day');
select test.ok((select created_at >= now() - interval '1 minute' from public.orders where id = '0d000000-0000-4000-8000-000000000402'),
               'created_at still moves to the payment day (register close unchanged)');

-- a part payment made by the server ---------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000000403', now(), 4000, 'pending', false, 'ready');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000000403', 'Mocha', 2000, 2);
select public.tab_pay('0d000000-0000-4000-8000-000000000403', 'card', null, 1500, 'Caja', 4000);
reset role;
select test.eq((select business_date from public.orders where part_of = '0d000000-0000-4000-8000-000000000403'), public.cr_today(),
               'a part payment counts on its own day');

-- a sale synced after its day was closed ----------------------------------------------------------------
insert into public.register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name)
  values (public.cr_today() - 2, 'Ana', 50000, now() - interval '40 hours', 'Ana');
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000000404', public.cr_day_start(public.cr_today() - 2) + interval '15 hours', 1500, 'cash_crc', true, 'done');
reset role;
select test.ok((select 'after_close' = any(flags) and 'late_sync' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000000404'),
               'a late sale for a closed day is flagged');
select test.eq((select business_date from public.orders where id = '0d000000-0000-4000-8000-000000000404'), public.cr_today() - 2,
               'it keeps the day it was rung');
select test.ok(exists (select 1 from public.audit_log where action = 'late_sale_after_close' and target_id = '0d000000-0000-4000-8000-000000000404'),
               'the manager sees it in the approvals log');

-- a device clock running ahead -------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000000405', now() + interval '2 hours', 1500, 'cash_crc', true, 'done');
reset role;
select test.ok((select 'clock_ahead' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000000405'), 'a clock ahead is flagged');

-- backfill of older rows ----------------------------------------------------------------------------------
alter table public.orders disable trigger order_times_upd;
update public.orders set rung_at = null, paid_at = null, business_date = null where id = '0d000000-0000-4000-8000-000000000402';
alter table public.orders enable trigger order_times_upd;
select test.ok(canopy.backfill_order_times() >= 1, 'backfill fills older rows');
select test.ok((select rung_at < created_at - interval '25 hours' from public.orders where id = '0d000000-0000-4000-8000-000000000402'),
               'backfill recovers the original ring time from the bill''s lines');

select test.done();
rollback;
