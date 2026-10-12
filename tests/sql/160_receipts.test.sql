-- Migration 0015: expense receipt files (private), the accountant's IVA summary.
begin;
select test.login('accountant'); set role authenticated;
select public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Cloro', 'account', '6204', 'amount_crc', 1130, 'iva_crc', 130, 'paid_from', 'cash'),
                           '7e000000-0000-4000-8000-000000001601');
select test.lives($$insert into storage.objects (bucket_id, name) values ('expense-receipts', '7e000000-0000-4000-8000-000000001601/factura.jpg')$$, 'the accountant uploads a receipt');
select test.eq(public.expense_attach('7e000000-0000-4000-8000-000000001601', '7e000000-0000-4000-8000-000000001601/factura.jpg')->>'ok', 'true', 'and attaches it to the expense');
select test.eq(public.expense_attach('7e000000-0000-4000-8000-000000001601', '7e000000-0000-4000-8000-000000001601/otra.jpg')->>'error', 'already_attached', 'a filed receipt is not replaced');
select test.eq(public.expense_attach('7e000000-0000-4000-8000-000000001601', 'otro-gasto/x.jpg')->>'error', 'bad_path', 'only a file in the expense''s own folder');
select test.eq((select count(*)::int from storage.objects where bucket_id = 'expense-receipts'), 1, 'the accountant sees the receipts');
select test.eq(public.tax_summary(public.cr_today(), public.cr_today())->>'ok', 'true', 'the accountant reads the IVA summary of sales');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq((select count(*)::int from storage.objects where bucket_id = 'expense-receipts'), 0, 'a café device cannot see the receipts');
select test.throws($$insert into storage.objects (bucket_id, name) values ('expense-receipts', 'x/y.jpg')$$, 'row-level security', 'nor upload one');
reset role;
select test.login('anon'); set role anon;
select test.eq((select count(*)::int from storage.objects where bucket_id = 'expense-receipts'), 0, 'visitors see nothing');
reset role;
select test.eq((select public from storage.buckets where id = 'expense-receipts'), false, 'the bucket is private');
select test.done();
rollback;
