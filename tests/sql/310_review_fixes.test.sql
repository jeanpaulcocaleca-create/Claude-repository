-- Migration 0028: the review's fixes. A till sale never goes negative; a room order paid later belongs to that day; days
-- with sales and no register are listed; the journal reverses only its own entries; posting a range answers period_closed;
-- cash only on assets; a cancelled bill cancels its record-only document; labor cost after a switch to a fixed pay; a PIN
-- in use is refused and the owner role needs the phone code; visitors' questions have a size and a pace.
begin;
-- 1) the till guard
select test.login('cafe'); set role authenticated;
select test.throws($$select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003101', 'total_crc', -500, 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Combo', 'price_crc', -500, 'qty', 1))))$$, 'negative_total', 'a negative sale from the till is refused');
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003102', 'total_crc', 1300, 'payment_method', 'efectivo', 'status', 'listo',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
reset role;
select test.eq((select count(*) from public.orders where id = '0d000000-0000-4000-8000-000000003101'), 0::bigint, 'nothing was kept');
select test.ok((select 'bad_method' = any(flags) and 'bad_status' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000003102'),
               'an unknown method or status is kept and flagged (the money came in; an older page may send them)');
-- 1b) a sale a tablet kept offline from before the one-time operational reset (D-038) is recorded and flagged, never refused
reset role;
insert into public.audit_log (action, manager_name, summary, details) values ('reinicio_operativo', 'SQL Editor', 'prueba', '{}');
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003195', 'total_crc', 1300, 'payment_method', 'cash_crc', 'created_at', (now() - interval '1 day')::text,
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 1300, 'qty', 1))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000003196', 'total_crc', 1300, 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 1300, 'qty', 1))));
reset role;
select test.ok((select 'before_reset' = any(flags) from public.orders where id = '0d000000-0000-4000-8000-000000003195'), 'a sale dated before the reset is flagged before_reset');
select test.ok((select not ('before_reset' = any(flags)) from public.orders where id = '0d000000-0000-4000-8000-000000003196'), 'a sale of today is not');
-- a refund (the server's own negative sale) still goes through
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000003103', now() - interval '1 minute', 2500, 'card', true, 'done');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000003103', 'Latte', 2500, 1);
update public.register_days set closed_at = now(), closed_by_name = 'Ana' where business_date = public.cr_today();
insert into public.register_days (business_date, opened_by, opened_by_name, float_crc, closed_at, closed_by_name)
  select public.cr_today(), test.staff('ana'), 'Ana', 50000, now(), 'Ana' where not exists (select 1 from public.register_days where business_date = public.cr_today());
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000003103', 'cliente insatisfecho', false)->>'ok', 'true', 'a refund is still recorded');
reset role;
select test.eq((select count(*) from public.orders where refund_of = '0d000000-0000-4000-8000-000000003103' and total_crc < 0), 1::bigint, 'as a negative sale of its own');

-- 2) a room order paid on a later day belongs to the day the money came in
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, source, guest_name)
  values ('0d000000-0000-4000-8000-000000003104', now() - interval '30 hours', 4000, 'pending', false, 'delivered', 'room', 'Habitación 2');
select test.login('cafe'); set role authenticated;
select test.eq(public.finish_room_order('0d000000-0000-4000-8000-000000003104', 'card')->>'ok', 'true', 'paid at the window today');
reset role;
select test.eq((select (created_at at time zone 'America/Costa_Rica')::date = public.cr_today() and business_date = public.cr_today() from public.orders where id = '0d000000-0000-4000-8000-000000003104'), true,
               'it counts for today''s register and today''s books, once');

-- 3) cash by day lists a day with sales and no register; the ledger's pending days include it
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000003105', public.cr_day_start(public.cr_today() - 3) + interval '10 hours', 3000, 'card', true, 'done');
select test.login('owner', 'aal2'); set role authenticated;
select public.cash_reconciliation(public.cr_today() - 3, public.cr_today()) as cr \gset
select test.eq((select x->>'opened' || '|' || (x->>'closed') || '|' || (x->>'sales_crc') from jsonb_array_elements((:'cr'::jsonb)->'days') x where x->>'date' = (public.cr_today() - 3)::text), 'false|false|0',
               'the day without a register is listed as not opened');
select test.eq((select x->>'opened' from jsonb_array_elements((:'cr'::jsonb)->'days') x where x->>'date' = public.cr_today()::text), 'true', 'today''s register is there');
select public.acct_overview() as ov \gset
select test.ok((:'ov'::jsonb)->'pending_days' ? (public.cr_today() - 3)::text, 'the day without a register waits to be posted');
select test.ok((:'ov'::jsonb)->'days_without_register' ? (public.cr_today() - 3)::text, 'and is named as such');
-- 4) the journal reverses only what it wrote itself
select public.acct_entry_post(public.cr_today(), 'ajuste', jsonb_build_array(jsonb_build_object('account', '6299', 'debit', 100), jsonb_build_object('account', '1101', 'credit', 100)), gen_random_uuid(), false) as m \gset
select test.eq(public.acct_journal_reverse(((:'m'::jsonb)->>'entry_id')::bigint, null, 'error')->>'ok', 'true', 'a manual entry is reversed from the journal');
select public.acct_post_days(public.cr_today(), public.cr_today()) as pd \gset
select test.eq((:'pd'::jsonb)->>'ok', 'true', 'today''s day is posted');
reset role;
select max(id) as dayentry from acct.entries where source = 'day' \gset
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.acct_journal_reverse(:dayentry, null, 'x')->>'error', 'use_document', 'a day entry is not reversed from the journal');
select test.throws($$select public.acct_entry_reverse(1, null, 'x')$$, 'permission denied', 'the unrestricted reversal is no longer a page call');
-- 5) posting a range into a closed month answers, it does not fail
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select public.acct_period_set(extract(year from public.cr_today())::int * 100 + extract(month from public.cr_today())::int, 'closed') as pc \gset
select test.eq((:'pc'::jsonb)->>'ok', 'true', 'the month closed');
select test.eq(public.acct_post_days(public.cr_today() - 3, public.cr_today())->>'error', 'period_closed', 'posting into a closed month says so');
select test.eq(public.acct_period_set(extract(year from public.cr_today())::int * 100 + extract(month from public.cr_today())::int, 'open')->>'ok', 'true', 'reopened');
-- 6) cash only on an asset
select test.eq(public.acct_account_save('6298', 'Gasto con caja', 'expense', true, true)->>'error', 'cash_not_asset', 'an expense account is never cash');
select test.eq(public.acct_account_save('1105', 'Caja terraza', 'asset', true, true)->>'ok', 'true', 'an asset can be');
reset role;

-- 7) a record-only document follows a bill cancelled by status
update public.settings set value = '"shadow"' where key = 'einvoice_mode';
insert into public.settings (key, value) select 'einvoice_mode', '"shadow"' where not exists (select 1 from public.settings where key = 'einvoice_mode');
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, guest_name)
  values ('0d000000-0000-4000-8000-000000003106', now(), 2000, 'pending', false, 'ready', 'Mesa 9');
select test.eq((select status from public.e_documents where order_id = '0d000000-0000-4000-8000-000000003106'), 'pending', 'the bill got its document');
update public.orders set status = 'cancelled' where id = '0d000000-0000-4000-8000-000000003106';
select test.eq((select status from public.e_documents where order_id = '0d000000-0000-4000-8000-000000003106'), 'cancelled', 'cancelled with the bill');

-- 8) labor cost: a switch from hourly to fixed pay is not counted twice
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.staff_pay_set(test.staff('ana'), 'hourly', 2000, public.cr_today() - 40)->>'ok', 'true', 'Ana by the hour');
select test.eq(public.staff_pay_set(test.staff('ana'), 'period', 300000, public.cr_today() - 10)->>'ok', 'true', 'then on a fixed pay');
select test.eq(public.pay_period_save(public.cr_today() - 10, public.cr_today() + 3)->>'ok', 'true', 'a pay period for the fixed pay');
reset role;
insert into public.time_entries (staff_id, clock_in, clock_out) values (test.staff('ana'), public.cr_day_start(public.cr_today() - 5) + interval '8 hours', public.cr_day_start(public.cr_today() - 5) + interval '12 hours');
select test.login('accountant', 'aal2'); set role authenticated;
select public.labor_cost(public.cr_today() - 5, public.cr_today() - 5) as lc \gset
select test.eq((select (x->>'labor_crc')::numeric from jsonb_array_elements((:'lc'::jsonb)->'days') x), round(300000::numeric / 14, 2), 'only the fixed pay''s share of the day, not 4 h × the old hourly rate on top');
reset role;

-- 9) the team: a PIN in use is refused; the owner role needs the phone code
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.manager_save_staff(null, null, null, 'Nuevo', '5284', true, 'staff')->>'error', 'pin_in_use', 'Luis''s PIN cannot be given to someone else');
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', '5284', true, 'staff')->>'ok', 'true', 'Luis keeps his own');
select test.eq(public.manager_save_staff(null, null, null, 'Nuevo', '7391', true, 'staff')->>'error', 'pin_in_use', 'nor the owner''s');
select test.eq(public.manager_save_staff(null, null, null, 'Nuevo', '9052', true, 'staff')->>'ok', 'true', 'a free PIN is fine');
reset role;
select test.login('owner', 'aal1'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'owner')->>'error', 'owner_role_only', 'without the phone code the owner role is not given, even with a manager PIN');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'owner')->>'ok', 'true', 'with the phone code it is');
reset role;

-- 10) visitors' questions: a size and a pace
select test.login('anon'); set role anon;
select test.lives($$insert into public.chat_questions (message, lang, session) values ('¿A qué hora abren?', 'es', 'visita-1')$$, 'a visitor asks');
select test.throws($$insert into public.chat_questions (message, lang, session) values (repeat('a', 501), 'es', 'visita-1')$$, 'too_long', 'not a wall of text');
insert into public.chat_questions (message, lang, session) select 'pregunta ' || n, 'es', 'visita-1' from generate_series(1, 19) n;
select test.throws($$insert into public.chat_questions (message, lang, session) values ('una más', 'es', 'visita-1')$$, 'too_many', 'not twenty-one in an hour from one visit');
select test.lives($$insert into public.chat_questions (message, lang, session) values ('hola', 'fr', 'visita-2')$$, 'another visit goes on');
reset role;
select test.eq((select lang from public.chat_questions where session = 'visita-2'), null::text, 'an unknown language is dropped');
select test.done();
rollback;
