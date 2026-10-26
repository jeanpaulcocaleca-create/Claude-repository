-- supabase/tools/reversion-0033.sql: undoes migration 0033 and leaves every changed function exactly as it was (the
-- production snapshot's fingerprints), keeps every record, and the café keeps working; 0033 can then be applied again.
begin;
-- state made under 0033: an unlock bound to its sign-in, a logged lock, a logged clash
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.clock_punch(test.staff('luis'), '1111') from generate_series(1, 5);
select test.eq(public.manager_save_staff(null, null, null, 'Nuevo', '5284', true, 'staff')->>'error', 'pin_in_use', 'a clash under 0033');
reset role;

\o /dev/null
\ir ../../supabase/tools/reversion-0035.sql
\ir ../../supabase/tools/reversion-0034.sql
\ir ../../supabase/tools/reversion-0033.sql
\o
select test.eq(public.canopy_schema_version(), 32, 'the database is back at version 32 (0035 and 0034 reverted first: each reversal refuses while a later migration is applied)');
select test.ok(to_regprocedure('public.pin_lock_clear(uuid, uuid, text)') is null and to_regprocedure('public.access_lock_all()') is null
               and to_regprocedure('public._jwt_session()') is null, 'the new functions are gone');
select test.eq((select string_agg(left(md5(p.prosrc), 12), ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace
                   and p.proname in ('_verify_pin', 'manager_save_staff', '_unlocked_any_device', 'access_unlock', 'access_lock', '_unlock_staff')),
               '0c5f7a2270ad a5ce5063025f cd39715d9ad6 d20cb1e7c9e4 6f10dd3d34f0 1d935764616d',   -- _unlock_staff, _unlocked_any_device, _verify_pin, access_lock, access_unlock, manager_save_staff
               'every function is byte for byte the one production has before 0033');
select test.ok(exists (select 1 from information_schema.columns where table_name = 'access_unlocks' and column_name = 'session_id'),
               'the new column stays (unused)');
select test.ok(exists (select 1 from public.audit_log where action = 'pin_locked') and exists (select 1 from public.audit_log where action = 'pin_in_use'),
               'nothing written under 0033 is removed');
select test.eq((select count(*)::int from public.access_unlocks), 1, 'nor the open unlock');
-- the café keeps working on the reverted database
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.access_level(), 'manager', 'a manager PIN opens the owner areas');
select test.eq(public.clock_punch(test.staff('marta'), '6173')->>'ok', 'true', 'the clock punches');
select test.eq(public.manager_save_staff(null, null, null, 'Otro', '8264', true, 'staff')->>'ok', 'true', 'the team editor saves');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('luis')), 5, 'Luis''s lock from before stays as it was');

-- 0033 can be applied again
\o /dev/null
\ir ../../supabase/migrations/0033_pines_seguros.sql
\o
select test.eq(public.canopy_schema_version(), 33, 'applied again: version 33');
select test.ok(to_regprocedure('public.pin_lock_clear(uuid, uuid, text)') is not null, 'with its functions');
select test.done();
rollback;
