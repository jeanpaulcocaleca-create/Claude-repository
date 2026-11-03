-- Migration 0033 (D-053): no PIN can be found out with the team editor, wrong-PIN locks cannot be abused, and each
-- unlock of the owner areas only works for the sign-in (session) that made it, for menu photos too.
begin;
-- a second manager, so "only an owner changes another manager" can be tried
insert into public.staff (id, name, role, active, pin_hash) values
  ('b3900000-0000-4000-8000-000000000001', 'Bea', 'manager', true, extensions.crypt('3917', extensions.gen_salt('bf')));
create temp table q (k text primary key, v text);
grant all on q to authenticated;

-- 1) the team editor answers every other refusal first: whether a PIN is free never leaks through them ---------------
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.manager_save_staff(null, null, gen_random_uuid(), 'x', '5284', true, 'staff')->>'error', 'not_found',
               'a made-up person with a PIN in use: not_found, not pin_in_use');
select test.eq(public.manager_save_staff(null, null, gen_random_uuid(), 'x', '8264', true, 'staff')->>'error', 'not_found',
               'and the same answer with a free PIN');
select test.eq(public.manager_save_staff(null, null, null, 'x', '7391', true, 'owner')->>'error', 'owner_role_only',
               'asking for the owner role with a PIN in use: owner_role_only');
select test.eq(public.manager_save_staff(null, null, null, 'x', '8264', true, 'owner')->>'error', 'owner_role_only',
               'and the same with a free PIN');
select test.eq(public.manager_save_staff(null, null, test.staff('dueno'), 'Dueño', '5284', true, 'owner')->>'error', 'owner_role_only',
               'the owner''s record without the phone code: owner_role_only, whatever the PIN');
select test.eq(public.manager_save_staff(null, null, 'b3900000-0000-4000-8000-000000000001', 'Bea', '5284', true, 'manager')->>'error',
               'manager_needs_owner', 'another manager''s record: manager_needs_owner with a PIN in use');
select test.eq(public.manager_save_staff(null, null, 'b3900000-0000-4000-8000-000000000001', 'Bea', '8264', true, 'manager')->>'error',
               'manager_needs_owner', 'and with a free PIN');
reset role;
update public.staff set role = 'staff' where id = 'b3900000-0000-4000-8000-000000000001';   -- Ana, for a moment the only manager
update public.staff set active = false where id = test.staff('dueno');
set role authenticated;
select test.eq(public.manager_save_staff(null, null, test.staff('ana'), 'Ana', '5284', true, 'staff')->>'error', 'last_manager',
               'the last manager made staff, with a PIN in use: last_manager');
select test.eq(public.manager_save_staff(null, null, test.staff('ana'), 'Ana', '8264', true, 'staff')->>'error', 'last_manager',
               'and with a free PIN');
reset role;
update public.staff set role = 'manager' where id = 'b3900000-0000-4000-8000-000000000001';
update public.staff set active = true where id = test.staff('dueno');
set role authenticated;
reset role;
select test.eq((select count(*)::int from public.audit_log where action in ('pin_in_use', 'staff_save')), 0,
               'none of those refusals wrote anything or counted toward the limit');
set role authenticated;
-- a real clash is still told, once every other check passed, and logged
select test.eq(public.manager_save_staff(null, null, null, 'Nuevo', '5284', true, 'staff')->>'error', 'pin_in_use',
               'a new person with Luis''s PIN: pin_in_use (two people never share a PIN)');
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', '5284', true, 'staff')->>'ok', 'true',
               'Luis may keep his own PIN');
select test.eq(public.manager_save_staff(null, null, null, 'Nuevo', '8264', true, 'staff')->>'ok', 'true', 'a free PIN is saved');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'pin_in_use' and manager_name = 'Ana (manager)'
                         and details->>'by_login' = 'c0000000-0000-4000-8000-000000000001' and details->>'account' = 'cafe'),
               'the clash is in the log: who tried it and from which login');
-- at most 10 PINs an hour per login (set or in use), and then nothing about any PIN is told
insert into public.audit_log (action, manager_name, target_id, summary, details)
  select 'pin_in_use', 'Ana', '', 'test', jsonb_build_object('by_login', 'c0000000-0000-4000-8000-000000000001')
    from generate_series(1, 7);
set role authenticated;
select test.eq(public.manager_save_staff(null, null, null, 'Otro', '5284', true, 'staff')->>'error', 'pin_tries',
               'the 11th PIN in an hour: pin_tries, even for a PIN in use');
select test.eq(public.manager_save_staff(null, null, null, 'Otro', '9264', true, 'staff')->>'error', 'pin_tries',
               'and for a free one');
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis Q.', null, true, 'staff')->>'ok', 'true',
               'changes without a PIN still work');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.manager_save_staff(null, null, null, 'Otra', '9264', true, 'staff')->>'ok', 'true',
               'another login is not limited by the café''s tries');
reset role;
update public.audit_log set at = now() - interval '61 minutes' where details->>'by_login' = 'c0000000-0000-4000-8000-000000000001';
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.manager_save_staff(null, null, null, 'Otro', '9265', true, 'staff')->>'ok', 'true',
               'an hour later the limit is gone');
reset role;
with k as (select hashtextextended('canopy.staff_pin', 0) as k)
select test.ok(exists (select 1 from pg_locks, k where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1
                         and classid::bigint = (k.k >> 32) & 4294967295 and objid::bigint = k.k & 4294967295),
               'PIN saves wait for each other: requests sent together cannot all read the same count');
-- bringing someone back needs a new PIN: their old one may have gone to someone else meanwhile
set role authenticated;
select test.eq(public.manager_save_staff(null, null, test.staff('marta'), 'Marta', null, false, 'staff')->>'ok', 'true', 'Marta leaves');
select test.eq(public.manager_save_staff(null, null, null, 'Nueva', '6173', true, 'staff')->>'ok', 'true',
               'her PIN is free for a new person');
select test.eq(public.manager_save_staff(null, null, test.staff('marta'), 'Marta', null, true, 'staff')->>'error', 'missing_pin',
               'Marta back without a new PIN: missing_pin (before 0033 two active people shared 6173)');
select test.eq(public.manager_save_staff(null, null, test.staff('marta'), 'Marta', '6173', true, 'staff')->>'error', 'pin_in_use',
               'nor with her old one, now someone else''s');
select test.eq(public.manager_save_staff(null, null, test.staff('marta'), 'Marta', '7395', true, 'staff')->>'ok', 'true',
               'with a new PIN she is back');
reset role;
select test.eq((select count(*)::int from public.staff where active and pin_hash = extensions.crypt('6173', pin_hash)), 1,
               'one active person per PIN');

-- 2) wrong PINs: an empty PIN is no try; each lock is logged; after a lock one wrong try locks again, as before ------
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select test.eq(public.access_unlock(test.staff('ana'), '')->>'error', 'bad_pin', 'an empty PIN is refused');
select public.access_unlock(test.staff('ana'), '   '), public.access_unlock(test.staff('ana'), null),
       public.access_unlock(test.staff('ana'), ''), public.access_unlock(test.staff('ana'), ''), public.access_unlock(test.staff('ana'), '');
select test.eq(public.clock_punch(test.staff('luis'), '')->>'error', 'bad_pin', 'the clock refuses an empty PIN too');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 0, 'six empty PINs: no try counted, no lock');
select test.eq((select failed_pins from public.staff where id = test.staff('luis')), 0, 'nor at the clock');
set role authenticated;
select public.access_unlock(test.staff('ana'), '1111') from generate_series(1, 4);
select test.eq(public.access_unlock(test.staff('ana'), '1112')->>'error', 'bad_pin', 'the 5th wrong PIN');
select test.eq(public.access_unlock(test.staff('ana'), '4826')->>'error', 'locked', 'locks: even the right PIN waits (nothing to guess)');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'pin_locked' and manager_name = 'Ana'
                         and details->>'account' = 'cafe' and target_id = 'c0000000-0000-4000-8000-000000000001'),
               'the lock is in the log: whose PIN and from which login');
update public.staff set locked_until = now() - interval '1 second' where id = test.staff('ana');   -- the 10 minutes are over
set role authenticated;
select test.eq(public.access_unlock(test.staff('ana'), '1113')->>'error', 'bad_pin', 'after the lock: one mistake');
select test.eq(public.access_unlock(test.staff('ana'), '4826')->>'error', 'locked',
               'locks again, as before 0033 (two tries there would double how fast a PIN is guessed)');
reset role;
select test.eq((select count(*)::int from public.audit_log where action = 'pin_locked' and manager_name = 'Ana'), 2, 'both locks logged');
select test.eq((select string_agg(summary || ' | ' || (details->>'tries') || ' | ' || (details->>'relock'), ' / ' order by id)
                  from public.audit_log where action = 'pin_locked' and manager_name = 'Ana'),
               'PIN locked for 10 minutes after 5 wrong tries | 5 | false / PIN locked again for 10 minutes: a wrong try after the last lock ended | 6 | true',
               'each says how it happened: 5 tries, or one more after a lock ended');
update public.staff set locked_until = now() - interval '1 second' where id = test.staff('ana');
set role authenticated;
select test.eq(public.access_unlock(test.staff('ana'), '4826')->>'ok', 'true', 'the right PIN after the lock opens');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 0, 'and starts the count again');

-- 3) taking a lock off: another manager with their PIN, the owner with the phone code ---------------------------------
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select public.clock_punch(test.staff('luis'), '1111') from generate_series(1, 5);
select test.eq(public.clock_punch(test.staff('luis'), '5284')->>'error', 'locked', 'Luis is locked at the clock');
reset role;
select test.login('cafe'); select test.session('tablet-b'); set role authenticated;
select test.eq(public.pin_lock_clear(test.staff('luis'))->>'error', 'owner_only', 'a tablet without the owner areas open cannot');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.pin_lock_clear(test.staff('marta'))->>'error', 'not_locked', 'someone not locked: not_locked');
select test.eq(public.pin_lock_clear(test.staff('luis'))->>'error', 'unknown_staff', 'the open areas are not enough: it asks for a manager PIN');
select test.eq(public.pin_lock_clear(test.staff('luis'), test.staff('ana'), '9999')->>'error', 'bad_pin', 'a wrong manager PIN');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 1, 'counts against that manager');
set role authenticated;
select test.eq(public.pin_lock_clear(test.staff('luis'), test.staff('ana'), '4826')->>'ok', 'true', 'Ana takes Luis''s lock off with her PIN');
select test.eq(public.clock_punch(test.staff('luis'), '5284')->>'ok', 'true', 'Luis clocks in');
reset role;
select test.ok(exists (select 1 from public.audit_log where action = 'pin_lock_cleared' and manager_name = 'Ana'
                         and target_id = test.staff('luis')::text and details->>'staff_name' = 'Luis Q.'),
               'logged: who took whose lock off');
-- twice a day per person at most, without the owner's code
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select public.clock_punch(test.staff('luis'), '1111') from generate_series(1, 5);
reset role;
select test.login('cafe'); select test.session('tablet-b'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.pin_lock_clear(test.staff('luis'), test.staff('ana'), '4826')->>'ok', 'true', 'a second time the same day');
select public.clock_punch(test.staff('luis'), '1111') from generate_series(1, 5);
select test.eq(public.pin_lock_clear(test.staff('luis'), test.staff('ana'), '4826')->>'error', 'clear_limit', 'a third time: clear_limit');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.pin_lock_clear(test.staff('luis'))->>'ok', 'true', 'the owner with the phone code can, without another PIN');
reset role;
-- nobody takes off their own lock; an owner's lock needs the owner's code
select test.login('cafe'); select test.session('tablet-b'); set role authenticated;
select test.unlock(test.staff('dueno'), '7391');
select public.access_unlock(test.staff('ana'), '1111') from generate_series(1, 5);
select test.eq(public.pin_lock_clear(test.staff('ana'), test.staff('ana'), '4826')->>'error', 'not_self', 'not with one''s own PIN');
select test.eq(public.pin_lock_clear(test.staff('ana'), test.staff('dueno'), '7391')->>'ok', 'true', 'the owner-role PIN takes a manager''s lock off');
select public.access_unlock(test.staff('dueno'), '1111') from generate_series(1, 5);
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.pin_lock_clear(test.staff('dueno'), test.staff('ana'), '4826')->>'error', 'owner_lock_needs_code',
               'an owner''s lock: only the owner with the phone code');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.pin_lock_clear(test.staff('dueno'))->>'ok', 'true', 'the owner with the phone code takes it off');
reset role;
update public.staff set failed_pins = 0, locked_until = null;

-- 4) each unlock belongs to its sign-in --------------------------------------------------------------------------------
delete from public.access_unlocks;   -- a clean start: no unlock open on any tablet
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
insert into q values ('ha', test.unlock(test.staff('ana'), '4826')::text);
select test.eq(public.access_level(), 'manager', 'tablet A, its token, its sign-in: the manager level');
reset role;
select test.eq((select session_id from public.access_unlocks order by created_at desc limit 1), 'tablet-a', 'the unlock names its sign-in');
select test.login('cafe', 'aal1', (select v::jsonb from q where k = 'ha')); select test.session('tablet-b'); set role authenticated;
select test.ok(public.access_level() is null, 'the same token on another sign-in of the café login (copied, or a second tablet): nothing');
reset role;
select test.login('cafe', 'aal1', (select v::jsonb from q where k = 'ha')); set role authenticated;
select test.ok(public.access_level() is null, 'and nothing on a token without a sign-in (fails closed)');
reset role;
select test.login('cafe', 'aal1', (select v::jsonb from q where k = 'ha')); select test.session('tablet-a'); set role authenticated;
select test.eq(public.access_level(), 'manager', 'tablet A after its token refreshed (same sign-in): still open');
reset role;
-- menu photos: Storage never receives the device token, only the sign-in
select test.login('owner', 'aal2'); set role authenticated;
select test.lives($$insert into storage.objects (bucket_id, name) values ('menu-photos', 'm-390.jpg')$$, 'the owner with the code puts a photo');
reset role;
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select test.lives($$insert into storage.objects (bucket_id, name) values ('menu-photos', 'a-390.jpg')$$,
                  'tablet A, unlocked, no token on the photo request: uploads (as before)');
reset role;
select test.login('cafe'); select test.session('tablet-b'); set role authenticated;
select test.throws($$insert into storage.objects (bucket_id, name) values ('menu-photos', 'b-390.jpg')$$, 'row-level security',
                   'tablet B, same login, no PIN typed there: refused (before 0033 it was allowed)');
update storage.objects set metadata = '{"x":1}' where bucket_id = 'menu-photos' and name = 'm-390.jpg';
delete from storage.objects where bucket_id = 'menu-photos' and name = 'm-390.jpg';
select test.ok(not public._unlocked_any_device(), 'tablet B is not told that another tablet is open');
reset role;
select test.eq((select count(*)::int from storage.objects where bucket_id = 'menu-photos' and name = 'm-390.jpg' and metadata is null), 1,
               'and could neither change nor delete a photo');
select test.login('cafe'); select test.session('tablet-a2'); set role authenticated;
select test.throws($$insert into storage.objects (bucket_id, name) values ('menu-photos', 'a2-390.jpg')$$, 'row-level security',
                   'tablet A signed in again (a new sign-in): refused, although the unlock has not expired');
reset role;
update public.access_unlocks set session_id = null;   -- an unlock made before 0033
select test.login('cafe', 'aal1', (select v::jsonb from q where k = 'ha')); select test.session('tablet-b'); set role authenticated;
select test.eq(public.access_level(), 'manager', 'an unlock from before 0033 still opens with its token (at most 15 minutes)');
reset role;
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;   -- a photo request: no token
select test.throws($$insert into storage.objects (bucket_id, name) values ('menu-photos', 'old-390.jpg')$$, 'row-level security',
                   'but never photos, not even on its own tablet: the PIN is typed again');
reset role;
update public.access_unlocks set session_id = 'tablet-a';
-- Lock and signing out end it on the server, on this sign-in, with or without the token
select test.login('cafe'); select test.session('tablet-b'); set role authenticated;
select public.access_lock();
reset role;
select test.eq((select count(*)::int from public.access_unlocks), 1, 'tablet B''s Lock does not end tablet A''s unlock');
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select public.access_lock();
reset role;
select test.eq((select count(*)::int from public.access_unlocks), 0, 'tablet A''s Lock (or sign-out) ends it, even without the token');
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select test.throws($$insert into storage.objects (bucket_id, name) values ('menu-photos', 'a3-390.jpg')$$, 'row-level security',
                   'and photos close with it');
select test.unlock(test.staff('ana'), '4826');
reset role;
select test.login('cafe'); select test.session('tablet-b'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
reset role;
select test.login('owner'); select test.session('owner-phone'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.access_lock_all();
reset role;
select test.eq((select count(*)::int from public.access_unlocks where user_id = '0e000000-0000-4000-8000-000000000002'), 0,
               '«Sign out everywhere» ends every unlock of that login');
select test.eq((select count(*)::int from public.access_unlocks where user_id = 'c0000000-0000-4000-8000-000000000001'), 2,
               'and none of another login');
select test.login('cafe'); select test.session('tablet-a'); set role authenticated;
select public.access_lock_all();
reset role;
select test.eq((select count(*)::int from public.access_unlocks), 0, 'the café''s own one ends both tablets');
select test.ok((select details->>'session_bound' from public.audit_log where action = 'access_open' order by id desc limit 1) = 'true',
               'each opening says it is bound to its sign-in');

-- 5) rights ------------------------------------------------------------------------------------------------------------
select test.ok(has_function_privilege('authenticated', 'public.pin_lock_clear(uuid, uuid, text)', 'execute')
               and has_function_privilege('authenticated', 'public.access_lock_all()', 'execute'), 'the new actions are for signed-in devices');
select test.ok(not has_function_privilege('anon', 'public.pin_lock_clear(uuid, uuid, text)', 'execute')
               and not has_function_privilege('anon', 'public.access_lock_all()', 'execute'), 'never for visitors');
select test.ok(not has_function_privilege('authenticated', 'public._jwt_session()', 'execute')
               and not has_function_privilege('authenticated', 'public._unlock_staff()', 'execute'), 'helpers stay internal');

select test.done();
rollback;
