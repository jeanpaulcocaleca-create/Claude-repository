-- Migration 0027: who took the money on a bill paid later, the till cannot rewrite who rang or who took the money,
-- "End my turn" can clock the same person out.
begin;
insert into public.settings (key, value) values ('operator_mode', '"record"');
-- Luis signs in on the device and clocks in; he opens a bill (pay later)
select test.login('cafe'); set role authenticated;
select public.pos_operator_start(test.staff('luis'), '5284', 'Caja', true) as op \gset
reset role;
select test.eq((:'op'::jsonb)->>'clocked_in', 'true', 'Luis clocks in and starts');
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op'::jsonb)->>'token')); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003001', 'total_crc', 4000, 'payment_method', 'pending', 'paid', false, 'status', 'ready',
       'guest_name', 'Mesa 2', 'items', jsonb_build_array(jsonb_build_object('item_name', 'Capuchino', 'price_crc', 2000, 'qty', 2))));
reset role;
select test.eq((select operator_name || '|' || coalesce(paid_operator_name, '-') from public.orders where id = '0d000000-0000-4000-8000-000000003001'), 'Luis|-', 'the open bill is Luis''s; nobody has taken the money yet');
-- Marta signs in on the same device (Luis ended his turn) and takes the payment
select test.login('cafe'); set role authenticated;
select public.pos_operator_end((:'op'::jsonb)->>'token') as e1 \gset
select test.eq((:'e1'::jsonb)->>'ended' || '|' || ((:'e1'::jsonb)->>'clocked_out'), 'true|false', 'the old call (token only) ends the turn and leaves the clock alone');
select public.pos_operator_start(test.staff('marta'), '6173', 'Caja', true) as op2 \gset
reset role;
select test.ok(exists (select 1 from public.time_entries where staff_id = test.staff('luis') and clock_out is null), 'Luis is still clocked in');
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op2'::jsonb)->>'token')); set role authenticated;
select test.eq(public.tab_pay('0d000000-0000-4000-8000-000000003001', 'card', null, null, 'Caja', 4000)->>'closed', 'true', 'Marta closes the bill in one payment');
reset role;
select test.eq((select operator_name || '|' || paid_operator_name || '|' || (paid_operator_session = (select id from public.operator_sessions where staff_id = test.staff('marta')))::text
                  from public.orders where id = '0d000000-0000-4000-8000-000000003001'), 'Luis|Marta|true', 'who rang it stays Luis; who took the money is Marta, through her session');
select test.ok(not exists (select 1 from public.orders where id = '0d000000-0000-4000-8000-000000003001' and 'no_paid_operator' = any(flags)), 'nothing to flag: she was signed in');
-- a part payment is its own sale of whoever takes it (as before)
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op'::jsonb)->>'token')); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003002', 'total_crc', 6000, 'payment_method', 'pending', 'paid', false, 'status', 'ready',
       'guest_name', 'Mesa 3', 'items', jsonb_build_array(jsonb_build_object('item_name', 'Capuchino', 'price_crc', 2000, 'qty', 3))));
reset role;
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op2'::jsonb)->>'token')); set role authenticated;
select public.tab_pay('0d000000-0000-4000-8000-000000003002', 'cash_crc', null, 2000, 'Caja', 6000) as part \gset
select test.eq((:'part'::jsonb)->>'closed', 'false', 'a part is paid');
reset role;
select test.eq((select operator_name from public.orders where id = ((:'part'::jsonb)->>'part_id')::uuid), 'Marta', 'the part is Marta''s sale');
-- a bill closed with nobody signed in is flagged (record mode)
select test.login('cafe'); set role authenticated;
select test.eq(public.tab_pay('0d000000-0000-4000-8000-000000003002', 'card', null, null, 'Caja', 4000)->>'closed', 'true', 'the rest is paid with nobody signed in');
reset role;
select test.ok(exists (select 1 from public.orders where id = '0d000000-0000-4000-8000-000000003002' and 'no_paid_operator' = any(flags)), 'flagged: nobody signed in took the money');
select test.eq((select paid_operator_name from public.orders where id = '0d000000-0000-4000-8000-000000003002'), null::text, 'and nobody is named');
-- the till cannot rewrite who rang or who took the money (no update right since 0025; the trigger keeps the names if one ever opens)
select test.login('cafe', 'aal1', jsonb_build_object('x-hg-operator', (:'op2'::jsonb)->>'token')); set role authenticated;
select test.throws($$update public.orders set paid_operator_name = 'Nadie', operator_name = 'Nadie', status = 'done' where id = '0d000000-0000-4000-8000-000000003001'$$,
                   'permission denied', 'the till does not update sales directly');
reset role;
select test.eq((select operator_name || '|' || paid_operator_name from public.orders where id = '0d000000-0000-4000-8000-000000003001'), 'Luis|Marta', 'both names stay as the server set them');
-- "End my turn" with the clock-out: Marta's shift ends; Luis's open shift is not hers to close
select test.login('cafe'); set role authenticated;
select public.pos_operator_end((:'op2'::jsonb)->>'token', true) as e2 \gset
select test.eq((:'e2'::jsonb)->>'ended' || '|' || ((:'e2'::jsonb)->>'clocked_out'), 'true|true', 'her turn ends and she is clocked out');
select public.pos_operator_end((:'op2'::jsonb)->>'token', true) as e3 \gset
select test.eq((:'e3'::jsonb)->>'ended' || '|' || ((:'e3'::jsonb)->>'clocked_out'), 'false|false', 'a second call does nothing');
reset role;
select test.ok(exists (select 1 from public.time_entries where staff_id = test.staff('marta') and clock_out is not null), 'Marta''s shift is closed');
select test.ok(exists (select 1 from public.time_entries where staff_id = test.staff('luis') and clock_out is null), 'Luis''s is still open');
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_operator_end('not-a-token', true)->>'ended', 'false', 'an unknown token ends nothing and clocks nobody out');
reset role;
select test.done();
rollback;
