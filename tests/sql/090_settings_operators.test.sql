-- Migration 0008: guarded settings; the operator on every sale.
begin;
-- a regulated setting to exercise the lock (the real ones arrive with their features)
insert into canopy.setting_defs (key, kind, choices, default_value, guard, description)
  values ('test_regulated', 'choice', '{off,on}', '"off"', 'test_rule_confirmed', 'prueba');

-- 1) settings ------------------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.setting('operator_mode'), '"off"'::jsonb, 'the operator mode starts off');
select test.eq(public.setting_set('operator_mode', '"record"')->>'error', 'owner_only', 'the café login cannot change settings');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.setting_set('operator_mode', '"record"')->>'error', 'owner_only', 'a manager cannot change settings');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.setting_set('operator_mode', '"sometimes"')->>'error', 'bad_value', 'only allowed values');
select test.eq(public.setting_set('test_regulated', '"on"')->>'error', 'needs_confirmation', 'a regulated setting stays locked');
select test.eq(public.compliance_confirm('test_rule_confirmed', '', 'x')->>'error', 'missing_reference', 'a confirmation needs who and which document');
select test.eq(public.compliance_confirm('test_rule_confirmed', 'Contadora M. Rojas', 'Oficio 12-2026')->>'ok', 'true', 'the owner records the confirmation');
select test.eq(public.setting_set('test_regulated', '"on"')->>'ok', 'true', 'then it can be switched on');
select test.eq(public.setting_set('operator_mode', '"record"')->>'ok', 'true', 'the owner sets the operator mode');
select test.ok((select bool_or(x->>'key' = 'operator_mode' and x->>'value' = 'record') from jsonb_array_elements(public.settings_get()) x),
               'settings_get shows the new value');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'setting_change' and target_id = 'operator_mode'), 'setting changes are logged');
select test.ok(exists (select 1 from public.audit_log where action = 'compliance_confirm'), 'confirmations are logged');

-- 2) operator sessions ---------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_operator_start(test.staff('luis'), '0000')->>'error', 'bad_pin', 'a wrong PIN starts nothing');
select public.pos_operator_start(test.staff('luis'), '5284', 'Caja') as op \gset
select test.eq((:'op'::jsonb)->>'clocked_in', 'false', 'Luis has not clocked in');
reset role;
-- a sale with Luis signed in on this device (the header the POS sends)
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op'::jsonb)->>'token')); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000901', 'total_crc', 1300, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
reset role;
select test.eq((select operator_name from public.orders where id = '0d000000-0000-4000-8000-000000000901'), 'Luis', 'the sale is Luis''s');
select test.ok((select 'operator_not_clocked_in' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000000901'),
               'and is marked: he had not clocked in');

-- clocking in at the POS
select test.login('cafe'); set role authenticated;
select public.pos_operator_start(test.staff('marta'), '6173', 'Caja', true) as op2 \gset
reset role;
select test.eq((:'op2'::jsonb)->>'clocked_in', 'true', 'Marta clocks in and starts in one step');
select test.ok(exists (select 1 from public.time_entries where staff_id = test.staff('marta') and clock_out is null), 'her shift started');

-- an offline sale rung by Marta arrives while Luis is signed in on the device: it stays Marta's
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op'::jsonb)->>'token')); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000902', 'created_at', now() - interval '1 minute', 'total_crc', 1300, 'payment_method', 'cash_crc',
       'operator', jsonb_build_object('token', (:'op2'::jsonb)->>'token', 'staff_id', test.staff('marta'), 'name', 'Marta'),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
-- chosen without internet (no PIN check possible): hers, but unverified
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000903', 'total_crc', 1300, 'payment_method', 'cash_crc',
       'operator', jsonb_build_object('staff_id', test.staff('marta'), 'name', 'Marta'),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
-- rung with nobody signed in
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000904', 'total_crc', 1300, 'payment_method', 'cash_crc', 'operator', null,
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
-- the till cannot write the operator itself
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, operator_id, operator_name)
  values ('0d000000-0000-4000-8000-000000000905', now(), 900, 'cash_crc', true, 'done', test.staff('ana'), 'Ana');
reset role;
select test.eq((select operator_name || '|' || array_to_string(flags, ',') from public.orders where id = '0d000000-0000-4000-8000-000000000902'),
               'Marta|', 'an offline sale keeps the person who rang it, verified');
select test.eq((select operator_name || '|' || array_to_string(flags, ',') from public.orders where id = '0d000000-0000-4000-8000-000000000903'),
               'Marta|operator_unverified', 'chosen without a PIN check: marked unverified');
select test.eq((select coalesce(operator_name, '-') || '|' || array_to_string(flags, ',') from public.orders where id = '0d000000-0000-4000-8000-000000000904'),
               '-|no_operator', 'nobody signed in: marked');
select test.eq((select operator_name from public.orders where id = '0d000000-0000-4000-8000-000000000905'), 'Luis',
               'a direct insert takes the device''s operator, not what the till wrote');

-- a payment on a bill through a server function carries the operator too
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op2'::jsonb)->>'token')); set role authenticated;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000000906', now(), 4000, 'pending', false, 'ready');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000000906', 'Mocha', 2000, 2);
select public.tab_pay('0d000000-0000-4000-8000-000000000906', 'card', null, 1500, 'Caja', 4000);
reset role;
select test.eq((select operator_name from public.orders where part_of = '0d000000-0000-4000-8000-000000000906'), 'Marta', 'a part payment is Marta''s');

-- ending the session: later sales with that token are no longer verified
select test.login('cafe'); set role authenticated;
select public.pos_operator_end((:'op'::jsonb)->>'token');
reset role;
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op'::jsonb)->>'token')); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000907', 'created_at', now() + interval '5 minutes', 'total_crc', 1300, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
reset role;
select test.ok((select operator_id is null and 'no_operator' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000000907'),
               'an ended session no longer signs sales');

-- 3) enforce ---------------------------------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('operator_mode', '"enforce"');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_operator_start(test.staff('luis'), '5284')->>'error', 'not_clocked_in', 'enforce: clock in first');
select test.eq(public.pos_operator_start(test.staff('luis'), '5284', null, true)->>'ok', 'true', 'or clock in right there');
reset role;

-- 4) off: no flags at all (production default) -------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('operator_mode', '"off"');
reset role;
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000000908', 'total_crc', 1300, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
reset role;
select test.eq((select flags from public.orders where id = '0d000000-0000-4000-8000-000000000908'), '{}'::text[], 'with the mode off nothing is marked');

select test.done();
rollback;
