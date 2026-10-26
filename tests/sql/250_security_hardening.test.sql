-- Migration 0025: each finding of the pre-release security review, tried again as an attack.
begin;
-- 1) the owner's PIN on the café tablet is not the owner's phone-code login
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('dueno'), '7391');
select test.eq(public.is_true_owner(), true, 'the owner''s PIN opens the owner areas on the tablet, as before');
select test.eq(acct.can_read(), false, 'but not the books');
select test.eq(public.acct_overview()->>'error', 'not_allowed', 'the ledger stays closed');
select test.eq(public.setting_set('operator_mode', '"record"')->>'error', 'owner_only', 'switches need the phone code');
select test.eq(public.compliance_confirm('price_display_rules', 'x', 'y')->>'error', 'owner_only', 'legal confirmations need the phone code');
select test.eq(public.tax_rate_save('IVA0', 'cero', 0, 'x', 'y')->>'error', 'owner_only', 'tax rates need the phone code');
select test.eq(public.accountant_grant('cafe@test.local')->>'error', 'owner_only', 'and so does giving accountant access');
select test.eq(public.payroll_staff()->>'error', 'not_allowed', 'pay rates stay closed');
select test.eq(public.bank_overview(null, null, null)->>'error', 'not_allowed', 'the bank stays closed');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.accountant_grant('cafe@test.local')->>'error', 'is_cafe_login', 'the café login never becomes the accountant''s');
reset role;

-- 2) the accountant always with the phone code
select test.login('accountant'); set role authenticated;
select test.eq(public.account_kind(), 'accountant_needs_code', 'a password alone is not enough');
select test.eq(public.acct_overview()->>'error', 'not_allowed', 'the books stay closed without the code');
reset role;

-- 3) a manager PIN alone does not open the sales numbers
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.product_profitability(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'profit by product needs the sales permission');
select test.eq(public.iva_report(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'so does the IVA of the period');
select test.eq(public.tax_summary(public.cr_today(), public.cr_today())->>'error', 'locked', 'and the sales IVA summary');
select test.eq(public.dashboard_today()->>'error', 'not_allowed', 'and today''s numbers');
select test.eq(public.cash_reconciliation(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'and the cash by day');
reset role;

-- 4) money is a number: NaN and infinity are refused
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.expense_save('{"date":"2026-10-01","description":"x","account":"6299","amount_crc":"NaN","iva_crc":0,"paid_from":"bank"}', gen_random_uuid())->>'error',
               'bad_value', 'an expense of NaN is refused (0034/0035 answer bad_value before the finite check of 0025 is reached)');
select test.throws($$select public.acct_entry_post(public.cr_today(), 'x', '[{"account":"1110","debit":"Infinity"},{"account":"3101","credit":"Infinity"}]', gen_random_uuid())$$,
                   'finite|unbalanced|infinity|overflow', 'an entry of infinity is refused');
reset role;

-- 5) nothing dated into a month before one already closed
set constraints all immediate; set constraints all deferred;
insert into acct.periods (id, starts_on, ends_on, status) values
  (extract(year from public.cr_today())::int * 100 + extract(month from public.cr_today())::int,
   date_trunc('month', public.cr_today())::date, (date_trunc('month', public.cr_today()) + interval '1 month - 1 day')::date, 'locked')
  on conflict (id) do update set status = 'locked';
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.expense_save(jsonb_build_object('date', (date_trunc('month', public.cr_today()) - interval '2 months')::date, 'description', 'atrasado',
       'account', '6299', 'amount_crc', 1000, 'iva_crc', 0, 'paid_from', 'bank'), gen_random_uuid())->>'error', 'period_closed', 'a month before a locked one is born closed');
reset role;
delete from acct.periods where id >= 200001;   -- test only: nothing was posted

-- 6) payables: the supplier is locked while an invoice or payment is saved (checked by reading the function)
select test.ok(position('for update' in pg_get_functiondef('public.supplier_payment_save(jsonb, uuid)'::regprocedure)) > 0, 'payments of a supplier one at a time');
select test.ok(position('for update' in pg_get_functiondef('public.supplier_invoice_save(jsonb, uuid)'::regprocedure)) > 0, 'invoices of a supplier one at a time');

-- 7) the bank: posting again after an undo makes a new entry; dollar accounts wait
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.bank_account_save('{"name":"BAC dólares","gl_account":"1111","currency":"USD"}')->>'error', 'usd_not_supported', 'dollar accounts wait');
select (public.bank_account_save('{"name":"BCR","gl_account":"1110"}'))->>'id' as acc \gset
select public.bank_import(:'acc', 'x.csv', jsonb_build_array(jsonb_build_object('date', public.cr_today(), 'description', 'COMISION', 'amount', -350)), gen_random_uuid());
reset role;
select id as fee from public.bank_lines where description = 'COMISION' \gset
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.bank_post(:'fee', '[{"account":"6299","amount":-350}]', null)->>'ok', 'true', 'posted to the wrong account');
select test.eq(public.bank_undo(:'fee')->>'ok', 'true', 'undone');
select test.eq(public.bank_auto_match(:'acc')->>'matched', '0', 'the reversed entry is not matched again');
select test.eq(public.bank_post(:'fee', '[{"account":"6208","amount":-350}]', null)->>'ok', 'true', 'posted again, to the right account');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(debit - credit) from acct.lines where account = '6208'), 350::numeric, 'the second posting is in the books');
select test.eq((select coalesce(sum(debit - credit), 0) from acct.lines where account = '6299'), 0::numeric, 'the first one is reversed');

-- 8) the dollar rate typed by hand stays within reason
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today() - 1, 500, 510, 'hacienda');
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.fx_rate_set(public.cr_today(), 5000, 5100)->>'error', 'bad_value', 'a rate of 5 000 is refused');
select test.eq(public.fx_rate_set(public.cr_today(), 560, 570)->>'error', 'big_change', 'a jump of more than 5 % needs the owner with the code');
select test.eq(public.fx_rate_set(public.cr_today(), 502, 512)->>'ok', 'true', 'a normal rate is typed');
reset role;

-- 9) inventory: an opening balance never rewrites the cost of an item with history; received lines stay
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000002501', 'Leche', 'ml', 1000, 1000);
insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('5a000000-0000-4000-8000-000000002501', 'purchase', 5000, 1);
select test.throws($$insert into public.stock_moves (item_id, kind, qty) values ('5a000000-0000-4000-8000-000000002501', 'adjust', 'NaN')$$, 'finite', 'not even in stock');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.stock_receive('5a000000-0000-4000-8000-000000002501', 0.001, 0.001, null, null, null, true)->>'ok', 'true', 'an "opening" on an item with history');
reset role;
select test.ok((select avg_cost > 0.9 from public.stock_items where id = '5a000000-0000-4000-8000-000000002501'), 'its average cost is not rewritten');
insert into public.purchase_orders (id, status) values ('9a000000-0000-4000-8000-000000002501', 'received');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, received_qty, unit_cost)
  values ('9b000000-0000-4000-8000-000000002501', '9a000000-0000-4000-8000-000000002501', '5a000000-0000-4000-8000-000000002501', 1, 1000, 1000, 1);
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$update public.purchase_lines set received_qty = 0 where id = '9b000000-0000-4000-8000-000000002501'$$, 'purchase_line_history', 'a received line is not rewritten');
select test.throws($$update public.stock_items set unit = '<img src=x onerror=alert(1)>' where id = '5a000000-0000-4000-8000-000000002501'$$, 'stock_items_unit_known', 'an item''s unit is one the pages know');
reset role;

-- 10) the café tablet sees the cash of earlier days only with the sales permission
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000002501', now() - interval '2 days', 1000, 'cash_crc', true, 'done');
insert into public.cash_tenders (order_id, crc_in, recorded_at) values ('0d000000-0000-4000-8000-000000002501', 1000, now() - interval '2 days');
select test.login('cafe'); set role authenticated;
select test.eq((select count(*)::int from public.cash_tenders where order_id = '0d000000-0000-4000-8000-000000002501'), 0, 'an earlier day''s cash is not visible');
reset role;

-- 11) the PIN: a wrong try is counted under a row lock (checked by reading the function)
select test.ok(position('for update' in pg_get_functiondef('public._verify_pin(uuid, text, boolean)'::regprocedure)) > 0, 'tries are counted one by one');
select test.done();
rollback;
