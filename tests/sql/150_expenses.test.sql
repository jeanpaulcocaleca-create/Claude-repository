-- Migration 0014: expenses with creditable IVA, posted to the ledger.
begin;
select test.login('cafe'); set role authenticated;
select test.eq(public.expense_save('{"date":"2026-10-01","description":"x","account":"6204","amount_crc":1130,"paid_from":"cash"}', gen_random_uuid())->>'error',
               'not_allowed', 'a locked café device cannot record expenses');
select test.unlock(test.staff('ana'), '4826');
select public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Jabón y cloro', 'vendor_name', 'Súper Monteverde', 'account', '6204',
       'amount_crc', 11300, 'iva_crc', 1300, 'paid_from', 'petty', 'invoice_no', '00100001010000012345'), '7e000000-0000-4000-8000-000000001501') as x1 \gset
select test.eq((:'x1'::jsonb)->>'ok', 'true', 'a manager with a PIN records a petty-cash expense');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Jabón y cloro', 'vendor_name', 'Súper Monteverde', 'account', '6204',
       'amount_crc', 11300, 'iva_crc', 1300, 'paid_from', 'petty', 'invoice_no', '00100001010000012345'), '7e000000-0000-4000-8000-000000001501')->>'repeat', 'true',
       'sending it again changes nothing');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'otra vez', 'vendor_name', 'súper monteverde', 'account', '6204',
       'amount_crc', 11300, 'paid_from', 'cash', 'invoice_no', '00100001010000012345'), gen_random_uuid())->>'error', 'duplicate_invoice',
       'the same invoice of the same supplier is refused');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'x', 'account', '1101', 'amount_crc', 100, 'paid_from', 'cash'), gen_random_uuid())->>'error',
       'bad_account', 'only expense accounts');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'x', 'account', '6299', 'amount_crc', 100, 'iva_crc', 100, 'paid_from', 'cash'), gen_random_uuid())->>'error',
       'bad_value', 'IVA must be less than the total');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'expense'),
               '1103:-11300.00,1140:1300.00,6204:10000.00', 'posted: expense without IVA + IVA credit against petty cash');
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.expense_void('7e000000-0000-4000-8000-000000001501', 'error')->>'error', 'not_allowed', 'a manager cannot void it');
reset role;
select test.login('accountant'); set role authenticated;
select test.eq(public.expense_void('7e000000-0000-4000-8000-000000001501', '')->>'error', 'missing_reason', 'a void needs a reason');
select test.eq(public.expense_void('7e000000-0000-4000-8000-000000001501', 'factura duplicada')->>'ok', 'true', 'the accountant voids it');
select test.eq(jsonb_array_length(public.expense_list(public.cr_today(), public.cr_today())->'expenses'), 1, 'it stays on the list, voided');
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Jabón', 'vendor_name', 'Súper Monteverde', 'account', '6204',
       'amount_crc', 11300, 'iva_crc', 1300, 'paid_from', 'bank', 'invoice_no', '00100001010000012345'), gen_random_uuid())->>'ok', 'true',
       'after a void, the invoice can be entered again correctly');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(l.debit - l.credit) from acct.lines l where l.account = '6204'), 10000::numeric, 'the voided expense nets to zero; the new one remains');
select test.done();
rollback;
