-- Migration 0007: no PIN check without a lockout.
begin;
select test.login('cafe'); set role authenticated;
select test.throws($$select * from public.hours_report('a1000000-0000-4000-8000-000000000002', '0000', now() - interval '7 days', now())$$,
                   'permission denied', 'hours_report can no longer be used to try PINs');
select test.eq(public.hours_for(test.staff('luis'), '0000', now() - interval '7 days', now())->>'error', 'bad_pin', 'hours_for refuses a wrong PIN');
select public.hours_for(test.staff('luis'), '0001', now() - interval '7 days', now());
select public.hours_for(test.staff('luis'), '0002', now() - interval '7 days', now());
select public.hours_for(test.staff('luis'), '0003', now() - interval '7 days', now());
select public.hours_for(test.staff('luis'), '0004', now() - interval '7 days', now());
select test.eq(public.hours_for(test.staff('luis'), '5284', now() - interval '7 days', now())->>'error', 'locked',
               'after 5 wrong PINs even the right one waits');
reset role;

-- every function that checks a PIN records the attempt (none is declared read-only)
select test.eq((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.provolatile <> 'v' and p.prosrc ~ '_verify_pin|crypt\('
                   and has_function_privilege('authenticated', p.oid, 'execute')), 0,
               'no read-only function that checks a PIN is open to the café login');
select test.done();
rollback;
