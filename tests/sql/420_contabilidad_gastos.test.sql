-- Migration 0035 (docs/CONTABILIDAD-REDISENO.md): expenses that repeat as templates a person confirms (nothing is ever
-- posted alone), payments of expenses on credit against the same 2101, the aging and the drawer payouts that count them;
-- then the reversal drill: supabase/tools/reversion-0035.sql and reversion-0034.sql leave every changed function exactly
-- as production has it at version 33, keep every record, and both migrations apply again.
begin;
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today(), 500, 510, 'hacienda') on conflict (day) do nothing;
insert into public.vendors (id, name, default_account, default_paid_from, default_iva_rate) values
  ('5b000000-0000-4000-8000-000000004201', 'Distribuidora Norte', '6205', 'credit', 0.13),
  ('5b000000-0000-4000-8000-000000004202', 'Inmobiliaria Verde', '6201', 'bank', 0);
select to_char(public.cr_today(), 'YYYY-MM-DD') as today \gset
select extract(isodow from public.cr_today())::int as dow \gset

-- every guard in one string: each probe stops right after its guard (an unknown payment, expense or template, an
-- account that does not exist), so an allowed caller writes nothing and the answer tells the guard from the validation
create function pg_temp.guards() returns text language sql as $$
  select concat_ws(' ',
    'expense_pay=' || coalesce(public.expense_pay(jsonb_build_object('expense_id', '00000000-0000-4000-8000-000000000000', 'amount_crc', 1, 'paid_from', 'bank', 'date', public.cr_today()),
                                                  gen_random_uuid())->>'error', 'ok'),
    'expense_payment_void=' || coalesce(public.expense_payment_void('00000000-0000-4000-8000-000000000000', 'x')->>'error', 'ok'),
    'expense_schedule_save=' || coalesce(public.expense_schedule_save('{"account":"9999"}'::jsonb)->>'error', 'ok'),
    'expense_schedule_void=' || coalesce(public.expense_schedule_void('00000000-0000-4000-8000-000000000000', 'x')->>'error', 'ok'),
    'expense_schedules_list=' || coalesce(public.expense_schedules_list()->>'error', 'ok'),
    'expense_due=' || coalesce(public.expense_due(7)->>'error', 'ok'));
$$;
select 'expense_pay=not_allowed expense_payment_void=not_allowed expense_schedule_save=not_allowed expense_schedule_void=not_allowed expense_schedules_list=not_allowed expense_due=not_allowed' as all_closed \gset
select 'expense_pay=not_found expense_payment_void=not_found expense_schedule_save=bad_account expense_schedule_void=not_found expense_schedules_list=ok expense_due=ok' as all_open \gset

-- 1) who may call what: the owner with the phone code or the accountant, never a tablet with a PIN -----------------------------
select test.login('anon'); set role anon;
select test.throws($$select public.expense_pay('{}'::jsonb, gen_random_uuid())$$, 'permission denied', 'a visitor cannot even call expense_pay');
select test.throws($$select public.expense_due(7)$$, 'permission denied', 'nor expense_due');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the café login without a PIN: everything closed');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.access_level(), 'manager', 'café + manager PIN: the owner areas of the tablet are open, so the refusals below mean something');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', gen_random_uuid(), 'amount_crc', 1, 'paid_from', 'bank', 'date', :'today'), gen_random_uuid())->>'error', 'not_allowed',
               'café + manager PIN: cannot pay an expense on credit');
select test.eq(public.expense_payment_void(gen_random_uuid(), 'x')->>'error', 'not_allowed', 'café + manager PIN: cannot void a payment');
select test.eq(public.expense_schedule_save('{"account":"6201"}'::jsonb)->>'error', 'not_allowed', 'café + manager PIN: cannot create a template');
select test.eq(public.expense_schedule_void(gen_random_uuid(), 'x')->>'error', 'not_allowed', 'café + manager PIN: cannot deactivate one');
select test.eq(public.expense_schedules_list()->>'error', 'not_allowed', 'café + manager PIN: cannot list them');
select test.eq(public.expense_due(7)->>'error', 'not_allowed', 'café + manager PIN: cannot see what is due');
select test.eq(pg_temp.guards(), :'all_closed', 'café + manager PIN: everything closed');
reset role;
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('dueno'), '7391');
select test.eq(pg_temp.guards(), :'all_closed', 'café + owner-role PIN: everything closed (the phone code is the owner''s own login)');
reset role;
select test.login('owner', 'aal1'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the owner without the phone code: everything closed');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_open', 'the owner with the phone code: everything open');
reset role;
select test.login('accountant', 'aal1'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the accountant without the phone code: everything closed');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_open', 'the accountant with the phone code: everything open');
reset role;
select test.eq((select count(*)::int from public.expense_payments) || '|' || (select count(*)::int from public.expense_schedules) || '|' || (select count(*)::int from acct.entries), '0|0|0',
               'the guard probes wrote nothing');
select test.ok(not has_function_privilege('anon', 'public.expense_pay(jsonb, uuid)', 'execute') and not has_function_privilege('anon', 'public.expense_payment_void(uuid, text)', 'execute')
               and not has_function_privilege('anon', 'public.expense_schedule_save(jsonb)', 'execute') and not has_function_privilege('anon', 'public.expense_schedule_void(uuid, text)', 'execute')
               and not has_function_privilege('anon', 'public.expense_schedules_list()', 'execute') and not has_function_privilege('anon', 'public.expense_due(int)', 'execute')
               and not has_function_privilege('anon', 'public._schedule_next(text, int, date)', 'execute'), 'a visitor may call none of them');
select test.ok(has_function_privilege('authenticated', 'public.expense_pay(jsonb, uuid)', 'execute') and has_function_privilege('authenticated', 'public.expense_payment_void(uuid, text)', 'execute')
               and has_function_privilege('authenticated', 'public.expense_schedule_save(jsonb)', 'execute') and has_function_privilege('authenticated', 'public.expense_schedule_void(uuid, text)', 'execute')
               and has_function_privilege('authenticated', 'public.expense_schedules_list()', 'execute') and has_function_privilege('authenticated', 'public.expense_due(int)', 'execute'),
               'a login may call the page''s functions (each one checks who it is)');
select test.ok(not has_function_privilege('authenticated', 'public._schedule_next(text, int, date)', 'execute') and not has_function_privilege('authenticated', 'public._expense_open(uuid)', 'execute'),
               'the internal ones are not callable from a page');

-- 2) an expense on credit and its payments ------------------------------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Harina y azúcar', 'amount_crc', 32600, 'iva_crc', 3600,
               'paid_from', 'credit', 'invoice_no', 'DN-1', 'date', :'today'), '7e000000-0000-4000-8000-000000004201')->>'ok', 'true', 'an expense on credit: 32 600 with 3 600 of IVA');
select public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 10000, 'paid_from', 'bank', 'date', :'today', 'reference', 'TRF 55'),
       '7e000000-0000-4000-8000-000000004211') as p1 \gset
select test.eq(((:'p1'::jsonb)->>'ok') || '|' || ((:'p1'::jsonb)->>'open_crc')::numeric || '|' || ((:'p1'::jsonb)->>'id'), 'true|22600.00|7e000000-0000-4000-8000-000000004211',
               'the accountant pays 10 000 from the bank: 22 600 still owed');
select test.ok(((:'p1'::jsonb)->>'entry_id') is not null, 'the payment posted an entry');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 10000, 'paid_from', 'bank', 'date', :'today'),
               '7e000000-0000-4000-8000-000000004211')->>'repeat', 'true', 'sending it again changes nothing');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'paid_from', 'cash', 'date', :'today'), '7e000000-0000-4000-8000-000000004212')->>'open_crc',
               '0.00', 'without an amount, the rest is paid: nothing owed');
select public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 1, 'paid_from', 'bank', 'date', :'today'), gen_random_uuid()) as p3 \gset
select test.eq(((:'p3'::jsonb)->>'error') || '|' || ((:'p3'::jsonb)->>'owed')::numeric, 'more_than_owed|0.00', 'one colón more than owed is refused, and the answer says what is owed');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 0, 'paid_from', 'bank', 'date', :'today'), gen_random_uuid())->>'error',
               'bad_value', 'a payment of zero');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 100, 'paid_from', 'credit', 'date', :'today'), gen_random_uuid())->>'error',
               'bad_value', 'a payment never leaves from credit');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 100, 'paid_from', 'bank'), gen_random_uuid())->>'error',
               'bad_value', 'a payment needs its date');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'amount_crc', 100, 'paid_from', 'bank', 'date', :'today'), null)->>'error',
               'bad_request', 'a request without its id');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Café en grano', 'amount_crc', 11300, 'iva_crc', 1300,
               'paid_from', 'credit', 'date', public.cr_today() - 5), '7e000000-0000-4000-8000-000000004202')->>'ok', 'true', 'a second expense on credit, five days old');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004202', 'amount_crc', 1000, 'paid_from', 'bank', 'date', public.cr_today() + 1), gen_random_uuid())->>'error',
               'future_date', 'no payments dated tomorrow');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004202', 'amount_crc', 1000, 'paid_from', 'payout', 'payout_id', gen_random_uuid(), 'date', :'today'),
               gen_random_uuid())->>'error', 'bad_payout', 'only a real drawer payout can be linked');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', gen_random_uuid(), 'amount_crc', 1000, 'paid_from', 'bank', 'date', :'today'), gen_random_uuid())->>'error', 'not_found',
               'an expense that does not exist');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Hielo', 'amount_crc', 2000, 'iva_crc', 0, 'paid_from', 'cash',
               'date', :'today'), '7e000000-0000-4000-8000-000000004204')->>'ok', 'true', 'an expense paid in cash');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004204', 'amount_crc', 1000, 'paid_from', 'bank', 'date', :'today'), gen_random_uuid())->>'error',
               'not_credit', 'an expense already paid takes no payments');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Servilletas', 'amount_crc', 5000, 'iva_crc', 0, 'paid_from', 'credit',
               'date', :'today'), '7e000000-0000-4000-8000-000000004203')->>'ok', 'true', 'a third expense on credit');
select test.eq(public.expense_void('7e000000-0000-4000-8000-000000004203', 'duplicado')->>'ok', 'true', 'voided');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004203', 'amount_crc', 1000, 'paid_from', 'bank', 'date', :'today'), gen_random_uuid())->>'error',
               'already_voided', 'a voided expense takes no payments');
-- the first payment was a mistake: its void gives the money back to what is owed, as a mirror entry
select test.eq(public.expense_payment_void('7e000000-0000-4000-8000-000000004211', '')->>'error', 'missing_reason', 'a void needs a reason');
select test.eq(public.expense_payment_void(gen_random_uuid(), 'x')->>'error', 'not_found', 'a payment that does not exist');
select test.eq(public.expense_payment_void('7e000000-0000-4000-8000-000000004211', 'transferencia rechazada')->>'ok', 'true', 'the accountant voids the bank payment');
select test.eq(public.expense_payment_void('7e000000-0000-4000-8000-000000004211', 'otra vez')->>'error', 'already_voided', 'only once');
select public.expense_list(public.cr_today() - 30, public.cr_today()) as el \gset
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select count(*)::int from public.expense_payments), 2, 'two payments saved (the repeat and every refusal saved none)');
select test.eq(public._expense_open('7e000000-0000-4000-8000-000000004201'), 10000::numeric, 'after the void: 10 000 owed again (32 600 − 22 600)');
select test.eq(public._expense_open('7e000000-0000-4000-8000-000000004202'), 11300::numeric, 'the second expense owes all of it');
select test.eq(public._expense_open('7e000000-0000-4000-8000-000000004203'), 0::numeric, 'a voided expense owes nothing');
select test.eq(public._expense_open('7e000000-0000-4000-8000-000000004204'), 0::numeric, 'nor one paid in cash');
select test.eq((select e.source || '|' || e.source_key || '|' || string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.id = ((:'p1'::jsonb)->>'entry_id')::bigint group by e.id), 'expense|exppay:7e000000-0000-4000-8000-000000004211|1110:-10000.00,2101:10000.00',
               'the payment: owed to suppliers goes down, the bank goes down');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'exppay:7e000000-0000-4000-8000-000000004212'), '1101:-22600.00,2101:22600.00', 'the rest left the drawer');
select test.eq((select e.source || '|' || (e.reverses = p.entry_id) || '|' || string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account)
                  from public.expense_payments p join acct.entries e on e.id = p.void_entry_id join acct.lines l on l.entry_id = e.id
                 where p.id = '7e000000-0000-4000-8000-000000004211' group by e.id, p.entry_id), 'reversal|true|1110:10000.00,2101:-10000.00',
               'the void is the mirror of the payment and points to it');
select test.eq((select voided_at is not null and void_reason = 'transferencia rechazada' and void_entry_id is not null and entry_id is not null and reference = 'TRF 55' and paid_from = 'bank'
                  from public.expense_payments where id = '7e000000-0000-4000-8000-000000004211'), true, 'the voided payment keeps both entries, its reason and its reference');
select test.eq((select created_by from public.expense_payments where id = '7e000000-0000-4000-8000-000000004212'), 'contador · contador@test.local', 'the accountant signed the payment');
select test.eq((select count(*)::int from public.audit_log where action = 'expense_payment' and target_id = '7e000000-0000-4000-8000-000000004201'), 3, 'two payments and one void in the log');
select test.eq((select string_agg(left(summary, 16), ',' order by id) from public.audit_log where action = 'expense_payment'), 'pago de 10000.00,pago de 22600.00,pago anulado: tr',
               'the log says the amounts and the void');
select test.eq((select (details->>'open_after') || '|' || (details->>'payment_id') from public.audit_log where action = 'expense_payment' order by id limit 1), '22600.00|7e000000-0000-4000-8000-000000004211',
               'and what was still owed after each payment');
-- the list shows each expense with what was paid, what is open and every payment, voided ones included
select test.eq((select (x->>'paid_crc')::numeric || '|' || (x->>'open_crc')::numeric || '|' || jsonb_array_length(x->'payments') from jsonb_array_elements((:'el'::jsonb)->'expenses') x
                 where x->>'id' = '7e000000-0000-4000-8000-000000004201'), '22600.00|10000.00|2', 'the list: paid 22 600, open 10 000, two payments');
select test.eq((select string_agg((p->>'paid_from') || ':' || (p->>'amount_crc')::numeric || ':' || (p->>'voided_at' is not null), ',') from jsonb_array_elements((:'el'::jsonb)->'expenses') x,
                 jsonb_array_elements(x->'payments') p where x->>'id' = '7e000000-0000-4000-8000-000000004201'), 'bank:10000.00:true,cash:22600.00:false', 'each payment with its state');
select test.eq((select (x->>'paid_crc')::numeric || '|' || (x->>'open_crc')::numeric || '|' || jsonb_array_length(x->'payments') from jsonb_array_elements((:'el'::jsonb)->'expenses') x
                 where x->>'id' = '7e000000-0000-4000-8000-000000004204'), '0|0|0', 'a cash expense: nothing paid later, nothing open');

-- 3) ap_aging: what is owed on expenses net of their payments; 2101 ties out --------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004202', 'number', 'IV-1', 'date', :'today', 'due_date', public.cr_today() + 10,
               'net_crc', 100000, 'iva_crc', 0, 'account', '6201'), '7e000000-0000-4000-8000-000000004221')->>'ok', 'true', 'a supplier invoice for the rent, open');
select public.ap_aging() as ag \gset
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq(((:'ag'::jsonb)#>>'{ledger,expenses_on_credit}')::numeric, 32600 + 11300 - 22600::numeric,
               'expenses on credit: the two live ones less the payment that stands (the voided payment and the voided expense count for nothing)');
select test.eq(((:'ag'::jsonb)#>>'{ledger,expenses_on_credit}')::numeric, public._expense_open('7e000000-0000-4000-8000-000000004201') + public._expense_open('7e000000-0000-4000-8000-000000004202'),
               'which is what the two expenses say they owe');
select test.eq(((:'ag'::jsonb)#>>'{ledger,invoices_open}')::numeric || '|' || ((:'ag'::jsonb)#>>'{ledger,received_not_invoiced}')::numeric, '100000.00|0', 'the invoice open, nothing delivered without invoice');
select test.eq(((:'ag'::jsonb)#>>'{ledger,ap_balance}')::numeric, (select sum(l.credit - l.debit) from acct.lines l where l.account = '2101'), 'ap_balance is the 2101 balance');
select test.eq(((:'ag'::jsonb)#>>'{ledger,ap_balance}')::numeric,
               ((:'ag'::jsonb)#>>'{ledger,invoices_open}')::numeric + ((:'ag'::jsonb)#>>'{ledger,received_not_invoiced}')::numeric + ((:'ag'::jsonb)#>>'{ledger,expenses_on_credit}')::numeric,
               'the tie-out: 2101 = open invoices + deliveries without invoice + expenses on credit net of payments');
select test.eq(((:'ag'::jsonb)#>>'{vendors,0,total}')::numeric, 100000::numeric, 'the supplier with the open invoice');

-- 4) a payment made with money taken from the drawer documents that payout -----------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.register_open(test.staff('ana'), '4826', 50000, 0)->>'ok', 'true', 'the register opens');
select test.eq(public.register_cash_move(test.staff('ana'), '4826', jsonb_build_object('direction', 'out', 'purpose', 'payout', 'amount', 4500, 'reason', 'Abono a Distribuidora Norte'),
               '7e000000-0000-4000-8000-000000004231')->>'ok', 'true', 'Ana takes ₡4 500 from the drawer to pay the supplier');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(((public.cash_payouts(public.cr_today(), public.cr_today()))#>>'{payouts,0,documented_crc}')::numeric, 0::numeric, 'the payout waits for its document');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004202', 'amount_crc', 4500, 'paid_from', 'payout', 'payout_id', '7e000000-0000-4000-8000-000000004231',
               'date', :'today'), '7e000000-0000-4000-8000-000000004214')->>'open_crc', '6800.00', 'the payment from the payout: 6 800 still owed on the coffee');
select test.eq(((public.cash_payouts(public.cr_today(), public.cr_today()))#>>'{payouts,0,documented_crc}')::numeric, 4500::numeric, 'now the payout is documented by that payment');
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004202', 'amount_crc', 1000, 'paid_from', 'card_credit', 'date', :'today'),
               '7e000000-0000-4000-8000-000000004215')->>'open_crc', '5800.00', 'a credit card payment: 5 800 owed');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select payout_id::text from public.expense_payments where id = '7e000000-0000-4000-8000-000000004214'), '7e000000-0000-4000-8000-000000004231', 'the payment remembers its payout');
-- the cash position counts that payout as documented too (cash_position of 0035), and a credit expense with a payment standing is not voided
select test.eq((public.cash_position()->>'payouts_open')::numeric, 0::numeric, 'cash_position: the 4 500 payout is documented by the expense payment');
select test.eq(public.expense_void('7e000000-0000-4000-8000-000000004202', 'anular con pagos')->>'error', 'has_payments', 'a credit expense with payments standing is not voided: the payments go first');
select test.eq((select voided_at is null from public.expenses where id = '7e000000-0000-4000-8000-000000004202'), true, 'and it stays as it was');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'exppay:7e000000-0000-4000-8000-000000004214'), '1104:-4500.00,2101:4500.00', 'posted against the payouts to document (1104)');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'exppay:7e000000-0000-4000-8000-000000004215'), '2101:1000.00,2160:-1000.00', 'a credit card payment goes to the credit card liability');

-- 5) templates for the expenses that repeat: nothing is posted alone; the page offers what is due with a deterministic id ----------
select test.eq(public._schedule_next('month', 31, '2026-01-15') || '|' || public._schedule_next('month', 31, '2026-01-31') || '|' || public._schedule_next('month', 1, '2026-02-28') || '|'
               || public._schedule_next('month', 15, '2026-03-15') || '|' || public._schedule_next('month', 30, '2026-02-10'),
               '2026-01-31|2026-02-28|2026-03-01|2026-04-15|2026-02-28', 'monthly: the day of the month strictly after the date, cut to the month''s last day');
select test.eq(public._schedule_next('week', 1, '2026-10-26') || '|' || public._schedule_next('week', 5, '2026-10-26') || '|' || public._schedule_next('week', 7, '2026-10-24'),
               '2026-11-02|2026-10-30|2026-10-25', 'weekly: the next such weekday strictly after the date (a Monday after a Monday is the next one)');
select test.login('accountant', 'aal2'); set role authenticated;
select public.expense_schedule_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004202', 'description', 'Alquiler del local', 'account', '6201', 'amount_crc', 250000, 'iva_crc', 0,
       'paid_from', 'bank', 'every', 'month', 'day_of', 1, 'next_due', public.cr_today() + 20)) as s1 \gset
select test.eq(((:'s1'::jsonb)->>'ok') || '|' || ((:'s1'::jsonb)->>'next_due'), 'true|' || (public.cr_today() + 20), 'the rent, monthly, first due in 20 days as the page says');
select (:'s1'::jsonb)->>'id' as s1id \gset
select public.expense_schedule_save(jsonb_build_object('description', 'Internet', 'account', '6203', 'amount_crc', 33900, 'iva_crc', 3900, 'paid_from', 'bank', 'every', 'month', 'day_of', 15,
       'next_due', public.cr_today() + 30)) as s2 \gset
select (:'s2'::jsonb)->>'id' as s2id \gset
select public.expense_schedule_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Hielo semanal', 'account', '6299', 'amount_crc', 5000, 'iva_crc', 0,
       'paid_from', 'cash', 'every', 'week', 'day_of', :dow, 'next_due', :'today')) as s3 \gset
select test.eq(((:'s3'::jsonb)->>'ok') || '|' || ((:'s3'::jsonb)->>'next_due'), 'true|' || :'today', 'the weekly ice, due today');
select (:'s3'::jsonb)->>'id' as s3id \gset
select public.expense_schedule_save(jsonb_build_object('description', 'Luz', 'account', '6202', 'amount_crc', 40000, 'iva_crc', 0, 'paid_from', 'bank', 'every', 'month', 'day_of', 1)) as s4 \gset
select (:'s4'::jsonb)->>'id' as s4id \gset
select public.expense_schedule_save(jsonb_build_object('description', 'Agua', 'account', '6202', 'amount_crc', 12000, 'iva_crc', 0, 'paid_from', 'bank', 'every', 'month', 'day_of', 31,
       'next_due', :'today')) as s5 \gset
select (:'s5'::jsonb)->>'id' as s5id \gset
select test.eq(public.expense_schedule_save(jsonb_build_object('id', :'s4id', 'description', 'Luz', 'account', '6202', 'amount_crc', 40000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1,
               'next_due', public.cr_today() - 40))->>'next_due', (:'s4'::jsonb)->>'next_due', 'a due date in the past is moved to the next one by the rule');
reset role;
select test.eq(((:'s4'::jsonb)->>'next_due')::date, public._schedule_next('month', 1, public.cr_today() - 1), 'without a due date: the next first of the month, today included');
select test.ok(((:'s4'::jsonb)->>'next_due')::date >= public.cr_today(), 'never in the past');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'day', 'day_of', 1))->>'error', 'bad_value',
               'every week or every month, nothing else');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'week', 'day_of', 8))->>'error', 'bad_value',
               'a week has seven days');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 32))->>'error', 'bad_value',
               'a month has at most 31');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 0))->>'error', 'bad_value',
               'and no day zero');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 0, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error', 'bad_value',
               'an amount of zero');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 1000, 'iva_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error',
               'bad_value', 'IVA must be less than the amount');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'card', 'every', 'month', 'day_of', 1))->>'error', 'bad_value',
               'an unknown way of paying');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'account', '1101', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error', 'bad_account',
               'only expense accounts');
select test.eq(public.expense_schedule_save(jsonb_build_object('description', 'x', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error', 'bad_account',
               'and the account is required');
select test.eq(public.expense_schedule_save(jsonb_build_object('vendor_id', gen_random_uuid(), 'description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error',
               'no_vendor', 'a supplier that does not exist');
select test.eq(public.expense_schedule_save(jsonb_build_object('account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error', 'bad_value',
               'neither a supplier nor a description: nothing to call it');
select test.eq(public.expense_schedule_save(jsonb_build_object('id', gen_random_uuid(), 'description', 'x', 'account', '6202', 'amount_crc', 1000, 'paid_from', 'bank', 'every', 'month', 'day_of', 1))->>'error',
               'not_found', 'changing a template that does not exist');
select test.eq(public.expense_schedule_void(:'s4id', 'duplicada')->>'ok', 'true', 'the duplicate template is deactivated');
-- what is due: the water and the ice today, each with the id its registration must use (template, period, first try)
select public.expense_due(7) as due7 \gset
select test.eq(jsonb_array_length((:'due7'::jsonb)->'due') || '|' || ((:'due7'::jsonb)->>'days'), '2|7', 'within 7 days: the water and the ice (the rent in 20, the internet in 30, the light deactivated)');
select test.eq((select string_agg(d->>'description', ',') from jsonb_array_elements((:'due7'::jsonb)->'due') d), 'Agua,Hielo semanal', 'by due date, then by name');
select test.eq((select (d->>'period_key') || '|' || (d->>'overdue') || '|' || (d->>'vendor') || '|' || (d->>'account_name') from jsonb_array_elements((:'due7'::jsonb)->'due') d where d->>'id' = :'s3id'),
               :'today' || '|false|Distribuidora Norte|Otros gastos', 'the ice: its period is today, not overdue, with its supplier and account');
select test.eq((select d->>'request_id' from jsonb_array_elements((:'due7'::jsonb)->'due') d where d->>'id' = :'s3id'), md5(:'s3id' || ':' || :'today' || ':1')::uuid::text,
               'the request id is deterministic: template, period, first try');
select (select d->>'request_id' from jsonb_array_elements((:'due7'::jsonb)->'due') d where d->>'id' = :'s3id') as rid \gset
select test.eq((select string_agg(d->>'description', ',') from jsonb_array_elements(public.expense_due(60)->'due') d), 'Agua,Hielo semanal,Alquiler del local,Internet',
               'within 60 days: the four live templates in due order');
select test.eq(public.expense_due(999)->>'days' || '|' || (public.expense_due(-5)->>'days') || '|' || (public.expense_due(null)->>'days'), '60|0|7', 'the horizon is between 0 and 60 days, 7 by default');
-- a person confirms the ice: the expense is registered with the template's id and the template moves on
select public.expense_save(jsonb_build_object('schedule_id', :'s3id', 'period_key', :'today', 'vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Hielo semanal', 'account', '6299',
       'amount_crc', 5000, 'iva_crc', 0, 'paid_from', 'cash', 'date', :'today'), :'rid') as r1 \gset
select test.eq(((:'r1'::jsonb)->>'ok') || '|' || ((:'r1'::jsonb)->>'next_due'), 'true|' || (public.cr_today() + 7), 'registered; the weekly template is due again in a week');
select test.eq(public.expense_save(jsonb_build_object('schedule_id', :'s3id', 'period_key', :'today', 'vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Hielo semanal', 'account', '6299',
               'amount_crc', 5000, 'iva_crc', 0, 'paid_from', 'cash', 'date', :'today'), :'rid')->>'repeat', 'true', 'a double tap sends the same id: nothing doubles');
select test.eq((select string_agg(d->>'description', ',') from jsonb_array_elements(public.expense_due(0)->'due') d), 'Agua', 'due today: only the water remains');
select test.eq((select (d->>'period_key') || '|' || (d->>'request_id') from jsonb_array_elements(public.expense_due(7)->'due') d where d->>'id' = :'s3id'),
               (public.cr_today() + 7) || '|' || md5(:'s3id' || ':' || (public.cr_today() + 7) || ':1')::uuid, 'within 7 days: the ice again, next period, a new id');
select public.expense_save(jsonb_build_object('schedule_id', :'s5id', 'period_key', :'today', 'description', 'Agua', 'account', '6202', 'amount_crc', 12000, 'iva_crc', 0, 'paid_from', 'bank',
       'date', :'today'), md5(:'s5id' || ':' || :'today' || ':1')::uuid) as r2 \gset
select test.eq(((:'r2'::jsonb)->>'ok') || '|' || coalesce((:'r2'::jsonb)->>'repeat', '-'), 'true|-', 'the water, due today, is registered with its own id (not a repeat of the ice)');
select test.eq(jsonb_array_length(public.expense_due(0)->'due'), 0, 'nothing due today any more');
select test.eq(public.expense_save(jsonb_build_object('schedule_id', gen_random_uuid(), 'period_key', :'today', 'description', 'x', 'account', '6202', 'amount_crc', 1000, 'iva_crc', 0, 'paid_from', 'bank',
               'date', :'today'), gen_random_uuid())->>'error', 'bad_schedule', 'a template that does not exist');
select test.eq(public.expense_save(jsonb_build_object('schedule_id', :'s3id', 'description', 'x', 'account', '6202', 'amount_crc', 1000, 'iva_crc', 0, 'paid_from', 'bank', 'date', :'today'),
               gen_random_uuid())->>'error', 'bad_schedule', 'a template without the period it covers');
select test.eq(public.expense_save(jsonb_build_object('schedule_id', :'s3id', 'period_key', 'hoy', 'description', 'x', 'account', '6202', 'amount_crc', 1000, 'iva_crc', 0, 'paid_from', 'bank',
               'date', :'today'), gen_random_uuid())->>'error', 'bad_schedule', 'a period that is not a date');
select test.eq(public.expense_save(jsonb_build_object('schedule_id', :'s4id', 'period_key', :'today', 'description', 'x', 'account', '6202', 'amount_crc', 1000, 'iva_crc', 0, 'paid_from', 'bank',
               'date', :'today'), gen_random_uuid())->>'error', 'bad_schedule', 'a deactivated template');
-- deactivating and changing templates
select test.eq(public.expense_schedule_void(:'s2id', '')->>'error', 'missing_reason', 'deactivating needs a reason');
select test.eq(public.expense_schedule_void(gen_random_uuid(), 'x')->>'error', 'not_found', 'a template that does not exist');
select test.eq(public.expense_schedule_void(:'s2id', 'ya no hay internet')->>'ok', 'true', 'the internet template is deactivated');
select test.eq(public.expense_schedule_void(:'s2id', 'otra vez')->>'error', 'already_voided', 'only once');
select test.eq(jsonb_array_length(public.expense_due(60)->'due'), 3, 'it is no longer due');
select test.eq(public.expense_schedule_save(jsonb_build_object('id', :'s1id', 'vendor_id', '5b000000-0000-4000-8000-000000004202', 'description', 'Alquiler del local', 'account', '6201', 'amount_crc', 260000,
               'iva_crc', 0, 'paid_from', 'bank', 'every', 'month', 'day_of', 1, 'next_due', public.cr_today() + 20))->>'ok', 'true', 'the rent goes up');
select public.expense_schedules_list() as sl \gset
select test.eq(jsonb_array_length((:'sl'::jsonb)->'schedules'), 5, 'the five templates, deactivated ones included');
select test.eq((select string_agg(s->>'active', ',') from jsonb_array_elements((:'sl'::jsonb)->'schedules') s), 'true,true,true,false,false', 'live ones first, then the deactivated');
select test.eq((select string_agg(s->>'description', ',' order by s->>'description') from jsonb_array_elements((:'sl'::jsonb)->'schedules') s where (s->>'active')::boolean), 'Agua,Alquiler del local,Hielo semanal',
               'the live ones: the water, the rent, the ice');
select test.ok((select bool_and((s->>'next_due')::date <= (nxt->>'next_due')::date) from (select s, lead(s) over (order by n) as nxt from jsonb_array_elements((:'sl'::jsonb)->'schedules') with ordinality as t(s, n)) x
                 where nxt is not null and (s->>'active')::boolean and (nxt->>'active')::boolean), 'the live ones by due date');
select test.eq((select (s->>'registered') || '|' || (s->>'last_registered') || '|' || (s->>'next_due') || '|' || (s->>'vendor') from jsonb_array_elements((:'sl'::jsonb)->'schedules') s where s->>'id' = :'s3id'),
               '1|' || :'today' || '|' || (public.cr_today() + 7) || '|Distribuidora Norte', 'the ice: registered once, today, due in a week');
select test.eq((select (s->>'amount_crc')::numeric || '|' || (s->>'account_name') from jsonb_array_elements((:'sl'::jsonb)->'schedules') s where s->>'id' = :'s1id'), '260000.00|Alquiler',
               'the rent with its new amount and the account''s name');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select schedule_id::text || '|' || period_key || '|' || created_by from public.expenses where id = :'rid'), :'s3id' || '|' || :'today' || '|contador · contador@test.local',
               'the expense remembers its template and period');
select test.eq((select count(*)::int from public.expenses where schedule_id = :'s3id'), 1, 'one expense of the ice template');
select test.eq((select next_due from public.expense_schedules where id = :'s5id'), public._schedule_next('month', 31, public.cr_today()), 'the water moved to the next last day of a month');
select test.ok((select next_due > public.cr_today() from public.expense_schedules where id = :'s5id'), 'strictly after today');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key = 'expense:' || :'rid'),
               '1101:-5000.00,6299:5000.00', 'the ice posted like any expense, by a person');
select test.eq((select count(*)::int from public.audit_log where action = 'expense_schedule'), 9, 'five templates created, two changed, two deactivated: nine log lines');
select test.eq((select string_agg(left(summary, 9), ',' order by id) from public.audit_log where action = 'expense_schedule'),
               'plantilla,plantilla,plantilla,plantilla,plantilla,plantilla,plantilla,plantilla,plantilla', 'every line names the template');
select test.eq((select summary from public.audit_log where action = 'expense_schedule' and target_id = :'s2id' order by id desc limit 1), 'plantilla desactivada: Internet · ya no hay internet',
               'the deactivation with its reason');
select test.eq((select details#>>'{before,amount_crc}' from public.audit_log where action = 'expense_schedule' and target_id = :'s1id' order by id desc limit 1), '250000.00',
               'the change keeps the amount it replaced');

-- 6) every entry of this test balances --------------------------------------------------------------------------------------
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) x), 0, 'every entry balances');

-- 7) the reversal drill: 0035 then 0034 off, the database at version 33 as production has it, nothing lost; then both on again ----
select (select count(*) from public.expenses) || '|' || (select count(*) from acct.entries) || '|' || (select count(*) from public.audit_log) || '|'
    || (select count(*) from public.expense_payments) || '|' || (select count(*) from public.expense_schedules) as before \gset
\o /dev/null
\ir ../../supabase/tools/reversion-0035.sql
\ir ../../supabase/tools/reversion-0034.sql
\o
select test.eq(public.canopy_schema_version(), 33, 'the database is back at version 33');
select test.ok(to_regprocedure('public.expense_pay(jsonb, uuid)') is null and to_regprocedure('public.expense_payment_void(uuid, text)') is null
               and to_regprocedure('public.expense_schedule_save(jsonb)') is null and to_regprocedure('public.expense_schedule_void(uuid, text)') is null
               and to_regprocedure('public.expense_schedules_list()') is null and to_regprocedure('public.expense_due(int)') is null
               and to_regprocedure('public._schedule_next(text, int, date)') is null, 'the functions of 0035 are gone');
select test.ok(to_regprocedure('public.vendors_list()') is null and to_regprocedure('public.vendor_save(jsonb)') is null and to_regprocedure('public.vendor_defaults_save(uuid, jsonb)') is null
               and to_regprocedure('public.vendor_history(uuid, date, date)') is null and to_regprocedure('public.purchases_list(date, date, uuid)') is null
               and to_regprocedure('public.sales_by_method(date, date)') is null and to_regprocedure('public.cash_position()') is null
               and to_regprocedure('public.period_compare(date, date)') is null and to_regprocedure('public._period_figures(date, date, boolean)') is null
               and to_regprocedure('public.acct_audit(date, date)') is null and to_regprocedure('public._expense_allowed()') is null and to_regprocedure('public._expense_open(uuid)') is null,
               'the functions of 0034 are gone');
-- the fingerprints of a database built through 0033 only (tests/build-db.sh with 0034 and 0035 left out; md5 of pg_proc.prosrc, 12 characters, ordered by name)
select test.eq((select string_agg(left(md5(p.prosrc), 12), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('expense_save', 'expense_list', '_receipts_allowed', 'ap_aging', 'cash_payouts', 'expense_void')),
               '6d8daad1dfd0 e53345ffd77f 2a6f8a0e78b2 ff152d1c7d07 8da950602fcd b1dbf85bd8ea',   -- _receipts_allowed (0015), ap_aging (0016), cash_payouts (0019), expense_list (0014), expense_save (0019), expense_void (0014)
               'every function is byte for byte the one production has before 0034');
select test.ok(to_regclass('public.expense_schedules') is not null and to_regclass('public.expense_payments') is not null
               and exists (select 1 from information_schema.columns where table_name = 'expenses' and column_name = 'schedule_id')
               and exists (select 1 from information_schema.columns where table_name = 'expenses' and column_name = 'period_key')
               and exists (select 1 from information_schema.columns where table_name = 'vendors' and column_name = 'default_account'), 'the new tables and columns stay (unused)');
select test.eq((select count(*) from public.expenses) || '|' || (select count(*) from acct.entries) || '|' || (select count(*) from public.audit_log) || '|'
            || (select count(*) from public.expense_payments) || '|' || (select count(*) from public.expense_schedules), :'before', 'nothing written under 0034 or 0035 is removed');
select test.ok((select bool_and(default_account is not null) from public.vendors where id in ('5b000000-0000-4000-8000-000000004201', '5b000000-0000-4000-8000-000000004202')),
               'nor what the suppliers'' habits say');
select test.ok(exists (select 1 from canopy.setting_defs where key = 'expense_receipt_photos'), 'the receipt-photos switch of 0035 stays (unused, the owner''s choice kept)');
-- the café and the accountant keep working on the reverted database, under the rules of before 0034
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.expense_save(jsonb_build_object('date', :'today', 'description', 'Jabón', 'account', '6204', 'amount_crc', 1130, 'iva_crc', 130, 'paid_from', 'petty'), gen_random_uuid())->>'ok',
               'true', 'a manager with a PIN registers an expense again (the rule of 0019)');
select test.eq(public.expense_list(public.cr_today(), public.cr_today())->>'ok', 'true', 'and lists them (0014)');
select test.ok(public._receipts_allowed(), 'and may add receipts (0015)');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'description', 'Azúcar', 'account', '6205', 'amount_crc', 2260, 'iva_crc', 260,
               'paid_from', 'credit', 'date', :'today'), '7e000000-0000-4000-8000-000000004205')->>'ok', 'true', 'the accountant registers an expense (every field given, as the old page sends them)');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004201', 'amount_crc', 1000, 'date', :'today'), gen_random_uuid())->>'error', 'bad_account',
               'the habits are not read any more: an expense without its account is refused as before');
select test.eq(jsonb_array_length(public.expense_list(public.cr_today() - 30, public.cr_today())->'expenses'), 8, 'the list has every expense, the ones of this test included');
select test.eq(((public.ap_aging())#>>'{ledger,expenses_on_credit}')::numeric, 32600 + 11300 + 2260::numeric,
               'ap_aging of 0016 counts the credit expenses in full again (the script warns that 2101 then differs by what was paid)');
select test.eq(((public.cash_payouts(public.cr_today(), public.cr_today()))#>>'{payouts,0,documented_crc}')::numeric, 0::numeric,
               'cash_payouts of 0019 no longer sees the payment made from the payout');
reset role;
set constraints all immediate; set constraints all deferred;

-- both migrations apply again
\o /dev/null
\ir ../../supabase/migrations/0034_contabilidad_lecturas.sql
\ir ../../supabase/migrations/0035_contabilidad_gastos.sql
\o
select test.eq(public.canopy_schema_version(), 35, 'applied again: version 35');
select test.ok(to_regprocedure('public.expense_pay(jsonb, uuid)') is not null and to_regprocedure('public.vendors_list()') is not null
               and to_regprocedure('public.expense_due(int)') is not null and to_regprocedure('public.cash_position()') is not null, 'with their functions');
select test.eq((select default_value from canopy.setting_defs where key = 'expense_receipt_photos'), 'false', 'and the receipt-photos switch, off');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '7e000000-0000-4000-8000-000000004201', 'paid_from', 'bank', 'date', :'today'), '7e000000-0000-4000-8000-000000004216')->>'open_crc',
               '0.00', 'expense_pay works again: the rest of the first expense is paid');
select test.eq(((public.ap_aging())#>>'{ledger,expenses_on_credit}')::numeric, 11300 - 4500 - 1000 + 2260::numeric, 'and the aging nets the payments again');
select test.ok(exists (select 1 from jsonb_array_elements(public.expense_due(7)->'due') d where d->>'id' = :'s3id'), 'the templates are still there: the ice is due again');
reset role;
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.expense_save(jsonb_build_object('date', :'today', 'description', 'Jabón', 'account', '6204', 'amount_crc', 1130, 'iva_crc', 130, 'paid_from', 'petty'), gen_random_uuid())->>'error',
               'not_allowed', 'and the tablet with a PIN registers no expenses again');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) x), 0, 'every entry still balances');
select test.done();
rollback;
