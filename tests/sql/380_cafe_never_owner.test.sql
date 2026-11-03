-- The café login never inherits the owner's rights (D-052): not by itself, not with a phone code, not with an unlock
-- another login left on the same device, and not with a PIN. A manager PIN gives the manager level for 15 minutes;
-- even an owner-role PIN never opens the books, the bank, the settings or the accountant (those need the owner's own
-- login with its phone code).
begin;

-- 1) the café login by itself
select test.login('cafe'); set role authenticated;
select test.eq(public.account_kind(), 'cafe', 'café login: its kind');
select test.ok(public.access_level() is null, 'café login: no owner or manager level without a PIN');
select test.ok(not public.is_owner() and not public.is_true_owner() and not public.owner_with_code(), 'café login: nothing of the owner');
select test.ok(not public.sales_open() and not acct.can_read(), 'café login: no sales numbers and no books');
reset role;
select test.login('cafe', 'aal2'); set role authenticated;
select test.ok(public.access_level() is null and not public.owner_with_code() and not acct.can_read(),
               'café login with a phone code: still nothing of the owner');
reset role;

-- 2) an unlock left on the device by another login is worth nothing to the café login
select test.login('owner'); set role authenticated;
select set_config('test.h_owner', test.unlock(test.staff('ana'), '4826')::text, false);
select test.eq(public.access_level(), 'manager', 'the owner''s login: Ana''s PIN opens the manager level on its own login');
reset role;
select test.login('cafe', 'aal1', current_setting('test.h_owner')::jsonb); set role authenticated;
select test.ok(public.access_level() is null and not public.is_owner(), 'café login: the other login''s unlock opens nothing');
select test.ok((public.access_state()->>'level') is null and (public.access_state()->>'name') is null,
               'café login: the page is told nothing is open, and no name to show');
reset role;
select test.login('cafe'); set role authenticated;
select set_config('test.h_cafe', test.unlock(test.staff('ana'), '4826')::text, false);
reset role;
select test.login('owner', 'aal1', current_setting('test.h_cafe')::jsonb); set role authenticated;
select test.ok(public.access_level() is null, 'and the other way round: the café''s unlock opens nothing on the owner''s login');
reset role;

-- 3) the café login with a manager PIN: the manager level, nothing of the owner
select test.login('cafe', 'aal1', current_setting('test.h_cafe')::jsonb); set role authenticated;
select test.eq(public.access_level(), 'manager', 'café + manager PIN: the manager level');
select test.ok(not public.is_true_owner() and not public.owner_with_code() and not acct.can_read(), 'café + manager PIN: not the owner');
select test.eq(public.acct_overview()->>'error', 'not_allowed', 'café + manager PIN: the books stay closed');
select test.eq(public.bank_overview(null, null, null)->>'error', 'not_allowed', 'café + manager PIN: the bank stays closed');
select test.eq(public.setting_set('operator_mode', '"record"')->>'error', 'owner_only', 'café + manager PIN: no settings');
select test.eq(public.accountant_grant('x@example.com')->>'error', 'owner_only', 'café + manager PIN: no accountant access');
select test.eq(public.owner_set_sales_access(test.staff('luis'), true)->>'error', 'owner_role_only', 'café + manager PIN: cannot open the sales to anyone');
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'owner')->>'error', 'owner_role_only',
               'café + manager PIN: cannot make anyone an owner');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'access_open' and manager_name = 'Ana'
                         and details->>'account' = 'cafe' and target_id = 'c0000000-0000-4000-8000-000000000001'),
               'the opening is in the log: who (Ana), on which login (the café''s), as a café login');

-- 4) the café login with an owner-role PIN: the owner areas of the tablet, never the owner's own rights
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('dueno'), '7391');
select test.eq(public.access_level(), 'owner', 'café + owner-role PIN: the owner areas of the tablet are open (D-022), so the checks below mean something');
select test.ok(not public.owner_with_code() and not acct.can_read(), 'café + owner-role PIN: never the owner with the phone code');
select test.eq(public.acct_overview()->>'error', 'not_allowed', 'café + owner-role PIN: the books stay closed');
select test.eq(public.bank_overview(null, null, null)->>'error', 'not_allowed', 'café + owner-role PIN: the bank stays closed');
select test.eq(public.payroll_staff()->>'error', 'not_allowed', 'café + owner-role PIN: pay rates stay closed');
select test.eq(public.setting_set('operator_mode', '"record"')->>'error', 'owner_only', 'café + owner-role PIN: no settings');
select test.eq(public.tax_rate_save('IVA0', 'cero', 0, 'x', 'y')->>'error', 'owner_only', 'café + owner-role PIN: no tax rates');
select test.eq(public.accountant_grant('x@example.com')->>'error', 'owner_only', 'café + owner-role PIN: no accountant access');
-- 5) Lock closes it again on this device
select public.access_lock();
select test.ok(public.access_level() is null and not public.is_owner(), 'after Lock: nothing open on the café login');
reset role;

select test.done();
rollback;
