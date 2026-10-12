-- Migrations 0021 and 0022: pay periods, approved hours locked, payroll prepared, reviewed, posted and paid.
begin;
-- a past period: Ana 3 shifts of 8 h; Luis 2 shifts of 6 h and one still open
select public.cr_today() - 20 as p0, public.cr_today() - 7 as p1 \gset
insert into public.time_entries (id, staff_id, clock_in, clock_out) values
  ('ae000000-0000-4000-8000-000000002201', test.staff('ana'), public.cr_day_start(public.cr_today() - 15) + interval '7 hours', public.cr_day_start(public.cr_today() - 15) + interval '15 hours'),
  ('ae000000-0000-4000-8000-000000002202', test.staff('ana'), public.cr_day_start(public.cr_today() - 14) + interval '7 hours', public.cr_day_start(public.cr_today() - 14) + interval '15 hours'),
  ('ae000000-0000-4000-8000-000000002203', test.staff('ana'), public.cr_day_start(public.cr_today() - 13) + interval '7 hours', public.cr_day_start(public.cr_today() - 13) + interval '15 hours'),
  ('ae000000-0000-4000-8000-000000002204', test.staff('luis'), public.cr_day_start(public.cr_today() - 15) + interval '8 hours', public.cr_day_start(public.cr_today() - 15) + interval '14 hours'),
  ('ae000000-0000-4000-8000-000000002205', test.staff('luis'), public.cr_day_start(public.cr_today() - 14) + interval '8 hours', public.cr_day_start(public.cr_today() - 14) + interval '14 hours'),
  ('ae000000-0000-4000-8000-000000002206', test.staff('luis'), public.cr_day_start(public.cr_today() - 10) + interval '8 hours', null);

select test.login('cafe'); set role authenticated;
select test.eq(public.pay_period_save(:'p0', :'p1')->>'error', 'not_allowed', 'a café device does not create pay periods');
select test.eq(public.timesheet(null)->>'error', 'not_allowed', 'nor sees the timesheets');
reset role;
select test.login('accountant'); set role authenticated;
select public.pay_period_save(:'p0', :'p1') as pp \gset
select test.eq((:'pp'::jsonb)->>'ok', 'true', 'the accountant creates the period');
select (:'pp'::jsonb)->>'id' as period \gset
select test.eq(public.pay_period_save(:'p1', public.cr_today())->>'error', 'overlaps', 'periods never overlap');
select public.timesheet(:'period') as ts \gset
select test.eq((select (x->>'hours')::numeric from jsonb_array_elements((:'ts'::jsonb)->'people') x where x->>'name' = 'Ana'), 24::numeric, 'Ana: 24 hours');
select test.eq((select (x->>'open')::int from jsonb_array_elements((:'ts'::jsonb)->'people') x where x->>'name' = 'Luis'), 1, 'Luis has a shift without clock-out');
select test.eq(public.timesheet_approve(:'period')->>'error', 'owner_only', 'the owner approves the hours, not the accountant');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.timesheet_approve(:'period')->>'error', 'open_shifts', 'not with a shift still open');
reset role;
update public.time_entries set clock_out = clock_in + interval '4 hours' where id = 'ae000000-0000-4000-8000-000000002206';
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.timesheet_approve(:'period')->>'ok', 'true', 'approved');
select test.eq(public.timesheet_approve(:'period')->>'error', 'not_open', 'once');
reset role;
-- the approved hours stay as approved: no punch, edit or delete, not even by a manager
select test.throws($$update public.time_entries set clock_out = clock_out + interval '1 hour' where id = 'ae000000-0000-4000-8000-000000002201'$$, 'period_locked', 'an approved shift is not changed');
select test.throws($$delete from public.time_entries where id = 'ae000000-0000-4000-8000-000000002201'$$, 'period_locked', 'nor deleted');
select test.throws(format($$insert into public.time_entries (staff_id, clock_in, clock_out) values (%L, %L, %L)$$, test.staff('ana'),
                          public.cr_day_start(public.cr_today() - 12) + interval '8 hours', public.cr_day_start(public.cr_today() - 12) + interval '9 hours'), 'period_locked', 'nor added');
select test.login('cafe'); set role authenticated;
select test.throws(format($$select public.manager_save_shift(%L, '4826', 'ae000000-0000-4000-8000-000000002201', null, %L, %L, 'olvido')$$, test.staff('ana'),
                          public.cr_day_start(public.cr_today() - 15) + interval '6 hours', public.cr_day_start(public.cr_today() - 15) + interval '15 hours'),
                   'period_locked', 'not even with a manager PIN');
select test.lives($$select public.clock_punch('a1000000-0000-4000-8000-000000000001', '4826')$$, 'today''s punches go on as usual');
reset role;
select test.eq((select hours from public.pay_period_hours where staff_id = test.staff('luis')), 16::numeric, 'the approved copy: Luis 16 h');

-- pay: rates, rules only with a confirmation, the payroll
select test.login('accountant'); set role authenticated;
select test.eq(public.staff_pay_set(test.staff('ana'), 'hourly', 2500, :'p0')->>'ok', 'true', 'Ana by the hour');
select test.eq(public.staff_pay_set(test.staff('luis'), 'hourly', 2000, :'p0')->>'ok', 'true', 'Luis by the hour');
select public.payroll_prepare(:'period') as pr \gset
select (:'pr'::jsonb)->>'run_id' as run \gset
select test.eq((select (x->>'gross')::numeric || '|' || (x->>'deductions')::numeric from (select public.payroll_get(:'period')->'totals' as x) q), '92000.00|0.00',
               'gross from the approved hours; no rules confirmed, no deductions');
select test.eq(public.payroll_rule_save('{"code":"ccss_obrero","name":"CCSS trabajador","kind":"employee","pct":10.5}')->>'error', 'missing_reference',
               'a rule needs who confirmed it and the document');
-- example percentages for the test only: the real ones come from the accountant (A-08)
select test.eq(public.payroll_rule_save('{"code":"ccss_obrero","name":"CCSS trabajador","kind":"employee","pct":10.5,"confirmed_by":"Contadora","reference":"prueba"}')->>'ok', 'true', 'employee rule');
select test.eq(public.payroll_rule_save('{"code":"ccss_patrono","name":"CCSS patrono","kind":"employer","pct":26.33,"confirmed_by":"Contadora","reference":"prueba"}')->>'ok', 'true', 'employer rule');
select test.eq(public.payroll_prepare(:'period')->>'ok', 'true', 'the draft is worked out again');
select test.eq(public.payroll_adjust(:'run', test.staff('ana'), 1000, '')->>'error', 'missing_reason', 'another deduction says what it is');
select test.eq(public.payroll_adjust(:'run', test.staff('ana'), 1000, 'adelanto')->>'ok', 'true', 'an advance taken from Ana''s pay');
select public.payroll_get(:'period') as pg \gset
select test.eq((select x->>'gross_crc' || '|' || (x->>'deductions_crc') || '|' || (x->>'employer_crc') || '|' || (x->>'net_crc')
                  from jsonb_array_elements((:'pg'::jsonb)->'lines') x where x->>'staff_name' = 'Ana'), '60000.00|6300.00|15798.00|52700.00', 'Ana: gross, deductions, employer, net');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.payroll_review(:'run')->>'error', 'accountant_only', 'the accountant reviews it');
select test.eq(public.payroll_post(:'run')->>'error', 'not_reviewed', 'nothing is posted before the review');
reset role;
select test.login('accountant'); set role authenticated;
select test.eq(public.payroll_review(:'run')->>'ok', 'true', 'reviewed');
select test.eq(public.payroll_adjust(:'run', test.staff('ana'), 0, null)->>'error', 'not_draft', 'a reviewed payroll does not change');
select test.eq(public.payroll_post(:'run')->>'ok', 'true', 'posted');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key = 'payroll:' || :'run'),
               '2130:-81340.00,2131:-33883.60,2132:-1000.00,6101:92000.00,6102:24223.60', 'salaries and charges against what is owed');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.timesheet_reopen(:'period', 'error')->>'error', 'payroll_posted', 'a posted payroll keeps its hours');
select test.eq(public.payroll_pay(:'run', 'bank', public.cr_today())->>'ok', 'true', 'paid by the bank');
select test.eq(public.staff_pay_set(test.staff('ana'), 'hourly', 2700, (:'p0')::date + 1)->>'error', 'used_by_payroll', 'a rate already paid is not rewritten');
select test.eq(public.staff_pay_set(test.staff('ana'), 'hourly', 2700, public.cr_today())->>'ok', 'true', 'a raise starts later');
select public.labor_cost(:'p0', :'p1') as lc \gset
select test.eq((select sum((x->>'labor_crc')::numeric) from jsonb_array_elements((:'lc'::jsonb)->'days') x), 92000::numeric, 'labor cost of the period: the hours at their rates');
reset role;
select test.eq((select status from public.pay_periods where id = :'period'), 'paid', 'the period is paid');
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(debit - credit) from acct.lines where account = '2130'), 0::numeric, 'net salaries owed: settled');
select test.done();
rollback;
