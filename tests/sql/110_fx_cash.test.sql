-- Migration 0010: exchange rate of the day, cash received and change, the register in colones and dollars.
begin;
-- 1) rates ------------------------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.fx_today()->>'stale', 'true', 'no rate yet: the POS is told');
select test.eq(public.fx_rate_set(public.cr_today(), 505, 512)->>'error', 'owner_only', 'the café login cannot type a rate');
reset role;
-- Hacienda's answer, as the job receives it
select test.eq(canopy.fx_record_hacienda('{"venta":{"fecha":"2026-10-12","valor":512.34},"compra":{"fecha":"2026-10-12","valor":505.11}}'::jsonb),
               '2026-10-12'::date, 'an answer from Hacienda is recorded');
select test.throws($$select canopy.fx_record_hacienda('{"venta":{"valor":5},"compra":{"valor":4}}'::jsonb)$$, 'fx_bad_answer', 'a nonsense answer is refused');
delete from public.fx_rates;
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today() - 1, 500, 510, 'hacienda');
select test.login('cafe'); set role authenticated;
select test.eq((public.fx_today()->>'rate')::numeric, 500::numeric, 'yesterday''s buy rate until today''s arrives');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.fx_rate_set(public.cr_today() - 1, 501, 511)->>'error', 'official_exists', 'a manager never overwrites the official rate');
select test.eq(public.fx_rate_set(public.cr_today(), 502, 512)->>'ok', 'true', 'a manager types today''s rate');
select test.eq(public.fx_rate_set(public.cr_today(), 900, 512)->>'error', 'bad_value', 'buy far above sell is refused');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'fx_rate_set'), 'a typed rate is logged');
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('fx_rate_kind', '"sell"');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq((public.fx_today()->>'rate')::numeric, 512::numeric, 'the owner can choose the sell rate');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('fx_rate_kind', '"buy"');
reset role;

-- 2) cash with change, dollars with change in colones, mixed --------------------------------------------------------
insert into public.register_days (business_date, opened_by_name, float_crc, float_usd) values (public.cr_today(), 'Ana', 50000, 20);
select test.login('cafe'); set role authenticated;
-- ₡2 200 paid with a ₡5 000 note: ₡2 800 change
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001101', 'total_crc', 2200, 'payment_method', 'cash_crc',
       'tender', jsonb_build_object('crc_in', 5000, 'change_crc', 2800),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1))));
-- ₡4 400 paid with $10 at 502: 5 020 − 4 400 = ₡620 change
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001102', 'total_crc', 4400, 'payment_method', 'cash_usd',
       'tender', jsonb_build_object('usd_in', 10, 'fx_rate', 502, 'change_crc', 620),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 2))));
-- ₡3 000 paid with $5 + ₡500 at 502: 2 510 + 500 = 3 010 → ₡10 change
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001103', 'total_crc', 3000, 'payment_method', 'cash_usd',
       'tender', jsonb_build_object('usd_in', 5, 'crc_in', 500, 'fx_rate', 502, 'change_crc', 10),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 3))));
-- a tender that does not add up, and a rate far from the official one
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001104', 'total_crc', 1000, 'payment_method', 'cash_usd',
       'tender', jsonb_build_object('usd_in', 2, 'fx_rate', 600, 'change_crc', 0),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Tea', 'price_crc', 1000, 'qty', 1))));
-- the same sale sent again keeps the first tender
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001101', 'total_crc', 2200, 'payment_method', 'cash_crc',
       'tender', jsonb_build_object('crc_in', 10000, 'change_crc', 7800),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1))));
-- an old sale without tender detail (a page before this update)
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000001105', now(), 1500, 'cash_usd', true, 'done');
reset role;
select test.eq((select crc_in || '|' || change_crc from public.cash_tenders where order_id = '0d000000-0000-4000-8000-000000001101'), '5000|2800', 'the first tender is kept');
select test.eq((select flags from public.cash_tenders where order_id = '0d000000-0000-4000-8000-000000001102'), '{}'::text[], 'a correct dollar payment has no flags');
select test.eq((select flags from public.cash_tenders where order_id = '0d000000-0000-4000-8000-000000001104'), '{mismatch,rate_differs}'::text[],
               'a tender that does not add up and an odd rate are marked');
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_tender('0d000000-0000-4000-8000-000000001101', '{"crc_in": 1}')->>'already', 'true', 'pos_record_tender is repeat-safe');
select test.eq(public._tender_insert('0d000000-0000-4000-8000-000000001105', '{"usd_in": 3}')->>'error', 'bad_value', 'dollars need a rate');
reset role;

-- 3) the drawer in two currencies --------------------------------------------------------------------------------------
-- colones: 50 000 float + (5 000 − 2 800) + (0 − 620) + (500 − 10) + 0 + 1 500 (old page: counted as before) = 53 570
-- dollars: 20 float + 10 + 5 + 2 = 37
select test.login('cafe'); set role authenticated;
select test.eq(public.register_expected()->>'expected_crc', '53570', 'the counter screen expects ₡53 570');
select test.eq((public.register_expected()->>'expected_usd')::numeric, 37::numeric, 'and $37');
select public.register_close(test.staff('ana'), '4826', 0, 53570, null, 36) as c \gset
reset role;
select test.eq(((:'c'::jsonb)->'register'->>'cash_diff_crc')::int, 0, 'colones match');
select test.eq(((:'c'::jsonb)->'register'->>'cash_diff_usd')::numeric, -1::numeric, 'one dollar short');
select test.eq(((:'c'::jsonb)->'register'->>'fx_rate')::numeric, 502::numeric, 'the day''s rate is kept with the close');
-- the POS of before still closes (no dollar count)
select test.login('cafe'); set role authenticated;
select test.eq((public.register_close(test.staff('ana'), '4826', 0, 53570, null)->'register'->>'cash_counted_usd'), null, 'an older POS still closes');
reset role;

select test.done();
rollback;
