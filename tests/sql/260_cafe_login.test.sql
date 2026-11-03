-- The café-login tool (supabase/tools/cafe-login.sql): as shipped it stops until the email is written; part 1 turns
-- one login into a café login (and refuses what it must), part 2 takes an owner grant away; the café login keeps
-- the POS and the time clock and needs a PIN for the owner areas.
begin;
-- logins for this test (the seed has cafe@, owner@ and contador@test.local)
insert into auth.users (id, email, created_at) values
  ('b2600000-0000-4000-8000-000000000001', 'Tablet.Cafe@Example.com', '2026-09-20 12:00+00'),   -- the café devices' login, of kind owner today
  ('b2600000-0000-4000-8000-000000000002', 'personal@example.com', '2026-08-25 12:00+00'),      -- someone's own login, with a phone code
  ('b2600000-0000-4000-8000-000000000003', 'jh.nadie@example.com', '2026-09-21 12:00+00'),      -- an owner grant nobody uses
  ('b2600000-0000-4000-8000-000000000004', 'nueva.tablet@example.com', '2026-10-13 12:00+00'),  -- a new login, no kind yet
  ('b2600000-0000-4000-8000-000000000005', 'solo@example.com', '2026-08-26 12:00+00'),
  ('b2600000-0000-4000-8000-000000000006', 'Ta+Cafe@example.com', '2026-10-13 12:00+00');       -- a new café login with a +label
insert into public.app_accounts (user_id, kind, label) values
  ('b2600000-0000-4000-8000-000000000001', 'owner', 'tablet.cafe@example.com'),
  ('b2600000-0000-4000-8000-000000000002', 'owner', 'personal@example.com'),
  ('b2600000-0000-4000-8000-000000000003', 'owner', 'jh.nadie@example.com'),
  ('b2600000-0000-4000-8000-000000000005', 'owner', 'solo@example.com');
insert into auth.mfa_factors (user_id, status, factor_type) values
  ('b2600000-0000-4000-8000-000000000002', 'verified', 'totp'),
  ('b2600000-0000-4000-8000-000000000001', 'unverified', 'totp');   -- started, never confirmed: does not count

-- why: an owner-kind login becomes the owner, without any PIN, as soon as a phone code is typed on it
select test.login('b2600000-0000-4000-8000-000000000001', 'aal2');
set role authenticated;
select test.ok(public.is_owner(), 'before: the café devices'' owner-kind login with a phone code is the owner without a PIN');
reset role;

-- the file as shipped: defines both steps, then stops at the example address
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\ir ../../supabase/tools/cafe-login.sql
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
select test.ok(:'LAST_ERROR_MESSAGE' ~ '^Falta el correo', 'the file as shipped stops until the email is written');

-- part 1 refuses, and changes nothing
select test.throws($$select pg_temp.canopy_cafe_login('correo@ejemplo.com', 'AAAA-MM-DD')$$, '^Falta el correo', 'part 1: the example address is refused');
select test.throws($$select pg_temp.canopy_cafe_login('  ', '2026-09-20')$$, '^Falta el correo', 'part 1: an empty address is refused');
select test.throws($$select pg_temp.canopy_cafe_login('nadie@example.com', '2026-09-20')$$, 'ningún ingreso con el correo na\*\*\*@example\.com',
                   'part 1: an email without a login is refused (shown masked)');
select test.throws($$select pg_temp.canopy_cafe_login('personal@example.com', '2026-08-25')$$, 'pe\*\*\*@example\.com \(creado 2026-08-25\) tiene el código del teléfono',
                   'part 1: a login with a verified phone code is refused');
select test.throws($$select pg_temp.canopy_cafe_login('contador@test.local', (select left(to_jsonb(u) ->> 'created_at', 10) from auth.users u where u.email = 'contador@test.local'))$$, 'ingreso del contador', 'part 1: the accountant login is refused');
select test.eq((select string_agg(a.kind, ',' order by u.id) from public.app_accounts a join auth.users u on u.id = a.user_id
                 where u.id::text like 'b2600000%' or u.email = 'contador@test.local'),
               'accountant,owner,owner,owner,owner', 'the refusals changed no login');
select test.eq((select count(*)::int from public.audit_log where action in ('login_kind_change', 'login_access_revoked')), 0,
               'the refusals logged nothing');

-- part 1: the café devices' login (case and spaces do not matter)
-- the follow-up's creation date is required, and must be the login's own: two masked emails can look the same
select test.throws($$select pg_temp.canopy_cafe_login('tablet.cafe@example.com', 'AAAA-MM-DD')$$, '^Falta la fecha', 'part 1: the date placeholder is refused');
select test.throws($$select pg_temp.canopy_cafe_login('tablet.cafe@example.com', '')$$, '^Falta la fecha', 'part 1: a missing date is refused');
select test.throws($$select pg_temp.canopy_cafe_login('tablet.cafe@example.com', '2026-08-25')$$,
                   'ta\*\*\*@example\.com \(creado 2026-09-20\) no es el ingreso creado el 2026-08-25', 'part 1: another login''s date is refused');
select test.throws($$select pg_temp.canopy_revoke_login('jh.nadie@example.com', '2026-09-20')$$, 'no es el ingreso creado el 2026-09-20', 'part 2: another login''s date is refused');
select test.eq((select string_agg(kind, ',' order by user_id) from public.app_accounts where user_id in
                  ('b2600000-0000-4000-8000-000000000001', 'b2600000-0000-4000-8000-000000000003')), 'owner,owner', 'a refused date changes nothing');
select test.eq(pg_temp.canopy_cafe_login(' Tablet.Cafe@example.COM ', ' 2026-09-20 '), 'ta***@example.com (creado 2026-09-20) → cafe', 'part 1: masked confirmation, with the creation date');
select test.eq((select kind from public.app_accounts where user_id = 'b2600000-0000-4000-8000-000000000001'), 'cafe', 'part 1: the login is now a café login');
select test.eq((select manager_name || ' · ' || target_id || ' · ' || (details ->> 'old_kind') || ' → ' || (details ->> 'new_kind')
                  from public.audit_log where action = 'login_kind_change'),
               'SQL Editor · b2600000-0000-4000-8000-000000000001 · owner → cafe', 'part 1: one line in the approvals log, old and new kind');
select test.eq(pg_temp.canopy_cafe_login('tablet.cafe@example.com', '2026-09-20'), 'ta***@example.com (creado 2026-09-20) ya era del café: no se cambió nada', 'part 1 again: nothing to do');
select test.eq((select count(*)::int from public.audit_log where action = 'login_kind_change'), 1, 'part 1 again: nothing logged');
-- a new login without a kind yet gets its café row (so the POS takes sales from its first sign-in)
select test.eq(pg_temp.canopy_cafe_login('nueva.tablet@example.com', '2026-10-13'), 'nu***@example.com (creado 2026-10-13) → cafe', 'part 1: a new login becomes a café login');
select test.eq(pg_temp.canopy_cafe_login('ta+cafe@example.com', '2026-10-13'), 'ta***+cafe@example.com (creado 2026-10-13) → cafe',
               'part 1: a +label stays visible, so a new café login is not taken for the personal one');
select test.ok((select details ? 'old_kind' and details ->> 'old_kind' is null from public.audit_log
                 where action = 'login_kind_change' and target_id = 'b2600000-0000-4000-8000-000000000004'), 'part 1: logged with no previous kind');

-- the café login afterwards: POS, kitchen and time clock as before; the owner areas only with a PIN
select test.login('b2600000-0000-4000-8000-000000000001');
set role authenticated;
select test.ok(public.is_cafe(), 'café login: still reaches the POS, kitchen screen and time clock');
select test.eq(public.account_kind(), 'cafe', 'café login: its kind');
select test.ok(not public.is_owner() and not public.sales_open(), 'café login: no owner areas and no sales without a PIN');
select test.eq((select count(*)::int from public.audit_log), 0, 'café login: the approvals log stays closed without a PIN');
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'manager') ->> 'error', 'owner_only',
               'café login: the team cannot be changed without a PIN');
select test.login('b2600000-0000-4000-8000-000000000001', 'aal2');
select test.ok(not public.is_owner() and not public.owner_with_code(), 'café login: a phone code never makes it the owner');
select test.login('b2600000-0000-4000-8000-000000000001');
select test.unlock(test.staff('ana'), '4826');
select test.ok(public.is_owner(), 'café login: a manager PIN still opens the owner areas');
-- the first-owner exception: with no active owner in the team, a manager PIN on an owner-kind login may make one
reset role;
update public.staff set active = false where id = test.staff('dueno');
set role authenticated;
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'owner') ->> 'error', 'owner_role_only',
               'café login: a manager PIN cannot make the first owner');
select test.login('b2600000-0000-4000-8000-000000000003');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'owner') ->> 'error', 'owner_role_only',
               'an owner-kind login without a code cannot either (closed by 0028, D-037): the owner role needs the phone code');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.manager_save_staff(null, null, test.staff('luis'), 'Luis', null, true, 'owner') ->> 'ok', 'true', 'the owner with the phone code gives the owner role');
reset role;
update public.staff set active = true, role = 'staff' where id in (test.staff('dueno'), test.staff('luis'));
update public.staff set role = 'owner' where id = test.staff('dueno');

-- part 2 refuses, and changes nothing
select test.throws($$select pg_temp.canopy_revoke_login('correo@ejemplo.com', 'AAAA-MM-DD')$$, '^Falta el correo', 'part 2: the example address is refused');
select test.throws($$select pg_temp.canopy_revoke_login('nadie@example.com', '2026-09-21')$$, 'ningún ingreso con el correo', 'part 2: an email without a login is refused');
select test.throws($$select pg_temp.canopy_revoke_login('tablet.cafe@example.com', '2026-09-20')$$, 'no tiene acceso de dueño \(tipo: cafe\)',
                   'part 2: only an owner grant is taken away (never the café login)');
-- part 2: the grant nobody uses
select test.eq(pg_temp.canopy_revoke_login('JH.nadie@example.com', '2026-09-21'), 'jh***@example.com (creado 2026-09-21) → sin acceso de dueño', 'part 2: masked confirmation');
select test.ok(not exists (select 1 from public.app_accounts where user_id = 'b2600000-0000-4000-8000-000000000003'), 'part 2: the grant is gone');
select test.ok(exists (select 1 from auth.users where id = 'b2600000-0000-4000-8000-000000000003' and email = 'jh.nadie@example.com'),
               'part 2: the login itself is not touched');
select test.eq((select manager_name || ' · ' || target_id || ' · ' || (details ->> 'old_kind') from public.audit_log where action = 'login_access_revoked'),
               'SQL Editor · b2600000-0000-4000-8000-000000000003 · owner', 'part 2: one line in the approvals log');
select test.login('b2600000-0000-4000-8000-000000000003', 'aal2');
set role authenticated;
select test.ok(not public.is_cafe() and not public.is_owner() and not public.owner_with_code(),
               'part 2: the login opens nothing any more, not even with a phone code');
reset role;

-- the last owner login stays (a grant whose login no longer exists does not count)
update public.app_accounts set kind = 'cafe' where kind = 'owner' and user_id <> 'b2600000-0000-4000-8000-000000000005';
insert into public.app_accounts (user_id, kind, label) values ('b2600000-0000-4000-8000-0000000000ff', 'owner', 'borrado@example.com');
select test.throws($$select pg_temp.canopy_cafe_login('solo@example.com', '2026-08-26')$$, 'ningún otro ingreso de tipo dueño', 'part 1 never leaves no owner login');
select test.throws($$select pg_temp.canopy_revoke_login('solo@example.com', '2026-08-26')$$, 'último ingreso de tipo dueño', 'part 2 never removes the last owner login');
select test.eq((select kind from public.app_accounts where user_id = 'b2600000-0000-4000-8000-000000000005'), 'owner', 'the last owner login is unchanged');
select test.eq((select string_agg(action, ',' order by id) from public.audit_log where action in ('login_kind_change', 'login_access_revoked')),
               'login_kind_change,login_kind_change,login_kind_change,login_access_revoked', 'only the four changes were logged');
select test.done();
rollback;
