-- Migration 0026: Costa Rican payroll. Rule categories (CCSS, INS), the employee's profile, the income-tax table
-- (OFF until the owner records the confirmation), extra pay, the split entry, the payslip, aguinaldo, vacations,
-- the settlement estimate and the month's report for the CCSS and the INS.
begin;
-- a past 14-day period: Ana 3 shifts of 8 h, Luis 2 shifts of 6 h and one of 4 h; Marta has a fixed pay per period
select public.cr_today() - 20 as p0, public.cr_today() - 7 as p1 \gset
insert into public.time_entries (id, staff_id, clock_in, clock_out) values
  ('ae000000-0000-4000-8000-000000002901', test.staff('ana'), public.cr_day_start(public.cr_today() - 15) + interval '7 hours', public.cr_day_start(public.cr_today() - 15) + interval '15 hours'),
  ('ae000000-0000-4000-8000-000000002902', test.staff('ana'), public.cr_day_start(public.cr_today() - 14) + interval '7 hours', public.cr_day_start(public.cr_today() - 14) + interval '15 hours'),
  ('ae000000-0000-4000-8000-000000002903', test.staff('ana'), public.cr_day_start(public.cr_today() - 13) + interval '7 hours', public.cr_day_start(public.cr_today() - 13) + interval '15 hours'),
  ('ae000000-0000-4000-8000-000000002904', test.staff('luis'), public.cr_day_start(public.cr_today() - 15) + interval '8 hours', public.cr_day_start(public.cr_today() - 15) + interval '14 hours'),
  ('ae000000-0000-4000-8000-000000002905', test.staff('luis'), public.cr_day_start(public.cr_today() - 14) + interval '8 hours', public.cr_day_start(public.cr_today() - 14) + interval '14 hours'),
  ('ae000000-0000-4000-8000-000000002906', test.staff('luis'), public.cr_day_start(public.cr_today() - 10) + interval '8 hours', public.cr_day_start(public.cr_today() - 10) + interval '12 hours');

-- the café device sees none of it
select test.login('cafe'); set role authenticated;
select test.eq(public.staff_profile_set(test.staff('ana'), '{"children": 1}')->>'error', 'not_allowed', 'a café device does not edit profiles');
select test.eq(public.payroll_month_report(2026, 1)->>'error', 'not_allowed', 'nor sees the month report');
select test.eq(public.aguinaldo_estimate(2026)->>'error', 'not_allowed', 'nor the aguinaldo');
select test.eq(public.vacation_balance(test.staff('ana'))->>'error', 'not_allowed', 'nor the vacations');
select test.eq(public.severance_estimate(test.staff('ana'), public.cr_today(), 'renuncia')->>'error', 'not_allowed', 'nor a settlement');
select test.throws($$select * from public.staff_profile$$, 'permission denied', 'the profile table is not readable');
reset role;

-- the accountant: profiles, rules by category, the tax table
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.staff_profile_set(test.staff('ana'), ('{"id_number": "1-1234-5678", "hired_on": "' || (public.cr_today() - 400) || '", "contract": "indefinido", "children": 2, "spouse": true}')::jsonb)->>'ok', 'true', 'Ana''s profile');
select test.eq(public.staff_profile_set(test.staff('marta'), '{"id_number": "155812345678", "contract": "indefinido", "children": 1}')->>'ok', 'true', 'Marta''s profile (DIMEX)');
select test.eq(public.staff_profile_set(test.staff('luis'), '{"id_number": "12"}')->>'error', 'bad_value', 'an ID number too short is refused');
select test.eq(public.staff_profile_set(test.staff('luis'), '{"hired_on": "2026-02-01", "ended_on": "2026-01-01"}')->>'error', 'bad_value', 'leaving before being hired is refused');
select test.eq(public.staff_profile_set(test.staff('ana'), '{"children": 2}')->>'changed', '[]', 'the same value again changes nothing');
select test.eq(public.staff_profile_set(test.staff('ana'), '{"spouse": false}')->>'changed', '["spouse"]', 'one field sent: only that field changes');
reset role;
select test.eq((select id_number || '|' || hired_on || '|' || children || '|' || spouse from public.staff_profile where staff_id = test.staff('ana')), '1-1234-5678|' || (public.cr_today() - 400) || '|2|false', 'the ID number and the dates stay');
select test.ok(not exists (select 1 from public.audit_log where action = 'staff_profile_set' and (details::text like '%1-1234-5678%' or details ? 'children' or details ? 'spouse')),
               'the log never carries the ID number, the family or the notes');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.staff_profile_set(test.staff('ana'), '{"spouse": true}')->>'ok', 'true', 'and back');
-- example percentages for the test only: the real ones come from the accountant (A-08)
select test.eq(public.payroll_rule_save('{"code":"ccss_obrero","name":"CCSS trabajador","kind":"employee","pct":10.5,"category":"ccss","confirmed_by":"Contadora","reference":"prueba"}')->>'ok', 'true', 'CCSS employee rule');
select test.eq(public.payroll_rule_save('{"code":"ccss_patrono","name":"CCSS patrono","kind":"employer","pct":26.33,"category":"ccss","confirmed_by":"Contadora","reference":"prueba"}')->>'ok', 'true', 'CCSS employer rule');
select test.eq(public.payroll_rule_save('{"code":"ins_rt","name":"INS riesgos del trabajo","kind":"employee","pct":1.5,"category":"ins","confirmed_by":"Contadora","reference":"prueba"}')->>'error', 'bad_value', 'the INS policy is never taken from the pay');
select test.eq(public.payroll_rule_save('{"code":"ins_rt","name":"INS riesgos del trabajo","kind":"employer","pct":1.5,"category":"ins","confirmed_by":"Contadora","reference":"prueba"}')->>'ok', 'true', 'INS employer rule');
select test.eq(public.payroll_rule_save('{"code":"x","name":"x","kind":"employer","pct":1,"category":"otro","confirmed_by":"C","reference":"r"}')->>'error', 'bad_value', 'only the three categories');
reset role;
select test.eq((select category from public.payroll_rules where code = 'ins_rt'), 'ins', 'the category is kept');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": null, "pct": 10}]}', 'Contadora', '')->>'error', 'missing_reference', 'a tax table needs who confirmed it and the document');
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": 900000, "pct": 10}, {"upto": null, "pct": 15}]}', 'Contadora', 'prueba')->>'error', 'bad_value', 'brackets go up');
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": 1352000, "pct": 10}]}', 'Contadora', 'prueba')->>'error', 'bad_value', 'the last bracket has no upper limit');
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": null, "pct": 10}, {"upto": 2000000, "pct": 15}]}', 'Contadora', 'prueba')->>'error', 'bad_value', 'nothing after the open bracket');
select test.eq(public.payroll_param_save('impuesto', '{}', 'Contadora', 'prueba')->>'error', 'bad_value', 'only the four parameters (renta, vacation, severance, ccss)');
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": "NaN", "pct": 0}, {"upto": null, "pct": 10}]}', 'Contadora', 'prueba')->>'error', 'bad_value', 'NaN is not a limit');
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": null, "pct": 10}], "credit_child": "Infinity"}', 'Contadora', 'prueba')->>'error', 'bad_value', 'nor infinity a credit');
select test.eq(public.payroll_param_save('vacation', '{"days_per_month": 0}', 'Contadora', 'prueba')->>'error', 'bad_value', 'vacation days per month above zero');
reset role;
select test.eq((select confirmed_by is null from public.payroll_params where key = 'vacation'), true, 'the vacation default is the law as written, confirmed by nobody');
select test.eq((select confirmed_by is null from public.payroll_params where key = 'severance'), true, 'so is the severance table');
select test.login('accountant', 'aal2'); set role authenticated;

-- the period, approved by the owner; the rates
select public.pay_period_save(:'p0', :'p1') as pp \gset
select (:'pp'::jsonb)->>'id' as period \gset
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.timesheet_approve(:'period')->>'ok', 'true', 'the owner approves the hours');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.staff_pay_set(test.staff('ana'), 'hourly', 2500, :'p0')->>'ok', 'true', 'Ana by the hour');
select test.eq(public.staff_pay_set(test.staff('luis'), 'hourly', 2000, :'p0')->>'ok', 'true', 'Luis by the hour');
select test.eq(public.staff_pay_set(test.staff('marta'), 'period', 1400000, :'p0')->>'ok', 'true', 'Marta: a fixed pay per period');
-- 1) nothing confirmed: the rules apply (they carry their own confirmation), the tax is off
select public.payroll_prepare(:'period') as pr \gset
select (:'pr'::jsonb)->>'run_id' as run \gset
reset role;
select test.eq((select r.params->>'renta_status' from public.payroll_runs r where r.id = :'run'), 'off', 'income tax: off until the owner records the confirmation');
select test.eq((select renta_crc || '|' || (renta_detail->>'status') from public.payroll_lines where run_id = :'run' and staff_id = test.staff('marta')), '0.00|off', 'Marta: no tax withheld while it is off');
select test.eq((select aguinaldo_accrual_crc from public.payroll_lines where run_id = :'run' and staff_id = test.staff('marta')), 0::numeric, 'no aguinaldo provision while it is off');
select test.eq((select (x->>'category') from public.payroll_lines, jsonb_array_elements(employer) x where run_id = :'run' and staff_id = test.staff('ana') and x->>'code' = 'ins_rt'), 'ins', 'the INS charge carries its category');
-- 2) the owner turns the two settings on: only after recording the confirmation
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.setting_set('payroll_renta_withhold', 'true')->>'error', 'needs_confirmation', 'the withholding stays locked');
select test.eq(public.setting_set('payroll_accrue_aguinaldo', 'true')->>'error', 'needs_confirmation', 'so does the provision');
select test.eq(public.compliance_confirm('payroll_cr_rules', 'Contadora M. Rojas', 'Oficio 7-2026')->>'ok', 'true', 'the owner records the confirmation');
select test.eq(public.setting_set('payroll_renta_withhold', 'true')->>'ok', 'true', 'withholding on');
select test.eq(public.setting_set('payroll_accrue_aguinaldo', 'true')->>'ok', 'true', 'provision on');
reset role;
-- 3) withholding on but no table yet: the payroll says so and is not reviewed
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_review(:'run')->>'error', 'prepare_again', 'the settings changed since the draft was prepared: it is worked out again first');
select test.eq(public.payroll_prepare(:'period')->>'ok', 'true', 'prepared again');
reset role;
select test.eq((select r.params->>'renta_status' from public.payroll_runs r where r.id = :'run'), 'no_table', 'no tax table yet');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_review(:'run')->>'error', 'renta_table_missing', 'not reviewed without the table');
-- the table (example figures for the test only; the real ones come from Hacienda through the accountant, A-08)
select test.eq(public.payroll_param_save('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": 1352000, "pct": 10}, {"upto": null, "pct": 15}], "credit_child": 1720, "credit_spouse": 2600, "method": "prorate", "valid_from": "2026-01-01"}',
                                        'Contadora M. Rojas', 'Decreto de tramos 2026 (prueba)')->>'ok', 'true', 'the tax table is saved with its confirmation');
select test.eq(public.payroll_review(:'run')->>'error', 'prepare_again', 'with the table now saved, the stale draft asks to be prepared again (not for a table it has)');
select test.eq(public.payroll_prepare(:'period')->>'ok', 'true', 'prepared with the table');
reset role;
select test.eq((select r.params->>'renta_status' from public.payroll_runs r where r.id = :'run'), 'on', 'income tax on');
-- Marta: 1 400 000 in 14 days -> 3 000 000 a month -> 0 + 43 000 + 247 200 = 290 200, less 1 720 for one child = 288 480 a month -> 134 624 for the 14 days
select test.eq((select renta_crc || '|' || (renta_detail->>'monthly_base') || '|' || (renta_detail->>'monthly_tax') || '|' || (renta_detail->>'credits')
                  from public.payroll_lines where run_id = :'run' and staff_id = test.staff('marta')), '134624.00|3000000.00|290200.00|1720', 'Marta: the monthly table, prorated to the period');
select test.eq((select deductions_crc || '|' || employer_crc || '|' || net_crc || '|' || aguinaldo_accrual_crc from public.payroll_lines where run_id = :'run' and staff_id = test.staff('marta')),
               '147000.00|389620.00|1118376.00|116666.67', 'Marta: CCSS 10,5 %, employer 26,33 % + INS 1,5 %, net after tax, one twelfth provisioned');
select test.eq((select renta_crc from public.payroll_lines where run_id = :'run' and staff_id = test.staff('ana')), 0::numeric, 'Ana (60 000 in 14 days): below the first bracket, no tax');
-- a calendar month is a month whatever its length: 1 500 000 a month -> 43 000 + 22 200 = 65 200 in February and in March alike
select test.eq((select string_agg(public._payroll_renta(1500000, d, 0, false, r.params)->>'amount', '|' order by d) from public.payroll_runs r, unnest(array[28, 30, 31]) d where r.id = :'run'),
               '65200.00|65200.00|65200.00', 'a 28-, 30- or 31-day period is taxed as a month');
select test.eq(public._payroll_renta(750000, 15, 0, false, (select params from public.payroll_runs where id = :'run'))->>'amount', '32600.00', 'a 15-day half: taken to a month, half the tax');
select test.login('accountant', 'aal2'); set role authenticated;
-- extra pay: vacation days paid, part of the salary
select test.eq(public.payroll_extra(:'run', test.staff('ana'), 10000, '')->>'error', 'missing_reason', 'extra pay says what it is');
select test.eq(public.payroll_extra(:'run', test.staff('ana'), -5, 'x')->>'error', 'bad_value', 'never negative');
select test.eq(public.payroll_extra(:'run', test.staff('ana'), 10000, 'vacaciones: 2 días')->>'ok', 'true', 'Ana: 10 000 extra');
reset role;
select test.eq((select gross_crc || '|' || extra_crc || '|' || deductions_crc || '|' || employer_crc || '|' || net_crc || '|' || aguinaldo_accrual_crc from public.payroll_lines where run_id = :'run' and staff_id = test.staff('ana')),
               '60000.00|10000.00|7350.00|19481.00|62650.00|5833.33', 'Ana: the rules apply to gross + extra');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_adjust(:'run', test.staff('marta'), 2000000, 'adelanto')->>'error', 'bad_value', 'another deduction never exceeds what is left');
select test.eq(public.payroll_adjust(:'run', test.staff('marta'), 10000, 'adelanto')->>'ok', 'true', 'an advance taken from Marta''s pay');
reset role;
select test.eq((select net_crc from public.payroll_lines where run_id = :'run' and staff_id = test.staff('marta')), 1108376.00::numeric, 'Marta: net after the advance');
select test.eq((select count(*) from public.audit_log where action in ('payroll_extra', 'payroll_adjust') and target_id = :'run'), 2::bigint, 'the extra and the advance are in the log');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_prepare(:'period')->>'kept', '2', 'prepared once more: the extra and the advance are kept');
reset role;
select test.eq((select extra_crc || '|' || extra_note from public.payroll_lines where run_id = :'run' and staff_id = test.staff('ana')), '10000.00|vacaciones: 2 días', 'Ana''s extra survived');
select test.eq((select other_crc || '|' || net_crc from public.payroll_lines where run_id = :'run' and staff_id = test.staff('marta')), '10000.00|1108376.00', 'Marta''s advance survived');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_review(:'run')->>'ok', 'true', 'reviewed');
select test.eq(public.payroll_extra(:'run', test.staff('ana'), 0, null)->>'error', 'not_draft', 'a reviewed payroll does not change');
select test.eq(public.payroll_post(:'run')->>'ok', 'true', 'posted');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key = 'payroll:' || :'run'),
               '2130:-1199666.00,2131:-553186.60,2132:-10000.00,2133:-22530.00,2140:-134624.00,2150:-125166.67,6101:1502000.00,6102:395476.60,6103:125166.67,6105:22530.00',
               'the entry: salaries, CCSS (6102/2131), INS apart (6105/2133), income tax (2140), other deductions (2132), net pay (2130), aguinaldo provision (6103/2150)');

-- the payslip
select test.login('accountant', 'aal2'); set role authenticated;
select public.payslip(:'run', test.staff('marta')) as ps \gset
select test.eq((:'ps'::jsonb)->>'ok' || '|' || ((:'ps'::jsonb)->'staff'->>'id_number') || '|' || ((:'ps'::jsonb)->>'renta_crc') || '|' || ((:'ps'::jsonb)->>'net_crc') || '|' || ((:'ps'::jsonb)->>'status'),
               'true|155812345678|134624.00|1108376.00|posted', 'Marta''s payslip');
select test.eq(public.payslip(:'run', test.staff('dueno'))->>'error', 'not_found', 'no payslip for someone not in the payroll');

-- the month for the CCSS and the INS (the month the period ends in)
select extract(year from :'p1'::date)::int as yy, extract(month from :'p1'::date)::int as mm \gset
select public.payroll_month_report(:yy, :mm) as mr \gset
select test.eq(jsonb_array_length((:'mr'::jsonb)->'people'), 3, 'three people in the month');
select test.eq((select x->>'salary_crc' || '|' || (x->>'employee_ccss_crc') || '|' || (x->>'employer_ccss_crc') || '|' || (x->>'employer_ins_crc') || '|' || (x->>'renta_crc')
                  from jsonb_array_elements((:'mr'::jsonb)->'people') x where x->>'staff_name' = 'Ana'), '70000.00|7350.00|18431.00|1050.00|0.00', 'Ana in the month: salary, CCSS both sides, INS, tax');
-- the days worked are the shift days that fall in the month (the shifts straddle two months on some dates of the calendar)
reset role;
select test.eq((select (x->>'days_worked')::int from jsonb_array_elements((:'mr'::jsonb)->'people') x where x->>'staff_name' = 'Ana'),
               (select count(distinct public._shift_day(clock_in))::int from public.time_entries where staff_id = test.staff('ana') and clock_out is not null
                  and date_trunc('month', public._shift_day(clock_in)) = date_trunc('month', :'p1'::date)), 'Ana: the days worked in the month');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq((select x->>'id_number' is null from jsonb_array_elements((:'mr'::jsonb)->'people') x where x->>'staff_name' = 'Luis'), true, 'Luis has no ID number on file (the page flags it)');
select test.eq((select x->>'amount_crc' from jsonb_array_elements((:'mr'::jsonb)->'rules') x where x->>'code' = 'ins_rt'), '22530.00', 'the INS total of the month');
select test.eq(public.payroll_month_report(2026, 13)->>'error', 'bad_value', 'a real month');

-- aguinaldo: the salaries from 1 December to 30 November over twelve; posting needs the confirmation
select extract(year from :'p1'::date)::int + case when extract(month from :'p1'::date) = 12 then 1 else 0 end as ay \gset
select public.aguinaldo_estimate(:ay) as ae \gset
select test.eq((select x->>'aguinaldo_crc' || '|' || (x->>'accrued_crc') || '|' || (x->>'months') from jsonb_array_elements((:'ae'::jsonb)->'lines') x where x->>'staff_name' = 'Marta'), '116666.67|116666.67|1', 'Marta: one twelfth, already provisioned');
select test.eq(jsonb_array_length((:'ae'::jsonb)->'lines'), 3, 'the three people');
select test.eq((:'ae'::jsonb)->>'pending_payrolls', '0', 'every period of the window has its payroll posted');
select test.eq(public.aguinaldo_prepare(:ay)->>'ok', 'true', 'the aguinaldo run is prepared');
reset role;
select (select id from public.payroll_special_runs where kind = 'aguinaldo' and year = :ay) as arun \gset
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.aguinaldo_post(:'arun', public.cr_today())->>'error', 'not_reviewed', 'the accountant reviews it first');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.aguinaldo_review(:'arun')->>'error', 'accountant_only', 'the owner does not review it');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.aguinaldo_review(:'arun')->>'ok', 'true', 'reviewed');
select test.eq(public.aguinaldo_prepare(:ay)->>'error', 'not_draft', 'a reviewed run is not prepared again');
reset role;
delete from public.compliance_confirmations where key = 'payroll_cr_rules';       -- as if the owner had never recorded it
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.aguinaldo_post(:'arun', public.cr_today())->>'error', 'needs_confirmation', 'nothing is posted without the confirmation');
reset role;
insert into public.compliance_confirmations (key, confirmed_by, reference) values ('payroll_cr_rules', 'Contadora M. Rojas', 'Oficio 7-2026');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.aguinaldo_post(:'arun', public.cr_today() + 1, 'x')->>'error', 'bad_value', 'not in the future');
select test.ok(case when public.cr_today() < make_date(:ay, 11, 30) then public.aguinaldo_post(:'arun', public.cr_today())->>'error' = 'too_early' else true end,
               'before 30 November it is posted only with a written reason');
select test.eq(public.aguinaldo_post(:'arun', public.cr_today(), 'adelanto autorizado por el dueño (prueba)')->>'ok', 'true', 'posted with the reason: the provisions covered it all, no entry needed');
reset role;
select test.eq((select entry_id is null and status = 'posted' from public.payroll_special_runs where id = :'arun'), true, 'nothing left to expense');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.aguinaldo_pay(:'arun', 'bank', public.cr_today())->>'ok', 'true', 'paid by the bank');
select public.aguinaldo_estimate(:ay) as ae2 \gset
select test.eq(jsonb_array_length((:'ae2'::jsonb)->'lines') || '|' || ((:'ae2'::jsonb)->>'paid_crc') || '|' || jsonb_array_length((:'ae2'::jsonb)->'runs'), '0|125166.67|1', 'nothing left to pay this year; what was paid is listed');
select test.eq(public.aguinaldo_prepare(:ay)->>'error', 'empty', 'a new run has nothing to take');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(debit - credit) from acct.lines where account = '2150'), 0::numeric, 'aguinaldo owed: settled');
select test.eq((select sum(credit) from acct.lines where account = '1110' and entry_id = (select pay_entry_id from public.payroll_special_runs where id = :'arun')), 125166.67::numeric, 'paid from the bank');

-- vacations: the balance is an estimate until the days-per-month rule is confirmed
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.vacation_record(test.staff('ana'), public.cr_today() - 3, public.cr_today() - 3, 1, 'paid_out', '')->>'error', 'missing_reason', 'paying days out is the exception: it needs a reason');
select public.vacation_record(test.staff('ana'), public.cr_today() - 3, public.cr_today() - 3, 1, 'taken', 'un día') as vr \gset
select test.eq((:'vr'::jsonb)->>'ok', 'true', 'a vacation day recorded');
select public.vacation_balance(test.staff('ana')) as vb \gset
select test.eq((:'vb'::jsonb)->>'months' || '|' || ((:'vb'::jsonb)->>'earned_days') || '|' || ((:'vb'::jsonb)->>'taken_days') || '|' || ((:'vb'::jsonb)->>'remaining_days') || '|' || ((:'vb'::jsonb)->>'daily_crc') || '|' || ((:'vb'::jsonb)->>'value_crc') || '|' || ((:'vb'::jsonb)->>'confirmed'),
               '13|13.00|1.00|12.00|5000.00|60000.00|false', 'Ana: 13 months since hired, one day per month, one taken, average daily pay 70 000 / 14 days, not confirmed');
select test.eq(public.payroll_param_save('vacation', '{"days_per_month": 1}', 'Contadora M. Rojas', 'Código de Trabajo art. 153')->>'ok', 'true', 'the vacation rule confirmed');
select test.eq(public.vacation_balance(test.staff('ana'))->>'confirmed', 'true', 'now confirmed');
select test.eq(public.vacation_void(((:'vr'::jsonb)->>'id')::uuid, '')->>'error', 'missing_reason', 'voiding says why');
select test.eq(public.vacation_void(((:'vr'::jsonb)->>'id')::uuid, 'se registró por error')->>'ok', 'true', 'voided, never deleted');
select test.eq(public.vacation_balance(test.staff('ana'))->>'taken_days', '0', 'the voided record does not count');
reset role;
select test.eq((select count(*) from public.vacations where staff_id = test.staff('ana')), 1::bigint, 'the record stays');
select test.login('accountant', 'aal2'); set role authenticated;
-- the settlement estimate: dismissal without cause after 13 months -> one month of notice, 19,5 days of severance
select public.severance_estimate(test.staff('ana'), public.cr_today(), 'despido_sin_causa') as se \gset
select test.eq((select x->>'days' || '|' || (x->>'amount_crc') || '|' || (x->>'applies') from jsonb_array_elements((:'se'::jsonb)->'items') x where x->>'key' = 'preaviso'), '30|150000.00|true', 'notice: 30 days at 5 000');
select test.eq((select x->>'days' || '|' || (x->>'amount_crc') from jsonb_array_elements((:'se'::jsonb)->'items') x where x->>'key' = 'cesantia'), '19.50|97500.00', 'severance: 19,5 days at 5 000');
select test.eq((select x->>'days' || '|' || (x->>'amount_crc') from jsonb_array_elements((:'se'::jsonb)->'items') x where x->>'key' = 'vacaciones'), '13.00|65000.00', 'unused vacations are paid');
select test.eq(((:'se'::jsonb)->>'total_crc')::numeric, (select sum((x->>'amount_crc')::numeric) from jsonb_array_elements((:'se'::jsonb)->'items') x where (x->>'applies')::boolean), 'the total adds the items that apply');
select test.eq((:'se'::jsonb)->>'confirmed', 'false', 'the severance table is still the law as written, not confirmed');
select public.severance_estimate(test.staff('ana'), public.cr_today(), 'renuncia') as se2 \gset
select test.eq((select x->>'applies' || '|' || (x->>'days') from jsonb_array_elements((:'se2'::jsonb)->'items') x where x->>'key' = 'cesantia'), 'false|0', 'a resignation: no severance');
select test.eq((select x->>'applies' from jsonb_array_elements((:'se2'::jsonb)->'items') x where x->>'key' = 'aguinaldo'), 'true', 'the aguinaldo is always owed');
select test.eq(public.severance_estimate(test.staff('ana'), public.cr_today(), 'otro')->>'error', 'bad_value', 'one of the four reasons');
select public.severance_estimate(test.staff('marta'), public.cr_today() + 400, 'despido_sin_causa') as se3 \gset
select test.eq((select x->>'amount_crc' is null from jsonb_array_elements((:'se3'::jsonb)->'items') x where x->>'key' = 'cesantia'), true, 'no posted payroll in the six months before that date: the severance amount is blank');
select test.eq((:'se3'::jsonb)->>'total_crc', null::text, 'and so is the total, never a misleading number');
-- exactly one year of service: fifteen days of notice (art. 28: "up to a year"), the table of art. 29 from a year on
select public.severance_estimate(test.staff('ana'), (public.cr_today() - 400 + interval '1 year')::date, 'despido_sin_causa') as se4 \gset
select test.eq((:'se4'::jsonb)->>'months', '12', 'twelve months to the day');
select test.eq((select x->>'days' from jsonb_array_elements((:'se4'::jsonb)->'items') x where x->>'key' = 'preaviso'), '15', 'notice at exactly one year: fifteen days, not a month');
select test.eq((select x->>'days' from jsonb_array_elements((:'se4'::jsonb)->'items') x where x->>'key' = 'cesantia'), '19.50', 'severance at exactly one year: the first year of the table');
-- the CCSS minimum contribution base (a monthly amount): saved with its confirmation, applied to the payrolls prepared from then on
select test.eq(public.payroll_param_save('ccss', '{"min_base_crc": "NaN"}', 'Contadora', 'prueba')->>'error', 'bad_value', 'a real amount');
select test.eq(public.payroll_param_save('ccss', '{"min_base_crc": 200000}', 'Contadora M. Rojas', 'CCSS base mínima 2026 (prueba)')->>'ok', 'true', 'the base is saved with its confirmation');
select test.eq(public.pay_period_save(public.cr_today() - 6, public.cr_today() - 1)->>'ok', 'true', 'a second period');
reset role;
insert into public.time_entries (staff_id, clock_in, clock_out) values (test.staff('luis'), public.cr_day_start(public.cr_today() - 4) + interval '8 hours', public.cr_day_start(public.cr_today() - 4) + interval '12 hours');
select id as period2 from public.pay_periods where starts_on = public.cr_today() - 6 \gset
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.timesheet_approve(:'period2')->>'ok', 'true', 'approved');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select public.payroll_prepare(:'period2') as pr2 \gset
select (:'pr2'::jsonb)->>'run_id' as run2 \gset
reset role;
-- Luis: 4 h × 2 000 = 8 000 in a 6-day period; the base taken to 6 days is 40 000. The worker's quota stays on his pay (10,5 % of 8 000 = 840);
-- the business pays its own 26,33 % on 40 000 = 10 532, the INS 1,5 % on 8 000 = 120, and the worker's quota on the difference, 10,5 % of 32 000 = 3 360
select test.eq((select deductions_crc || '|' || employer_crc || '|' || (select bool_or((e->>'floor')::boolean) from jsonb_array_elements(deductions) e)
                  from public.payroll_lines where run_id = :'run2' and staff_id = test.staff('luis')), '840.00|14012.00|false', 'the worker is deducted on his pay; the business carries the base; the deduction is not the floored one');
select test.eq((select e->>'amount' || '|' || (e->>'base') || '|' || (e->>'diff') || '|' || (e->>'floor') from public.payroll_lines, jsonb_array_elements(employer) e
                  where run_id = :'run2' and staff_id = test.staff('luis') and (e->>'absorbed')::boolean), '3360.00|40000.00|32000.00|true', 'the quota the business assumes: its own entry, flagged, with the base and the difference');
select test.eq((select count(*) from public.payroll_lines, jsonb_array_elements(employer) e where run_id = :'run2' and staff_id = test.staff('ana') and (e->>'absorbed')::boolean), 0::bigint, 'Ana is above the base: nothing assumed');
select test.eq((select renta_crc from public.payroll_lines where run_id = :'run2' and staff_id = test.staff('luis')), 0::numeric, 'no income tax on 8 000');
-- an empty parameter is refused; 0 is written on purpose and means "no minimum base"
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_param_save('ccss', '{}', 'Contadora', 'prueba')->>'error', 'bad_value', 'the amount must be written');
select test.eq(public.payroll_param_save('ccss', '{"min_base_crc": 0}', 'Contadora M. Rojas', 'sin base (prueba)')->>'ok', 'true', '0 is accepted: no minimum base');
reset role;
select test.eq((public._payroll_params_now()->>'ccss_min_base') is null, true, 'a base of 0 is no base');
-- a base far above the pay (a few hours in the period): the review names the cause, not just a negative net
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_param_save('ccss', '{"min_base_crc": 1000000, "worker_share": "otro"}', 'Contadora M. Rojas', 'prueba')->>'error', 'bad_value', 'the worker''s share is one of the two');
select test.eq(public.payroll_param_save('ccss', '{"min_base_crc": 1000000, "worker_share": "on_base"}', 'Contadora M. Rojas', 'CCSS base mínima 2026 (prueba)')->>'ok', 'true', 'a base of a million, the worker''s quota on the base');
select test.eq(public.payroll_review(:'run2')->>'error', 'prepare_again', 'the parameter changed after the draft: it is prepared again first');
select test.eq(public.payroll_prepare(:'period2')->>'ok', 'true', 'prepared again');
reset role;
select test.eq((select deductions_crc || '|' || (select bool_or((e->>'floor')::boolean) from jsonb_array_elements(deductions) e) from public.payroll_lines where run_id = :'run2' and staff_id = test.staff('luis')),
               '21000.00|true', 'on the base: 10,5 % of 200 000, the deduction flagged');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.payroll_review(:'run2')->>'error', 'floor_over_pay', 'Luis: 21 000 is more than his 8 000: the review says why');
select test.eq(public.payroll_param_save('ccss', '{"min_base_crc": 200000}', 'Contadora M. Rojas', 'CCSS base mínima 2026 (prueba)')->>'ok', 'true', 'back to 200 000');
select test.eq(public.payroll_prepare(:'period2')->>'ok', 'true', 'prepared again');
reset role;
select test.eq((select deductions_crc from public.payroll_lines where run_id = :'run2' and staff_id = test.staff('luis')), 840.00, 'and the line is as before');
select test.login('accountant', 'aal2'); set role authenticated;
-- payroll_staff carries the state the page needs
select public.payroll_staff() as st \gset
select test.eq(((:'st'::jsonb)->'cr'->>'confirmed') || '|' || ((:'st'::jsonb)->'cr'->>'renta_withhold') || '|' || ((:'st'::jsonb)->'cr'->>'accrue_aguinaldo'), 'true|true|true', 'the Costa Rican rules: confirmed and on');
select test.eq((select x->'profile'->>'id_number' from jsonb_array_elements((:'st'::jsonb)->'staff') x where x->>'name' = 'Ana'), '1-1234-5678', 'the profile travels with the staff list');
select test.eq((:'st'::jsonb)->'params'->'renta'->>'confirmed_by', 'Contadora M. Rojas', 'and the parameters with who confirmed them');
reset role;
select test.done();
rollback;
