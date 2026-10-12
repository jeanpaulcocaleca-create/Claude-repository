-- Migration 0020: bank accounts, statement import without duplicates, matching, posting, undo.
begin;
-- in the books already: a cash deposit and a transfer to a supplier
select acct.post(public.cr_today() - 2, 'Depósito de la caja', 'manual', 'test:dep',
                 '[{"account":"1110","debit":30000},{"account":"1101","credit":30000}]'::jsonb, null, 'prueba');
select acct.post(public.cr_today() - 1, 'Pago a proveedor', 'ap', 'test:pay',
                 '[{"account":"2101","debit":5000},{"account":"1110","credit":5000}]'::jsonb, null, 'prueba');

select test.login('cafe'); set role authenticated;
select test.eq(public.bank_overview(null, null, null)->>'error', 'not_allowed', 'a café device does not see the bank');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.bank_overview(null, null, null)->>'error', 'not_allowed', 'nor a manager with a PIN');
reset role;

select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.bank_account_save('{"name":"BCR colones","gl_account":"6208"}')->>'error', 'bad_account', 'a bank account goes to a cash or bank account of the books');
select public.bank_account_save('{"name":"BCR colones","bank":"BCR","gl_account":"1110","last4":"1234-5678-9012-3456"}') as ba \gset
select test.eq((:'ba'::jsonb)->>'ok', 'true', 'the accountant adds the account');
select (:'ba'::jsonb)->>'id' as acc \gset
reset role;
select test.eq((select last4 from public.bank_accounts), '3456', 'only the last 4 digits are kept');
select test.login('accountant', 'aal2'); set role authenticated;
select public.bank_import(:'acc', 'octubre.csv', jsonb_build_array(
  jsonb_build_object('date', public.cr_today() - 2, 'description', 'DEPOSITO EFECTIVO', 'amount', 30000, 'balance', 130000),
  jsonb_build_object('date', public.cr_today() - 1, 'description', 'TRANSF  PROVEEDOR', 'reference', '991', 'amount', -5000, 'balance', 125000),
  jsonb_build_object('date', public.cr_today() - 1, 'description', 'COMISION MANTENIMIENTO', 'amount', -350, 'balance', 124650),
  jsonb_build_object('date', public.cr_today(), 'description', 'LIQUIDACION TARJETAS', 'amount', 9500, 'balance', 134150),
  jsonb_build_object('date', public.cr_today(), 'description', 'SINPE MOVIL', 'amount', 1000),
  jsonb_build_object('date', public.cr_today(), 'description', 'SINPE MOVIL', 'amount', 1000)), '7e000000-0000-4000-8000-000000002101') as im \gset
select test.eq((:'im'::jsonb)->>'added', '6', 'six movements imported, the two identical SINPE both kept');
select test.eq(public.bank_import(:'acc', 'octubre.csv', '[]', '7e000000-0000-4000-8000-000000002101')->>'repeat', 'true', 'the same upload sent twice');
select test.eq(public.bank_import(:'acc', 'octubre-completo.csv', jsonb_build_array(
  jsonb_build_object('date', public.cr_today() - 1, 'description', 'transf proveedor', 'reference', '991', 'amount', -5000),
  jsonb_build_object('date', public.cr_today(), 'description', 'SINPE MOVIL', 'amount', 1000),
  jsonb_build_object('date', public.cr_today(), 'description', 'SINPE MOVIL', 'amount', 1000),
  jsonb_build_object('date', public.cr_today(), 'description', 'SINPE MOVIL', 'amount', 1000)), gen_random_uuid())->>'added', '1',
  'a statement that overlaps adds only what is new (a third SINPE)');
select test.eq(public.bank_import(:'acc', 'malo.csv', '[{"date":"2026-10-01","description":"x","amount":"abc"}]', gen_random_uuid())->>'error', 'bad_rows',
               'a file that does not read is refused whole');
select test.eq(public.bank_auto_match(:'acc')->>'matched', '2', 'the deposit and the transfer match the books by themselves');
reset role;
select id as fee from public.bank_lines where description = 'COMISION MANTENIMIENTO' \gset
select id as card from public.bank_lines where description = 'LIQUIDACION TARJETAS' \gset
select min(id) as s1 from public.bank_lines where description = 'SINPE MOVIL' \gset
select id as dep_line from acct.lines where account = '1110' and debit = 30000 \gset
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.bank_post(:'fee', '[{"account":"6208","amount":-300}]', null)->>'error', 'parts_differ', 'the parts must add up to the bank''s amount');
select test.eq(public.bank_post(:'fee', '[{"account":"1110","amount":-350}]', null)->>'error', 'bad_account', 'never against the bank''s own account');
select test.eq(public.bank_post(:'fee', '[{"account":"6208","amount":-350}]', null)->>'ok', 'true', 'a bank charge the books did not have');
select test.eq(public.bank_post(:'card', '[{"account":"1120","amount":10000},{"account":"6208","amount":-500,"memo":"comisión 5 %"}]', 'Liquidación de tarjetas')->>'ok',
               'true', 'a card deposit: the card sales, less the fee');
select test.eq(public.bank_ignore(:'s1', '')->>'error', 'missing_reason', 'ignoring needs a note');
select test.eq(public.bank_ignore(:'s1', 'transferencia entre cuentas propias')->>'ok', 'true', 'ignored with a note');
select public.bank_overview(:'acc', public.cr_today() - 30, public.cr_today()) as ov \gset
select test.eq(((:'ov'::jsonb)#>>'{summary,book_balance}')::numeric, 34150::numeric, 'books: 30 000 − 5 000 − 350 + 9 500');
select test.eq(((:'ov'::jsonb)#>>'{summary,statement_balance}')::numeric, 134150::numeric, 'statement: its last balance');
select test.eq(((:'ov'::jsonb)#>>'{summary,open_statement}')::numeric, 2000::numeric, 'two SINPE still to reconcile');
select test.eq(((:'ov'::jsonb)#>>'{summary,book_only}')::numeric, 0::numeric, 'nothing in the books missing from the bank');
select test.eq((select count(*)::int from jsonb_array_elements((:'ov'::jsonb)->'lines') x where x->>'status' = 'matched' and x->'ledger' is not null), 2,
               'matched lines show their entry');
-- undo: the bank charge's entry is reversed and the line is open again
select test.eq(public.bank_undo(:'fee')->>'ok', 'true', 'a posted line is undone');
select test.eq(public.bank_match(:'fee', :'dep_line')->>'error', 'no_match', 'a match needs the same amount');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(debit - credit) from acct.lines where account = '6208'), 500::numeric, 'only the card fee remains after the undo');
select test.eq((select sum(debit - credit) from acct.lines where account = '1120'), -10000::numeric, 'the card sales cleared');
select test.eq((select status from public.bank_lines where id = :'fee'), 'open', 'the charge is open again');
select test.done();
rollback;
