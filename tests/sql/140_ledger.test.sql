-- Migration 0013: double-entry ledger, the day's entry, periods, reports, the accountant.
begin;
-- 1) who may see it -------------------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(public.acct_overview()->>'error', 'not_allowed', 'the café login cannot open the accounting');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.acct_overview()->>'error', 'not_allowed', 'nor a manager with a PIN');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.acct_overview()->>'kind', 'accountant', 'the accountant can');
select test.eq(public.is_cafe(), false, 'and cannot open the POS');
select test.eq(public.register_today(), null::jsonb, 'nor the register');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.acct_overview()->>'ok', 'true', 'the owner (with the phone code) can');
select test.eq(public.accountant_grant('nadie@test.local')->>'error', 'no_such_login', 'the owner grants the role to an existing login only');
reset role;

-- 2) a manual entry: balanced or nothing; never edited -----------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.acct_entry_post(public.cr_today(), 'Aporte de capital',
        '[{"account":"1110","debit":500000},{"account":"3101","credit":400000}]', '7e000000-0000-4000-8000-000000001401')->>'error', 'unbalanced',
        'an unbalanced entry is refused');
select public.acct_entry_post(public.cr_today(), 'Aporte de capital',
        '[{"account":"1110","debit":500000},{"account":"3101","credit":500000}]', '7e000000-0000-4000-8000-000000001401', true) as e1 \gset
select test.eq((:'e1'::jsonb)->>'ok', 'true', 'a balanced opening entry is posted');
select test.eq(public.acct_entry_post(public.cr_today(), 'Aporte de capital',
        '[{"account":"1110","debit":500000},{"account":"3101","credit":500000}]', '7e000000-0000-4000-8000-000000001401', true)->>'entry_id',
        (:'e1'::jsonb)->>'entry_id', 'the same request twice is one entry');
select test.eq(public.acct_entry_post(public.cr_today(), 'x', '[{"account":"9999","debit":1},{"account":"3101","credit":1}]', gen_random_uuid())->>'error',
        'unknown_account', 'an unknown account is refused');
reset role;
set constraints all immediate; set constraints all deferred;   -- check the pending entries now, then back to normal
select test.throws($$update acct.lines set debit = 1 where entry_id = (select min(id) from acct.entries)$$, 'ledger_immutable', 'a line is never edited');
select test.throws($$delete from acct.entries$$, 'ledger_immutable', 'an entry is never deleted');
select test.throws($$select acct.post(current_date, 'x', 'manual', null, '[{"account":"1101","debit":10},{"account":"4101","credit":9}]'); set constraints all immediate$$,
                   'ledger_unbalanced', 'the database itself refuses an unbalanced entry');
set constraints all deferred;

-- 3) the day's entry --------------------------------------------------------------------------------------------------
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000001401', 'Leche', 'ml', 1000, 1000);
insert into public.stock_moves (item_id, kind, qty, unit_cost, note) values ('5a000000-0000-4000-8000-000000001401', 'purchase', 10000, 1, 'compra');
insert into public.recipes (menu_item_id, stock_item_id, qty) select id, '5a000000-0000-4000-8000-000000001401', 200 from public.menu_items where name = 'Latte';
select id as latte from public.menu_items where name = 'Latte' \gset
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today(), 500, 510, 'hacienda');
insert into public.register_days (business_date, opened_by_name, float_crc) values (public.cr_today(), 'Ana', 50000);
select test.login('cafe'); set role authenticated;
-- latte ₡2 200 cash (₡5 000 note, ₡2 800 change); latte ₡2 200 paid with $10 at 500; ₡1 300 card
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001401', 'total_crc', 2200, 'payment_method', 'cash_crc',
       'tender', jsonb_build_object('crc_in', 5000, 'change_crc', 2800),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001402', 'total_crc', 2200, 'payment_method', 'cash_usd',
       'tender', jsonb_build_object('usd_in', 10, 'fx_rate', 500, 'change_crc', 2800),
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))));
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001403', 'total_crc', 1300, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Espresso', 'price_crc', 1300, 'qty', 1))));
-- a bill: ₡2 000 paid by card now, ₡2 000 still open at the close
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000001404', now(), 4000, 'pending', false, 'ready');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000001404', 'Mocha', 2000, 2);
select public.tab_pay('0d000000-0000-4000-8000-000000001404', 'card', null, 2000, 'Caja', 4000);
-- close the day: colones 50 000 + 2 200 − 2 800 = 49 400, counted 49 300 (₡100 short); $10
select public.register_close(test.staff('ana'), '4826', 3300, 49300, null, 10);
reset role;
select test.eq((select count(*)::int from acct.entries where source = 'day'), 0, 'automatic posting is off until the accountant approves the chart');

select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.acct_post_days(public.cr_today(), public.cr_today())->>'entries', '1', 'the accountant posts the day');
-- the balance check runs at commit as the caller (here: forced now, still as the accountant)
select test.lives('set constraints all immediate', 'the commit-time balance check runs with the accountant''s rights');
set constraints all deferred;
reset role;
set constraints all immediate; set constraints all deferred;   -- check the pending entries now, then back to normal
create temp table t_day as
  select l.account, sum(l.debit - l.credit) as amt from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'day' group by l.account;
-- sales: 2 200 + 2 200 + 1 300 = 5 700, IVA 253 + 253 + 150 = 656 → net 5 044
select test.eq((select amt from t_day where account = '4101'), -5044::numeric, 'sales without IVA (credit)');
select test.eq((select amt from t_day where account = '2110'), -656::numeric, 'IVA payable (credit)');
-- cash: (5 000 − 2 800) + (0 − 2 800) − 100 short = −500 ; dollars 10 × 500 = 5 000
select test.eq((select amt from t_day where account = '1101'), -700::numeric, 'colones: (5 000 − 2 800) + (0 − 2 800) − 100 short');
select test.eq((select amt from t_day where account = '1102'), 5000::numeric, 'dollars valued at the day''s rate');
select test.eq((select amt from t_day where account = '1120'), 3300::numeric, 'card: sale + part of the bill');
select test.eq((select amt from t_day where account = '2120'), -2000::numeric, 'the part paid on an open bill waits as a customer advance');
select test.eq((select amt from t_day where account = '6211'), 100::numeric, 'the shortage is an expense');
-- inventory: bought 10 000 ml at 1; sold 400 ml
select test.eq((select amt from t_day where account = '5101'), 400::numeric, 'cost of sales at average cost');
select test.eq((select amt from t_day where account = '1150'), 9600::numeric, 'inventory: purchase minus what was sold');
select test.eq((select amt from t_day where account = '2101'), -10000::numeric, 'the purchase is owed to the supplier');
select test.eq((select sum(amt) from t_day), 0::numeric, 'the day balances');

-- 4) a late sale after the close: only the difference is posted ----------------------------------------------------------
select test.login('cafe'); set role authenticated;
select public.tab_pay('0d000000-0000-4000-8000-000000001404', 'sinpe', null, null, 'Caja', 2000);
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select public.acct_post_days(public.cr_today(), public.cr_today());
select test.eq(public.acct_post_days(public.cr_today(), public.cr_today())->>'entries', '0', 'nothing new: nothing posted');
reset role;
set constraints all immediate; set constraints all deferred;   -- check the pending entries now, then back to normal
select test.eq((select count(*)::int from acct.entries where source = 'day'), 2, 'one adjustment entry for the late payment');
select test.eq((select sum(l.debit - l.credit) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'day' and l.account = '2120'), 0::numeric,
               'the bill is paid in full: the advance is used up');
select test.eq((select sum(l.debit - l.credit) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'day' and l.account = '1110'), 2000::numeric,
               'SINPE went to the bank');

-- 5) reports ---------------------------------------------------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.acct_income_statement(public.cr_today(), public.cr_today()) as pnl \gset
select public.acct_balance_sheet(public.cr_today()) as bs \gset
select public.acct_trial_balance(public.cr_today(), public.cr_today()) as tb \gset
select public.acct_cash_flow(public.cr_today(), public.cr_today()) as cf \gset
reset role;
-- revenue: 5 044 + (Mocha 4 000 − IVA 460 = 3 540) = 8 584 ; expenses: COGS 400 + shortage 100
select test.eq(((:'pnl'::jsonb)->>'revenue')::numeric, 8584::numeric, 'income statement: revenue');
select test.eq(((:'pnl'::jsonb)->>'net_income')::numeric, 8084::numeric, 'net income');
select test.eq((:'bs'::jsonb)->>'balanced', 'true', 'balance sheet: assets = liabilities + equity + results');
select test.eq((select sum((r->>'debit')::numeric) - sum((r->>'credit')::numeric) from jsonb_array_elements((:'tb'::jsonb)->'rows') r), 0::numeric,
               'trial balance: debits = credits');
select test.eq(((:'cf'::jsonb)->>'closing')::numeric, 500000 - 700 + 5000 + 2000::numeric, 'cash flow closing = cash and bank balances');

-- 6) automatic posting once approved ----------------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.setting_set('ledger_auto_post', 'true')->>'error', 'needs_confirmation', 'automatic posting waits for the approved chart');
select public.compliance_confirm('chart_of_accounts_approved', 'Contadora M. Rojas', 'Correo 2026-10-12');
select test.eq(public.setting_set('ledger_auto_post', 'true')->>'ok', 'true', 'then it can be switched on');
reset role;
insert into public.register_days (business_date, opened_by_name, float_crc) values (public.cr_today() - 1, 'Ana', 50000);
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000001405', public.cr_day_start(public.cr_today() - 1) + interval '10 hours', 1300, 'card', true, 'done');
update public.register_days set closed_at = now(), closed_by_name = 'Ana', cash_diff_crc = 0 where business_date = public.cr_today() - 1;
set constraints all immediate; set constraints all deferred;   -- check the pending entries now, then back to normal
select test.ok(exists (select 1 from acct.entries where source = 'day' and source_key like 'day:' || (public.cr_today() - 1) || ':%'),
               'closing the register posts the day');

-- 7) reversal and periods --------------------------------------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.acct_journal_reverse(((:'e1'::jsonb)->>'entry_id')::bigint, null, 'error de monto')->>'ok', 'true', 'a mistake is reversed');
select test.eq(public.acct_journal_reverse(((:'e1'::jsonb)->>'entry_id')::bigint, null, 'otra vez')->>'error', 'already_reversed', 'only once');
select test.eq(public.acct_period_set(to_char(public.cr_today(), 'YYYYMM')::int, 'closed')->>'ok', 'true', 'the month is closed');
select test.eq(public.acct_entry_post(public.cr_today(), 'tarde', '[{"account":"1101","debit":1},{"account":"4201","credit":1}]', gen_random_uuid())->>'error',
               'period_closed', 'nothing more is dated in a closed month');
select test.eq(public.acct_period_set(to_char(public.cr_today(), 'YYYYMM')::int, 'locked')->>'ok', 'true', 'and then locked');
select test.eq(public.acct_period_set(to_char(public.cr_today(), 'YYYYMM')::int, 'open')->>'error', 'locked', 'a locked month never reopens');
reset role;
-- a register close in a locked month still closes; the failed posting waits for the accountant
insert into public.register_days (business_date, opened_by_name, float_crc) values (public.cr_today() - 2, 'Ana', 50000);
insert into public.orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-000000001406', public.cr_day_start(public.cr_today() - 2) + interval '10 hours', 1300, 'card', true, 'done');
update public.register_days set closed_at = now(), closed_by_name = 'Ana' where business_date = public.cr_today() - 2;
select test.ok((select closed_at is not null from public.register_days where business_date = public.cr_today() - 2), 'the register closes anyway');
select test.ok(exists (select 1 from public.audit_log where action = 'ledger_post_failed' and target_id = (public.cr_today() - 2)::text)
               or to_char(public.cr_today() - 2, 'YYYYMM') <> to_char(public.cr_today(), 'YYYYMM'), 'and the failed posting is logged');
set constraints all immediate; set constraints all deferred;   -- check the pending entries now, then back to normal

select test.done();
rollback;
