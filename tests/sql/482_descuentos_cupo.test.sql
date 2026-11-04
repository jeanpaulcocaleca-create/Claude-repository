-- Migration 0038 (D-065): the employee's daily discount (owner's adjustment 3, Q3's default W1, build plan L4).
-- One Empleado per employee and Costa Rica day. A valid sale consumes it. It comes back only through a valid void (a
-- manager who is not the beneficiary, no paid part left) or descuento_cupo_devolver (a manager's own PIN picked from
-- the list, never the beneficiary, or the owner with the phone code; audit discount_freed naming who). An approval never
-- used expires after 30 minutes or is let go by the page, without consuming the day. A sale queued on a let-go or
-- expired approval takes the day again, or is flagged discount_daily_twice and takes the day back as soon as the
-- approval holding it stops holding it (let go, expired, voided, given back). A removal or a cancel with nothing paid
-- keeps the day used until a give-back; with money paid it stays used for good; a refund changes nothing. Item 12: the
-- day's trigger never makes a kitchen update, an add, a payment, a void or a cancel fail. Everything goes through the
-- real functions as the café login on a registered till (proposal §2.5b-g, §2.7, §5.1 items 3 and 12; api-0038
-- §4.2-4.5, §5, §8; build plan L4).
begin;

-- people: the seed (Ana manager 4826, Luis 5284 and Marta 6173 staff, Dueño owner 7391) plus test-only staff, one
-- employee per case so no case shares a day with another. Test PINs only: Bea 3917, Gil 3918 (inactive), Hal 3919
-- (managers), the employees 8204-8235 by their place in the list
create table test.t482_people (name text primary key, id uuid not null, pin text not null);
grant select on test.t482_people to authenticated;
insert into test.t482_people values
  ('ana', test.staff('ana'), '4826'), ('luis', test.staff('luis'), '5284'), ('marta', test.staff('marta'), '6173'),
  ('dueno', test.staff('dueno'), '7391');
insert into test.t482_people (name, id, pin)
  select n, ('b4820000-0000-4000-8000-' || lpad(o::text, 12, '0'))::uuid,
         case n when 'bea' then '3917' when 'gil' then '3918' when 'hal' then '3919' else (8200 + o)::text end
    from unnest(array['bea', 'gil', 'hal', 'eva', 'fede', 'iris', 'hugo', 'kai', 'olga', 'tomas', 'raul', 'sara', 'uma',
                      'pablo', 'quim', 'walter', 'ximena', 'yago', 'nora', 'omar', 'zoe', 'vera', 'ines', 'jose', 'mia',
                      'leo', 'lia', 'cora', 'dani', 'elsa', 'ruth', 'gus', 'pia', 'rita', 'teo', 'nico', 'vale']) with ordinality u(n, o);
insert into public.staff (id, name, role, active, pin_hash)
  select id, initcap(name), case when name in ('bea', 'gil', 'hal') then 'manager' else 'staff' end, name <> 'gil',
         extensions.crypt(pin, extensions.gen_salt('bf', 4))
    from test.t482_people where name not in ('ana', 'luis', 'marta', 'dueno');
create function test.p482(n text) returns uuid language sql stable as $$ select id from test.t482_people where name = n $$;
create function test.k482(n text) returns text language sql stable as $$ select pin from test.t482_people where name = n $$;
-- order ids and request ids of this file
create function test.o482(n int) returns uuid language sql immutable as $$ select ('d4820000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.r482(n int) returns uuid language sql immutable as $$ select ('e4820000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
-- this file's café sign-in: the registered till «Caja 1» (test.login resets the claims and the unlock header)
create function test.cafe482(sid text default 'till-482') returns void language sql as $$
  select test.login('cafe'); select test.session(sid) $$;

-- the window's call for an Empleado as the page sends it: the manager's code (Ana's by default), then the employee's
create function test.emp482(who text, sub int default 10000, bill uuid default null, expect int default null,
                            auth text default '4826', req uuid default null) returns jsonb language sql as $$
  select public.descuento_autorizar('empleado', auth, sub, test.k482(who), null, bill, expect, req, 'Caja 1') $$;
-- a ticket carrying an approval, as pos.html sends it (pos_record_sale): one line at the approved subtotal. Paid, or a
-- «Pay later» ticket (pending, for the kitchen)
create function test.sale482(oid uuid, appr jsonb, paid boolean default true, at timestamptz default now()) returns jsonb
language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', at,
           'total_crc', (appr ->> 'subtotal')::int - (appr ->> 'amount')::int,
           'payment_method', case when paid then 'cash_crc' else 'pending' end, 'paid', paid,
           'status', case when paid then 'done' else 'new' end, 'needs_kitchen', not paid,
           'station', 'Caja 1', 'guest_name', 'Ticket 482',
           'subtotal_crc', (appr ->> 'subtotal')::int, 'discount_crc', (appr ->> 'amount')::int, 'discount_id', appr ->> 'id',
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', (appr ->> 'subtotal')::int, 'qty', 1)))) $$;
-- an open bill of two lines, 4000 + 6000 (a «Pay later» bill, or a room bill from the live bar); line ids from its id
create function test.item482(oid uuid, n int) returns uuid language sql immutable as $$ select md5(oid::text || '-' || n)::uuid $$;
create function test.bill482(oid uuid, guest text, src text default 'front') returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', now(), 'total_crc', 10000,
           'payment_method', 'pending', 'paid', false, 'status', case when src = 'room' then 'new' else 'ready' end,
           'station', 'Caja 1', 'source', src, 'guest_name', guest,
           'items', jsonb_build_array(
              jsonb_build_object('id', test.item482(oid, 1), 'item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
              jsonb_build_object('id', test.item482(oid, 2), 'item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) $$;
-- one guest pays the first line of a bill (pay by item: a part of its own)
create function test.payitem482(oid uuid) returns jsonb language sql as $$
  select public.tab_pay(oid, 'cash_crc', jsonb_build_array(jsonb_build_object('item_id', test.item482(oid, 1), 'qty', 1)),
                        null, 'Caja 1') $$;
-- as the test superuser: an approval's day ('counts' while it holds the day), and the audit rows of one action about one
-- target, each as {manager_id, manager_name} + details, oldest first
create function test.day482(appr text) returns text language sql stable as $$
  select coalesce(freed_how, 'counts')
         || case when (freed_at is null) = (freed_how is null) then '' else ' (freed_at and freed_how disagree)' end
    from public.discount_approvals where id = appr::uuid $$;
create function test.log482(act text, target text) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('manager_id', manager_id, 'manager_name', manager_name) || details order by id), '[]')
    from public.audit_log where action = act and target_id = target $$;
-- every audit row about what happened to one approval's day, by action (left out: discount_approved, and the
-- discount_daily_refused rows other requests write against the approval that holds the day)
create function test.trail482(appr text) returns text language sql stable as $$
  select coalesce(string_agg(action, ',' order by id), '')
    from public.audit_log where target_id = appr and action like 'discount%'
     and action not in ('discount_approved', 'discount_daily_refused') $$;

-- the till: this sign-in is a registered till (test.till is the fixture for files that only need one)
select test.cafe482();
select test.ok(test.till('Caja 1') between 1 and 3, '0 fixture: the café sign-in till-482 is a registered till');
select id as till_id from public.discount_tills where session_id = 'till-482' and ended_at is null \gset
-- the Latte goes to the kitchen (item 12 adds one to a ticket the kitchen finished)
update public.menu_categories set kitchen = true where id = (select category_id from public.menu_items where name = 'Latte');
select id as latte from public.menu_items where name = 'Latte' \gset
\set cafe_uid 'c0000000-0000-4000-8000-000000000001'

-- 1) an approval never used holds the day; the page lets it go (descuento_liberar) and the day is free again ---------
set role authenticated;
select test.emp482('eva') as eva1 \gset
select test.emp482('eva') as eva1b \gset
select test.emp482('fede') as fede1 \gset
reset role;
select (:'eva1'::jsonb) ->> 'id' as eva1_id \gset
select test.eq((:'eva1'::jsonb) ->> 'ok', 'true', '1 Eva: an Empleado with Ana''s code and Eva''s is approved');
select test.eq((select cr_day = public.cr_today() and order_id is null and used_at is null and beneficiary_id = test.p482('eva')
                       and beneficiary_name = 'Eva' and approved_by = test.staff('ana')
                  from public.discount_approvals where id = :'eva1_id'), true,
               '1 the approval is Eva''s, authorized by Ana, of today''s Costa Rica day, on no order yet');
select test.eq(test.day482(:'eva1_id'), 'counts', '1 unused, it holds Eva''s day');
select test.eq((:'eva1b'::jsonb) - 'until',
               '{"ok": false, "error": "daily_used", "beneficiary": "Eva", "pending": true, "station": "Caja 1"}'::jsonb,
               '1 a second Empleado for Eva the same day: daily_used, pending (not used yet), and the station that holds it');
select test.eq(((:'eva1b'::jsonb) ->> 'until')::timestamptz,
               (select created_at + interval '30 minutes' from public.discount_approvals where id = :'eva1_id'),
               '1 until = the approval''s time + 30 minutes (when it is let go by itself)');
select test.eq(test.log482('discount_daily_refused', :'eva1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana',
                 'beneficiary_name', 'Eva', 'beneficiary', test.p482('eva'), 'approval', :'eva1_id', 'pending', true,
                 'category', 'empleado', 'till', :'till_id', 'by_login', :'cafe_uid', 'station', 'Caja 1')),
               '1 the refusal is logged once (discount_daily_refused): Ana, Eva, the approval that holds the day, the till');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.p482('eva')), 1,
               '1 the refusal left no second approval');
select test.eq((:'fede1'::jsonb) ->> 'ok', 'true', '1 the day is per employee: Fede''s Empleado is approved while Eva''s is held');
-- other logins cannot let it go
select test.login('owner', 'aal2'); select test.session('owner-482'); set role authenticated;
select public.descuento_liberar(:'eva1_id') as r_owner \gset
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select public.descuento_liberar(:'eva1_id') as r_acct \gset
reset role;
select test.eq(:'r_owner'::jsonb, '{"ok": false, "error": "not_found"}'::jsonb, '1 another login (the owner''s) cannot let it go: not_found');
select test.eq(:'r_acct'::jsonb, '{"ok": false, "error": "no_account"}'::jsonb, '1 the accountant login: no_account');
select test.eq(test.day482(:'eva1_id'), 'counts', '1 and Eva''s day stays held');
-- the till that made it lets it go
select test.cafe482(); set role authenticated;
select public.descuento_liberar(:'eva1_id') as r1 \gset
select public.descuento_liberar(:'eva1_id') as r2 \gset
select public.descuento_liberar() as r3 \gset
select public.descuento_liberar(gen_random_uuid()) as r3b \gset
select test.emp482('eva', 10000, null, null, '4826', test.r482(1)) as eva2 \gset
reset role;
select (:'eva2'::jsonb) ->> 'id' as eva2_id \gset
select test.eq(:'r1'::jsonb, jsonb_build_object('ok', true, 'id', :'eva1_id'), '1 descuento_liberar on the unused approval: ok');
select test.eq(test.day482(:'eva1_id'), 'released', '1 it is freed as released');
select test.eq((select freed_at from public.discount_approvals where id = :'eva1_id'), now(), '1 freed_at = when it was let go');
select test.eq(test.log482('discount_released', :'eva1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', null, 'approval', :'eva1_id',
                 'category', 'empleado', 'beneficiary_name', 'Eva', 'authorizer', 'Ana', 'station', 'Caja 1', 'by_login', :'cafe_uid')),
               '1 audit discount_released: the approval, Eva, Ana, the station and the login');
select test.eq(:'r2'::jsonb, jsonb_build_object('ok', true, 'already', true, 'id', :'eva1_id'),
               '1 letting it go again: ok, already');
select test.eq(jsonb_array_length(test.log482('discount_released', :'eva1_id')), 1, '1 and nothing is written twice');
select test.eq(:'r3'::jsonb, '{"ok": false, "error": "not_found"}'::jsonb, '1 descuento_liberar with no id: not_found');
select test.eq(:'r3b'::jsonb, '{"ok": false, "error": "not_found"}'::jsonb, '1 descuento_liberar with an unknown id: not_found');
select test.eq((:'eva2'::jsonb) ->> 'ok', 'true', '1 after the release Eva can get one again the same day (it never consumed the day)');
select test.ok((:'eva2'::jsonb) -> 'prior' = 'null'::jsonb, '1 and its answer has no prior (only a void is a prior)');
-- by request id (the page's lost-reply path); a replay of that request afterwards does not take the day back
select test.cafe482(); set role authenticated;
select public.descuento_liberar(p_request_id => test.r482(1)) as r4 \gset
select public.descuento_liberar(p_request_id => test.r482(99)) as r4b \gset
select public.descuento_autorizar('empleado', '', 10000, p_request_id => test.r482(1)) as eva2r \gset
select test.emp482('eva') as eva3 \gset
reset role;
select (:'eva3'::jsonb) ->> 'id' as eva3_id \gset
select test.eq(:'r4'::jsonb, jsonb_build_object('ok', true, 'id', :'eva2_id'), '1 descuento_liberar by request id: ok, that approval');
select test.eq(:'r4b'::jsonb, '{"ok": false, "error": "not_found"}'::jsonb, '1 by a request id nothing was made with: not_found');
select test.eq(test.day482(:'eva2_id'), 'released', '1 it is freed as released');
select test.eq(((:'eva2r'::jsonb) ->> 'id') || '|' || ((:'eva2r'::jsonb) ->> 'replay'), :'eva2_id' || '|true',
               '1 a replay of that request (no code) answers its stored approval, replay: true');
select test.eq(test.day482(:'eva2_id'), 'released', '1 and the replay did not take the day back');
select test.eq((:'eva3'::jsonb) ->> 'ok', 'true', '1 so Eva''s day is still free: a third approval is ok');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.p482('eva') and freed_at is null), 1,
               '1 exactly one of Eva''s approvals holds the day');
-- a lost reply: the same request sent again with the codes is the same approval, never daily_used
select test.cafe482(); set role authenticated;
select test.emp482('cora', 10000, null, null, '4826', test.r482(2)) as cora1 \gset
select test.emp482('cora', 10000, null, null, '4826', test.r482(2)) as cora1r \gset
reset role;
select test.eq((:'cora1r'::jsonb) - 'replay', :'cora1'::jsonb, '1 a lost reply asked again (same request id, same codes): the same answer');
select test.eq((:'cora1r'::jsonb) ->> 'replay', 'true', '1 marked replay, not daily_used');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.p482('cora')), 1,
               '1 and one approval row, holding Cora''s day');
-- descuento_liberar lets go any category (api §13.12); a Local has no day to hold
select test.cafe482(); set role authenticated;
select public.descuento_autorizar('local', '4826', 5000, p_station => 'Caja 1') ->> 'id' as loc1_id \gset
select public.descuento_autorizar('local', '4826', 5000, p_station => 'Caja 1') ->> 'ok' as loc2_ok \gset
select public.descuento_liberar(:'loc1_id') as r5 \gset
reset role;
select test.eq(:'loc2_ok'::text, 'true', '1 a Local has no daily limit: a second one at once is approved');
select test.eq(:'r5'::jsonb, jsonb_build_object('ok', true, 'id', :'loc1_id'), '1 a Local approval is let go the same way');
select test.eq(test.day482(:'loc1_id'), 'released', '1 freed as released');

-- 2) unused for 30 minutes it expires, at the next request for that employee, which then succeeds ----------------------
select test.cafe482(); set role authenticated;
select test.emp482('iris') ->> 'id' as iris1_id \gset
select test.emp482('hugo') ->> 'id' as hugo1_id \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '29 minutes 59 seconds' where id = :'iris1_id';
update public.discount_approvals set created_at = created_at - interval '45 minutes' where id = :'hugo1_id';
select test.cafe482(); set role authenticated;
select test.emp482('iris') as iris1b \gset
reset role;
select test.eq((:'iris1b'::jsonb) ->> 'error', 'daily_used', '2 Iris, 29 min 59 s after an unused approval: still daily_used');
select test.eq((:'iris1b'::jsonb) ->> 'pending', 'true', '2 pending');
select test.eq(((:'iris1b'::jsonb) ->> 'until')::timestamptz, now() + interval '1 second', '2 let go by itself in one second');
select test.eq(test.day482(:'iris1_id'), 'counts', '2 it still holds the day');
select test.eq(test.day482(:'hugo1_id'), 'counts',
               '2 a request for Iris expires none of another employee''s approvals (Hugo''s, 45 minutes old, still counts)');
update public.discount_approvals set created_at = created_at - interval '1 second' where id = :'iris1_id';
select test.cafe482(); set role authenticated;
select test.emp482('iris') as iris2 \gset
select test.emp482('hugo') ->> 'ok' as hugo2_ok \gset
reset role;
select (:'iris2'::jsonb) ->> 'id' as iris2_id \gset
select test.eq((:'iris2'::jsonb) ->> 'ok', 'true', '2 exactly 30 minutes after: the next request for Iris succeeds');
select test.eq(test.day482(:'iris1_id'), 'expired', '2 the old one is freed as expired by that request');
select test.eq((select freed_at from public.discount_approvals where id = :'iris1_id'), now(), '2 freed_at = that request''s time');
select test.eq(test.day482(:'iris2_id'), 'counts', '2 the new one holds the day');
select test.eq(:'hugo2_ok' || '|' || test.day482(:'hugo1_id'), 'true|expired', '2 Hugo''s own next request expires his and succeeds');
select test.eq(test.trail482(:'iris1_id'), '', '2 an expiry writes no audit row of its own (the report shows it)');
-- a past Costa Rica day never holds today
select test.cafe482(); set role authenticated;
select test.emp482('kai') ->> 'id' as kai1_id \gset
reset role;
update public.discount_approvals set cr_day = cr_day - 1, created_at = created_at - interval '1 day' where id = :'kai1_id';
select test.cafe482(); set role authenticated;
select test.emp482('kai') ->> 'ok' as kai2_ok \gset
reset role;
select test.eq(:'kai2_ok'::text, 'true', '2 one Empleado per Costa Rica day: Kai''s live approval of yesterday does not hold today');
-- a sale consumes it: an approval used by a sale never expires, however old
select test.cafe482(); set role authenticated;
select test.emp482('olga') as olga1 \gset
select test.sale482(test.o482(1), :'olga1') ->> 'ok' as s \gset
reset role;
select (:'olga1'::jsonb) ->> 'id' as olga1_id \gset
select test.eq(:'s'::text, 'true', '2 Olga''s ticket sale is recorded (pos_record_sale)');
select test.eq((select order_id = test.o482(1) and used_at is not null from public.discount_approvals where id = :'olga1_id'), true,
               '2 the sale consumed the approval (order_id, used_at)');
select test.eq((select discount_id::text || '|' || discount_reason || '|' || discount_by || '|'
                       || ('discount_not_verified' = any (flags)) || '|' || ('discount_daily_twice' = any (flags))
                  from public.orders where id = test.o482(1)), :'olga1_id' || '|Employee|Ana|false|false',
               '2 the sale carries it, verified, by Ana, with no discount flag');
update public.discount_approvals set created_at = created_at - interval '2 hours' where id = :'olga1_id';
select test.cafe482(); set role authenticated;
select test.emp482('olga') as olga2 \gset
select public.descuento_liberar(:'olga1_id') as r \gset
reset role;
select test.eq(:'olga2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Olga", "pending": false}'::jsonb,
               '2 two hours later Olga''s day is still used: daily_used, not pending (no station, no until)');
select test.eq(test.day482(:'olga1_id'), 'counts', '2 a used approval is never expired');
select test.eq(:'r'::jsonb, jsonb_build_object('ok', false, 'error', 'discount_used', 'id', :'olga1_id'),
               '2 the page cannot let a used approval go: discount_used');
select test.eq(test.day482(:'olga1_id'), 'counts', '2 the day stays used');
-- an approval older than 30 minutes not yet marked expired (no request since): a sale still consumes it as usual
select test.cafe482(); set role authenticated;
select test.emp482('tomas') as tomas1 \gset
reset role;
select (:'tomas1'::jsonb) ->> 'id' as tomas1_id \gset
update public.discount_approvals set created_at = created_at - interval '40 minutes' where id = :'tomas1_id';
select test.cafe482(); set role authenticated;
select test.sale482(test.o482(2), :'tomas1', true, now() - interval '35 minutes') ->> 'ok' as s \gset
select test.emp482('tomas') as tomas2 \gset
reset role;
select test.eq(:'s' || '|' || test.day482(:'tomas1_id'), 'true|counts',
               '2 Tomás: his queued sale on a 40-minute-old unused approval is recorded and the approval holds the day');
select test.eq(test.trail482(:'tomas1_id'), '', '2 no discount_used_after_release: it was never let go');
select test.eq(:'tomas2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Tomas", "pending": false}'::jsonb,
               '2 and the next request is daily_used: a used approval is never expired');
-- a sale that does not match its approval (a smaller discount) is linked and consumes the day all the same
select test.cafe482(); set role authenticated;
select test.emp482('pia') as pia1 \gset
select test.sale482(test.o482(33), (:'pia1'::jsonb) || '{"amount": 2000}') ->> 'ok' as s \gset
select test.emp482('pia') as pia2 \gset
reset role;
select (:'pia1'::jsonb) ->> 'id' as pia1_id \gset
select test.eq(:'s' || '|' || (select discount_id::text || '|' || discount_crc || '|' || ('discount_not_verified' = any (flags))
                                   from public.orders where id = test.o482(33)), 'true|' || :'pia1_id' || '|2000|true',
               '2 Pía''s sale with a smaller discount than approved: linked, as charged, flagged discount_not_verified');
select test.eq(test.day482(:'pia1_id'), 'counts', '2 used by a sale, matching or not: the day is consumed');
select test.eq(:'pia2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Pia", "pending": false}'::jsonb,
               '2 a new Empleado for Pía: daily_used');

-- 3) a sale queued on a let-go or expired approval arrives ------------------------------------------------------------
-- a) no other live approval that day: it takes the day again
select test.cafe482(); set role authenticated;
select test.emp482('raul') as raul1 \gset
select public.descuento_liberar(((:'raul1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.sale482(test.o482(3), :'raul1') as s \gset
select test.emp482('raul') as raul1b \gset
reset role;
select (:'raul1'::jsonb) ->> 'id' as raul1_id \gset
select test.eq(:'rel' || '|' || ((:'s'::jsonb) ->> 'ok'), 'true|true', '3a Raúl''s approval is let go, then his queued sale arrives and is recorded');
select test.eq(test.day482(:'raul1_id'), 'counts', '3a the sale takes the day again (freed_at and freed_how cleared)');
select test.eq((select order_id = test.o482(3) from public.discount_approvals where id = :'raul1_id'), true, '3a the approval is consumed by that sale');
select test.eq((select discount_id::text || '|' || discount_reason || '|' || discount_by || '|' || ('discount_daily_twice' = any (flags))
                  from public.orders where id = test.o482(3)), :'raul1_id' || '|Employee|Ana|false',
               '3a the sale carries it, verified, not flagged discount_daily_twice');
select test.eq(test.log482('discount_used_after_release', :'raul1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'Caja 1', 'order', test.o482(3),
                 'approval', :'raul1_id', 'category', 'empleado', 'freed_how', 'released', 'beneficiary_name', 'Raul', 'day_taken', true)),
               '3a audit discount_used_after_release {day_taken: true, freed_how: released}');
select test.eq(:'raul1b'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Raul", "pending": false}'::jsonb,
               '3a a new Empleado for Raúl: daily_used (the day is used again)');
select test.throws($$insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, subtotal_crc, amount_crc,
                       category, beneficiary_id, beneficiary_name, cr_day, approver_role)
                     values ('a1000000-0000-4000-8000-000000000001', 'Ana', 'percent', 30, 'Employee', 1000, 300, 'empleado',
                             test.p482('raul'), 'Raul', public.cr_today(), 'manager')$$,
                   'discount_employee_once',
                   '3a the database itself refuses a second live Empleado for Raúl that day (unique index discount_employee_once)');
-- b) another live approval holds the day: the sale is linked, stays freed and is flagged discount_daily_twice; a later
--    void of the other sale gives the day to this one (never a third discount)
select test.cafe482(); set role authenticated;
select test.emp482('sara') as sara1 \gset
select public.descuento_liberar(((:'sara1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.emp482('sara') as sara2 \gset
select test.sale482(test.o482(4), :'sara1') ->> 'ok' as s1 \gset
select test.emp482('sara') as sara2b \gset
reset role;
select (:'sara1'::jsonb) ->> 'id' as sara1_id \gset
select (:'sara2'::jsonb) ->> 'id' as sara2_id \gset
select test.eq(:'rel' || '|' || ((:'sara2'::jsonb) ->> 'ok') || '|' || :'s1', 'true|true|true',
               '3b Sara: approval 1 let go, approval 2 approved, then the queued sale on approval 1 arrives and is recorded');
select test.eq((select discount_id::text || '|' || ('discount_daily_twice' = any (flags)) || '|' || discount_crc
                  from public.orders where id = test.o482(4)), :'sara1_id' || '|true|3000',
               '3b the sale is linked to approval 1 with its discount and flagged discount_daily_twice');
select test.eq(test.day482(:'sara1_id') || '|' || test.day482(:'sara2_id'), 'released|counts',
               '3b approval 1 stays freed (released); approval 2 keeps the day');
select test.eq((select order_id = test.o482(4) from public.discount_approvals where id = :'sara1_id'), true, '3b approval 1 is consumed by the sale');
select test.eq(test.log482('discount_used_after_release', :'sara1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'Caja 1', 'order', test.o482(4),
                 'approval', :'sara1_id', 'category', 'empleado', 'freed_how', 'released', 'beneficiary_name', 'Sara', 'day_taken', false)),
               '3b audit discount_used_after_release {day_taken: false}');
select test.eq((:'sara2b'::jsonb) ->> 'error' || '|' || ((:'sara2b'::jsonb) ->> 'pending'), 'daily_used|true',
               '3b a third request for Sara: daily_used (approval 2, unused, holds the day)');
select test.cafe482(); set role authenticated;
select test.sale482(test.o482(5), :'sara2') ->> 'ok' as s2 \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o482(5), 'wrong item') ->> 'ok' as v \gset
select test.emp482('sara') as sara3 \gset
reset role;
select test.eq(:'s2' || '|' || :'v', 'true|true', '3b approval 2 is used by a sale, which Ana voids');
select test.eq(test.day482(:'sara2_id'), 'void', '3b the void frees approval 2');
select test.eq(test.day482(:'sara1_id'), 'counts', '3b and approval 1, still on a live sale, takes the day back');
select test.eq(:'sara3'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Sara", "pending": false}'::jsonb,
               '3b so Sara cannot get a third discount: daily_used');
-- c) an approval expired by a later request, then let go, then its queued sale arrives: it takes the day again
select test.cafe482(); set role authenticated;
select test.emp482('uma') as uma1 \gset
reset role;
select (:'uma1'::jsonb) ->> 'id' as uma1_id \gset
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = :'uma1_id';
select test.cafe482(); set role authenticated;
select test.emp482('uma') as uma2 \gset
select public.descuento_liberar(((:'uma2'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.sale482(test.o482(6), :'uma1', true, now() - interval '28 minutes') ->> 'ok' as s \gset
select test.emp482('uma') as uma3 \gset
reset role;
select test.eq(test.day482(:'uma1_id') || '|' || test.day482((:'uma2'::jsonb) ->> 'id') || '|' || :'s',
               'counts|released|true', '3c Úma: the expired approval''s queued sale takes the day (the second one was let go)');
select test.eq((select details ->> 'freed_how' || '|' || (details ->> 'day_taken') from public.audit_log
                 where action = 'discount_used_after_release' and target_id = :'uma1_id'), 'expired|true',
               '3c audit discount_used_after_release {freed_how: expired, day_taken: true}');
select test.eq((:'uma3'::jsonb) ->> 'error', 'daily_used', '3c a new Empleado for Úma: daily_used');
-- d) the discount_daily_twice sale is voided while its approval is still freed: nothing changes, the other approval
--    keeps the day (the trigger acts only on an approval that still counts)
select test.cafe482(); set role authenticated;
select test.emp482('gus') as gus1 \gset
select public.descuento_liberar(((:'gus1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.emp482('gus') as gus2 \gset
select test.sale482(test.o482(32), :'gus1') ->> 'ok' as s \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o482(32), 'twice') ->> 'ok' as v \gset
select test.emp482('gus') as gus3 \gset
reset role;
select (:'gus1'::jsonb) ->> 'id' as gus1_id \gset
select (:'gus2'::jsonb) ->> 'id' as gus2_id \gset
select test.eq(:'rel' || '|' || :'s' || '|' || :'v' || '|' || (select ('discount_daily_twice' = any (flags))::text from public.orders where id = test.o482(32)),
               'true|true|true|true', '3d Gus: approval 1 let go, approval 2 holds the day, the daily_twice sale on approval 1 is voided');
select test.eq(test.day482(:'gus1_id') || '|' || test.day482(:'gus2_id'), 'released|counts',
               '3d the void changes nothing: approval 1 stays released, approval 2 keeps the day');
select test.eq(test.trail482(:'gus1_id'), 'discount_released,discount_used_after_release',
               '3d the void wrote nothing for the freed approval (no discount_freed, no discount_not_freed)');
select test.eq((:'gus3'::jsonb) ->> 'error' || '|' || ((:'gus3'::jsonb) ->> 'pending'), 'daily_used|true',
               '3d so Gus still cannot get another: daily_used (approval 2 pending)');
select test.cafe482(); set role authenticated;
select public.descuento_liberar(:'gus1_id') as r \gset
reset role;
select test.eq(:'r'::jsonb, jsonb_build_object('ok', false, 'error', 'discount_used', 'id', :'gus1_id'),
               '3d letting go approval 1 (freed, but on a sale): discount_used, not already (a used approval is never let go)');
-- e) a discount_daily_twice sale holds no day while the other approval holds it; that other approval is then let go
--    unused: the sale takes the day back, so a new request is daily_used (review, money: before the fix the day came
--    back free and the employee got a second, clean discounted sale the same day; adjustment 3)
select test.cafe482(); set role authenticated;
select test.emp482('nico') as nico1 \gset
select public.descuento_liberar(((:'nico1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.emp482('nico') as nico2 \gset
select test.sale482(test.o482(37), :'nico1') ->> 'ok' as s \gset
select public.descuento_liberar(((:'nico2'::jsonb) ->> 'id')::uuid) as rel2 \gset
select test.emp482('nico') as nico3 \gset
reset role;
select (:'nico1'::jsonb) ->> 'id' as nico1_id \gset
select (:'nico2'::jsonb) ->> 'id' as nico2_id \gset
select test.eq(:'rel' || '|' || ((:'nico2'::jsonb) ->> 'ok') || '|' || :'s' || '|'
               || (select ('discount_daily_twice' = any (flags))::text from public.orders where id = test.o482(37)),
               'true|true|true|true', '3e Nico: approval 1 let go, approval 2 holds the day, the queued sale on approval 1 is flagged daily_twice');
select test.eq(:'rel2'::jsonb, jsonb_build_object('ok', true, 'id', :'nico2_id'), '3e approval 2, never used, is let go by the page');
select test.eq(test.day482(:'nico1_id') || '|' || test.day482(:'nico2_id'), 'counts|released',
               '3e the daily_twice sale''s approval takes the day back (approval 2 released)');
select test.eq(:'nico3'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Nico", "pending": false}'::jsonb,
               '3e so a new Empleado for Nico is daily_used (his sale of the day stands), never a second clean discount');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.p482('nico')), 2,
               '3e ... and no third approval exists');
select test.eq((select count(*)::int from public.orders o join public.discount_approvals a on a.id = o.discount_id
                 where a.beneficiary_id = test.p482('nico') and o.voided_at is null), 1, '3e ... one discounted sale for Nico today');
-- f) the same, but approval 2 is never let go: it expires unused (older than 30 minutes) and the next request expires it
select test.cafe482(); set role authenticated;
select test.emp482('vale') as vale1 \gset
reset role;
select (:'vale1'::jsonb) ->> 'id' as vale1_id \gset
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = :'vale1_id';
select test.cafe482(); set role authenticated;
select test.emp482('vale') as vale2 \gset
select test.sale482(test.o482(38), :'vale1', true, now() - interval '20 minutes') ->> 'ok' as s \gset
reset role;
select (:'vale2'::jsonb) ->> 'id' as vale2_id \gset
select test.eq(test.day482(:'vale1_id') || '|' || test.day482(:'vale2_id') || '|' || :'s' || '|'
               || (select ('discount_daily_twice' = any (flags))::text from public.orders where id = test.o482(38)),
               'expired|counts|true|true',
               '3f Vale: approval 1 expired by approval 2''s request, then its queued sale arrives: flagged daily_twice, approval 2 holds the day');
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = :'vale2_id';
select test.cafe482(); set role authenticated;
select test.emp482('vale') as vale3 \gset
reset role;
select test.eq(:'vale3'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Vale", "pending": false}'::jsonb,
               '3f approval 2 aged 30 minutes unused: the next request expires it, the daily_twice sale takes the day back: daily_used');
select test.eq(test.day482(:'vale1_id') || '|' || test.day482(:'vale2_id'), 'counts|expired',
               '3f ... approval 1, on its live sale, counts again; approval 2 expired');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.p482('vale')), 2,
               '3f ... and no third approval exists');

-- 4) voids --------------------------------------------------------------------------------------------------------------
-- a) a manager who is not the beneficiary voids the sale: the day comes back, and the next answer names who voided
select test.cafe482(); set role authenticated;
select test.emp482('pablo') as pablo1 \gset
select test.sale482(test.o482(7), :'pablo1') ->> 'ok' as s \gset
select test.emp482('pablo') as pablo1b \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o482(7), 'wrong item') as v \gset
select test.emp482('pablo') as pablo2 \gset
reset role;
select (:'pablo1'::jsonb) ->> 'id' as pablo1_id \gset
select (:'pablo2'::jsonb) ->> 'id' as pablo2_id \gset
select test.eq(:'s' || '|' || ((:'pablo1b'::jsonb) ->> 'error'), 'true|daily_used', '4a Pablo''s sale is recorded and his day is used');
select test.eq((:'v'::jsonb) ->> 'ok', 'true', '4a Ana voids the sale (manager_void_order)');
select test.eq(test.day482(:'pablo1_id'), 'void', '4a the approval is freed as void');
select test.eq(test.log482('discount_freed', :'pablo1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'how', 'void',
                 'approval', :'pablo1_id', 'order', test.o482(7), 'beneficiary_name', 'Pablo', 'by', 'Ana', 'by_login', :'cafe_uid')),
               '4a audit discount_freed {how: void}: Ana, the order, Pablo');
select test.eq((:'pablo2'::jsonb) ->> 'ok', 'true', '4a Pablo can get one again the same day');
select test.eq((:'pablo2'::jsonb) -> 'prior', '{"how": "void", "by": "Ana"}'::jsonb, '4a its answer says the earlier one was voided by Ana');
select test.eq((select details -> 'prior' from public.audit_log where action = 'discount_approved' and target_id = :'pablo2_id'),
               '{"how": "void", "by": "Ana"}'::jsonb, '4a and its discount_approved row carries the same prior');
-- b) the owner voids: the same (anyone who may void and is not the beneficiary)
select test.cafe482(); set role authenticated;
select test.emp482('quim') as quim1 \gset
select test.sale482(test.o482(8), :'quim1') ->> 'ok' as s \gset
select public.manager_void_order(test.staff('dueno'), '7391', test.o482(8), 'error') ->> 'ok' as v \gset
select test.emp482('quim') as quim2 \gset
reset role;
select (:'quim1'::jsonb) ->> 'id' as quim1_id \gset
select test.eq(:'s' || '|' || :'v' || '|' || test.day482(:'quim1_id'), 'true|true|void', '4b Dueño voids Quim''s sale: freed as void');
select test.eq((select manager_name || '|' || (details ->> 'by') from public.audit_log where action = 'discount_freed' and target_id = :'quim1_id'),
               'Dueño|Dueño', '4b discount_freed names Dueño');
select test.eq((:'quim2'::jsonb) -> 'prior', '{"how": "void", "by": "Dueño"}'::jsonb, '4b Quim''s next approval: prior voided by Dueño');
-- c) the beneficiary voids their own sale: the void stands, the day stays used
select test.cafe482(); set role authenticated;
select test.emp482('bea') as bea1 \gset
select test.sale482(test.o482(9), :'bea1') ->> 'ok' as s \gset
select public.manager_void_order(test.p482('bea'), '3917', test.o482(9), 'mine') as v \gset
select test.emp482('bea') as bea2 \gset
reset role;
select (:'bea1'::jsonb) ->> 'id' as bea1_id \gset
select test.eq((:'bea1'::jsonb) ->> 'beneficiary' || '|' || :'s', 'Bea|true', '4c Bea (a manager) gets an Empleado from Ana and the sale is recorded');
select test.eq((:'v'::jsonb) ->> 'ok', 'true', '4c Bea voids her own sale: the void stands');
select test.eq((select voided_by from public.orders where id = test.o482(9)), test.p482('bea'), '4c voided by Bea');
select test.eq(test.day482(:'bea1_id'), 'counts', '4c the day stays used');
select test.eq(test.log482('discount_self_void', :'bea1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', test.p482('bea'), 'manager_name', 'Bea', 'approval', :'bea1_id',
                 'order', test.o482(9), 'beneficiary_name', 'Bea', 'by_login', :'cafe_uid')),
               '4c audit discount_self_void names Bea, the approval and the order');
select test.eq(test.trail482(:'bea1_id'), 'discount_self_void', '4c and no discount_freed');
select test.eq(:'bea2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Bea", "pending": false}'::jsonb,
               '4c a new Empleado for Bea: daily_used');
-- d) a Local sale has no day: its void frees nothing and logs nothing about a day
select test.cafe482(); set role authenticated;
select public.descuento_autorizar('local', '4826', 10000, p_station => 'Caja 1') as loc3 \gset
select test.sale482(test.o482(10), :'loc3') ->> 'ok' as s \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o482(10), 'error') ->> 'ok' as v \gset
reset role;
select (:'loc3'::jsonb) ->> 'id' as loc3_id \gset
select test.eq(:'s' || '|' || :'v' || '|' || test.day482(:'loc3_id') || '|' || test.trail482(:'loc3_id'), 'true|true|counts|',
               '4d a Local sale voided: nothing freed, no day row (only Empleado has a daily slot)');
-- e) a voided bill that still has a paid part: the part stays a sale, the day stays used for good
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(11), 'Mesa Walter') ->> 'ok' as b \gset
select test.emp482('walter', 10000, test.o482(11), 10000) as walter1 \gset
select test.payitem482(test.o482(11)) as p \gset
reset role;
select (:'walter1'::jsonb) ->> 'id' as walter1_id \gset
select test.trail482(:'walter1_id') as w_trail, test.day482(:'walter1_id') as w_day \gset
set role authenticated;
select public.manager_void_order(test.staff('ana'), '4826', test.o482(11), 'left') ->> 'ok' as v \gset
select test.emp482('walter') as walter2 \gset
reset role;
select test.eq(:'b' || '|' || ((:'walter1'::jsonb) ->> 'total') || '|' || ((:'p'::jsonb) ->> 'amount'), 'true|7000|2800',
               '4e Walter''s bill: 10000 less 30 % = 7000; one guest pays the Latte by item (2800)');
select test.eq(:'w_day' || '|' || :'w_trail', 'counts|', '4e the payment by item does not touch the day (nothing logged)');
select test.eq(:'v'::text, 'true', '4e Ana voids the bill: the void stands');
select test.eq((select count(*)::int from public.orders where part_of = test.o482(11) and paid and voided_at is null), 1,
               '4e its paid part stays a sale');
select test.eq(test.day482(:'walter1_id'), 'counts', '4e the day stays used');
select test.eq(test.log482('discount_not_freed', :'walter1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'why', 'parts', 'how', 'void',
                 'approval', :'walter1_id', 'order', test.o482(11), 'beneficiary_name', 'Walter', 'by_login', :'cafe_uid')),
               '4e audit discount_not_freed {why: parts, how: void} names Ana');
select test.eq(:'walter2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Walter", "pending": false}'::jsonb,
               '4e a new Empleado for Walter: daily_used');
-- the used day refuses a bill-mode request too, and the bill is left as it was
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(34), 'Mesa Walter 2') ->> 'ok' as b \gset
select test.emp482('walter', 10000, test.o482(34), 10000) as walter3 \gset
reset role;
select test.eq(:'walter3'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Walter", "pending": false}'::jsonb,
               '4e Walter on a new bill: daily_used');
select test.eq((select discount_id is null and discount_crc = 0 and total_crc = 10000 from public.orders where id = test.o482(34)), true,
               '4e the bill is not discounted');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.p482('walter')), 1,
               '4e and no approval row was added');
-- f) the paid part was voided first: nothing paid in parts is left, so the bill's void frees the day
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(12), 'Mesa Ximena') ->> 'ok' as b \gset
select test.emp482('ximena', 10000, test.o482(12), 10000) as ximena1 \gset
select test.payitem482(test.o482(12)) as p \gset
select public.manager_void_order(test.staff('ana'), '4826', ((:'p'::jsonb) ->> 'part_id')::uuid, 'wrong card') ->> 'ok' as vp \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o482(12), 'left') ->> 'ok' as v \gset
select test.emp482('ximena') ->> 'ok' as ximena2_ok \gset
reset role;
select (:'ximena1'::jsonb) ->> 'id' as ximena1_id \gset
select test.eq(:'b' || '|' || ((:'ximena1'::jsonb) ->> 'ok') || '|' || ((:'p'::jsonb) ->> 'ok') || '|' || :'vp' || '|' || :'v',
               'true|true|true|true|true', '4f Ximena''s bill: discounted, a part paid, the part voided, then the bill voided');
select test.eq(test.day482(:'ximena1_id'), 'void', '4f no paid part is left: the day is freed as void');
select test.eq(:'ximena2_ok'::text, 'true', '4f Ximena can get one again');
-- g) an order inserted already voided (the till's insert grant) frees nothing: only an UPDATE fires the trigger
select test.cafe482(); set role authenticated;
select test.emp482('yago') as yago1 \gset
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, station, subtotal_crc, discount_crc,
                           discount_id, voided_at, voided_by, void_reason)
  values (test.o482(13), now(), 7000, 'cash_crc', true, 'done', 'Caja 1', 10000, 3000, ((:'yago1'::jsonb) ->> 'id')::uuid,
          now(), test.staff('ana'), 'crafted');
select test.emp482('yago') as yago2 \gset
reset role;
select (:'yago1'::jsonb) ->> 'id' as yago1_id \gset
select test.eq((select voided_at is not null from public.orders where id = test.o482(13)), true, '4g a crafted order is inserted already voided');
select test.eq(test.day482(:'yago1_id') || '|' || test.trail482(:'yago1_id'), 'counts|', '4g the approval it carries is not freed, nothing logged');
select test.eq(:'yago2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Yago", "pending": false}'::jsonb,
               '4g a new Empleado for Yago: daily_used');

-- 5) cancels ------------------------------------------------------------------------------------------------------------
-- a) cancel_unpaid_order on an unpaid bill: no PIN, the cancel stands, the day still counts until a give-back
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(14), 'Mesa Marta') ->> 'ok' as b \gset
select test.emp482('marta', 10000, test.o482(14), 10000) as marta1 \gset
select public.cancel_unpaid_order(test.o482(14)) as c \gset
select test.emp482('marta') as marta1b \gset
reset role;
select (:'marta1'::jsonb) ->> 'id' as marta1_id \gset
select test.eq(:'b' || '|' || ((:'marta1'::jsonb) ->> 'ok'), 'true|true', '5a Marta''s bill carries her Empleado discount');
select test.eq(:'c'::jsonb, '{"ok": true}'::jsonb, '5a cancel_unpaid_order: cancelled, no PIN');
select test.eq((select status from public.orders where id = test.o482(14)), 'cancelled', '5a the bill is cancelled');
select test.eq(test.day482(:'marta1_id'), 'counts', '5a the day still counts');
select test.eq(test.log482('discount_not_freed', :'marta1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'Caja 1', 'why', 'needs_manager',
                 'how', 'bill_cancelled', 'approval', :'marta1_id', 'order', test.o482(14), 'beneficiary_name', 'Marta',
                 'by_login', :'cafe_uid')),
               '5a audit discount_not_freed {why: needs_manager, how: bill_cancelled}');
select test.eq(:'marta1b'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Marta", "pending": false}'::jsonb,
               '5a a new Empleado for Marta: daily_used');
-- b) cancel_room_order («No show») on a room bill with nothing paid: the same; Ana gives the day back
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(15), 'Hab Nora', 'room') ->> 'ok' as b \gset
select test.emp482('nora', 10000, test.o482(15), 10000) as nora1 \gset
select public.cancel_room_order(test.o482(15)) as c \gset
select test.emp482('nora') ->> 'error' as nora1b \gset
reset role;
select (:'nora1'::jsonb) ->> 'id' as nora1_id \gset
select test.eq(:'b' || '|' || ((:'nora1'::jsonb) ->> 'total') || '|' || (:'c'::jsonb ->> 'ok'), 'true|7000|true',
               '5b Nora''s room bill carries her Empleado discount; cancel_room_order: cancelled, no PIN');
select test.eq(test.day482(:'nora1_id') || '|' || :'nora1b', 'counts|daily_used', '5b the day still counts (daily_used)');
select test.eq((select details ->> 'why' || '|' || (details ->> 'how') from public.audit_log
                 where action = 'discount_not_freed' and target_id = :'nora1_id'), 'needs_manager|bill_cancelled',
               '5b audit discount_not_freed {why: needs_manager, how: bill_cancelled}');
select test.cafe482(); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(:'nora1_id', test.staff('ana'), '4826', 'Bitácora') as g \gset
select test.cafe482(); set role authenticated;
select test.emp482('nora') ->> 'ok' as nora2_ok \gset
reset role;
select test.eq(:'g'::jsonb, jsonb_build_object('ok', true, 'how', 'bill_cancelled', 'approval', :'nora1_id', 'beneficiary', 'Nora'),
               '5b Ana gives the day back (descuento_cupo_devolver): ok, bill_cancelled');
select test.eq(test.day482(:'nora1_id'), 'bill_cancelled', '5b the approval is freed as bill_cancelled');
select test.eq(test.log482('discount_freed', :'nora1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'how', 'bill_cancelled',
                 'approval', :'nora1_id', 'order', test.o482(15), 'beneficiary_name', 'Nora', 'by_login', :'cafe_uid',
                 'station', 'Bitácora', 'phone_code', false)),
               '5b audit discount_freed names Ana (who confirmed), the order, Nora; no phone code');
select test.eq(:'nora2_ok'::text, 'true', '5b Nora can get one again');
-- c) cancel_room_order with one item paid by item first: the cancel stands, the day stays used for good
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(16), 'Hab Omar', 'room') ->> 'ok' as b \gset
select test.emp482('omar', 10000, test.o482(16), 10000) as omar1 \gset
select test.payitem482(test.o482(16)) ->> 'ok' as p \gset
select public.cancel_room_order(test.o482(16)) as c \gset
select test.emp482('omar') ->> 'error' as omar1b \gset
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(((:'omar1'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826') as g \gset
reset role;
select (:'omar1'::jsonb) ->> 'id' as omar1_id \gset
select test.eq(:'b' || '|' || :'p' || '|' || (:'c'::jsonb ->> 'ok'), 'true|true|true',
               '5c Omar''s room bill: discounted, one item paid by item, then cancel_room_order: the cancel stands');
select test.eq(test.day482(:'omar1_id') || '|' || :'omar1b', 'counts|daily_used', '5c the day stays used (daily_used)');
select test.eq(test.log482('discount_not_freed', :'omar1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'Caja 1', 'why', 'parts',
                 'how', 'bill_cancelled', 'approval', :'omar1_id', 'order', test.o482(16), 'beneficiary_name', 'Omar',
                 'by_login', :'cafe_uid')),
               '5c audit discount_not_freed {why: parts, how: bill_cancelled}');
select test.eq(:'g'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '5c descuento_cupo_devolver: not_freeable (money was paid)');
select test.eq(test.day482(:'omar1_id'), 'counts', '5c still counts');
-- d) cancel_unpaid_order refuses a bill with a paid part (as before 0038): nothing about the day changes
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(17), 'Mesa Zoe') ->> 'ok' as b \gset
select test.emp482('zoe', 10000, test.o482(17), 10000) as zoe1 \gset
select test.payitem482(test.o482(17)) ->> 'ok' as p \gset
select public.cancel_unpaid_order(test.o482(17)) as c \gset
reset role;
select (:'zoe1'::jsonb) ->> 'id' as zoe1_id \gset
select test.eq(:'c'::jsonb, '{"ok": false, "error": "has_parts"}'::jsonb, '5d cancel_unpaid_order on Zoe''s bill with a paid part: has_parts');
select test.eq(test.day482(:'zoe1_id') || '|' || test.trail482(:'zoe1_id'), 'counts|', '5d the day still counts and nothing is logged about it');

-- 6) taken off a bill -------------------------------------------------------------------------------------------------
-- a) descuento_quitar_cuenta with nothing paid: no PIN, removed, the day still counts (W1)
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(18), 'Mesa Luis') ->> 'ok' as b \gset
select test.emp482('luis', 10000, test.o482(18), 10000) as luis1 \gset
select public.descuento_quitar_cuenta(test.o482(18), 7000, 'Caja 1') as q \gset
select test.emp482('luis') as luis1b \gset
reset role;
select (:'luis1'::jsonb) ->> 'id' as luis1_id \gset
select test.eq(:'b' || '|' || ((:'luis1'::jsonb) ->> 'total'), 'true|7000', '6a Luis''s bill carries his Empleado discount (7000)');
select test.eq(:'q'::jsonb, '{"ok": true, "total": 10000, "discount": 0, "paid": false, "beneficiary": "Luis", "counts": true}'::jsonb,
               '6a descuento_quitar_cuenta with nothing paid: no PIN, the bill back to 10000, and counts: true');
select test.eq((select discount_id is null and discount_crc = 0 and total_crc = 10000 from public.orders where id = test.o482(18)), true,
               '6a the bill no longer carries the discount');
select test.eq(test.day482(:'luis1_id'), 'counts', '6a the day still counts (freed_at stays null)');
select test.eq(test.log482('discount_not_freed', :'luis1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'Caja 1', 'why', 'needs_manager',
                 'how', 'bill_removed', 'approval', :'luis1_id', 'order', test.o482(18), 'beneficiary_name', 'Luis',
                 'by_login', :'cafe_uid')),
               '6a audit discount_not_freed {why: needs_manager, how: bill_removed}');
select test.eq(jsonb_array_length(test.log482('tab_discount_removed', test.o482(18)::text)), 1, '6a and the bill''s tab_discount_removed row');
select test.eq(:'luis1b'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Luis", "pending": false}'::jsonb,
               '6a a new Empleado for Luis: daily_used');
-- b) the same through an old page's call tab_set_discount(bill, null) (W3)
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(19), 'Mesa Vera') ->> 'ok' as b \gset
select test.emp482('vera', 10000, test.o482(19), 10000) as vera1 \gset
select public.tab_set_discount(test.o482(19), null, 7000, 'Caja 1') as q \gset
select test.emp482('vera') ->> 'error' as vera1b \gset
reset role;
select (:'vera1'::jsonb) ->> 'id' as vera1_id \gset
select test.eq(:'q'::jsonb, '{"ok": true, "total": 10000, "discount": 0}'::jsonb, '6b the old page''s × (tab_set_discount null) with nothing paid: removed');
select test.eq(test.day482(:'vera1_id') || '|' || :'vera1b', 'counts|daily_used', '6b the day still counts (daily_used)');
select test.eq((select details ->> 'why' || '|' || (details ->> 'how') from public.audit_log
                 where action = 'discount_not_freed' and target_id = :'vera1_id'), 'needs_manager|bill_removed',
               '6b audit discount_not_freed {why: needs_manager, how: bill_removed}');
-- c) after a payment: a manager's PIN and a reason; the day stays used for good
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(20), 'Mesa Ines') ->> 'ok' as b \gset
select test.emp482('ines', 10000, test.o482(20), 10000) as ines1 \gset
select test.payitem482(test.o482(20)) ->> 'ok' as p \gset
select public.descuento_quitar_cuenta(test.o482(20), 4200, 'Caja 1') as q1 \gset
select public.descuento_quitar_cuenta(test.o482(20), 4200, 'Caja 1', test.staff('ana'), '4826') as q2 \gset
select public.descuento_quitar_cuenta(test.o482(20), 4200, 'Caja 1', test.staff('ana'), '4826', 'cliente se queja') as q3 \gset
select test.emp482('ines') as ines1b \gset
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(((:'ines1'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826') as g \gset
reset role;
select (:'ines1'::jsonb) ->> 'id' as ines1_id \gset
select test.eq(:'q1'::jsonb, '{"ok": false, "error": "needs_pin"}'::jsonb, '6c after one item is paid: without a PIN, needs_pin');
select test.eq(:'q2'::jsonb, '{"ok": false, "error": "missing_reason"}'::jsonb, '6c with Ana''s PIN but no reason: missing_reason');
select test.eq(:'q3'::jsonb, '{"ok": true, "total": 6000, "discount": 1200, "paid": true, "beneficiary": "Ines", "counts": true}'::jsonb,
               '6c with Ana''s PIN and a reason: removed (the paid Latte keeps its 1200), counts: true');
select test.eq(test.day482(:'ines1_id'), 'counts', '6c the day stays used');
select test.eq(test.log482('discount_removed_paid', test.o482(20)::text),
               jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'approval', :'ines1_id',
                 'category', 'empleado', 'beneficiary_name', 'Ines', 'reason', 'cliente se queja', 'discount_kept', 1200,
                 'total_crc', 6000, 'bill', 'Mesa Ines', 'station', 'Caja 1', 'by_login', :'cafe_uid')),
               '6c audit discount_removed_paid names Ana, the approval, the reason and what the paid item kept');
select test.eq(test.log482('discount_not_freed', :'ines1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'Caja 1', 'why', 'paid',
                 'how', 'bill_removed', 'approval', :'ines1_id', 'order', test.o482(20), 'beneficiary_name', 'Ines',
                 'by_login', :'cafe_uid')),
               '6c audit discount_not_freed {why: paid, how: bill_removed}');
select test.eq(:'ines1b'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Ines", "pending": false}'::jsonb,
               '6c a new Empleado for Inés: daily_used');
select test.eq(:'g'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '6c descuento_cupo_devolver after a payment: not_freeable');
select test.eq(test.day482(:'ines1_id'), 'counts', '6c still counts for good');
-- d) a PIN sent with nothing paid is checked but frees nothing: giving the day back is its own logged step
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(21), 'Mesa Jose') ->> 'ok' as b \gset
select test.emp482('jose', 10000, test.o482(21), 10000) as jose1 \gset
select public.descuento_quitar_cuenta(test.o482(21), 7000, 'Caja 1', test.staff('ana'), '1111', 'x') as q0 \gset
select public.descuento_quitar_cuenta(test.o482(21), 7000, 'Caja 1', test.staff('ana'), '4826', 'x') as q \gset
select test.emp482('jose') ->> 'error' as jose1b \gset
reset role;
select (:'jose1'::jsonb) ->> 'id' as jose1_id \gset
select test.eq(:'q0'::jsonb, '{"ok": false, "error": "bad_pin"}'::jsonb, '6d a wrong PIN sent with nothing paid: bad_pin, nothing removed');
select test.eq((:'q'::jsonb) ->> 'ok' || '|' || ((:'q'::jsonb) ->> 'paid') || '|' || ((:'q'::jsonb) ->> 'counts'), 'true|false|true',
               '6d Ana''s right PIN with nothing paid: removed, paid false, counts true');
select test.eq(test.day482(:'jose1_id') || '|' || :'jose1b', 'counts|daily_used', '6d the day still counts: the PIN gave nothing back');
select test.eq(test.trail482(:'jose1_id'), 'discount_not_freed', '6d only discount_not_freed: no discount_freed');
select test.eq(jsonb_array_length(test.log482('discount_removed_paid', test.o482(21)::text)), 0, '6d and no discount_removed_paid');
-- e) taken off with nothing paid, then the bill voided: the void no longer concerns the discount (the bill does not
--    carry it), the day still counts, and a manager can give it back (it was taken off its bill with nothing paid and
--    no discount_removed_paid row names it, proposal §2.5g step 2)
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(35), 'Mesa Rita') ->> 'ok' as b \gset
select test.emp482('rita', 10000, test.o482(35), 10000) as rita1 \gset
select public.descuento_quitar_cuenta(test.o482(35), 7000, 'Caja 1') ->> 'counts' as q \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o482(35), 'walked out') ->> 'ok' as v \gset
select test.emp482('rita') ->> 'error' as rita1b \gset
reset role;
select test.trail482((:'rita1'::jsonb) ->> 'id') as rita_trail, test.day482((:'rita1'::jsonb) ->> 'id') as rita_day \gset
set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(((:'rita1'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826') as g \gset
select test.cafe482(); set role authenticated;
select test.emp482('rita') ->> 'ok' as rita2_ok \gset
reset role;
select (:'rita1'::jsonb) ->> 'id' as rita1_id \gset
select test.eq(:'b' || '|' || ((:'rita1'::jsonb) ->> 'ok') || '|' || :'q' || '|' || :'v' || '|' || :'rita1b',
               'true|true|true|true|daily_used',
               '6e Rita''s discount taken off her bill with nothing paid, then the bill voided: the day still counts');
select test.eq(:'rita_day' || '|' || :'rita_trail', 'counts|discount_not_freed',
               '6e the void wrote nothing about the day (the bill no longer carried the discount): only the removal''s row');
select test.eq(:'g'::jsonb, jsonb_build_object('ok', true, 'how', 'bill_removed', 'approval', :'rita1_id', 'beneficiary', 'Rita'),
               '6e Ana gives the day back: ok, bill_removed (the discount took no money; voiding the bill afterwards changes nothing)');
select test.eq(:'rita2_ok'::text, 'true', '6e then Rita can get one again');

-- 7) descuento_cupo_devolver: every refusal, then the give-back ------------------------------------------------------
-- Luis's approval of 6a (taken off his bill with nothing paid) is the one to give back
select test.login('accountant', 'aal2'); set role authenticated;
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '4826') as g_acct \gset
reset role;
select test.login('owner', 'aal1'); set role authenticated;
select public.descuento_cupo_devolver(:'luis1_id') as g_owner1 \gset
reset role;
select test.cafe482(); set role authenticated;
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '4826') as g_closed \gset
-- Ana opens the owner areas on this till; another sign-in of the café does not get them
select test.unlock(test.staff('ana'), '4826');
select test.session('other-482');
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '4826') as g_other \gset
select test.session('till-482');
select public.descuento_cupo_devolver(:'luis1_id') as g_noone \gset
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '') as g_nopin \gset
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), null) as g_nullpin \gset
select public.descuento_cupo_devolver(:'luis1_id', gen_random_uuid(), '4826') as g_ghost \gset
select public.descuento_cupo_devolver(:'luis1_id', test.staff('marta'), '6173') as g_staff \gset
select public.descuento_cupo_devolver(:'luis1_id', test.p482('gil'), '3918') as g_inactive \gset
select public.descuento_cupo_devolver(:'luis1_id', test.staff('luis'), '5284') as g_self \gset
reset role;
-- a wrong PIN of the picked manager: counted on that person's own 0033 counter, never as a discount code
select count(*) as wrong0 from public.audit_log where action = 'discount_code_wrong' \gset
select failed_pins as ana_fp0 from public.staff where id = test.staff('ana') \gset
set role authenticated;
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '1111') as g_bad \gset
reset role;
select failed_pins as ana_fp1 from public.staff where id = test.staff('ana') \gset
select test.cafe482(); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
-- Hal: five wrong PINs here lock him at his own 0033 counter; then his right PIN answers locked
select public.descuento_cupo_devolver(:'luis1_id', test.p482('hal'), '0000') ->> 'error' as h1 \gset
select public.descuento_cupo_devolver(:'luis1_id', test.p482('hal'), '0001') ->> 'error' as h2 \gset
select public.descuento_cupo_devolver(:'luis1_id', test.p482('hal'), '0002') ->> 'error' as h3 \gset
select public.descuento_cupo_devolver(:'luis1_id', test.p482('hal'), '0003') ->> 'error' as h4 \gset
select public.descuento_cupo_devolver(:'luis1_id', test.p482('hal'), '0004') ->> 'error' as h5 \gset
select public.descuento_cupo_devolver(:'luis1_id', test.p482('hal'), '3919') as g_locked \gset
reset role;
select test.eq(:'g_acct'::jsonb, '{"ok": false, "error": "no_account"}'::jsonb, '7 the accountant login: no_account');
select test.eq(:'g_owner1'::jsonb, '{"ok": false, "error": "owner_only"}'::jsonb,
               '7 the owner login without the phone code and no unlock: owner_only');
select test.eq(:'g_closed'::jsonb, '{"ok": false, "error": "owner_only"}'::jsonb,
               '7 the café login with the owner areas closed: owner_only, even with a right manager PIN');
select test.eq(:'g_other'::jsonb, '{"ok": false, "error": "owner_only"}'::jsonb,
               '7 Ana''s unlock belongs to the sign-in that made it: from another sign-in, owner_only');
select test.eq(:'g_noone'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb, '7 owner areas open, nobody picked: unknown_staff');
select test.eq(:'g_nopin'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb, '7 Ana picked with an empty PIN: unknown_staff');
select test.eq(:'g_nullpin'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb, '7 Ana picked with no PIN: unknown_staff');
select test.eq(:'g_ghost'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb, '7 a person who does not exist: unknown_staff');
select test.eq(:'g_staff'::jsonb, '{"ok": false, "error": "not_manager"}'::jsonb, '7 Marta (staff) picked with her own PIN: not_manager');
select test.eq(:'g_inactive'::jsonb, '{"ok": false, "error": "inactive"}'::jsonb, '7 Gil (an inactive manager): inactive');
select test.eq(:'g_self'::jsonb, '{"ok": false, "error": "not_self"}'::jsonb,
               '7 Luis picked for his own day, even with his right PIN: not_self (never the beneficiary)');
select test.eq(:'g_bad'::jsonb, '{"ok": false, "error": "bad_pin"}'::jsonb, '7 Ana with a wrong PIN: bad_pin');
select test.eq(:'ana_fp1'::int, :'ana_fp0'::int + 1, '7 the wrong PIN counts on Ana''s own failed_pins (0033)');
select test.eq((select count(*) from public.audit_log where action = 'discount_code_wrong'), :'wrong0'::bigint,
               '7 and never as a discount code (no discount_code_wrong row)');
select test.eq(:'h1' || ',' || :'h2' || ',' || :'h3' || ',' || :'h4' || ',' || :'h5', 'bad_pin,bad_pin,bad_pin,bad_pin,bad_pin',
               '7 Hal with five wrong PINs: bad_pin each time');
select test.eq(:'g_locked'::jsonb, '{"ok": false, "error": "locked"}'::jsonb, '7 then Hal''s right PIN: locked (his own 0033 lock applies)');
select test.eq((select failed_pins = 5 and locked_until > now() from public.staff where id = test.p482('hal')), true,
               '7 Hal is locked at his own counter: 5 tries, locked_until set');
select test.eq((select count(*)::int from public.audit_log where action = 'pin_locked' and manager_id = test.p482('hal')), 1,
               '7 and that lock is logged (pin_locked)');
select test.eq(test.day482(:'luis1_id') || '|' || jsonb_array_length(test.log482('discount_freed', :'luis1_id')), 'counts|0',
               '7 none of those refusals gave Luis''s day back or wrote discount_freed');
-- Ana with her own PIN gives it back
select test.cafe482(); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '4826', 'Reloj') as g_ok \gset
select public.descuento_cupo_devolver(:'luis1_id', test.staff('ana'), '4826', 'Reloj') as g_again \gset
select test.cafe482(); set role authenticated;
select test.emp482('luis') as luis2 \gset
reset role;
select test.eq(:'g_ok'::jsonb, jsonb_build_object('ok', true, 'how', 'bill_removed', 'approval', :'luis1_id', 'beneficiary', 'Luis'),
               '7 Ana with her PIN: ok, bill_removed');
select test.eq(test.day482(:'luis1_id'), 'bill_removed', '7 Luis''s approval is freed as bill_removed');
select test.eq((select freed_at from public.discount_approvals where id = :'luis1_id'), now(), '7 freed_at = when it was given back');
select test.eq(test.log482('discount_freed', :'luis1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'how', 'bill_removed',
                 'approval', :'luis1_id', 'order', test.o482(18), 'beneficiary_name', 'Luis', 'by_login', :'cafe_uid',
                 'station', 'Reloj', 'phone_code', false)),
               '7 audit discount_freed names Ana (who confirmed), the bill and Luis');
select test.eq(:'g_again'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '7 giving it back twice: not_freeable');
select test.eq((:'luis2'::jsonb) ->> 'ok', 'true', '7 then a new Empleado for Luis is approved');
select test.ok((:'luis2'::jsonb) -> 'prior' = 'null'::jsonb, '7 and its answer has no prior (a give-back is not a void)');
-- the owner with the phone code: no PIN, the audit row names the owner
select test.login('owner', 'aal2'); set role authenticated;
select public.descuento_cupo_devolver(:'marta1_id') as g_code \gset
reset role;
select test.cafe482(); set role authenticated;
select test.emp482('marta') ->> 'ok' as marta2_ok \gset
reset role;
select test.eq(:'g_code'::jsonb, jsonb_build_object('ok', true, 'how', 'bill_cancelled', 'approval', :'marta1_id', 'beneficiary', 'Marta'),
               '7 the owner login with the phone code (aal2), no PIN: Marta''s cancelled bill gives the day back');
select test.eq(test.day482(:'marta1_id'), 'bill_cancelled', '7 freed as bill_cancelled');
select test.eq(test.log482('discount_freed', :'marta1_id'),
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', 'owner login · owner@test.local',
                 'how', 'bill_cancelled', 'approval', :'marta1_id', 'order', test.o482(14), 'beneficiary_name', 'Marta',
                 'by_login', '0e000000-0000-4000-8000-000000000002', 'station', null, 'phone_code', true)),
               '7 audit discount_freed names the owner''s login (phone code)');
select test.eq(:'marta2_ok'::text, 'true', '7 a new Empleado for Marta is approved');
-- the owner's PIN typed on a tablet opens the owner areas there, but it is not the phone code: a person is still picked
select test.cafe482(); set role authenticated;
select test.unlock(test.staff('dueno'), '7391');
select public.descuento_cupo_devolver(:'jose1_id') as g_tablet \gset
select public.descuento_cupo_devolver(:'jose1_id', test.staff('dueno'), '7391', 'Reloj') as g_dueno \gset
reset role;
select test.eq(:'g_tablet'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb,
               '7 the café login with the owner''s unlock and nobody picked: unknown_staff (an owner PIN on a tablet is not the phone code)');
select test.eq((:'g_dueno'::jsonb) ->> 'ok' || '|' || test.day482(:'jose1_id'), 'true|bill_removed',
               '7 Dueño picked from the list with his own PIN gives Jose''s day back');
select test.eq((select jsonb_build_object('manager_id', manager_id, 'manager_name', manager_name, 'phone_code', details -> 'phone_code')
                  from public.audit_log where action = 'discount_freed' and target_id = :'jose1_id'),
               jsonb_build_object('manager_id', test.staff('dueno'), 'manager_name', 'Dueño', 'phone_code', false),
               '7 and the audit row names Dueño, without the phone code');
-- never the beneficiary: Ana as beneficiary (the owner's code authorizes her), taken off a bill, then Ana picked
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(22), 'Mesa Ana') ->> 'ok' as b \gset
select public.descuento_autorizar('empleado', '7391', 10000, '4826', null, test.o482(22), 10000, null, 'Caja 1') as ana1 \gset
select public.descuento_quitar_cuenta(test.o482(22), 7000, 'Caja 1') ->> 'counts' as q \gset
select test.unlock(test.staff('ana'), '4826');
reset role;
select failed_pins as ana_fp2 from public.staff where id = test.staff('ana') \gset
set role authenticated;
select public.descuento_cupo_devolver(((:'ana1'::jsonb) ->> 'id')::uuid, test.staff('ana'), '9999') as g_ana_bad \gset
select public.descuento_cupo_devolver(((:'ana1'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826') as g_ana \gset
reset role;
select failed_pins as ana_fp3 from public.staff where id = test.staff('ana') \gset
select (:'ana1'::jsonb) ->> 'id' as ana1_id \gset
select test.eq((:'ana1'::jsonb) ->> 'beneficiary' || '|' || ((:'ana1'::jsonb) ->> 'role') || '|' || :'q', 'Ana|owner|true',
               '7 Ana''s Empleado on a bill, authorized by Dueño''s code, taken off with nothing paid (counts)');
select test.eq(:'g_ana_bad'::jsonb, '{"ok": false, "error": "not_self"}'::jsonb, '7 Ana picked for her own day with a wrong PIN: not_self');
select test.eq(:'g_ana'::jsonb, '{"ok": false, "error": "not_self"}'::jsonb, '7 and with her right PIN: not_self');
select test.eq(:'ana_fp3'::int, :'ana_fp2'::int, '7 not_self is answered before the PIN is tested (Ana''s failed_pins unchanged)');
select test.eq(test.day482(:'ana1_id'), 'counts', '7 Ana''s day still counts');
select test.cafe482(); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(:'ana1_id', test.p482('bea'), '3917') as g_bea \gset
reset role;
select test.eq(:'g_bea' ::jsonb ->> 'ok' || '|' || test.day482(:'ana1_id'), 'true|bill_removed',
               '7 another manager (Bea, picked on Ana''s unlock) gives it back');
select test.eq((select manager_id = test.p482('bea') and manager_name = 'Bea' from public.audit_log
                 where action = 'discount_freed' and target_id = :'ana1_id'), true, '7 and the audit row names Bea, not Ana');

-- 8) not_freeable and day_over: only a discount that took no money gives the day back, and only today ------------------
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(23), 'Mesa Mia') ->> 'ok' as b \gset
select test.emp482('mia', 10000, test.o482(23), 10000) as mia1 \gset
select public.descuento_quitar_cuenta(test.o482(23), 7000, 'Caja 1') ->> 'counts' as q \gset
reset role;
select (:'mia1'::jsonb) ->> 'id' as mia1_id \gset
update public.discount_approvals set cr_day = cr_day - 1 where id = :'mia1_id';
-- a Local taken off a bill with nothing paid
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(24), 'Mesa Local') ->> 'ok' as b \gset
select public.descuento_autorizar('local', '4826', 10000, null, null, test.o482(24), 10000, null, 'Caja 1') as loc4 \gset
select public.descuento_quitar_cuenta(test.o482(24), 9000, 'Caja 1') as qloc \gset
select test.unlock(test.staff('ana'), '4826');
reset role;
select failed_pins as ana_fp4 from public.staff where id = test.staff('ana') \gset
set role authenticated;
select public.descuento_cupo_devolver(:'olga1_id', test.staff('ana'), '9999') as nf_used \gset
select public.descuento_cupo_devolver(:'pablo1_id', test.staff('ana'), '9999') as nf_void \gset
select public.descuento_cupo_devolver(:'bea1_id', test.staff('ana'), '9999') as nf_selfvoid \gset
select public.descuento_cupo_devolver(:'walter1_id', test.staff('ana'), '9999') as nf_voidparts \gset
select public.descuento_cupo_devolver(:'yago1_id', test.staff('ana'), '9999') as nf_crafted \gset
select public.descuento_cupo_devolver(:'iris2_id', test.staff('ana'), '9999') as nf_unused \gset
select public.descuento_cupo_devolver(:'zoe1_id', test.staff('ana'), '9999') as nf_onbill \gset
select public.descuento_cupo_devolver(((:'loc4'::jsonb) ->> 'id')::uuid, test.staff('ana'), '9999') as nf_local \gset
select public.descuento_cupo_devolver(gen_random_uuid(), test.staff('ana'), '9999') as nf_ghost \gset
select public.descuento_cupo_devolver(:'mia1_id', test.staff('ana'), '9999') as nf_day \gset
reset role;
select failed_pins as ana_fp5 from public.staff where id = test.staff('ana') \gset
set role authenticated;
select public.descuento_cupo_devolver(:'mia1_id', test.staff('ana'), '4826') as nf_day2 \gset
reset role;
select test.eq((:'loc4'::jsonb) ->> 'ok' || '|' || ((:'qloc'::jsonb) ->> 'ok') || '|' || ((:'qloc'::jsonb) ? 'counts')::text, 'true|true|false',
               '8 a Local on a bill, taken off with nothing paid: removed, no counts key (no day)');
select test.eq(:'nf_used'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '8 an approval still on its sale (Olga): not_freeable');
select test.eq(:'nf_void'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '8 an approval already freed by a void (Pablo): not_freeable');
select test.eq(:'nf_selfvoid'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb,
               '8 a sale its beneficiary voided (Bea): not_freeable (a void is not a give-back)');
select test.eq(:'nf_voidparts'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb,
               '8 a voided bill with a paid part (Walter): not_freeable');
select test.eq(:'nf_crafted'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '8 the order inserted already voided (Yago): not_freeable');
select test.eq(:'nf_unused'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb,
               '8 an approval never used (Iris): not_freeable (the page lets it go, or it expires)');
select test.eq(:'nf_onbill'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '8 an approval still on an open bill (Zoe): not_freeable');
select test.eq(:'nf_local'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '8 a Local (no day to give back): not_freeable');
select test.eq(:'nf_ghost'::jsonb, '{"ok": false, "error": "not_freeable"}'::jsonb, '8 an approval that does not exist: not_freeable');
select test.eq(:'nf_day'::jsonb, '{"ok": false, "error": "day_over"}'::jsonb,
               '8 Mía''s approval taken off a bill, with its day moved to yesterday: day_over');
select test.eq(:'nf_day2'::jsonb, '{"ok": false, "error": "day_over"}'::jsonb, '8 day_over also with a right PIN');
select test.eq(:'ana_fp5'::int, :'ana_fp4'::int,
               '8 not_freeable and day_over are answered before any PIN is tested (Ana''s failed_pins unchanged by ten wrong PINs)');
select test.eq(test.day482(:'mia1_id'), 'counts', '8 Mía''s past day is not given back');

-- 9) a give-back with a discount_daily_twice sale of the same day: that sale takes the day back --------------------------
select test.cafe482(); set role authenticated;
select test.emp482('leo') as leo1 \gset
select public.descuento_liberar(((:'leo1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.bill482(test.o482(25), 'Mesa Leo') ->> 'ok' as b \gset
select test.emp482('leo', 10000, test.o482(25), 10000) as leo2 \gset
select test.sale482(test.o482(26), :'leo1') ->> 'ok' as s \gset
select public.descuento_quitar_cuenta(test.o482(25), 7000, 'Caja 1') ->> 'counts' as q \gset
select test.unlock(test.staff('ana'), '4826');
select public.descuento_cupo_devolver(((:'leo2'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826') ->> 'how' as g \gset
select test.cafe482(); set role authenticated;
select test.emp482('leo') as leo3 \gset
reset role;
select (:'leo1'::jsonb) ->> 'id' as leo1_id \gset
select (:'leo2'::jsonb) ->> 'id' as leo2_id \gset
select test.eq(:'rel' || '|' || :'b' || '|' || ((:'leo2'::jsonb) ->> 'ok') || '|' || :'s' || '|' || :'q',
               'true|true|true|true|true',
               '9 Leo: approval 1 let go; approval 2 on a bill; the queued sale on approval 1 arrives; approval 2 taken off (counts)');
select test.eq((select 'discount_daily_twice' = any (flags) from public.orders where id = test.o482(26)), true,
               '9 the queued sale was flagged discount_daily_twice');
select test.eq(:'g' || '|' || test.day482(:'leo2_id'), 'bill_removed|bill_removed', '9 Ana gives approval 2''s day back');
select test.eq(test.day482(:'leo1_id'), 'counts', '9 and approval 1, on a live sale, takes the day back');
select test.eq(:'leo3'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Leo", "pending": false}'::jsonb,
               '9 so the give-back never opens a third discount for Leo: daily_used');

-- 10) item 12: no fragile triggers. A «Pay later» ticket carrying an Empleado discount: the kitchen, an add, a payment
--     on a later day, a void and a cancel all go through; the day's trigger fires only on its own transitions ---------
select test.cafe482(); set role authenticated;
select test.emp482('ruth') as ruth1 \gset
select test.sale482(test.o482(27), :'ruth1', false) ->> 'ok' as s \gset
update public.orders set status = 'preparing', accepted_at = now() where id = test.o482(27);
update public.orders set status = 'ready', ready_at = now() where id = test.o482(27);
select public.tab_add_items(test.o482(27), jsonb_build_array(jsonb_build_object('menu_item_id', :'latte', 'qty', 1))) as a \gset
reset role;
select (:'ruth1'::jsonb) ->> 'id' as ruth1_id \gset
select test.eq(:'s'::text, 'true', '10 Ruth''s «Pay later» kitchen ticket is recorded with her Empleado discount');
select test.eq((select status from public.orders where id = test.o482(27)), 'preparing',
               '10 the till moved it through the kitchen (preparing, ready) and an added Latte started a new round (preparing)');
select test.eq((:'a'::jsonb) ->> 'ok', 'true', '10 tab_add_items on the discounted ticket: ok');
select test.eq(test.day482(:'ruth1_id') || '|' || test.trail482(:'ruth1_id'), 'counts|',
               '10 none of those updates fired the day''s trigger (the day counts, nothing logged)');
select test.cafe482(); set role authenticated;
select public.manager_void_order(test.staff('ana'), '4826', test.o482(27), 'walked out') ->> 'ok' as v \gset
reset role;
select test.eq(:'v' || '|' || test.day482(:'ruth1_id') || '|' || test.trail482(:'ruth1_id'), 'true|void|discount_freed',
               '10 manager_void_order on it: the void stands and frees the day (discount_freed)');
-- tab_pay on a later day: the payment moves the ticket to today and closes it; the trigger does not fire
select test.cafe482(); set role authenticated;
select test.emp482('dani') as dani1 \gset
select test.sale482(test.o482(28), :'dani1', false) ->> 'ok' as s \gset
reset role;
select (:'dani1'::jsonb) ->> 'id' as dani1_id \gset
update public.orders set created_at = created_at - interval '1 day' where id = test.o482(28);
select test.cafe482(); set role authenticated;
select public.tab_pay(test.o482(28), 'cash_crc', null, null, 'Caja 1') as p \gset
select test.emp482('dani') ->> 'error' as dani1b \gset
reset role;
select test.eq((:'p'::jsonb) ->> 'closed' || '|' || :'s', 'true|true', '10 Dani''s ticket, rung yesterday, is paid today (tab_pay): closed');
select test.eq((select paid and status = 'done' and created_at = now() from public.orders where id = test.o482(28)), true,
               '10 it belongs to today and is done');
select test.eq(test.day482(:'dani1_id') || '|' || test.trail482(:'dani1_id') || '|' || :'dani1b', 'counts||daily_used',
               '10 the payment did not fire the trigger: the day counts, nothing logged (daily_used)');
-- a room bill closed at the bar with finish_order: done and paid, the trigger does not fire
select test.cafe482(); set role authenticated;
select test.bill482(test.o482(36), 'Hab Teo', 'room') ->> 'ok' as b \gset
select test.emp482('teo', 10000, test.o482(36), 10000) as teo1 \gset
select public.finish_order(test.o482(36), 'card') as f \gset
select test.emp482('teo') ->> 'error' as teo1b \gset
reset role;
select (:'teo1'::jsonb) ->> 'id' as teo1_id \gset
select test.eq(:'b' || '|' || ((:'teo1'::jsonb) ->> 'total') || '|' || (:'f'::jsonb ->> 'ok')
               || '|' || (select status || ',' || paid from public.orders where id = test.o482(36)), 'true|7000|true|done,true',
               '10 Teo''s room bill with his discount is closed with finish_order: done and paid');
select test.eq(test.day482(:'teo1_id') || '|' || test.trail482(:'teo1_id') || '|' || :'teo1b', 'counts||daily_used',
               '10 the day counts, nothing logged (the status change to done does not fire the trigger)');
-- cancel_unpaid_order on a «Pay later» ticket: cancelled, the day counts until a give-back
select test.cafe482(); set role authenticated;
select test.emp482('elsa') as elsa1 \gset
select test.sale482(test.o482(29), :'elsa1', false) ->> 'ok' as s \gset
select public.cancel_unpaid_order(test.o482(29)) as c \gset
reset role;
select (:'elsa1'::jsonb) ->> 'id' as elsa1_id \gset
select test.eq(:'s' || '|' || (:'c'::jsonb ->> 'ok') || '|' || test.day482(:'elsa1_id'), 'true|true|counts',
               '10 cancel_unpaid_order on Elsa''s «Pay later» ticket: cancelled, the day still counts');
select test.eq((select details ->> 'why' || '|' || (details ->> 'how') from public.audit_log
                 where action = 'discount_not_freed' and target_id = :'elsa1_id'), 'needs_manager|bill_cancelled',
               '10 audit discount_not_freed {why: needs_manager, how: bill_cancelled}');
-- a forced error inside the trigger (a test-only broken approval row): the void still commits, discount_trigger_error.
-- The case runs in a savepoint (it changes the table's rule); its values are captured, then rolled back, then asserted
-- (as 270_production_followup does). Fede's approval of 1 (still unused) goes on a «Pay later» ticket
select test.cafe482(); set role authenticated;
select test.sale482(test.o482(30), :'fede1', false) ->> 'ok' as s \gset
reset role;
select (:'fede1'::jsonb) ->> 'id' as fede1_id \gset
savepoint broken;
select pg_get_constraintdef(oid) as rule from pg_constraint where conname = 'discount_approvals_categoria' \gset
alter table public.discount_approvals drop constraint discount_approvals_categoria;
update public.discount_approvals set amount_crc = amount_crc + 1 where id = :'fede1_id';
alter table public.discount_approvals add constraint discount_approvals_categoria :rule not valid;
select test.cafe482(); set role authenticated;
select public.manager_void_order(test.staff('ana'), '4826', test.o482(30), 'walked out') as bv \gset
reset role;
select (select (voided_at is not null)::text from public.orders where id = test.o482(30)) as bv_voided,
       test.day482(:'fede1_id') as bv_day,
       test.log482('discount_trigger_error', test.o482(30)::text) as bv_err,
       jsonb_array_length(test.log482('discount_freed', :'fede1_id')) as bv_freed \gset
rollback to savepoint broken;
select test.eq(:'s'::text, 'true', '10 Fede''s «Pay later» ticket carries his Empleado discount');
select test.eq((:'bv'::jsonb) ->> 'ok' || '|' || :'bv_voided', 'true|true',
               '10 with the approval row broken, manager_void_order still answers ok and the order is voided');
select test.eq(:'bv_day' || '|' || :'bv_freed', 'counts|0', '10 the failed update left the day as it was (no discount_freed)');
select test.eq(:'bv_err'::jsonb,
               jsonb_build_array(jsonb_build_object('manager_id', null, 'manager_name', null, 'order', test.o482(30),
                 'approval', :'fede1_id', 'sqlstate', '23514')),
               '10 audit discount_trigger_error {order, approval, sqlstate} (the broken row''s check violation)');
select test.eq((select convalidated from pg_constraint where conname = 'discount_approvals_categoria'), true,
               '10 after the savepoint the table''s rule is the real one again (validated)');
select test.eq((select amount_crc from public.discount_approvals where id = :'fede1_id'), 3000, '10 and the approval row is whole again');

-- 11) a refund after the close changes none of the trigger's columns: the day stays used -------------------------------
-- (last: closing today's register stops voids of today's paid sales)
select test.cafe482(); set role authenticated;
select test.emp482('lia') as lia1 \gset
select test.sale482(test.o482(31), :'lia1') ->> 'ok' as s \gset
reset role;
select (:'lia1'::jsonb) ->> 'id' as lia1_id \gset
insert into public.register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name)
  values (public.cr_today(), 'Ana', 50000, now(), 'Ana');
select test.cafe482(); set role authenticated;
select public.manager_refund_order(test.staff('ana'), '4826', test.o482(31), 'cliente') as rf \gset
select test.emp482('lia') as lia2 \gset
reset role;
select test.eq(:'s' || '|' || ((:'rf'::jsonb) ->> 'ok'), 'true|true', '11 Lía''s sale is refunded after the register closed');
select test.eq((select refunded_at is not null and voided_at is null from public.orders where id = test.o482(31)), true,
               '11 the sale is marked refunded, not voided');
select test.eq(test.day482(:'lia1_id') || '|' || test.trail482(:'lia1_id'), 'counts|', '11 the day stays used, nothing logged about it');
select test.eq(:'lia2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Lia", "pending": false}'::jsonb,
               '11 a new Empleado for Lía: daily_used');

-- 12) the report shows each outcome with its status (proposal §2.5e) ---------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.descuentos_informe(public.cr_today(), public.cr_today()) as rep \gset
reset role;
select test.eq((:'rep'::jsonb) ->> 'ok', 'true', '12 descuentos_informe for today, as the owner with the phone code');
with want(id, status) as (values
  (:'eva1_id', 'released'), (:'iris1_id', 'expired'), (:'olga1_id', 'used'), (:'raul1_id', 'used'), (:'sara1_id', 'used'),
  (:'pablo1_id', 'voided_freed'), (:'ximena1_id', 'voided_freed'), (:'bea1_id', 'voided_counts'), (:'walter1_id', 'voided_counts'),
  (:'yago1_id', 'voided_counts'), (:'loc3_id', 'voided'), (:'luis1_id', 'removed'), (:'vera1_id', 'removed_counts'),
  (:'jose1_id', 'removed'), (:'ines1_id', 'removed_paid'), (:'marta1_id', 'bill_cancelled'), (:'nora1_id', 'bill_cancelled'),
  (:'omar1_id', 'bill_cancelled_counts'), (:'elsa1_id', 'bill_cancelled_counts'), (:'zoe1_id', 'open_bill'), (:'lia1_id', 'refunded'),
  (:'ana1_id', 'removed'), (:'leo1_id', 'used'), (:'leo2_id', 'removed'), (:'ruth1_id', 'voided_freed'), (:'dani1_id', 'used'),
  (:'tomas1_id', 'used'), (:'uma1_id', 'used'), (:'teo1_id', 'used'), (:'gus2_id', 'pending'),
  (:'pia1_id', 'used_unverified'), (:'nico1_id', 'used'), (:'nico2_id', 'released'), (:'vale1_id', 'used'), (:'vale2_id', 'expired')),
got as (select r ->> 'id' as id, r ->> 'status' as status from jsonb_array_elements((:'rep'::jsonb) -> 'rows') r)
select test.eq((select string_agg(coalesce(p.name, w.id) || ':' || coalesce(g.status, 'missing'), ', ' order by w.id)
                  from want w left join got g on g.id = w.id
                  left join public.discount_approvals a on a.id = w.id::uuid left join test.t482_people p on p.id = a.beneficiary_id),
               (select string_agg(coalesce(p.name, w.id) || ':' || w.status, ', ' order by w.id)
                  from want w left join public.discount_approvals a on a.id = w.id::uuid left join test.t482_people p on p.id = a.beneficiary_id),
               '12 each approval of this file has its lifecycle''s status: released, expired, used, voided_freed, voided_counts, '
               'voided, removed, removed_counts, removed_paid, bill_cancelled, bill_cancelled_counts, open_bill, refunded');

-- 13) across the whole file -------------------------------------------------------------------------------------------
select test.eq((select count(*)::int from public.audit_log where action = 'discount_code_wrong'), 0,
               '13 no refusal of the day''s lifecycle (daily_used, give-back PINs) was counted as a wrong discount code');
select test.eq((select count(*)::int from public.audit_log where action in ('discount_trigger_error', 'discount_check_error')), 0,
               '13 outside the forced case no trigger and no sale check ever failed');
select test.cafe482(); set role authenticated;
select public.descuento_estado() -> 'till' ->> 'state' as st \gset
reset role;
select test.eq(:'st'::text, 'ok', '13 the till is still ok (nothing in this file cost it a wait)');
select test.eq((select count(*)::int from public.audit_log l, jsonb_each_text(l.details) kv, test.t482_people p
                 where (l.action like 'discount%' or l.action = 'tab_discount_removed') and kv.value = p.pin), 0,
               '13 no audit row of the day''s lifecycle holds a PIN as a value');
select test.eq((select count(*)::int from public.audit_log l, test.t482_people p
                 where l.action like 'discount%' and (l.summary ~ ('\m' || p.pin || '\M') or l.manager_name ~ ('\m' || p.pin || '\M'))), 0,
               '13 nor in a summary or a name');

select test.done();
rollback;
