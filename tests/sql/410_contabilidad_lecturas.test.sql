-- Migration 0034 (docs/CONTABILIDAD-REDISENO.md): the suppliers' confirmed habits, expenses only for the owner with the
-- phone code or the accountant (never a café tablet with a PIN), and the new read-only functions of contabilidad.html:
-- vendors_list, vendor_history, purchases_list, sales_by_method, cash_position, period_compare, acct_audit.
begin;
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today(), 500, 510, 'hacienda') on conflict (day) do nothing;
-- two suppliers typed straight into the table (as the inventory page did before 0034): one will get its habits, one stays bare
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000004101', 'Lácteos del Bosque'),
                                             ('5b000000-0000-4000-8000-000000004102', 'Ferretería Central');
select to_char(public.cr_today(), 'YYYY-MM-DD') as today \gset

-- every guard in one string: each probe stops right after its guard (a future date, a bad range, a missing name, an
-- unknown supplier), so an allowed caller writes nothing and the answer tells the guard from the validation
create function pg_temp.guards() returns text language sql as $$
  select concat_ws(' ',
    'expense_save=' || coalesce(public.expense_save(jsonb_build_object('date', public.cr_today() + 1, 'description', 'g', 'account', '6204', 'amount_crc', 1130, 'iva_crc', 130, 'paid_from', 'cash'), gen_random_uuid())->>'error', 'ok'),
    'expense_list=' || coalesce(public.expense_list(public.cr_today() - 500, public.cr_today())->>'error', 'ok'),
    'cash_position=' || coalesce(public.cash_position()->>'error', 'ok'),
    'acct_audit=' || coalesce(public.acct_audit(public.cr_today() - 500, public.cr_today())->>'error', 'ok'),
    'vendor_defaults_save=' || coalesce(public.vendor_defaults_save('00000000-0000-4000-8000-000000000000', '{}'::jsonb)->>'error', 'ok'),
    'vendor_save=' || coalesce(public.vendor_save('{"name":""}'::jsonb)->>'error', 'ok'),
    'vendors_list=' || coalesce(public.vendors_list()->>'error', 'ok'),
    'vendor_history=' || coalesce(public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 500, public.cr_today())->>'error', 'ok'),
    'purchases_list=' || coalesce(public.purchases_list(public.cr_today() - 500, public.cr_today(), null)->>'error', 'ok'),
    'sales_by_method=' || coalesce(public.sales_by_method(public.cr_today() - 500, public.cr_today())->>'error', 'ok'),
    'period_compare=' || coalesce(public.period_compare(public.cr_today() - 500, public.cr_today())->>'error', 'ok'));
$$;
select 'expense_save=not_allowed expense_list=not_allowed cash_position=not_allowed acct_audit=not_allowed vendor_defaults_save=not_allowed vendor_save=not_allowed '
    || 'vendors_list=not_allowed vendor_history=not_allowed purchases_list=not_allowed sales_by_method=not_allowed period_compare=not_allowed' as all_closed \gset
select 'expense_save=future_date expense_list=bad_range cash_position=ok acct_audit=bad_range vendor_defaults_save=not_found vendor_save=missing_name '
    || 'vendors_list=ok vendor_history=bad_range purchases_list=bad_range sales_by_method=bad_range period_compare=bad_range' as all_open \gset

-- 1) who may call what ------------------------------------------------------------------------------------------------
select test.login('anon'); set role anon;
select test.throws($$select public.expense_save('{}'::jsonb, gen_random_uuid())$$, 'permission denied', 'a visitor cannot even call expense_save');
select test.throws($$select public.vendors_list()$$, 'permission denied', 'nor vendors_list');
select test.throws($$select public.cash_position()$$, 'permission denied', 'nor cash_position');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the café login without a PIN: everything closed');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.access_level(), 'manager', 'café + manager PIN: the owner areas of the tablet are open, so the refusals below mean something');
-- the owner's decision of 2026-10-26: a tablet with a PIN registers no expenses and reads no books
select test.eq(public.expense_save(jsonb_build_object('date', :'today', 'description', 'Jabón', 'account', '6204', 'amount_crc', 1130, 'iva_crc', 130, 'paid_from', 'cash'),
               gen_random_uuid())->>'error', 'not_allowed', 'café + manager PIN: cannot register an expense (allowed before 0034)');
select test.eq(public.expense_list(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'café + manager PIN: cannot list expenses');
select test.eq(public.cash_position()->>'error', 'not_allowed', 'café + manager PIN: no cash position');
select test.eq(public.acct_audit(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'café + manager PIN: no accounting log');
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004101', '{"account":"6204"}'::jsonb)->>'error', 'not_allowed',
               'café + manager PIN: cannot set a supplier''s habits');
select test.eq(public.vendor_save('{"name":"Otro"}'::jsonb)->>'error', 'not_allowed', 'café + manager PIN: cannot create a supplier');
select test.eq(public.vendors_list()->>'ok', 'true', 'café + manager PIN: sees the suppliers (like Inventory → Receive)');
select test.eq(public.vendors_list()->>'can_edit', 'false', 'but the list says it cannot edit them');
select test.eq(public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 30, public.cr_today())->>'ok', 'true', 'café + manager PIN: a supplier''s history');
-- …but not the supplier's expenses (documents of the books), nor its cédula, payment notes or habits: those open only with the books' door
select test.eq((public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 400, public.cr_today()))->'expenses', '[]'::jsonb, 'café + PIN: the expenses of the supplier stay out');
select test.ok((public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 400, public.cr_today()))#>'{vendor,tax_id}' = 'null'::jsonb
               and (public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 400, public.cr_today()))#>'{vendor,payment_notes}' = 'null'::jsonb
               and (public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 400, public.cr_today()))#>'{totals,expenses}' = 'null'::jsonb
               and (public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 400, public.cr_today()))#>'{vendor,owed_expenses}' = 'null'::jsonb, 'café + PIN: no cédula, payment notes, expense totals or owed expenses');
select test.ok((select bool_and(v->'tax_id' = 'null'::jsonb and v->'payment_notes' = 'null'::jsonb and v->'default_account' = 'null'::jsonb and v->'owed_expenses' = 'null'::jsonb and v->'expenses_12m' = 'null'::jsonb)
                  from jsonb_array_elements(public.vendors_list()->'vendors') v), 'café + PIN: vendors_list hides the cédula, the payment notes, the habits and the expense figures');
select test.eq(public.purchases_list(public.cr_today() - 30, public.cr_today(), null)->>'ok', 'true', 'café + manager PIN: the purchases');
select test.eq(public.sales_by_method(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'café + manager PIN without the sales permission: no sales by method');
select test.eq(public.period_compare(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'nor the period comparison');
select test.eq(pg_temp.guards(), replace(replace(replace(:'all_closed', 'vendors_list=not_allowed', 'vendors_list=ok'),
               'vendor_history=not_allowed', 'vendor_history=bad_range'), 'purchases_list=not_allowed', 'purchases_list=bad_range'),
               'café + manager PIN: only the three supplier readings open');
reset role;
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('dueno'), '7391');
select test.eq(public.expense_save(jsonb_build_object('date', :'today', 'description', 'Jabón', 'account', '6204', 'amount_crc', 1130, 'iva_crc', 130, 'paid_from', 'cash'),
               gen_random_uuid())->>'error', 'not_allowed', 'café + owner-role PIN: still no expenses (the phone code is the owner''s own login)');
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
select test.eq(pg_temp.guards(), replace(:'all_open', 'vendor_save=missing_name', 'vendor_save=not_allowed'),
               'the accountant with the phone code: everything open except creating suppliers');
reset role;
select test.eq((select count(*)::int from public.expenses) || '|' || (select count(*)::int from public.vendors) || '|' || (select count(*)::int from acct.entries), '0|2|0',
               'the guard probes wrote nothing');

-- 2) vendor_save: the owner with the phone code creates and changes suppliers ------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.vendor_save(jsonb_build_object('name', '  Panadería La Espiga ', 'contact_name', 'Rosa', 'phone', '8888-0000', 'whatsapp', '8888-0000', 'email', 'rosa@espiga.cr',
       'lead_days', 3, 'order_days', 'Lun, Jue', 'notes', 'pan de masa madre', 'tax_id', '3-101-123456', 'credit_days', 15)) as vs \gset
select test.eq((:'vs'::jsonb)->>'ok', 'true', 'the owner with the phone code creates a supplier');
select (:'vs'::jsonb)->>'id' as v3 \gset
select test.eq((select name || '|' || contact_name || '|' || lead_days || '|' || tax_id || '|' || credit_days || '|' || active from public.vendors where id = :'v3'),
               'Panadería La Espiga|Rosa|3|3-101-123456|15|true', 'saved trimmed, with the accountant''s tax id and the credit days');
select test.eq(public.vendor_save('{"name":"panadería la espiga"}'::jsonb)->>'error', 'duplicate_name', 'the same name again (any case) is refused');
select test.eq(public.vendor_save('{"name":"LÁCTEOS DEL BOSQUE"}'::jsonb)->>'error', 'duplicate_name', 'also a supplier typed before 0034');
select test.eq(public.vendor_save('{"name":"   "}'::jsonb)->>'error', 'missing_name', 'a supplier needs a name');
select test.eq(public.vendor_save('{"name":"x","credit_days":181}'::jsonb)->>'error', 'bad_value', 'credit days above 180 are refused');
select test.eq(public.vendor_save('{"name":"x","credit_days":-1}'::jsonb)->>'error', 'bad_value', 'and negative ones');
select test.eq(public.vendor_save('{"name":"x","lead_days":61}'::jsonb)->>'error', 'bad_value', 'lead days above 60 are refused');
select test.eq(public.vendor_save('{"name":"x","lead_days":-1}'::jsonb)->>'error', 'bad_value', 'and negative ones');
select test.eq(public.vendor_save(jsonb_build_object('id', gen_random_uuid(), 'name', 'x'))->>'error', 'not_found', 'changing a supplier that does not exist');
select test.eq(public.vendor_save(jsonb_build_object('id', :'v3', 'name', 'Panadería La Espiga', 'contact_name', 'Rosa Mora', 'lead_days', 2, 'credit_days', 30,
               'tax_id', '3-101-123456'))->>'ok', 'true', 'the owner changes the supplier (its own name is not a duplicate)');
select test.eq((select contact_name || '|' || lead_days || '|' || credit_days || '|' || coalesce(phone, '-') from public.vendors where id = :'v3'), 'Rosa Mora|2|30|-',
               'the change is saved (a field left out is cleared, as the form sends everything)');
reset role;
select test.eq((select count(*)::int from public.audit_log where action = 'vendor_save' and target_id = :'v3'), 2, 'both saves are in the log');
select test.eq((select string_agg(left(summary, 18), ',' order by id) from public.audit_log where action = 'vendor_save'), 'proveedor nuevo: P,proveedor cambiado',
               'the log says which was new and which a change');
select test.eq((select details#>>'{before,credit_days}' from public.audit_log where action = 'vendor_save' order by id desc limit 1), '15', 'the change keeps what it replaced');
select test.ok((select manager_name is not null and manager_name <> '' from public.audit_log where action = 'vendor_save' order by id limit 1), 'and who did it');
select test.eq((select count(*)::int from public.vendors), 3, 'three suppliers: the two typed and the one created');

-- 3) vendor_defaults_save: the accountant confirms what is habitual for a supplier --------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004101', jsonb_build_object('account', '6205', 'paid_from', 'bank', 'iva_rate', 0.13,
               'payment_notes', '  SINPE 8888-1111  '))->>'ok', 'true', 'the accountant saves the habits of Lácteos del Bosque');
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004101', '{"account":"6205","iva_rate":0.05}'::jsonb)->>'error', 'bad_value',
               'an IVA rate that does not exist in Costa Rica is refused');
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004101', '{"account":"6205","paid_from":"bitcoin"}'::jsonb)->>'error', 'bad_value',
               'an unknown way of paying is refused');
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004101', '{"account":"1101"}'::jsonb)->>'error', 'bad_account', 'the habitual account must be an expense account');
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004101', '{"account":"9999"}'::jsonb)->>'error', 'bad_account', 'and must exist');
select test.eq(public.vendor_defaults_save(gen_random_uuid(), '{}'::jsonb)->>'error', 'not_found', 'an unknown supplier');
reset role;
select test.eq((select default_account || '|' || default_paid_from || '|' || default_iva_rate || '|' || payment_notes from public.vendors where id = '5b000000-0000-4000-8000-000000004101'),
               '6205|bank|0.1300|SINPE 8888-1111', 'the habits are on the supplier, trimmed; the refusals changed nothing');
select test.eq((select count(*)::int from public.audit_log where action = 'vendor_defaults'), 1, 'one log line (the refusals wrote none)');
select test.ok((select summary like 'lo habitual de Lácteos del Bosque: 6205 · bank · IVA 0.13%' and details#>'{before,account}' = 'null'::jsonb
                  from public.audit_log where action = 'vendor_defaults'), 'the log says what was set and that nothing was set before');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.vendor_defaults_save('5b000000-0000-4000-8000-000000004102', '{"iva_rate":0}'::jsonb)->>'ok', 'true',
               'the owner with the phone code confirms an exempt supplier (rate 0, no account yet)');
reset role;
select test.eq((select default_iva_rate::text || '|' || coalesce(default_account, '-') || '|' || coalesce(default_paid_from, '-') from public.vendors where id = '5b000000-0000-4000-8000-000000004102'),
               '0.0000|-|-', 'a rate of zero is a confirmed habit, not an empty one');

-- 4) expense_save v2: the request says the supplier, the amount and the date; the habits fill the rest -------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 11300, 'date', :'today'), '7e000000-0000-4000-8000-000000004101') as e1 \gset
select test.eq((:'e1'::jsonb)->>'ok', 'true', 'supplier + amount + date is enough for a supplier with habits');
select test.eq(((:'e1'::jsonb)->>'account') || '|' || ((:'e1'::jsonb)->>'paid_from') || '|' || ((:'e1'::jsonb)->>'iva_crc')::numeric, '6205|bank|1300.00',
               'the answer says what was filled in: the account, the way of paying and the IVA (11 300 − 11 300 / 1.13)');
select test.ok(((:'e1'::jsonb)->>'entry_id') is not null, 'and the entry it posted');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 11300, 'date', :'today'), '7e000000-0000-4000-8000-000000004101')->>'repeat',
               'true', 'sending it again changes nothing');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 5000, 'iva_crc', 0, 'account', '6204', 'paid_from', 'cash',
               'description', 'Bolsas', 'date', :'today'), '7e000000-0000-4000-8000-000000004103')->>'account', '6204', 'what the request says wins over the habits');
-- a supplier without habits: the server asks for exactly what is missing, never guesses
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'amount_crc', 20000, 'date', :'today'), gen_random_uuid())->>'error',
               'needs_account', 'no habitual account: needs_account');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'amount_crc', 20000, 'date', :'today', 'account', '6206'), gen_random_uuid())->>'error',
               'needs_paid_from', 'with the account but no way of paying: needs_paid_from');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'amount_crc', 20000, 'date', :'today', 'account', '6206', 'paid_from', 'bank'),
               '7e000000-0000-4000-8000-000000004102')->>'ok', 'true', 'with both, the exempt supplier''s rate of zero gives the IVA');
reset role;
select test.eq((select iva_crc || '|' || description from public.expenses where id = '7e000000-0000-4000-8000-000000004102'), '0.00|Ferretería Central',
               'IVA zero; the description falls back to the supplier''s name');
update public.vendors set default_iva_rate = null where id = '5b000000-0000-4000-8000-000000004102';   -- no rate confirmed any more
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'amount_crc', 20000, 'date', :'today', 'account', '6206', 'paid_from', 'bank'),
               gen_random_uuid())->>'error', 'needs_iva', 'no rate and no IVA in the request: needs_iva (the server never invents IVA)');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', gen_random_uuid(), 'amount_crc', 1000, 'date', :'today', 'account', '6206', 'paid_from', 'bank', 'iva_crc', 0),
               gen_random_uuid())->>'error', 'no_vendor', 'a supplier that does not exist: no_vendor');
select test.eq(public.expense_save(jsonb_build_object('amount_crc', 1000, 'date', :'today', 'account', '6206', 'paid_from', 'bank', 'iva_crc', 0), gen_random_uuid())->>'error',
               'bad_value', 'neither a supplier nor a description: bad_value (nothing to call the expense)');
select test.eq(public.expense_save(jsonb_build_object('vendor_name', 'Súper Monteverde', 'description', 'Hielo', 'amount_crc', 2000, 'date', :'today', 'account', '6299', 'paid_from', 'petty',
               'iva_crc', 0), '7e000000-0000-4000-8000-000000004104')->>'ok', 'true', 'a supplier typed by name, as before 0034');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 1000, 'date', public.cr_today() + 1), gen_random_uuid())->>'error',
               'future_date', 'no expenses dated tomorrow');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 3390, 'date', :'today', 'invoice_no', 'F-77'),
               '7e000000-0000-4000-8000-000000004105')->>'ok', 'true', 'an expense with its invoice number');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 3390, 'date', :'today', 'invoice_no', 'f-77'), gen_random_uuid())->>'error',
               'duplicate_invoice', 'the same invoice of the same supplier is refused');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 1000, 'date', :'today', 'account', '1101'), gen_random_uuid())->>'error',
               'bad_account', 'only expense accounts');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 1000, 'date', :'today', 'account', '9999'), gen_random_uuid())->>'error',
               'bad_account', 'and only ones that exist');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 1000, 'iva_crc', 1000, 'date', :'today'), gen_random_uuid())->>'error',
               'bad_value', 'IVA must be less than the total');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 0, 'date', :'today'), gen_random_uuid())->>'error',
               'bad_value', 'an expense of zero');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 1000, 'paid_from', 'bitcoin', 'date', :'today'), gen_random_uuid())->>'error',
               'bad_value', 'an unknown way of paying');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 1000, 'date', :'today'), null)->>'error', 'bad_request',
               'a request without its id');
-- an expense on credit of the bare supplier: it is owed in full
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'account', '6206', 'paid_from', 'credit', 'amount_crc', 22600, 'iva_crc', 2600,
               'description', 'Reparación del horno', 'invoice_no', 'R-1', 'date', public.cr_today() - 10), '7e000000-0000-4000-8000-000000004106')->>'ok', 'true', 'an expense on credit');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select count(*)::int from public.expenses), 6, 'six expenses saved; every refusal left none');
select test.eq((select description || '|' || vendor_name || '|' || created_by from public.expenses where id = '7e000000-0000-4000-8000-000000004101'),
               'Lácteos del Bosque|Lácteos del Bosque|contador · contador@test.local', 'the description falls back to the supplier''s name; the accountant signed it');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'expense:7e000000-0000-4000-8000-000000004101'), '1110:-11300.00,1140:1300.00,6205:10000.00',
               'posted: the expense without IVA, the IVA credit, the bank account from the habits');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'expense:7e000000-0000-4000-8000-000000004106'), '1140:2600.00,2101:-22600.00,6206:20000.00', 'on credit: owed to suppliers (2101)');
select test.eq((select count(*)::int from acct.entries where source_key = 'expense:7e000000-0000-4000-8000-000000004101'), 1, 'the repeat posted no second entry');
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) x), 0, 'every entry balances');
select test.eq(public._expense_open('7e000000-0000-4000-8000-000000004106'), 22600::numeric, 'the credit expense is owed in full');
select test.eq(public._expense_open('7e000000-0000-4000-8000-000000004101'), 0::numeric, 'a paid one owes nothing');

-- 5) expense_list v2 -----------------------------------------------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.expense_list(public.cr_today() - 30, public.cr_today()) as el \gset
select test.eq(jsonb_array_length((:'el'::jsonb)->'expenses'), 6, 'the list has the six');
select test.ok((select bool_and(x ? 'open_crc' and x ? 'account_name') from jsonb_array_elements((:'el'::jsonb)->'expenses') x), 'each one says what it still owes');
select test.eq((select (x->>'open_crc')::numeric from jsonb_array_elements((:'el'::jsonb)->'expenses') x where x->>'id' = '7e000000-0000-4000-8000-000000004106'), 22600::numeric,
               'the credit expense: 22 600 open');
select test.eq(public.expense_list(public.cr_today() - 401, public.cr_today())->>'error', 'bad_range', 'more than 400 days: bad_range');
select test.eq(public.expense_list(public.cr_today(), public.cr_today() - 1)->>'error', 'bad_range', 'an inverted range');
select test.eq(public.expense_list(null, public.cr_today())->>'error', 'bad_range', 'a missing date');
select test.eq(public.expense_list(public.cr_today() - 400, public.cr_today())->>'ok', 'true', 'exactly 400 days is fine');
reset role;

-- 6) vendor_history: a supplier's invoices, payments, expenses and orders, with the aging of what is open -----------------------
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000004101', 'Leche', 'ml', 1000, 1000);
insert into public.purchase_orders (id, vendor_id, status) values
  ('9a000000-0000-4000-8000-000000004101', '5b000000-0000-4000-8000-000000004101', 'received'),   -- A: delivered and invoiced, open
  ('9a000000-0000-4000-8000-000000004102', '5b000000-0000-4000-8000-000000004102', 'received'),   -- B: delivered, no invoice yet
  ('9a000000-0000-4000-8000-000000004103', '5b000000-0000-4000-8000-000000004102', 'received'),   -- C: delivered, invoiced and paid
  ('9a000000-0000-4000-8000-000000004104', '5b000000-0000-4000-8000-000000004102', 'cancelled'),  -- D: cancelled
  ('9a000000-0000-4000-8000-000000004105', '5b000000-0000-4000-8000-000000004101', 'sent');       -- E: sent, nothing arrived
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values
  ('9b000000-0000-4000-8000-000000004101', '9a000000-0000-4000-8000-000000004101', '5a000000-0000-4000-8000-000000004101', 10, 10000, 1);
insert into public.purchase_receipts (id, po_id, vendor_id, invoice_no, total_crc, final) values
  ('7e000000-0000-4000-8000-000000004111', '9a000000-0000-4000-8000-000000004101', '5b000000-0000-4000-8000-000000004101', 'A-1', 10000, true),
  ('7e000000-0000-4000-8000-000000004112', '9a000000-0000-4000-8000-000000004102', '5b000000-0000-4000-8000-000000004102', null, 3000, true),
  ('7e000000-0000-4000-8000-000000004113', '9a000000-0000-4000-8000-000000004103', '5b000000-0000-4000-8000-000000004102', 'B-1', 4000, true);
select test.login('accountant', 'aal2'); set role authenticated;
-- Lácteos: A-1 (11 300, due in 30 days: current), S-9 (2 260, 70 days late: older), S-10 (1 000, 15 days late: 30), S-11 (1 500, 45 days late: 60)
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'number', 'A-1', 'date', :'today', 'due_date', public.cr_today() + 30,
               'net_crc', 10000, 'iva_crc', 1300, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000004111')), '7e000000-0000-4000-8000-000000004121')->>'ok', 'true',
               'the invoice of the delivery');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'number', 'S-9', 'date', public.cr_today() - 80, 'due_date', public.cr_today() - 70,
               'net_crc', 2000, 'iva_crc', 260, 'account', '6206'), '7e000000-0000-4000-8000-000000004122')->>'ok', 'true', 'an old service invoice');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'number', 'S-10', 'date', public.cr_today() - 20, 'due_date', public.cr_today() - 15,
               'net_crc', 1000, 'iva_crc', 0, 'account', '6206'), '7e000000-0000-4000-8000-000000004123')->>'ok', 'true', 'one 15 days late');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'number', 'S-11', 'date', public.cr_today() - 50, 'due_date', public.cr_today() - 45,
               'net_crc', 1500, 'iva_crc', 0, 'account', '6206'), '7e000000-0000-4000-8000-000000004124')->>'ok', 'true', 'one 45 days late');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'amount_crc', 260, 'paid_from', 'bank', 'date', :'today', 'reference', 'TRF 1',
               'invoice_ids', jsonb_build_array('7e000000-0000-4000-8000-000000004122')), '7e000000-0000-4000-8000-000000004131')->>'ok', 'true', 'part of S-9 is paid');
select test.eq(public.expense_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004101', 'paid_from', 'credit', 'amount_crc', 5650, 'description', 'Crema', 'date', :'today'),
               '7e000000-0000-4000-8000-000000004107')->>'iva_crc', '650.00', 'an expense on credit of Lácteos (its habits give the account and the IVA)');
-- Ferretería: B-1 equals its delivery and is paid in cash
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'number', 'B-1', 'date', :'today', 'net_crc', 4000, 'iva_crc', 0,
               'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000004113')), '7e000000-0000-4000-8000-000000004125')->>'ok', 'true', 'B-1 equals its delivery');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000004102', 'amount_crc', 4000, 'paid_from', 'cash', 'date', :'today',
               'invoice_ids', jsonb_build_array('7e000000-0000-4000-8000-000000004125')), '7e000000-0000-4000-8000-000000004132')->>'ok', 'true', 'and is paid in full');
select public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 100, public.cr_today()) as vh \gset
select test.eq((:'vh'::jsonb)->>'ok', 'true', 'the history of Lácteos del Bosque');
select test.eq(((:'vh'::jsonb)#>>'{vendor,name}') || '|' || ((:'vh'::jsonb)#>>'{vendor,default_account}') || '|' || ((:'vh'::jsonb)#>>'{vendor,owed_invoices}')::numeric || '|'
               || ((:'vh'::jsonb)#>>'{vendor,owed_expenses}')::numeric, 'Lácteos del Bosque|6205|15800.00|5650.00',
               'the supplier with its habits, what its invoices still owe (11 300 + 2 000 + 1 000 + 1 500) and what its credit expenses owe');
select test.eq(((:'vh'::jsonb)#>>'{aging,current}')::numeric || '|' || ((:'vh'::jsonb)#>>'{aging,d30}')::numeric || '|' || ((:'vh'::jsonb)#>>'{aging,d60}')::numeric || '|'
               || ((:'vh'::jsonb)#>>'{aging,older}')::numeric, '11300.00|1000.00|1500.00|2000.00', 'aging: current, up to 30, up to 60, older');
select test.eq(jsonb_array_length((:'vh'::jsonb)->'invoices') || '|' || jsonb_array_length((:'vh'::jsonb)->'payments') || '|' || jsonb_array_length((:'vh'::jsonb)->'expenses') || '|'
               || jsonb_array_length((:'vh'::jsonb)->'orders'), '4|1|4|2', 'four invoices, one payment, four expenses, two orders in the range');
select test.eq((select (x->>'open')::numeric from jsonb_array_elements((:'vh'::jsonb)->'invoices') x where x->>'number' = 'S-9'), 2000::numeric, 'S-9 is open for 2 000 after its payment');
select test.eq((select (x->>'deliveries') || '|' || (x->>'due_date') from jsonb_array_elements((:'vh'::jsonb)->'invoices') x where x->>'number' = 'A-1'), '1|' || (public.cr_today() + 30),
               'A-1: its delivery and its due date');
select test.eq((select x->>'invoices' from jsonb_array_elements((:'vh'::jsonb)->'payments') x), 'S-9', 'the payment says which invoice it paid');
select test.eq((select (x->>'open_crc')::numeric from jsonb_array_elements((:'vh'::jsonb)->'expenses') x where x->>'description' = 'Crema'), 5650::numeric, 'the credit expense: open');
select test.eq((select sum((x->>'open_crc')::numeric) from jsonb_array_elements((:'vh'::jsonb)->'expenses') x where x->>'description' <> 'Crema'), 0::numeric, 'the paid ones: nothing open');
select test.eq((select (x->>'lines') || '|' || (x->>'ordered_crc')::numeric || '|' || (x->>'received_crc')::numeric || '|' || (x->>'invoice_no')
                  from jsonb_array_elements((:'vh'::jsonb)->'orders') x where x->>'id' = '9a000000-0000-4000-8000-000000004101'), '1|10000.00|10000|A-1',
               'order A: its line, what was ordered, what arrived and its invoice');
select test.eq(((:'vh'::jsonb)#>>'{totals,invoiced}')::numeric || '|' || ((:'vh'::jsonb)#>>'{totals,paid}')::numeric || '|' || ((:'vh'::jsonb)#>>'{totals,expenses}')::numeric || '|'
               || ((:'vh'::jsonb)#>>'{totals,received}')::numeric, '16060.00|260.00|25340.00|10000',
               'totals: invoiced 11 300 + 2 260 + 1 000 + 1 500; paid 260; expenses 11 300 + 5 000 + 3 390 + 5 650; received 10 000');
select test.eq(public.vendor_history('5b000000-0000-4000-8000-000000004101', public.cr_today() - 401, public.cr_today())->>'error', 'bad_range', 'more than 400 days: bad_range');
select test.eq(public.vendor_history(gen_random_uuid(), public.cr_today() - 30, public.cr_today())->>'error', 'not_found', 'an unknown supplier');
-- vendors_list: the same figures per supplier, and what the page may do
select public.vendors_list() as vl \gset
select test.eq((:'vl'::jsonb)->>'can_edit', 'false', 'the accountant may not edit suppliers');
select test.eq(jsonb_array_length((:'vl'::jsonb)->'vendors'), 3, 'the three suppliers');
select test.eq((select (x->>'owed_invoices')::numeric || '|' || (x->>'owed_expenses')::numeric || '|' || (x->>'overdue') || '|' || (x->>'last_purchase') || '|' || (x->>'bought_12m')::numeric || '|'
                  || (x->>'deliveries_12m') || '|' || (x->>'expenses_12m') || '|' || (x->>'default_account_name')
                  from jsonb_array_elements((:'vl'::jsonb)->'vendors') x where x->>'id' = '5b000000-0000-4000-8000-000000004101'),
               '15800.00|5650.00|true|' || :'today' || '|37500.00|1|4|Empaques y desechables',
               'Lácteos: owed, overdue, last purchase today, bought in 12 months (10 000 delivered + 4 500 invoiced services + 23 000 expenses without IVA), counts, habits');
select test.eq((select (x->>'owed_invoices')::numeric || '|' || (x->>'owed_expenses')::numeric || '|' || (x->>'overdue') || '|' || coalesce(x->>'tax_id', '-') || '|' || coalesce(x->>'credit_days', '-')
                  from jsonb_array_elements((:'vl'::jsonb)->'vendors') x where x->>'id' = '5b000000-0000-4000-8000-000000004102'), '0.00|22600.00|false|-|-',
               'Ferretería: B-1 paid, the repair on credit still owed, nothing late, no tax id or credit days yet');
select test.ok((select x->>'tax_id' = '3-101-123456' and x->>'credit_days' = '30' and x->>'last_purchase' is null and (x->>'bought_12m')::numeric = 0
                  from jsonb_array_elements((:'vl'::jsonb)->'vendors') x where x->>'id' = :'v3'), 'the bakery: its tax id and credit days, nothing bought yet');
select test.ok(jsonb_array_length((:'vl'::jsonb)->'accounts') > 0 and (select bool_and(a->>'code' like '5%' or a->>'code' like '6%') from jsonb_array_elements((:'vl'::jsonb)->'accounts') a),
               'the expense accounts for the habits form');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.vendors_list()->>'can_edit', 'true', 'the owner with the phone code may edit suppliers');
reset role;

-- 7) purchases_list: each order with its deliveries, invoices, payments and stage ----------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.purchases_list(public.cr_today() - 1, public.cr_today(), null) as pl \gset
select test.eq(jsonb_array_length((:'pl'::jsonb)->'orders'), 5, 'the five orders of these days');
select test.eq((select string_agg(right(x->>'id', 1) || ':' || (x->>'stage'), ',' order by x->>'id') from jsonb_array_elements((:'pl'::jsonb)->'orders') x),
               '1:invoiced,2:received,3:paid,4:cancelled,5:sent', 'stages: invoiced and open, delivered without invoice, paid, cancelled, sent');
select test.eq((select jsonb_array_length(x->'receipts') || '|' || jsonb_array_length(x->'invoices') || '|' || (x->'invoices'->0->>'open_crc')::numeric || '|' || (x->>'paid_crc')::numeric
                  || '|' || (x->>'vendor') || '|' || (x->>'lines') || '|' || (x->>'items')
                  from jsonb_array_elements((:'pl'::jsonb)->'orders') x where x->>'id' = '9a000000-0000-4000-8000-000000004101'), '1|1|11300.00|0|Lácteos del Bosque|1|Leche',
               'order A: one delivery, its invoice open for 11 300, nothing paid, the supplier, the line and what was ordered');
select test.eq((select (x->>'paid_crc')::numeric || '|' || (x->'invoices'->0->>'open_crc')::numeric from jsonb_array_elements((:'pl'::jsonb)->'orders') x
                 where x->>'id' = '9a000000-0000-4000-8000-000000004103'), '4000.00|0.00', 'order C: paid in full');
select test.eq((select x->'receipts'->0->>'invoice_id' from jsonb_array_elements((:'pl'::jsonb)->'orders') x where x->>'id' = '9a000000-0000-4000-8000-000000004102'), null::text,
               'order B: its delivery still waits for the invoice');
select test.eq(jsonb_array_length(public.purchases_list(public.cr_today() - 1, public.cr_today(), '5b000000-0000-4000-8000-000000004102')->'orders'), 3, 'filtered by supplier: Ferretería''s three');
select test.eq(jsonb_array_length((:'pl'::jsonb)->'vendors'), 3, 'the active suppliers for the filter');
select test.eq(public.purchases_list(public.cr_today() - 401, public.cr_today(), null)->>'error', 'bad_range', 'more than 400 days: bad_range');
select test.eq(jsonb_array_length(public.purchases_list(public.cr_today() - 400, public.cr_today() - 2, null)->'orders'), 0, 'other days: none of these');
reset role;

-- 8) sales_by_method: the day's takings by way of paying, as the day's entry counts them ---------------------------------------
select public.cr_today() - 3 as d1 \gset
-- latte ₡2 200 with a ₡5 000 note (₡2 800 change); latte ₡2 200 paid with $10 at 500 (₡2 800 change in colones); card, SINPE, other; a void; an open bill
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values
  ('0d000000-0000-4000-8000-000000004101', public.cr_day_start(:'d1') + interval '9 hours', 2200, 'cash_crc', true, 'done'),
  ('0d000000-0000-4000-8000-000000004102', public.cr_day_start(:'d1') + interval '9 hours', 2200, 'cash_usd', true, 'done'),
  ('0d000000-0000-4000-8000-000000004103', public.cr_day_start(:'d1') + interval '10 hours', 1300, 'card', true, 'done'),
  ('0d000000-0000-4000-8000-000000004104', public.cr_day_start(:'d1') + interval '11 hours', 4000, 'sinpe', true, 'done'),
  ('0d000000-0000-4000-8000-000000004105', public.cr_day_start(:'d1') + interval '12 hours', 500, 'other', true, 'done'),
  ('0d000000-0000-4000-8000-000000004106', public.cr_day_start(:'d1') + interval '13 hours', 999, 'card', true, 'done'),
  ('0d000000-0000-4000-8000-000000004107', public.cr_day_start(:'d1') + interval '14 hours', 7000, 'pending', false, 'ready'),
  ('0d000000-0000-4000-8000-000000004108', public.cr_day_start(public.cr_today() - 2) + interval '10 hours', 1130, 'card', true, 'done');
update public.orders set voided_at = now(), void_reason = 'error' where id = '0d000000-0000-4000-8000-000000004106';
insert into public.cash_tenders (order_id, crc_in, usd_in, change_crc, fx_rate) values ('0d000000-0000-4000-8000-000000004101', 5000, 0, 2800, null),
                                                                                    ('0d000000-0000-4000-8000-000000004102', 0, 10, 2800, 500);
select test.login('accountant', 'aal2'); set role authenticated;
select public.sales_by_method(public.cr_today() - 3, public.cr_today()) as sm \gset
select test.eq(jsonb_array_length((:'sm'::jsonb)->'days'), 2, 'two days with takings');
select test.eq((:'sm'::jsonb)#>>'{days,0,day}', :'d1'::text, 'oldest first');
select test.eq(((:'sm'::jsonb)#>>'{days,0,cash_crc}')::numeric || '|' || ((:'sm'::jsonb)#>>'{days,0,cash_usd}')::numeric || '|' || ((:'sm'::jsonb)#>>'{days,0,card}')::numeric || '|'
               || ((:'sm'::jsonb)#>>'{days,0,sinpe}')::numeric || '|' || ((:'sm'::jsonb)#>>'{days,0,other}')::numeric || '|' || ((:'sm'::jsonb)#>>'{days,0,total}')::numeric,
               '-600|5000.00|1300|4000|500|10200.00', 'colones (5 000 − 2 800) + (0 − 2 800), dollars 10 × 500, card, SINPE, other; the void and the open bill left out');
select test.eq(((:'sm'::jsonb)#>>'{days,1,card}')::numeric, 1130::numeric, 'the next day: its card sale');
select test.eq(public.sales_by_method(public.cr_today() - 366, public.cr_today())->>'ok', 'true', '366 days is fine');
select test.eq(public.sales_by_method(public.cr_today() - 367, public.cr_today())->>'error', 'bad_range', '367 days: bad_range');
reset role;
-- the same figures the day's entry posts to the money accounts
select test.ok((select count(*) = 5 and bool_and(t.amount = v.amt) from acct.day_target(:'d1') t
                  join (values ('1101', -600), ('1102', 5000), ('1110', 4000), ('1120', 1300), ('1130', 500)) v(acc, amt) on v.acc = t.account),
               'the day''s entry counts the same money per account (colones, dollars, SINPE to the bank, cards, other)');

-- 9) cash_position: cash and banks according to the books ------------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(jsonb_typeof(public.cash_position()->'posted_through'), 'null', 'no day posted yet: posted_through is empty');
select test.eq(public.acct_entry_post(:'today', 'Aporte de capital', '[{"account":"1110","debit":500000},{"account":"3101","credit":500000}]',
               '7e000000-0000-4000-8000-000000004141', true)->>'ok', 'true', 'the accountant posts the opening capital into the bank');
select test.eq(public.acct_post_days(:'d1', :'d1')->>'entries', '1', 'and posts the day of the sales');
select public.bank_account_save(jsonb_build_object('name', 'BCR colones', 'bank', 'BCR', 'currency', 'CRC', 'last4', '1234', 'gl_account', '1110')) as ba \gset
select test.eq((:'ba'::jsonb)->>'ok', 'true', 'a bank account on 1110');
reset role;
insert into public.bank_lines (account_id, date, description, amount, balance, fingerprint, status) values
  (((:'ba'::jsonb)->>'id')::uuid, public.cr_today() - 1, 'Depósito', 100000, 480000, 'f1', 'open'),
  (((:'ba'::jsonb)->>'id')::uuid, public.cr_today(), 'Pago', -11300, 468700, 'f2', 'open');
select test.login('accountant', 'aal2'); set role authenticated;
select public.cash_position() as cp \gset
select test.eq((:'cp'::jsonb)->>'ok', 'true', 'the cash position');
select test.ok((:'cp'::jsonb) ?& array['as_of', 'posted_through', 'accounts', 'payouts_open', 'cards_to_settle', 'advances', 'ap', 'iva_net'], 'with every field the page shows');
select test.eq((:'cp'::jsonb)->>'posted_through', :'d1'::text, 'posted through the day that was posted');
select test.eq((select string_agg(a->>'code', ',' order by a->>'code') from jsonb_array_elements((:'cp'::jsonb)->'accounts') a), '1101,1102,1103,1110,1111', 'the cash accounts of the chart');
select test.ok((select bool_and(a ? 'name' and a ? 'balance' and a ? 'bank') from jsonb_array_elements((:'cp'::jsonb)->'accounts') a), 'each with its name, balance and bank account');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg((a->>'code') || ':' || (a->>'balance')::numeric, ',' order by a->>'code') from jsonb_array_elements((:'cp'::jsonb)->'accounts') a),
               (select string_agg(x.code || ':' || x.bal, ',' order by x.code) from (select a.code, coalesce(sum(l.debit - l.credit), 0) as bal from acct.accounts a
                   left join acct.lines l on l.account = a.code where a.cash and a.active group by a.code) x),
               'every balance is the ledger''s balance of that account');
select test.eq((select (a->>'balance')::numeric from jsonb_array_elements((:'cp'::jsonb)->'accounts') a where a->>'code' = '1110'), 500000 - 11300 - 20000 - 3390 - 260 + 4000::numeric,
               'the bank: the capital − the three expenses paid by bank − the transfer to Lácteos + the SINPE sales');
select test.eq((select (a#>>'{bank,name}') || '|' || (a#>>'{bank,last4}') || '|' || (a#>>'{bank,statement_balance}')::numeric || '|' || (a#>>'{bank,statement_day}') || '|' || (a#>>'{bank,open_lines}')
                  from jsonb_array_elements((:'cp'::jsonb)->'accounts') a where a->>'code' = '1110'), 'BCR colones|1234|468700.00|' || :'today' || '|2',
               'the bank account with the latest statement balance and the lines still to match');
select test.eq(((:'cp'::jsonb)->>'ap')::numeric, (select sum(l.credit - l.debit) from acct.lines l where l.account = '2101'), 'owed to suppliers = the 2101 balance');
select test.eq(((:'cp'::jsonb)->>'ap')::numeric, 22600 + 5650 + 1300 + 2260 + 1000 + 1500 - 260 - 4000::numeric,
               'the two credit expenses, A-1''s IVA, the three service invoices, less the two payments (today''s deliveries are not posted yet)');
select test.eq(((:'cp'::jsonb)->>'cards_to_settle')::numeric, (select sum(l.debit - l.credit) from acct.lines l where l.account = '1120'), 'cards to settle = the 1120 balance');
select test.eq(((:'cp'::jsonb)->>'advances')::numeric, (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = '2120'), 'customer advances = the 2120 balance');
select test.eq(((:'cp'::jsonb)->>'iva_net')::numeric, (select coalesce(sum(l.credit - l.debit), 0) from acct.lines l where l.account = '2110')
                                                  - (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = '1140'), 'IVA to pay net of IVA credit');
select test.eq(((:'cp'::jsonb)->>'payouts_open')::numeric, 0::numeric, 'no payout waits for its document');

-- 10) period_compare: the period and the one before it, and the state of each month ----------------------------------------
select (date_trunc('month', public.cr_today()) - interval '2 months')::date as m0 \gset
select public.cr_today() - :'m0'::date + 1 as len \gset
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values
  ('0d000000-0000-4000-8000-000000004109', public.cr_day_start(:'m0') + interval '10 hours', 1130, 'card', true, 'done');
insert into public.register_days (business_date, opened_by_name, float_crc) values (:'m0', 'Ana', 50000);   -- that day's register, still open
select test.login('accountant', 'aal2'); set role authenticated;
select public.period_compare(:'m0', :'today') as pc \gset
select test.eq((:'pc'::jsonb)->>'ok', 'true', 'the comparison for the accountant');
select test.eq(((:'pc'::jsonb)#>>'{current,from}') || '|' || ((:'pc'::jsonb)#>>'{current,to}') || '|' || ((:'pc'::jsonb)#>>'{previous,from}') || '|' || ((:'pc'::jsonb)#>>'{previous,to}'),
               :'m0' || '|' || :'today' || '|' || (:'m0'::date - :len) || '|' || (:'m0'::date - 1), 'the previous period has the same length and ends the day before');
select test.eq(((:'pc'::jsonb)#>>'{current,gross}')::numeric, 10200 + 1130 + 1130::numeric, 'gross takings of the period: the three days of sales');
select test.eq(((:'pc'::jsonb)#>>'{current,orders}') || '|' || ((:'pc'::jsonb)#>>'{current,days_with_sales}') || '|' || ((:'pc'::jsonb)#>>'{current,days_posted}'), '7|3|1',
               'seven paid orders (the void and the open bill left out), three days with sales, one posted');
select test.eq(((:'pc'::jsonb)#>>'{previous,gross}')::numeric || '|' || ((:'pc'::jsonb)#>>'{previous,orders}'), '0|0', 'nothing happened in the previous period');
select test.eq(((:'pc'::jsonb)->>'books_visible') || '|' || ((:'pc'::jsonb)->>'labor_visible'), 'true|true', 'the accountant sees the books and the labor');
select test.eq(((:'pc'::jsonb)#>>'{current,books,revenue}')::numeric, (public.acct_income_statement(:'m0', :'today')->>'revenue')::numeric, 'the books'' revenue is the income statement''s');
select test.eq(jsonb_array_length((:'pc'::jsonb)->'months'), 3, 'three months in the range');
select test.eq((select string_agg(m->>'state', ',' order by m->>'month') from jsonb_array_elements((:'pc'::jsonb)->'months') m), 'estimate,empty,estimate',
               'a month with a register day still open: estimate; a month with nothing: empty; this month: estimate');
select test.eq(((:'pc'::jsonb)#>>'{months,0,from}') || '|' || ((:'pc'::jsonb)#>>'{months,2,to}'), :'m0' || '|' || :'today', 'the months are cut to the range');
reset role;
select test.eq(((:'pc'::jsonb)#>>'{current,expenses}')::numeric,
               (select sum(e.amount_crc - e.iva_crc) from public.expenses e where e.voided_at is null and e.date between :'m0' and :'today')
               + (select sum(i.net_crc) from public.supplier_invoices i where i.account is not null and i.voided_at is null and i.date between :'m0' and :'today'),
               'expenses: every expense without IVA plus the service invoices dated in the period');
select test.eq(((:'pc'::jsonb)#>>'{current,iva_in}')::numeric,
               (select sum(e.iva_crc) from public.expenses e where e.voided_at is null and e.date between :'m0' and :'today')
               + (select sum(i.iva_crc) from public.supplier_invoices i where i.voided_at is null and i.date between :'m0' and :'today'), 'IVA credit of expenses and invoices');
-- the first month's register day: closed and not posted → final; posted → books
update public.register_days set closed_at = now(), closed_by_name = 'Ana', cash_diff_crc = 0 where business_date = :'m0';
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.period_compare(:'m0', :'today')#>>'{months,0,state}', 'final', 'closed and not yet posted: final');
select test.eq(public.acct_post_days(:'m0', :'m0')->>'entries', '1', 'the accountant posts that day');
select test.eq(public.period_compare(:'m0', :'today')#>>'{months,0,state}', 'books', 'every closed day posted: books');
select test.eq(public.period_compare(:'m0', :'today')#>>'{current,days_posted}', '2', 'two days posted now');
select test.eq(public.period_compare(public.cr_today() - 366, public.cr_today())->>'ok', 'true', '366 days is fine');
select test.eq(public.period_compare(public.cr_today() - 367, public.cr_today())->>'error', 'bad_range', '367 days: bad_range');
reset role;
-- a manager allowed to see the sales: the figures without the books and without labor
update public.staff set can_see_sales = true where id = test.staff('ana');
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.period_compare(:'m0', :'today') as pcm \gset
select test.eq(((:'pcm'::jsonb)->>'ok') || '|' || ((:'pcm'::jsonb)->>'books_visible') || '|' || ((:'pcm'::jsonb)->>'labor_visible'), 'true|false|false',
               'a manager with the sales permission: the comparison without books or labor');
select test.eq(jsonb_typeof((:'pcm'::jsonb)#>'{current,books}') || '|' || jsonb_typeof((:'pcm'::jsonb)#>'{current,labor}'), 'null|null', 'the books and the labor are empty for the manager');
select test.eq(((:'pcm'::jsonb)#>>'{current,gross}')::numeric, 12460::numeric, 'the same takings');
select test.eq(public.sales_by_method(:'d1', :'d1')->>'ok', 'true', 'and the takings by method');
select test.eq(public.cash_position()->>'error', 'not_allowed', 'but never the cash position');
reset role;

-- 11) acct_audit: the accounting lines of the log, newest first, at most 500 ----------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.acct_audit(public.cr_today() - 1, public.cr_today()) as au \gset
select test.eq((:'au'::jsonb)->>'ok', 'true', 'the accounting log');
select test.ok(jsonb_array_length((:'au'::jsonb)->'rows') >= 4, 'at least the supplier saves, the habits and the posted days');
select test.eq((select string_agg(distinct r->>'action', ',') from jsonb_array_elements((:'au'::jsonb)->'rows') r where r->>'action' not in
                 ('acct_period', 'acct_mapping_set', 'acct_account_save', 'compliance_confirm', 'setting_change', 'accountant_access', 'e_document_failed', 'fx_rate_set', 'tax_rate_save',
                  'payroll_rule_save', 'payroll_param_save', 'po_settle', 'po_pay', 'vendor_save', 'vendor_defaults', 'expense_schedule', 'expense_payment', 'timesheet_approve', 'timesheet_reopen')),
               null::text, 'only the allow-listed actions (the unlocks of this test are in the log and stay out)');
select test.eq((select count(*)::int from jsonb_array_elements((:'au'::jsonb)->'rows') r where r->>'action' = 'vendor_save'), 2, 'both supplier saves');
select test.ok((select bool_and((r->>'at')::timestamptz >= (nxt->>'at')::timestamptz)
                  from (select r, lead(r) over (order by n) as nxt from jsonb_array_elements((:'au'::jsonb)->'rows') with ordinality as t(r, n)) x where nxt is not null), 'newest first');
select test.ok((select bool_and(r ? 'id' and r ? 'who' and r ? 'target' and r ? 'summary' and r ? 'details') from jsonb_array_elements((:'au'::jsonb)->'rows') r), 'each line with who, what and the details');
select test.eq(public.acct_audit(public.cr_today() - 401, public.cr_today())->>'error', 'bad_range', 'more than 400 days: bad_range');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'access_open'), 'there were other actions to leave out');
insert into public.audit_log (action, manager_name, target_id, summary, details) select 'setting_change', 'test', 'k', 'x', '{}'::jsonb from generate_series(1, 505);
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(jsonb_array_length(public.acct_audit(public.cr_today() - 1, public.cr_today())->'rows'), 500, 'never more than 500 lines');
reset role;

-- 12) rights: a visitor may call none of the new functions; a login may call the page's ones; the internal ones nobody ------------
select test.ok(not has_function_privilege('anon', 'public.expense_save(jsonb, uuid)', 'execute') and not has_function_privilege('anon', 'public.expense_list(date, date)', 'execute')
               and not has_function_privilege('anon', 'public.vendors_list()', 'execute') and not has_function_privilege('anon', 'public.vendor_save(jsonb)', 'execute')
               and not has_function_privilege('anon', 'public.vendor_defaults_save(uuid, jsonb)', 'execute') and not has_function_privilege('anon', 'public.vendor_history(uuid, date, date)', 'execute')
               and not has_function_privilege('anon', 'public.purchases_list(date, date, uuid)', 'execute') and not has_function_privilege('anon', 'public.sales_by_method(date, date)', 'execute')
               and not has_function_privilege('anon', 'public.cash_position()', 'execute') and not has_function_privilege('anon', 'public.period_compare(date, date)', 'execute')
               and not has_function_privilege('anon', 'public.acct_audit(date, date)', 'execute') and not has_function_privilege('anon', 'public._expense_allowed()', 'execute')
               and not has_function_privilege('anon', 'public._expense_open(uuid)', 'execute') and not has_function_privilege('anon', 'public._period_figures(date, date, boolean)', 'execute'),
               'a visitor may call none of them');
select test.ok(has_function_privilege('authenticated', 'public.expense_save(jsonb, uuid)', 'execute') and has_function_privilege('authenticated', 'public.expense_list(date, date)', 'execute')
               and has_function_privilege('authenticated', 'public.vendors_list()', 'execute') and has_function_privilege('authenticated', 'public.vendor_save(jsonb)', 'execute')
               and has_function_privilege('authenticated', 'public.vendor_defaults_save(uuid, jsonb)', 'execute') and has_function_privilege('authenticated', 'public.vendor_history(uuid, date, date)', 'execute')
               and has_function_privilege('authenticated', 'public.purchases_list(date, date, uuid)', 'execute') and has_function_privilege('authenticated', 'public.sales_by_method(date, date)', 'execute')
               and has_function_privilege('authenticated', 'public.cash_position()', 'execute') and has_function_privilege('authenticated', 'public.period_compare(date, date)', 'execute')
               and has_function_privilege('authenticated', 'public.acct_audit(date, date)', 'execute'), 'a login may call the page''s functions (each one checks who it is)');
select test.ok(not has_function_privilege('authenticated', 'public._expense_open(uuid)', 'execute') and not has_function_privilege('authenticated', 'public._period_figures(date, date, boolean)', 'execute'),
               'the internal ones are not callable from a page');
-- the receipts folder follows the new rule: the café with a PIN no longer sees or adds receipts
select test.eq((select pg_get_functiondef('public._receipts_allowed()'::regprocedure) ~ 'acct\.can_read\(\)' and pg_get_functiondef('public._receipts_allowed()'::regprocedure) !~ 'is_owner'),
               true, '_receipts_allowed is the books'' rule, not the owner areas'' one');
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.ok(not public._receipts_allowed(), 'café + manager PIN: no receipts');
select test.throws($$insert into storage.objects (bucket_id, name) values ('expense-receipts', '7e000000-0000-4000-8000-000000004101/x.jpg')$$, 'row-level security', 'nor upload one');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.ok(public._receipts_allowed(), 'the accountant: yes');
reset role;

set constraints all immediate; set constraints all deferred;
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) x), 0, 'every entry of this test balances');
select test.done();
rollback;
