-- Migration 0019: money put into and taken out of the drawer; payouts documented later; cash reconciliation.
begin;
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today(), 500, 510, 'hacienda');
select test.login('cafe'); set role authenticated;
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"bank","amount":1000,"reason":"x"}', gen_random_uuid())->>'error',
               'not_open', 'nothing moves before the register is open');
select test.eq(public.register_open(test.staff('ana'), '4826', 50000, 20)->>'ok', 'true', 'register opened with ₡50 000 and $20');
-- a cash sale of ₡10 000
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000002001', 'total_crc', 10000, 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 10000, 'qty', 1))));
-- a barista cannot move money; a manager can, with the reason
select test.eq(public.register_cash_move(test.staff('luis'), '1357', '{"direction":"out","purpose":"bank","amount":1000,"reason":"x"}', gen_random_uuid())->>'error',
               'not_manager', 'a barista''s PIN does not move money');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"payout","amount":4500,"reason":""}', gen_random_uuid())->>'error',
               'missing_reason', 'the reason is required');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"in","purpose":"payout","amount":4500,"reason":"x"}', gen_random_uuid())->>'error',
               'bad_value', 'a payout only goes out');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"payout","amount":4500,"reason":"Leche en el súper"}',
               '7e000000-0000-4000-8000-000000002001')->>'ok', 'true', 'a payout for a purchase');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"payout","amount":4500,"reason":"Leche en el súper"}',
               '7e000000-0000-4000-8000-000000002001')->>'repeat', 'true', 'sent twice, saved once');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"bank","amount":30000,"reason":"Depósito BCR"}',
               '7e000000-0000-4000-8000-000000002002')->>'ok', 'true', 'cash taken to the bank');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"in","purpose":"bank","amount":20000,"reason":"Cambio en monedas"}',
               '7e000000-0000-4000-8000-000000002003')->>'ok', 'true', 'change brought from the bank');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"owner","currency":"USD","amount":10,"reason":"El dueño"}',
               '7e000000-0000-4000-8000-000000002004')->>'ok', 'true', 'the owner takes $10');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', '{"direction":"out","purpose":"petty","amount":5000,"reason":"equivocado"}',
               '7e000000-0000-4000-8000-000000002005')->>'ok', 'true', 'a movement typed wrong');
select test.eq(public.register_cash_void(test.staff('ana'), '4826', '7e000000-0000-4000-8000-000000002005', 'era otro monto')->>'ok', 'true', 'voided while the day is open');
-- 50 000 + 10 000 − 4 500 − 30 000 + 20 000 = 45 500 ; $20 − $10 = $10
select test.eq((public.register_expected()->>'expected_crc')::numeric, 45500::numeric, 'the drawer expects the money in and out');
select test.eq((public.register_expected()->>'expected_usd')::numeric, 10::numeric, 'and the dollars');
select test.eq(jsonb_array_length(public.register_cash_moves()->'moves'), 5, 'the counter lists the day''s movements, voided included');
select public.register_close(test.staff('ana'), '4826', 0, 45500, null, 10) as c \gset
select test.eq((:'c'::jsonb)#>>'{register,cash_diff_crc}', '0', 'the count is exact: no false shortage');
select test.eq((:'c'::jsonb)#>>'{register,cash_diff_usd}', '0.00', 'in dollars too');
select test.eq(public.register_cash_void(test.staff('ana'), '4826', '7e000000-0000-4000-8000-000000002002', 'x')->>'error', 'closed_day', 'after the close, nothing is voided');
reset role;

-- the books: each movement against where the money went
select test.login('accountant'); set role authenticated;
select test.eq(public.acct_post_days(public.cr_today(), public.cr_today())->>'entries', '1', 'the day is posted');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source = 'day' and l.account in ('1101', '1102', '1104', '1110', '3102')),
               '1101:-4500.00,1102:-5000.00,1104:4500.00,1110:10000.00,3102:5000.00',
               'cash: +10 000 sale − 4 500 − 30 000 + 20 000; bank +10 000; payout to document; owner $10 at ₡500');

-- the accountant documents the payout with the supermarket invoice
select test.login('accountant'); set role authenticated;
select public.cash_payouts(public.cr_today(), public.cr_today()) as po \gset
select test.eq(((:'po'::jsonb)#>>'{payouts,0,documented_crc}')::numeric, 0::numeric, 'the payout waits for its document');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Leche', 'vendor_name', 'Súper', 'account', '6299',
       'amount_crc', 4500, 'iva_crc', 0, 'paid_from', 'payout', 'payout_id', '7e000000-0000-4000-8000-000000002002'), gen_random_uuid())->>'error', 'bad_payout',
       'only a payout can be linked');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Leche', 'vendor_name', 'Súper', 'account', '6299',
       'amount_crc', 4500, 'iva_crc', 0, 'paid_from', 'payout', 'payout_id', '7e000000-0000-4000-8000-000000002001'), gen_random_uuid())->>'ok', 'true',
       'the expense, paid with the payout');
select test.eq(((public.cash_payouts(public.cr_today(), public.cr_today()))#>>'{payouts,0,documented_crc}')::numeric, 4500::numeric, 'now documented');
select public.cash_reconciliation(public.cr_today(), public.cr_today()) as cr \gset
select test.eq(((:'cr'::jsonb)#>>'{days,0,sales_crc}')::numeric, 10000::numeric, 'reconciliation: cash sales');
select test.eq(((:'cr'::jsonb)#>>'{days,0,out_crc}')::numeric || '|' || ((:'cr'::jsonb)#>>'{days,0,in_crc}')::numeric || '|' || ((:'cr'::jsonb)#>>'{days,0,out_usd}')::numeric,
               '34500.00|20000.00|10.00', 'reconciliation: money out and in, each currency');
select test.eq((:'cr'::jsonb)#>>'{days,0,diff_crc}', '0', 'and the difference');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(l.debit - l.credit) from acct.lines l where l.account = '1104'), 0::numeric, 'nothing left to document');
select test.login('cafe'); set role authenticated;
select test.eq(public.register_cash_void(test.staff('ana'), '4826', '7e000000-0000-4000-8000-000000002001', 'x')->>'error', 'closed_day', 'a documented payout stays');
select test.eq(public.cash_reconciliation(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'the café device does not read the reconciliation');
reset role;
select test.done();
rollback;
