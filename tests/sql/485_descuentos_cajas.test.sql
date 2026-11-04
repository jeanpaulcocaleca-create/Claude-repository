-- Migration 0038 (D-065): the failed-attempt control of the discount codes, «Cajas registradas en puestos» (the owner's
-- adjustment 2; mecanismo-intentos.md §1-§13.1 with the corrections of its §16; build plan L1, L3 and L5; api-0038 §3,
-- §4.1-4.2, §4.7-4.11, §7, §8). Only a sign-in that a manager registered on that very device tests codes: anything else
-- is refused before any code is compared, and nothing is counted. Three places, each with its own wrong-code count that
-- stays with the place whatever device holds it: 2 free mistakes an hour, then 30 s, 1, 5 and 10 minutes, and 12 in 24
-- hours stop that till (never another) until the 12th most recent is 24 hours old or a manager resumes the place (once
-- per place and twice per café in 24 h; the owner's SQL tool outside the caps). A registered tablet comes back to its
-- own place with its device key after any new sign-in, with no PIN and no count. Per-person caps (2 places held, 3
-- removals or replacements and 6 registrations in 24 h) and nothing café-wide that one person can use up. A person
-- locked at the name-picked PIN boxes (0033) is accepted at the window, which never reads, resets or counts a 0033
-- counter and never opens the owner areas. No PIN, code, key or raw sign-in id is stored in the log or answered. Built
-- without descuento_caja_cerrar (L1): a signed-out tablet's row stays live and its key rebinds it. Everything goes
-- through the real functions as the café login (authenticated, with a session_id); a short simulation runs as an
-- assertion (§12). From the review: a long argument costs no more work than a short one, so no statement timeout tells a
-- wrong code from a right one (§16); a lost reply never strands a tablet without its key (§17); the windows keep
-- rolling past a stop, never a fresh 12 (§18). The two-connection checks of mecanismo §13.2 are in
-- tests/sql/concurrency-descuentos.sh.
begin;

-- people besides the seed (Ana manager 4826, Luis 5284 and Marta 6173 staff, Dueño owner 7391): Bea and Ciro,
-- managers, and Rosa and Teo, staff. Test PINs only (3917, 3918, 8521, 8522); cost 4 keeps each code's single bcrypt
-- pass over every active PIN short. Pablo (staff, Marta's PIN: a code shared by two people, D-053) is added in §4
insert into public.staff (id, name, role, active, pin_hash) values
  ('0b485000-0000-4000-8000-000000000001', 'Bea', 'manager', true, extensions.crypt('3917', extensions.gen_salt('bf', 4))),
  ('0b485000-0000-4000-8000-000000000002', 'Rosa', 'staff', true, extensions.crypt('8521', extensions.gen_salt('bf', 4))),
  ('0b485000-0000-4000-8000-000000000003', 'Teo', 'staff', true, extensions.crypt('8522', extensions.gen_salt('bf', 4))),
  ('0b485000-0000-4000-8000-000000000005', 'Ciro', 'manager', true, extensions.crypt('3918', extensions.gen_salt('bf', 4)));
create function test.p485(n text) returns uuid language sql immutable as $$
  select case n when 'bea' then '0b485000-0000-4000-8000-000000000001'::uuid
                when 'rosa' then '0b485000-0000-4000-8000-000000000002'::uuid
                when 'teo' then '0b485000-0000-4000-8000-000000000003'::uuid
                when 'pablo' then '0b485000-0000-4000-8000-000000000004'::uuid
                when 'ciro' then '0b485000-0000-4000-8000-000000000005'::uuid
                else test.staff(n) end $$;
create function test.pin485(n text) returns text language sql immutable as $$
  select case n when 'ana' then '4826' when 'luis' then '5284' when 'marta' then '6173' when 'dueno' then '7391'
                when 'bea' then '3917' when 'ciro' then '3918' when 'rosa' then '8521' when 'teo' then '8522'
                when 'pablo' then '6173' end $$;
\set cafe 'c0000000-0000-4000-8000-000000000001'
\set owner_label 'owner login · owner@test.local'

-- the devices of this file: their current sign-in (session id) and the device key the page keeps (localStorage
-- 'hg-disc-till'); every key the server ever returned (to prove none is stored or logged); every window answer
create table test.devs485 (dev text primary key, sess text not null, key text);
create table test.allkeys485 (key text primary key);
create table test.ans485 (n serial primary key, sess text, j jsonb, ck timestamptz not null default clock_timestamp());
create table test.ev485 (scen text, step int, who text, res text);
grant all on test.devs485, test.allkeys485, test.ans485, test.ev485 to authenticated;
grant usage on sequence test.ans485_n_seq to authenticated;
create function test.s485(p_dev text) returns text language sql stable as $$ select sess from test.devs485 where dev = p_dev $$;

-- a device as the café login: test.login resets the claims and the unlock header, test.session gives the sign-in its id
-- (null: a token without session_id)
create function test.dev485(p_sess text) returns void language plpgsql as $$
begin
  perform test.login('cafe');
  if p_sess is not null then perform test.session(p_sess); end if;
end $$;
-- the window's call on that device, as pos.html sends it (Local at ₡1000 unless told otherwise); every answer is kept
create function test.c485(p_sess text, p_cat text, p_pin text, p_emp text default null, p_comp text default null,
                          p_station text default 'Caja 485', p_sub int default 1000, p_bill uuid default null,
                          p_expect int default null, p_req uuid default null) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform test.dev485(p_sess);
  r := public.descuento_autorizar(p_cat, p_pin, p_sub, p_emp, p_comp, p_bill, p_expect, p_req, p_station);
  insert into test.ans485 (sess, j) values (p_sess, r);
  return r;
end $$;
-- on that device a person opens the owner areas with their PIN (0033: the unlock is bound to this sign-in)
create function test.open485(p_sess text, p_who text) returns void language plpgsql as $$
begin
  perform test.dev485(p_sess);
  perform test.unlock(test.p485(p_who), test.pin485(p_who));
end $$;
-- Reloj de marcas › Bitácora › «Registrar este dispositivo para descuentos» on that device, with p_who's unlock there;
-- the page keeps the key it gets
create function test.reg485(p_dev text, p_sess text, p_who text, p_station text default null, p_repl uuid default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform test.open485(p_sess, p_who);
  r := public.descuento_caja_registrar(p_station, p_repl);
  if r ? 'key' then
    insert into test.devs485 values (p_dev, p_sess, r ->> 'key') on conflict (dev) do update set sess = excluded.sess, key = excluded.key;
    insert into test.allkeys485 values (r ->> 'key') on conflict do nothing;
  end if;
  return r;
end $$;
-- a new sign-in on a device that holds its key: the page calls descuento_caja_volver and keeps the new key
create function test.vol485(p_dev text, p_sess text, p_station text default null) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform test.dev485(p_sess);
  r := public.descuento_caja_volver((select key from test.devs485 where dev = p_dev), p_station);
  if r ? 'key' then
    update test.devs485 set sess = p_sess, key = r ->> 'key' where dev = p_dev;
    insert into test.allkeys485 values (r ->> 'key') on conflict do nothing;
  end if;
  return r;
end $$;
-- descuento_caja_volver with a given key on a given sign-in
create function test.volk485(p_sess text, p_key text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform test.dev485(p_sess);
  r := public.descuento_caja_volver(p_key);
  if r ? 'key' then insert into test.allkeys485 values (r ->> 'key') on conflict do nothing; end if;
  return r;
end $$;

-- readers and time travel, as the test superuser (definer), so the café login can use them between its own calls
create function test.back485(d interval) returns void language sql security definer as $$ select test.back(d) $$;
-- every window moved 25 hours back: each place calm again, every per-person and resume cap spent long ago
create function test.calm485() returns void language sql security definer as $$ select test.back(interval '25 hours') $$;
-- a clean start: every live till ended by the owner's tool function (every key spent), then every window calm
create function test.fresh485() returns void language sql security definer as $$
  select public._discount_tills_end_all('t485 fixture reset'); select test.back(interval '25 hours') $$;
create function test.endall485(p_by text) returns jsonb language sql security definer as $$
  select public._discount_tills_end_all(p_by) $$;
create function test.tid485(p_sess text) returns uuid language sql stable security definer as $$
  select id from public.discount_tills where session_id = p_sess and ended_at is null $$;
create function test.slot485(p_sess text) returns int language sql stable security definer as $$
  select slot::int from public.discount_tills where session_id = p_sess and ended_at is null $$;
create function test.till485(p_id uuid) returns jsonb language sql stable security definer as $$
  select to_jsonb(t) from public.discount_tills t where t.id = p_id $$;
-- a sign-in's row: the live one, else the one that ended last
create function test.rowof485(p_sess text) returns jsonb language sql stable security definer as $$
  select to_jsonb(t) from public.discount_tills t where t.session_id = p_sess
   order by (t.ended_at is null) desc, t.ended_at desc limit 1 $$;
create function test.lastat485(p_act text) returns timestamptz language sql stable security definer as $$
  select at from public.audit_log where action = p_act order by id desc limit 1 $$;
create function test.wrong485(p_slot int) returns int language sql stable security definer as $$
  select count(*)::int from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = p_slot::text
     and at > now() - interval '24 hours' $$;
create function test.n485(p_act text) returns int language sql stable security definer as $$
  select count(*)::int from public.audit_log where action = p_act $$;
create function test.last485(p_act text) returns jsonb language sql stable security definer as $$
  select jsonb_build_object('manager_id', manager_id, 'manager_name', manager_name, 'target_id', target_id, 'details', details)
    from public.audit_log where action = p_act order by id desc limit 1 $$;
-- every person's 0033 counter and lock, and one person's
create function test.pins485() returns text language sql stable security definer as $$
  select string_agg(name || ':' || failed_pins || ':' || coalesce(locked_until::text, '-'), ' ' order by id) from public.staff $$;
create function test.pin1485(p_who text) returns text language sql stable security definer as $$
  select failed_pins || case when locked_until > now() then '/locked' else '/open' end from public.staff where id = test.p485(p_who) $$;
create function test.locked485() returns text language sql stable security definer as $$
  select coalesce(string_agg(name, ' ' order by name), '') from public.staff where locked_until > now() $$;
create function test.live485() returns text language sql stable security definer as $$
  select coalesce(string_agg(slot || '=' || coalesce(station, '-') || ':' || enrolled_by_name, ' ' order by slot), '')
    from public.discount_tills where ended_at is null $$;
create function test.state485(p_slot int) returns jsonb language sql stable security definer as $$
  select to_jsonb(g) from public._discount_slot_state(p_slot) g $$;
create function test.person485(p_who text) returns text language sql stable security definer as $$
  select places || '/' || ends_24h || '/' || enrolls_24h from public._discount_person(test.p485(p_who)) $$;
create function test.ncat485() returns int language sql stable security definer as $$
  select count(*)::int from public.discount_approvals where category is not null $$;
create function test.unl485() returns int language sql stable security definer as $$ select count(*)::int from public.access_unlocks $$;
-- the live places as the panel lists them, built here from the table (p_by's own marked mine)
create function test.places485(p_by uuid, p_mine_only boolean) returns jsonb language sql stable security definer as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', t.slot, 'till', t.id, 'station', t.station, 'by', t.enrolled_by_name,
           'since', t.enrolled_at, 'last_used', t.last_used_at, 'mine', coalesce(t.enrolled_by = p_by, false)) order by t.slot), '[]')
    from public.discount_tills t where t.ended_at is null and (not p_mine_only or t.enrolled_by = p_by) $$;
-- when the 12th most recent counted wrong code of a place turns 24 hours old
create function test.stopend485(p_slot int) returns timestamptz language sql stable security definer as $$
  select at + interval '24 hours' from public.audit_log
   where action = 'discount_code_wrong' and details ->> 'slot' = p_slot::text
     and id > coalesce((select max(id) from public.audit_log where action = 'discount_till_resumed' and details ->> 'slot' = p_slot::text), 0)
   order by at desc, id desc offset 11 limit 1 $$;
-- the only form of a sign-in id the log may hold, and a key's stored form, computed here (not with 0038's helpers)
create function test.tag485(p_sess text) returns text language sql immutable as $$
  select 's' || left(encode(sha256(convert_to(p_sess, 'UTF8')), 'hex'), 7) $$;
create function test.hash485(p_key text) returns text language sql immutable as $$
  select encode(sha256(convert_to(p_key, 'UTF8')), 'hex') $$;
create function test.keys485(j jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(k, ' ' order by k), '') from jsonb_object_keys(j) k $$;
-- a paid ticket carrying an approval, as pos.html sends it (pos_record_sale): one line at the approved subtotal
create function test.sale485(oid uuid, appr jsonb) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', now(),
           'total_crc', (appr ->> 'subtotal')::int - (appr ->> 'amount')::int, 'payment_method', 'cash_crc', 'paid', true,
           'status', 'done', 'needs_kitchen', false, 'station', 'Caja 485', 'guest_name', 'Ticket 485',
           'subtotal_crc', (appr ->> 'subtotal')::int, 'discount_crc', (appr ->> 'amount')::int, 'discount_id', appr ->> 'id',
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', (appr ->> 'subtotal')::int, 'qty', 1)))) $$;
create function test.order485(oid uuid) returns jsonb language sql stable security definer as $$
  select jsonb_build_object('discount_id', o.discount_id, 'discount_crc', o.discount_crc, 'reason', o.discount_reason,
                            'unverified', 'discount_not_verified' = any (coalesce(o.flags, '{}')),
                            'approval_order', (select a.order_id from public.discount_approvals a where a.id = o.discount_id))
    from public.orders o where o.id = oid $$;
-- n wrong codes at one till, waiting out each wait (10 minutes 1 second after each)
create function test.hammer485(p_sess text, n int) returns jsonb language plpgsql as $$
declare i int; r jsonb;
begin
  for i in 1 .. n loop
    r := test.c485(p_sess, 'local', '0000');
    perform test.back485(interval '10 minutes 1 second');
  end loop;
  return r;
end $$;
-- a «Pay later» bill of two lines, 4000 + 6000
create function test.bill485(oid uuid) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', now(), 'total_crc', 10000,
           'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja 485', 'source', 'front',
           'guest_name', 'Cuenta 485',
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
                                      jsonb_build_object('item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) $$;

-- a function's text, for the structure checks (§10, §16)
create function test.src485(p text) returns text language sql stable as $$ select prosrc from pg_proc where oid = p::regprocedure $$;
\set aut 'public.descuento_autorizar(text,text,integer,text,text,uuid,integer,uuid,text)'

-- 1) an unregistered sign-in gets nothing (mecanismo §1 item 1, §6 6a-6b, §13.1 item 1) ------------------------------
select test.pins485() as pins0 \gset
set role authenticated;
select test.eq(test.c485('t485-z1', 'local', '4826', p_station => 'Cocina'), '{"ok": false, "error": "till_not_enrolled"}'::jsonb,
               '1 a manager''s right code on a sign-in that is not a registered till: till_not_enrolled, and nothing else');
select test.eq(test.c485('t485-z1', 'local', '0000', p_station => 'Cocina'), '{"ok": false, "error": "till_not_enrolled"}'::jsonb,
               '1 a wrong code there: the very same answer (no code is compared)');
select test.eq(test.c485('t485-z1', 'empleado', '4826', '5284', p_station => 'Cocina'), '{"ok": false, "error": "till_not_enrolled"}'::jsonb,
               '1 an Empleado with both right codes there: the same');
select test.eq(public.descuento_estado(),
               '{"ok": true, "owner_ready": true, "guia_enabled": false, "session": true, "till": {"registered": false, "ended": false}}'::jsonb,
               '1 descuento_estado on that sign-in: it has a session id and is not registered (never was)');
select test.eq(test.pins485(), :'pins0', '1 nobody''s PIN counter or lock moved (no bcrypt, no _verify_pin, no 0033 write)');
select test.eq(test.n485('discount_code_wrong'), 0, '1 nothing counted');
select test.eq(test.ncat485(), 0, '1 nothing approved');
select test.eq(test.n485('discount_till_unknown'), 1, '1 three codes from one sign-in within the hour: one discount_till_unknown row');
select test.eq(test.last485('discount_till_unknown'),
               jsonb_build_object('manager_id', null, 'manager_name', null, 'target_id', null, 'details',
                 jsonb_build_object('session_tag', test.tag485('t485-z1'), 'station', 'Cocina', 'by_login', :'cafe', 'account', 'cafe')),
               '1 ... holding the sign-in only as its tag (s + 7 hex of its sha256), the page''s station, the login and the account');
select test.eq(test.c485('t485-z0', 'local', ''), '{"ok": false, "error": "no_request"}'::jsonb, '1 an empty code on another sign-in: no_request');
select test.eq(test.c485('t485-z0', 'local', '   '), '{"ok": false, "error": "no_request"}'::jsonb, '1 a blank code: no_request');
select test.eq(test.n485('discount_till_unknown'), 1, '1 ... an empty code tests nothing and logs nothing');
select test.eq((select count(*)::int from generate_series(2, 26) i where test.c485('t485-z' || i, 'local', '1234') ->> 'error' = 'till_not_enrolled'),
               25, '1 25 more sign-ins minted with the café password: every one refused');
select test.eq(test.n485('discount_till_unknown'), 20, '1 ... and the log took 20 rows in that hour, then nothing more (20 an hour café-wide)');
select test.back485(interval '61 minutes');
select test.eq(test.c485('t485-z27', 'local', '1234') ->> 'error', 'till_not_enrolled', '1 an hour later another sign-in');
select test.eq(test.n485('discount_till_unknown'), 21, '1 ... is logged again (a rolling hour)');
-- a token without session_id (never a shared bucket)
select test.eq(test.c485(null, 'local', '4826'), '{"ok": false, "error": "no_session"}'::jsonb,
               '1 a token without session_id: no_session');
select test.eq(public.descuento_estado(),
               '{"ok": true, "owner_ready": true, "guia_enabled": false, "session": false, "till": {"registered": false, "ended": false}}'::jsonb,
               '1 descuento_estado says that sign-in has no session id');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.access_level(), 'manager', '1 (Ana opens the owner areas on that sign-in, as before 0033)');
select test.eq(public.descuento_caja_registrar('Sin sesión'), '{"ok": false, "error": "no_session"}'::jsonb,
               '1 ... even so it cannot be registered: no_session');
select test.eq(public.descuento_caja_volver(repeat('ab', 32)), '{"ok": false, "error": "no_session"}'::jsonb,
               '1 ... nor brought back with a key: no_session');
select test.eq(test.n485('discount_till_unknown'), 21, '1 no_session logs nothing either');
select test.eq(test.n485('discount_code_wrong') + test.ncat485(), 0, '1 still nothing counted, nothing approved');
select test.eq((select count(*)::int from test.ans485 where sess like 't485-z%' and j ->> 'error' not in ('till_not_enrolled', 'no_request')), 0,
               '1 every answer to an unregistered sign-in was till_not_enrolled (or no_request for an empty code)');
reset role;
select test.eq((select count(*)::int from public.discount_tills), 0, '1 and no till exists');

-- 2) registering (mecanismo §1 item 2, §5.2 descuento_caja_registrar, §13.1 item 2) ---------------------------------
set role authenticated;
select test.dev485('t485-a1');
select test.eq(public.descuento_caja_registrar('Caja del frente'), '{"ok": false, "error": "owner_only"}'::jsonb,
               '2 without the owner areas open on this sign-in: owner_only');
select test.eq(public.access_unlock(test.staff('luis'), '5284') ->> 'error', 'not_manager', '2 a staff member cannot open them (0033): not_manager');
select test.unlock(test.staff('ana'), '4826');
select test.unl485() as unl0 \gset
select public.descuento_caja_registrar('Caja del frente') as ra \gset
insert into test.devs485 values ('A', 't485-a1', (:'ra'::jsonb) ->> 'key');
insert into test.allkeys485 values ((:'ra'::jsonb) ->> 'key');
select test.tid485('t485-a1') as ida \gset
select test.eq(test.keys485(:'ra'::jsonb), 'by key ok replaced slot state station until wait wait_s',
               '2 Ana opened the owner areas here: registered; the answer holds ok, key, station, slot, by, replaced, state, until, wait, wait_s');
select test.ok((:'ra'::jsonb) ->> 'key' ~ '^[0-9a-f]{64}$', '2 ... the device key is 32 random bytes as 64 lowercase hex characters');
select test.eq((:'ra'::jsonb) - 'key', '{"ok": true, "station": "Caja del frente", "slot": 1, "by": "Ana", "replaced": null, "state": "ok", "until": null, "wait": null, "wait_s": null}'::jsonb,
               '2 ... in place 1 (every place free and clean), by Ana, nothing replaced, the place calm');
select test.eq(test.till485(:'ida') - 'id' - 'enrolled_at',
               jsonb_build_object('slot', 1, 'session_id', 't485-a1', 'login_id', :'cafe', 'station', 'Caja del frente',
                 'enrolled_by', test.staff('ana'), 'enrolled_by_name', 'Ana', 'last_used_at', null,
                 'key_hash', test.hash485((:'ra'::jsonb) ->> 'key'), 'rebound_from', null, 'prev_key_hash', null, 'ended_at', null,
                 'ended_by', null, 'ended_by_name', null, 'ended_how', null),
               '2 the row: this sign-in and login, the station, who registered it, and only the sha256 of the key');
select test.eq(test.last485('discount_till_enrolled'),
               jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'target_id', :'ida', 'details',
                 jsonb_build_object('till', :'ida', 'slot', 1, 'till_station', 'Caja del frente', 'session_tag', test.tag485('t485-a1'),
                   'replaced', null, 'replaced_station', null, 'state', 'ok', 'by_login', :'cafe', 'account', 'cafe')),
               '2 audit discount_till_enrolled names Ana, the till, the place, the sign-in''s tag; never the key');
select test.eq(test.unl485(), :unl0, '2 registering wrote no unlock (adjustment 1: no PIN is tested here)');
-- the reply that carried the key was lost (a Wi-Fi drop) and «Registrar» is tapped again on the same sign-in: the
-- owner areas are still open here, so the key is made again and sent; the first one is spent (finding: a lost reply)
select public.descuento_caja_registrar('Otro nombre') as ra2 \gset
select test.eq((:'ra2'::jsonb) - 'key', '{"ok": true, "already": true, "station": "Caja del frente", "slot": 1}'::jsonb,
               '2 again on the same sign-in: already, same place and station (the name sent is ignored)');
select test.ok((:'ra2'::jsonb) ->> 'key' ~ '^[0-9a-f]{64}$' and (:'ra2'::jsonb) ->> 'key' <> (:'ra'::jsonb) ->> 'key',
               '2 ... and a new device key (the page that lost the first reply has one again)');
select test.eq(test.till485(:'ida') ->> 'key_hash', test.hash485((:'ra2'::jsonb) ->> 'key'),
               '2 ... the same row keeps only the new key''s sha256: the first key is spent');
update test.devs485 set key = (:'ra2'::jsonb) ->> 'key' where dev = 'A';
insert into test.allkeys485 values ((:'ra2'::jsonb) ->> 'key');
select test.eq(test.n485('discount_till_enrolled'), 1, '2 ... and nothing is logged again');
select public.descuento_estado() as ea \gset
select test.eq(((:'ea'::jsonb) -> 'till') - 'since',
               '{"registered": true, "slot": 1, "station": "Caja del frente", "by": "Ana", "state": "ok", "until": null, "wait": null, "wait_s": null, "warn": null}'::jsonb,
               '2 descuento_estado: registered in place 1 by Ana, calm');
select test.eq(((:'ea'::jsonb) #>> '{till,since}')::timestamptz, (test.till485(:'ida') ->> 'enrolled_at')::timestamptz,
               '2 ... since its registration');
-- an unlock made on another sign-in opens nothing here (0033 binds it to its own sign-in)
select test.dev485('t485-x1');
select test.unlock(test.staff('ana'), '4826') as hx \gset
select test.login('cafe', 'aal1', :'hx'::jsonb);
select test.session('t485-y1');
select test.ok(public.access_level() is null, '2 another sign-in''s unlock token opens nothing on this one (0033)');
select test.eq(public.descuento_caja_registrar('Y'), '{"ok": false, "error": "owner_only"}'::jsonb, '2 ... and cannot register it: owner_only');
-- only the café login (and the owner's) may call any of it
select test.login('accountant', 'aal2');
select test.session('t485-acc');
select test.eq(jsonb_build_array(public.descuento_estado(), public.descuento_autorizar('local', '4826', 1000),
                                 public.descuento_caja_registrar('X'), public.descuento_caja_volver(repeat('ab', 32)),
                                 public.descuento_cajas(), public.descuento_caja_reanudar(1, test.staff('ana'), '4826'),
                                 public.descuento_caja_quitar(:'ida', test.staff('ana'), '4826')),
               (select jsonb_agg('{"ok": false, "error": "no_account"}'::jsonb) from generate_series(1, 7)),
               '2 the accountant: no_account from estado, autorizar, registrar, volver, cajas, reanudar and quitar');
-- per person (R, scenario A2's caps): 2 places held, 3 removals or replacements, 6 registrations in 24 hours
select test.eq(test.reg485('B', 't485-b1', 'ana', E'  Caja  B​ ') - 'key',
               '{"ok": true, "station": "Caja B", "slot": 2, "by": "Ana", "replaced": null, "state": "ok", "until": null, "wait": null, "wait_s": null}'::jsonb,
               '2 Ana registers a second device: place 2 (its station cleaned: no-break spaces, zero-width character)');
select test.eq(test.reg485('C', 't485-c1', 'ana', 'Caja C'),
               jsonb_build_object('ok', false, 'error', 'person_limit', 'mine', test.places485(test.staff('ana'), true)),
               '2 her third: person_limit, listing her own 2 places (slot, till, station, by, since, last_used, mine)');
select test.eq(test.live485(), '1=Caja del frente:Ana 2=Caja B:Ana', '2 ... nothing changed');
select test.ok(test.tid485('t485-c1') is null and test.n485('discount_till_enrolled') = 2, '2 ... no row and no log row for it');
select test.eq(test.reg485('C', 't485-c1', 'bea', 'Caja C') ->> 'slot', '3', '2 Bea registers it: place 3');
select test.eq(test.reg485('D', 't485-d1', 'bea', 'Caja D'),
               jsonb_build_object('ok', false, 'error', 'till_full', 'places', test.places485(test.p485('bea'), false)),
               '2 a 4th device: till_full with the 3 live places (Bea''s marked mine)');
select test.eq(test.n485('discount_till_ended'), 0, '2 ... and no till ended by itself');
select test.eq(test.reg485('D', 't485-d1', 'ana', 'Caja D') ->> 'error', 'person_limit',
               '2 the 4th device by Ana, who holds 2: person_limit (before till_full)');
select test.reg485('D', 't485-d1', 'ana', 'Caja D', test.tid485('t485-b1')) as rd \gset
select test.tid485('t485-d1') as idd \gset
select test.eq((:'rd'::jsonb) - 'key',
               '{"ok": true, "station": "Caja D", "slot": 2, "by": "Ana", "replaced": "Caja B", "state": "ok", "until": null, "wait": null, "wait_s": null}'::jsonb,
               '2 Ana replaces one of her own with «Reemplazar con este dispositivo»: the new device takes its place 2');
select test.eq((select jsonb_build_object('how', x ->> 'ended_how', 'by', x ->> 'ended_by', 'name', x ->> 'ended_by_name', 'key', x ->> 'key_hash',
                                          'ended', x ->> 'ended_at' is not null)
                  from (select test.rowof485('t485-b1') x) q),
               jsonb_build_object('how', 'replaced', 'by', test.staff('ana'), 'name', 'Ana', 'key', null, 'ended', true),
               '2 ... the replaced row ends replaced, by Ana, its key spent; the row stays');
select test.eq(test.last485('discount_till_ended') - 'target_id',
               jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'details',
                 jsonb_build_object('till', test.rowof485('t485-b1') ->> 'id', 'slot', 2,
                   'till_station', 'Caja B', 'how', 'replaced', 'station', 'Caja D', 'by_login', :'cafe', 'account', 'cafe')),
               '2 ... audit discount_till_ended {how: replaced} names Ana');
select test.eq(test.last485('discount_till_enrolled') #>> '{details,replaced_station}', 'Caja B',
               '2 ... and the new registration''s row names the till it replaced');
select test.eq(test.person485('ana'), '2/1/3', '2 Ana: 2 places held, 1 replacement, 3 registrations in 24 h');
select test.eq(test.c485('t485-b1', 'local', '4826'), '{"ok": false, "error": "till_ended"}'::jsonb, '2 the replaced sign-in hears till_ended');
select test.eq(public.descuento_estado() -> 'till', '{"registered": false, "ended": true}'::jsonb, '2 ... descuento_estado: ended');
select test.eq(test.vol485('B', 't485-b2'), '{"ok": false, "error": "key_invalid"}'::jsonb,
               '2 ... and its key, on its next sign-in: key_invalid (a replacement spends it)');
select test.eq(test.reg485('E', 't485-e1', 'ana', 'Caja E', test.tid485('t485-c1')),
               jsonb_build_object('ok', false, 'error', 'person_limit', 'mine', test.places485(test.staff('ana'), true)),
               '2 Ana, at 2 places, cannot replace Bea''s till: person_limit');
select test.open485('t485-a1', 'ana');
select test.eq(public.descuento_caja_quitar(:'idd', test.staff('ana'), '4826', 'Caja del frente'),
               '{"ok": true, "station": "Caja D", "slot": 2}'::jsonb, '2 Ana removes D («Quitar registro»): her 2nd ending');
select test.eq(test.reg485('E', 't485-e1', 'ana', 'Caja E', test.tid485('t485-c1')), '{"ok": false, "error": "place_free"}'::jsonb,
               '2 a replacement while a place is free (and she holds 1): place_free');
select test.eq(test.live485(), '1=Caja del frente:Ana 3=Caja C:Bea', '2 ... nothing changed');
select test.eq(test.reg485('E', 't485-e1', 'ana', 'Caja E') ->> 'slot', '2', '2 Ana registers E in the free place');
select test.open485('t485-a1', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-e1'), test.staff('ana'), '4826') ->> 'ok', 'true', '2 ... removes it: her 3rd ending');
select test.eq(test.reg485('F', 't485-f1', 'ana', 'Caja F') ->> 'slot', '2', '2 ... registers F: her 5th registration');
select test.open485('t485-a1', 'ana');
select test.eq(public.descuento_cajas() -> 'me', '{"places": 2, "ends_24h": 3, "enrolls_24h": 5}'::jsonb,
               '2 the approvals log tells Ana where she stands (me)');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-f1'), test.staff('ana'), '0000'), '{"ok": false, "error": "end_limit"}'::jsonb,
               '2 her 4th removal in 24 h: end_limit');
select test.eq(test.pin1485('ana'), '0/open', '2 ... answered before her PIN was tested (a wrong one did not count)');
select test.eq(test.reg485('G', 't485-g1', 'ana', 'Caja G', :'ida'), '{"ok": false, "error": "end_limit"}'::jsonb,
               '2 ... and her 4th replacement, even of her own till: end_limit');
select test.eq(test.live485(), '1=Caja del frente:Ana 2=Caja F:Ana 3=Caja C:Bea', '2 ... nothing changed');
select test.eq(test.reg485('G', 't485-g1', 'bea', 'Caja G', test.tid485('t485-f1')) ->> 'replaced', 'Caja F',
               '2 Bea, at 0 of 3, replaces at once');
select test.open485('t485-g1', 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-c1'), test.p485('bea'), '3917') ->> 'ok', 'true', '2 ... and removes C');
select test.eq(test.person485('bea'), '1/2/2', '2 Bea: 1 place, 2 endings, 2 registrations');
select test.eq(test.reg485('H', 't485-h1', 'ana', 'Caja H') ->> 'slot', '3', '2 Ana''s 6th registration');
select test.eq(test.reg485('I', 't485-i1', 'ana', 'Caja I'), '{"ok": false, "error": "enroll_limit"}'::jsonb,
               '2 her 7th in 24 h: enroll_limit');
select test.eq(test.live485(), '1=Caja del frente:Ana 2=Caja G:Bea 3=Caja H:Ana', '2 ... nothing changed');
select test.eq(test.person485('ana'), '2/3/6', '2 Ana: 2 places, 3 endings, 6 registrations (each cap is hers alone)');
-- (R) a registration goes to the most used free place: stopped first, then the most wrong codes, then the one left last
select test.fresh485();
select test.reg485('J', 't485-j1', 'ana', 'Caja J') ->> 'slot' as sj \gset
select test.reg485('K', 't485-k1', 'bea', 'Caja K') ->> 'slot' as sk \gset
select test.eq(test.hammer485('t485-j1', 12) ->> 'blocked', 'stopped', '2 place ' || :sj || ' stopped by 12 wrong codes');
select test.open485('t485-k1', 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-j1'), test.p485('bea'), '3917') ->> 'ok', 'true',
               '2 ... and its till removed: a stopped free place, next to a clean free one');
select test.reg485('L', 't485-l1', 'bea', 'Caja L') as rl \gset
select test.eq((:'rl'::jsonb) - 'key' - 'wait_s',
               jsonb_build_object('ok', true, 'station', 'Caja L', 'slot', :sj::int, 'by', 'Bea', 'replaced', null, 'state', 'stopped',
                                  'until', test.stopend485(:sj), 'wait', 'stop'),
               '2 the next registration lands in the stopped place, and the answer says it is stopped and until when');
select test.ok(((:'rl'::jsonb) ->> 'wait_s')::int >= 1, '2 ... with the seconds left by the server''s clock');
select test.eq(test.last485('discount_till_enrolled') #>> '{details,state}', 'stopped', '2 ... and its log row says so');
select test.endall485('t485 fixture reset');
select test.calm485();
select test.reg485('M', 't485-m1', 'ana', 'Caja M') ->> 'slot' as sm \gset
select test.reg485('N', 't485-n1', 'bea', 'Caja N') ->> 'slot' as sn \gset
select test.c485('t485-n1', 'local', '0000'), test.c485('t485-n1', 'local', '0000');
select test.endall485('t485 fixture reset');
select test.eq(test.reg485('O', 't485-o1', 'ana', 'Caja O') ->> 'slot', :'sn', '2 of the free places, the one with wrong codes first');
select test.eq(test.reg485('P0', 't485-p01', 'dueno', 'Caja P') ->> 'slot', :'sm', '2 then, of two clean ones, the one left last');
select test.eq(test.last485('discount_till_enrolled') - 'target_id' - 'details', jsonb_build_object('manager_id', test.staff('dueno'), 'manager_name', 'Dueño'),
               '2 (registered with the owner''s PIN typed on the tablet: that is not the phone code, it names the owner''s staff record)');
select test.eq(test.person485('dueno'), '1/0/1', '2 ... and counts on the owner''s own per-person allowance');
select test.reg485('Q', 't485-q1', 'ciro', 'Caja Q') ->> 'slot' as sq3 \gset
select test.c485('t485-q1', 'local', '0000'), test.c485('t485-q1', 'local', '0000'), test.c485('t485-q1', 'local', '0000');
select test.open485('t485-q1', 'ciro');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-q1'), test.p485('ciro'), '3918') ->> 'ok', 'true', '2 (a place left waiting: 3 wrong codes, its till removed)');
select test.reg485('R', 't485-r1', 'ciro', 'Caja R') as rr \gset
select test.eq((:'rr'::jsonb) - 'key' - 'wait_s',
               jsonb_build_object('ok', true, 'station', 'Caja R', 'slot', :sq3::int, 'by', 'Ciro', 'replaced', null, 'state', 'wait',
                                  'until', now() + interval '30 seconds', 'wait', '30s'),
               '2 a registration into a waiting place says so: state wait, until when, which wait');
reset role;

-- 3) the per-till budget, the owner's adjustment 2 itself (mecanismo §1 item 4, §3, §13.1 item 3) --------------------
set role authenticated;
select test.fresh485();
select test.reg485('TA', 't485-ta1', 'ana', 'Caja A') ->> 'slot' as sa \gset
select test.reg485('TB', 't485-tb1', 'bea', 'Caja B') ->> 'slot' as sb \gset
select test.eq(test.c485('t485-ta1', 'local', '0000'),
               '{"ok": false, "error": "bad_pin", "step": "manager", "warn": null, "blocked": null, "until": null, "wait": null, "wait_s": null}'::jsonb,
               '3 the 1st wrong code in an hour: bad_pin, nothing else');
select test.eq(test.c485('t485-ta1', 'local', '0000'),
               '{"ok": false, "error": "bad_pin", "step": "manager", "warn": null, "blocked": null, "until": null, "wait": null, "wait_s": null}'::jsonb,
               '3 the 2nd: free too (two typos an hour cost only the message)');
select test.c485('t485-ta1', 'local', '0000') as w3 \gset
select test.eq((:'w3'::jsonb) - 'until' - 'wait_s',
               '{"ok": false, "error": "bad_pin", "step": "manager", "warn": "wait_1m", "blocked": "wait", "wait": "30s"}'::jsonb,
               '3 the 3rd in an hour starts a 30-second wait, and warns that the next costs 1 minute');
select test.eq(((:'w3'::jsonb) ->> 'until')::timestamptz, now() + interval '30 seconds', '3 ... until 30 s after it');
select test.back485(interval '1 second');
select test.till485(test.tid485('t485-ta1')) ->> 'last_used_at' as lu3 \gset
select test.c485('t485-ta1', 'local', '4826') as tw \gset
select test.eq((:'tw'::jsonb) - 'wait_s', jsonb_build_object('ok', false, 'error', 'till_wait', 'until', now() + interval '29 seconds', 'wait', '30s'),
               '3 Ana''s right code during the wait: till_wait {until, wait, wait_s}, untested');
select test.eq(test.pin1485('ana'), '0/open', '3 ... her counter untouched');
select test.eq(test.wrong485(:sa), 3, '3 ... nothing counted');
select test.eq(test.till485(test.tid485('t485-ta1')) ->> 'last_used_at', :'lu3', '3 ... and the till was not even marked used (refused before its lock)');
select test.eq(test.c485('t485-tb1', 'local', '4826') ->> 'ok', 'true', '3 another till approves at once');
select test.eq(test.c485('t485-ta1', 'local', '0000') ->> 'error', 'till_wait', '3 the same sign-in from a copied session: the same wait');
select test.eq(test.c485('t485-m3', 'local', '0000') ->> 'error', 'till_not_enrolled', '3 a minted sign-in: nothing');
select test.eq(test.wrong485(:sa), 3, '3 ... still 3 counted');
select test.dev485('t485-ta1');
select public.descuento_estado() -> 'till' as e3 \gset
select test.eq((:'e3'::jsonb) - 'since' - 'wait_s',
               jsonb_build_object('registered', true, 'slot', :sa::int, 'station', 'Caja A', 'by', 'Ana', 'state', 'wait',
                                  'until', now() + interval '29 seconds', 'wait', '30s', 'warn', 'wait_1m'),
               '3 descuento_estado shows the wait, its length and what the next mistake costs');
select test.ok(((:'e3'::jsonb) ->> 'wait_s')::int between 1 and 29, '3 ... and the seconds left, by the server''s clock');
select test.back485(interval '30 seconds');
select test.c485('t485-ta1', 'local', '4826') as appr_ta \gset
select test.eq((:'appr_ta'::jsonb) ->> 'ok', 'true', '3 after 30 s a right code works');
select test.eq(test.wrong485(:sa), 3, '3 ... and resets nothing (3 still counted)');
select test.eq((test.till485(test.tid485('t485-ta1')) ->> 'last_used_at')::timestamptz, now(), '3 ... a tested call marks the till used');
select test.dev485('t485-ta1');
select test.eq(public.descuento_estado() #>> '{till,warn}', 'wait_1m', '3 calm again, the next mistake would cost 1 minute');
select test.c485('t485-ta1', 'local', '0000') as w4 \gset
select test.eq((:'w4'::jsonb) - 'wait_s', jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', 'manager', 'warn', 'wait_5m',
                                  'blocked', 'wait', 'until', now() + interval '1 minute', 'wait', '1m'),
               '3 the 4th: 1 minute (the next: 5)');
select test.back485(interval '1 minute 1 second');
select test.c485('t485-ta1', 'local', '0000') as w5 \gset
select test.eq((:'w5'::jsonb) - 'wait_s', jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', 'manager', 'warn', 'wait_10m',
                                  'blocked', 'wait', 'until', now() + interval '5 minutes', 'wait', '5m'),
               '3 the 5th: 5 minutes (the next: 10)');
select test.back485(interval '5 minutes 1 second');
select test.c485('t485-ta1', 'local', '0000') as w6 \gset
select test.eq((:'w6'::jsonb) - 'wait_s', jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', 'manager', 'warn', 'wait_10m',
                                  'blocked', 'wait', 'until', now() + interval '10 minutes', 'wait', '10m'),
               '3 the 6th and later: 10 minutes each');
select test.back485(interval '10 minutes 1 second');
select test.hammer485('t485-ta1', 5) as w11 \gset
select test.eq(test.wrong485(:sa), 11, '3 11 wrong codes counted');
select test.eq((:'w11'::jsonb) ->> 'warn', 'stop', '3 ... the 11th warns that one more stops discounts on this till');
select test.eq(test.c485('t485-ta1', 'local', '4826') ->> 'ok', 'true', '3 at 11 a right code still works');
select test.dev485('t485-ta1');
select test.eq(public.descuento_estado() #>> '{till,warn}', 'stop', '3 ... and descuento_estado warns: stop');
select test.n485('discount_till_stopped') as stops0 \gset
select test.c485('t485-ta1', 'local', '0000') as w12 \gset
select test.eq((:'w12'::jsonb) - 'wait_s', jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', 'manager', 'warn', null,
                                  'blocked', 'stopped', 'until', test.stopend485(:sa), 'wait', 'stop'),
               '3 the 12th in 24 h stops the till until the 12th most recent is 24 h old (no warning left)');
select test.ok(test.stopend485(:sa) > now() + interval '22 hours', '3 ... (about 23 hours from now)');
select test.eq(test.n485('discount_till_stopped'), :stops0 + 1, '3 ... one discount_till_stopped row');
select test.eq(test.last485('discount_till_stopped'),
               jsonb_build_object('manager_id', null, 'manager_name', null, 'target_id', test.tid485('t485-ta1'), 'details',
                 jsonb_build_object('till', test.tid485('t485-ta1'), 'slot', :sa::int, 'till_station', 'Caja A', 'station', 'Caja 485',
                   'until', test.stopend485(:sa), 'day_n', 12, 'by_login', :'cafe')),
               '3 ... naming the till, its place, both stations, until when, and the count');
select test.eq(test.c485('t485-ta1', 'local', '4826') - 'wait_s',
               jsonb_build_object('ok', false, 'error', 'till_stopped', 'until', test.stopend485(:sa), 'wait', 'stop'),
               '3 a right code while stopped: till_stopped, untested');
select test.eq(test.c485('t485-ta1', 'local', '0000') ->> 'error', 'till_stopped', '3 ... a wrong one too (not counted)');
select test.eq(test.wrong485(:sa), 12, '3 ... 12 counted, never more');
select test.dev485('t485-ta1');
select test.eq((public.descuento_estado() -> 'till') - 'since' - 'wait_s',
               jsonb_build_object('registered', true, 'slot', :sa::int, 'station', 'Caja A', 'by', 'Ana', 'state', 'stopped',
                                  'until', test.stopend485(:sa), 'wait', 'stop', 'warn', null),
               '3 descuento_estado: stopped, until when, nothing to warn');
select test.eq(test.c485('t485-tb1', 'local', '4826') ->> 'ok', 'true', '3 till B is unaffected');
select test.eq(case when (:'appr_ta'::jsonb) ->> 'ok' = 'true' then test.sale485('d4850000-0000-4000-8000-000000000003', :'appr_ta'::jsonb) ->> 'ok' end, 'true',
               '3 selling never stops: the sale with the approval till A gave before it stopped is saved');
select test.eq(test.order485('d4850000-0000-4000-8000-000000000003'),
               jsonb_build_object('discount_id', (:'appr_ta'::jsonb) ->> 'id', 'discount_crc', 100, 'reason', 'Local', 'unverified', false,
                                  'approval_order', 'd4850000-0000-4000-8000-000000000003'),
               '3 ... and linked and verified as before (the order trigger never consults this guard)');
select test.eq(test.wrong485(:sb) + test.wrong485(6 - :sa - :sb), 0, '3 ... the other places'' counts are 0');
select test.eq(test.pin1485('ana'), '0/open', '3 Ana''s 0033 counter never moved');
select test.back485((test.stopend485(:sa) - now()) - interval '1 second');
select test.eq(test.c485('t485-ta1', 'local', '4826') ->> 'error', 'till_stopped', '3 one second before the 12th most recent is 24 h old: still stopped');
select test.back485(interval '2 seconds');
select test.eq(test.c485('t485-ta1', 'local', '4826') ->> 'ok', 'true', '3 ... then it works by itself, nobody resumed it');
reset role;

-- 4) what counts, and what never does (mecanismo §6 6e-6f, §13.1 item 4) --------------------------------------------
-- Guía Turista switched on locally, as L2 says tests do (the accountant's confirmation, then the setting)
insert into public.compliance_confirmations (key, confirmed_by, reference) values ('courtesy_iva_confirmed', 'test', 'test');
insert into public.settings (key, value) values ('pos_discount_guia', '"on"');
set role authenticated;
select test.calm485();
select test.s485('TB') as tb \gset
select test.tid485(:'tb') as idb \gset
select test.eq(test.c485(:'tb', 'local', '5284') ->> 'error', 'bad_pin', '4 a staff PIN at the manager step: bad_pin');
select test.eq(test.last485('discount_code_wrong') - 'target_id',
               jsonb_build_object('manager_id', null, 'manager_name', null, 'details',
                 jsonb_build_object('till', :'idb', 'slot', :sb::int, 'session_tag', test.tag485(:'tb'), 'station', 'Caja 485',
                   'till_station', 'Caja B', 'step', 'manager', 'why', 'not_allowed', 'category', 'local', 'authorizer', null,
                   'by_login', :'cafe', 'account', 'cafe', 'hour_n', 1, 'day_n', 1)),
               '4 ... counted: why not_allowed, with the till, its place, the sign-in''s tag, both stations and the counts');
select test.calm485();
select test.eq(test.c485(:'tb', 'guia', '4826', p_comp => 'Tours Monteverde') ->> 'step', 'owner', '4 a manager''s code for Guía: bad_pin at the owner step');
select test.eq(test.last485('discount_code_wrong') #>> '{details,why}', 'not_allowed', '4 ... counted as not_allowed');
select test.calm485();
select test.eq(test.c485(:'tb', 'empleado', '4826', '0000'),
               '{"ok": false, "error": "bad_employee", "step": "employee", "warn": null, "blocked": null, "until": null, "wait": null, "wait_s": null}'::jsonb,
               '4 a wrong employee code after Ana''s: bad_employee');
select test.eq(test.last485('discount_code_wrong') - 'target_id' #- '{details,till}' #- '{details,session_tag}' #- '{details,hour_n}' #- '{details,day_n}',
               jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'details',
                 jsonb_build_object('slot', :sb::int, 'station', 'Caja 485', 'till_station', 'Caja B', 'step', 'employee',
                   'why', 'no_match', 'category', 'empleado', 'authorizer', test.staff('ana'), 'by_login', :'cafe', 'account', 'cafe')),
               '4 ... counted, and the row names Ana, whose code came first');
select test.calm485();
select test.eq(test.c485(:'tb', 'empleado', '4826', '7391') ->> 'error', 'bad_employee', '4 the owner as beneficiary: bad_employee');
select test.eq(test.last485('discount_code_wrong') #>> '{details,why}', 'owner_beneficiary', '4 ... counted as owner_beneficiary, naming Ana');
select test.calm485();
select test.n485('discount_code_wrong') as nw \gset
select test.eq(test.c485(:'tb', 'empleado', '4826', '4826'), '{"ok": false, "error": "not_self"}'::jsonb, '4 Ana''s own code as the employee: not_self');
select test.eq(test.n485('discount_code_wrong'), :nw, '4 ... not counted (it tells the typist nothing new)');
select test.eq(test.last485('discount_self_refused'),
               jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'target_id', :'idb', 'details',
                 jsonb_build_object('category', 'empleado', 'till', :'idb', 'slot', :sb::int, 'station', 'Caja 485', 'by_login', :'cafe')),
               '4 ... and logged as discount_self_refused');
-- a code shared by two active people (D-053) authorizes nobody and looks like any wrong code
reset role;
insert into public.staff (id, name, role, active, pin_hash)
  values ('0b485000-0000-4000-8000-000000000004', 'Pablo', 'staff', true, extensions.crypt('6173', extensions.gen_salt('bf', 4)));
set role authenticated;
select test.calm485();
select test.eq(test.c485(:'tb', 'local', '6173') ->> 'error', 'bad_pin', '4 a shared code at the manager step: bad_pin');
select test.eq(test.last485('discount_code_wrong') #>> '{details,why}', 'ambiguous', '4 ... counted as ambiguous');
select test.eq(test.last485('pin_duplicate'),
               jsonb_build_object('manager_id', null, 'manager_name', null, 'target_id', :'idb', 'details',
                 jsonb_build_object('step', 'manager', 'till', :'idb', 'by_login', :'cafe')),
               '4 ... with a pin_duplicate row that names no one (never the code, never the people: managers read the log)');
reset role;
select test.eq((select to_jsonb(d.staff_ids) from public.discount_pin_shared d
                 where d.audit_id = (select max(id) from public.audit_log where action = 'pin_duplicate')),
               jsonb_build_array(test.p485('pablo'), test.staff('marta')),
               '4 ... the two people by id only in discount_pin_shared, next to that row');
set role authenticated;
select test.calm485();
select test.eq(test.c485(:'tb', 'empleado', '4826', '6173'),
               '{"ok": false, "error": "bad_employee", "step": "employee", "warn": null, "blocked": null, "until": null, "wait": null, "wait_s": null}'::jsonb,
               '4 a shared code at the employee step: bad_employee, like any wrong code');
select test.eq(test.last485('pin_duplicate') #>> '{details,step}', 'employee', '4 ... and another pin_duplicate row');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_cajas() -> 'shared_code', 'true'::jsonb, '4 the approvals log tells a manager a code is shared, without names');
select test.eq((select count(*) filter (where details ? 'staff_ids' or details::text ~ (test.p485('pablo')::text || '|' || test.staff('marta')::text))
                       || ' of ' || count(*) from public.audit_log where action = 'pin_duplicate'),
               '0 of 2', '4 ... and a manager reading the log itself (its «audit read» rule) gets both rows, without anyone''s id');
select test.eq(current_user || ' ' || public.access_level(), 'authenticated manager', '4 (that read was a manager''s unlock as the café login)');
select test.throws('select * from public.discount_pin_shared', 'permission denied', '4 ... and who shares the code is closed to every sign-in');
select test.open485(:'tb', 'dueno');
select test.eq(public.descuento_cajas() -> 'shared_code', '["Marta", "Pablo"]'::jsonb, '4 ... and the owner who they are');
reset role;
update public.staff set active = false where id = test.p485('pablo');
select test.eq((select to_jsonb(x) from public._discount_take_staff(test.p485('pablo')) x), '{"ok": false, "locked": false}'::jsonb,
               '4 _discount_take_staff of an inactive person: not ok (counted as inactive at the window)');
select test.eq((select to_jsonb(x) from public._discount_staff_state(test.p485('pablo')) x), '{"ok": false, "locked": false}'::jsonb,
               '4 _discount_staff_state of an inactive person: not ok');
select test.ok(not exists (select 1 from public.audit_log a join public.discount_tills t on t.id::text = a.details ->> 'till'
                            where a.action = 'discount_code_wrong'
                              and not (a.target_id = t.id::text and a.details ->> 'slot' = t.slot::text
                                       and a.details ->> 'session_tag' = test.tag485(t.session_id) and a.details ->> 'step' is not null))
               and (select count(*) from public.audit_log where action = 'discount_code_wrong')
                 = (select count(*) from public.audit_log a join public.discount_tills t on t.id::text = a.details ->> 'till'
                     where a.action = 'discount_code_wrong'),
               '4 every wrong-code row names its till, that till''s place, its sign-in''s tag and the step');
select test.eq((select string_agg(distinct test.keys485(details), ' | ') from public.audit_log where action = 'discount_code_wrong'),
               'account authorizer by_login category day_n hour_n session_tag slot station step till till_station why',
               '4 ... and exactly these keys (never a code, a name or a raw sign-in id)');
-- (+) the refusals of steps 1-5 test no code: their own answer, even while the till waits, and nothing counted
set role authenticated;
select test.calm485();
select test.c485(:'tb', 'local', '0000'), test.c485(:'tb', 'local', '0000'), test.c485(:'tb', 'local', '0000');
select test.n485('discount_code_wrong') as nw \gset
select test.n485('discount_till_unknown') as nu \gset
select test.eq(test.c485(:'tb', 'local', '4826') ->> 'error', 'till_wait', '4 (+) till B waits (3 wrong codes)');
select test.eq(jsonb_build_array(test.c485(:'tb', 'vip', '4826'), test.c485(:'tb', 'local', '4826', p_sub => 0),
                                 test.c485(:'tb', 'empleado', '4826'), test.c485(:'tb', 'guia', '7391', p_comp => ' '),
                                 test.c485(:'tb', 'local', '4826', p_bill => gen_random_uuid(), p_expect => 1000),
                                 test.c485(:'tb', 'local', '')),
               '[{"ok": false, "error": "bad_discount"}, {"ok": false, "error": "empty"}, {"ok": false, "error": "missing_employee"},
                 {"ok": false, "error": "missing_company"}, {"ok": false, "error": "not_found"}, {"ok": false, "error": "no_request"}]'::jsonb,
               '4 (+) during the wait: a bad category, an empty sale, no employee code, no company, a missing bill and an empty code get their own answers');
reset role;
update public.settings set value = '"off"' where key = 'pos_discount_guia';
set role authenticated;
select test.eq(test.c485(:'tb', 'guia', '7391', p_comp => 'Tours Monteverde'), '{"ok": false, "error": "guia_off"}'::jsonb,
               '4 (+) Guía switched off: guia_off before any code (L2), during the wait too');
reset role;
update public.settings set value = '"on"' where key = 'pos_discount_guia';
update public.staff set active = false where id = test.staff('dueno');
set role authenticated;
select test.eq(test.c485(:'tb', 'guia', '7391', p_comp => 'Tours Monteverde'), '{"ok": false, "error": "no_owner"}'::jsonb,
               '4 (+) no active owner with a PIN: no_owner before any code');
reset role;
update public.staff set active = true where id = test.staff('dueno');
set role authenticated;
select test.eq(test.n485('discount_code_wrong'), :nw, '4 (+) none of those counted');
select test.eq(test.n485('discount_till_unknown'), :nu, '4 (+) ... nor logged as an unknown device');
select test.eq(test.c485(:'tb', 'local', '4826') ->> 'error', 'till_wait', '4 (+) and the wait is still the same wait');
-- (+) every refusal after a valid code stays uncounted: daily_used, a replayed request id from another moment, a bill
select test.calm485();
select test.c485(:'tb', 'empleado', '4826', '5284') as emp1 \gset
select test.eq((:'emp1'::jsonb) ->> 'beneficiary', 'Luis', '4 (+) an Empleado for Luis at till B');
reset role;
select test.eq((select jsonb_build_object('till', till_id, 'session', session_id) from public.discount_approvals where id = ((:'emp1'::jsonb) ->> 'id')::uuid),
               jsonb_build_object('till', :'idb', 'session', :'tb'), '4 (+) the approval stores the till it came from (till_id)');
select test.eq((select details - 'kind' - 'value' - 'subtotal_crc' - 'discount_crc' - 'station' - 'category' - 'beneficiary_name'
                       - 'company' - 'approver_role' - 'bill' - 'prior' - 'by_login'
                  from public.audit_log where action = 'discount_approved' and target_id = (:'emp1'::jsonb) ->> 'id'),
               jsonb_build_object('till', :'idb', 'slot', :sb::int, 'person_locked', false, 'employee_locked', false),
               '4 (+) ... and its discount_approved row the till, the place and whether either person was locked (0033)');
set role authenticated;
select test.n485('discount_code_wrong') as nw \gset
select test.eq(test.c485(:'tb', 'empleado', '4826', '5284') ->> 'error', 'daily_used', '4 (+) a second Empleado for Luis today: daily_used');
select test.c485(:'tb', 'local', '4826', p_req => 'e4850000-0000-4000-8000-000000000001') ->> 'ok' as rq1 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '31 minutes' where request_id = 'e4850000-0000-4000-8000-000000000001';
set role authenticated;
select test.eq(test.c485(:'tb', 'local', '4826', p_req => 'e4850000-0000-4000-8000-000000000001'), '{"ok": false, "error": "bad_request"}'::jsonb,
               '4 (+) the request id of an approval made 31 minutes ago: bad_request after the code (the request backstop)');
select test.eq(test.last485('discount_refused') #>> '{details,why}', 'bad_request', '4 (+) ... logged as discount_refused');
select test.eq(test.last485('discount_refused') #>> '{details,session_tag}', test.tag485(:'tb'), '4 (+) ... with the sign-in''s tag, not its id');
select test.eq(test.n485('discount_code_wrong'), :nw, '4 (+) daily_used and bad_request did not count');
select test.eq(test.bill485('d4850000-0000-4000-8000-000000000001') ->> 'ok', 'true', '4 (+) a «Pay later» bill of 10000');
reset role;
-- tab_set_discount refusing the bill after the codes (a stub inside a savepoint: what it answers and writes is read into
-- psql variables, the savepoint is undone, then asserted)
savepoint stub485;
create or replace function public.tab_set_discount(p_order_id uuid, p_discount_id uuid, p_expect int default null,
                                                   p_station text default null)
returns jsonb language sql as $$ select '{"ok": false, "error": "refund_first"}'::jsonb $$;
set role authenticated;
select test.calm485();
select test.c485(:'tb', 'local', '4826', p_sub => 10000, p_bill => 'd4850000-0000-4000-8000-000000000001', p_expect => 10000) as billref \gset
reset role;
select (select count(*) from public.audit_log where action = 'discount_code_wrong') as nw_stub,
       (select count(*) from public.audit_log where action = 'discount_refused' and details ->> 'why' = 'refund_first'
           and target_id = 'd4850000-0000-4000-8000-000000000001') as ref_stub,
       (select count(*) from public.discount_approvals where bill_id = 'd4850000-0000-4000-8000-000000000001') as appr_stub \gset
rollback to savepoint stub485;
select test.eq(:'billref'::jsonb, '{"ok": false, "error": "refund_first"}'::jsonb, '4 (+) a bill refused after a valid code: its refusal');
select test.eq(:nw_stub::int, :nw, '4 (+) ... not counted');
select test.eq(:ref_stub || '/' || :appr_stub, '1/0', '4 (+) ... logged as discount_refused, and its approval rolled back');

-- 5) the owner's adjustment 1: the window never opens anything (build plan L3; mecanismo §13.1 item 5) -----------------
set role authenticated;
select test.calm485();
select test.unl485() as unl1 \gset
select test.n485('access_open') as ao1 \gset
select test.pins485() as pins1 \gset
select test.s485('TA') as ta \gset
select test.eq(test.c485(:'ta', 'guia', '7391', p_comp => 'Tours Monteverde') ->> 'role', 'owner', '5 the owner''s code gives Guía Turista at till A');
select test.eq(test.c485(:'ta', 'local', '4826') ->> 'ok', 'true', '5 Ana''s code gives Local there');
select test.eq(test.c485(:'ta', 'empleado', '4826', '8522') ->> 'beneficiary', 'Teo', '5 Ana''s and Teo''s give Empleado there');
select test.dev485(:'ta');
select test.ok(public.access_level() is null and not public.is_owner(), '5 access_level() stays null on that till');
select test.eq(test.unl485(), :unl1, '5 ... no access_unlocks row was written');
select test.eq(test.n485('access_open'), :ao1, '5 ... no owner area was opened (no access_open row)');
select test.eq(test.pins485(), :'pins1', '5 ... and no PIN counter or lock of anyone moved');

-- 6) people locked by 0033 do not block the window (scenario E1, mecanismo §1 item 5, §13.1 item 6) -----------------
select test.calm485();
select test.n485('discount_code_wrong') as nw \gset
select test.dev485('t485-evil');
select count(*) from (select public.access_unlock(p, '0000') from unnest(array[test.staff('ana'), test.p485('bea'), test.staff('dueno')]) p,
                             generate_series(1, 5)) q;
select test.eq(test.locked485(), 'Ana Bea Dueño', '6 from a minted sign-in, 5 wrong tries each at the unlock box lock Ana, Bea and the owner');
select test.pins485() as pinsl \gset
select test.s485('TB') as tb \gset
select test.eq(test.c485(:'tb', 'local', '4826') ->> 'ok', 'true', '6 at till B Ana''s right code still approves');
select test.eq(test.c485(:'ta', 'guia', '7391', p_comp => 'Tours Monteverde') ->> 'ok', 'true', '6 at till A the owner''s gives Guía');
select test.eq(test.c485(:'ta', 'local', '3917') ->> 'ok', 'true', '6 ... and Bea''s gives Local');
reset role;
select test.eq((select string_agg(manager_name || ':' || (details ->> 'person_locked'), ' ' order by id)
                  from (select * from public.audit_log where action = 'discount_approved' order by id desc limit 3) q),
               'Ana:true Dueño:true Bea:true', '6 ... each approval says person_locked (their PIN is locked at the name-picked boxes)');
set role authenticated;
select test.eq(test.pins485(), :'pinsl', '6 the 0033 counters and locks stay exactly as they were');
select test.eq(test.n485('discount_code_wrong'), :nw, '6 nothing counted');
select test.dev485(:'tb');
select test.eq(public.access_unlock(test.staff('ana'), '4826') ->> 'error', 'locked', '6 the name-picked box still says Ana is locked');
-- a locked employee is accepted too (Rosa locked at the time clock's own PIN box, hours_for)
select count(*) from (select public.hours_for(test.p485('rosa'), '0000', now(), now()) from generate_series(1, 5)) q;
select test.eq(test.pin1485('rosa'), '5/locked', '6 Rosa locked at the time clock');
select test.pins485() as pinsl \gset
select test.c485(:'ta', 'empleado', '4826', '8521') as er \gset
select test.eq((:'er'::jsonb) ->> 'beneficiary', 'Rosa', '6 a locked employee is accepted at the employee step');
reset role;
select test.eq((select (details ->> 'person_locked') || '/' || (details ->> 'employee_locked') from public.audit_log
                 where action = 'discount_approved' and target_id = (:'er'::jsonb) ->> 'id'), 'true/true',
               '6 ... the approval says both were locked');
set role authenticated;
select test.eq(test.pin1485('rosa'), '5/locked', '6 ... and Rosa''s counter did not move');
-- (R) scenario C: the managers kept locked, every tablet signs in again (new session ids)
select test.eq(test.vol485('TA', 't485-ta-c') ->> 'slot', :'sa', '6 (R) till A signs in again: back in its place by its key, no PIN');
select test.eq(test.vol485('TB', 't485-tb-c') ->> 'slot', :'sb', '6 (R) till B too');
select test.eq(test.c485('t485-ta-c', 'local', '4826') ->> 'ok', 'true', '6 (R) Ana''s right code approves at till A');
select test.eq(test.c485('t485-tb-c', 'local', '4826') ->> 'ok', 'true', '6 (R) ... and at till B');
select test.dev485('t485-new-c');
select test.eq(public.access_unlock(test.staff('ana'), '4826') ->> 'error', 'locked', '6 (R) a brand-new device cannot open the owner areas while Ana is locked');
select test.eq(public.descuento_caja_registrar('Nueva'), '{"ok": false, "error": "owner_only"}'::jsonb, '6 (R) ... so it cannot be registered (as documented: runbook E-lock)');
select test.eq(test.pins485(), :'pinsl', '6 (R) the locks are still exactly as they were');
-- the owner's SQL Editor tool clears every 0033 lock at once (pines-desbloquear.sql)
reset role;
select test.n485('pin_lock_cleared') as plc0 \gset
\o /dev/null
\ir ../../supabase/tools/pines-desbloquear.sql
\o
select test.eq(test.locked485(), '', '6 pines-desbloquear.sql clears every lock');
select test.eq((select string_agg(coalesce(manager_id::text, '-') || ':' || manager_name || ':' || (details ->> 'staff_name') || ':' || (details ->> 'how'), ' ' order by details ->> 'staff_name')
                  from (select * from public.audit_log where action = 'pin_lock_cleared' order by id desc limit 4) q),
               '-:owner (SQL Editor):Ana:sql_editor -:owner (SQL Editor):Bea:sql_editor -:owner (SQL Editor):Dueño:sql_editor -:owner (SQL Editor):Rosa:sql_editor',
               '6 ... one pin_lock_cleared row per person, by owner (SQL Editor), how sql_editor');
select test.eq(test.n485('pin_lock_cleared'), :plc0 + 4, '6 ... 4 rows, no more');
select test.eq((select string_agg(failed_pins::text, '') from public.staff where id in (test.staff('ana'), test.p485('bea'), test.staff('dueno'), test.p485('rosa'))),
               '0000', '6 ... and their counters are at 0');
select test.eq(public._pin_locks_clear_all('t485') - 'places', '{"ok": true, "cleared": 0, "still_locked": 0}'::jsonb, '6 run again: nothing to clear');
-- (R) the window writes no 0033 counter: 4 wrong tries (no lock yet) stay 4 across a right code at the window
set role authenticated;
select test.dev485('t485-evil');
select count(*) from (select public.access_unlock(test.staff('ana'), '0000') from generate_series(1, 4)) q;
select count(*) from (select public.hours_for(test.staff('marta'), '0000', now(), now()) from generate_series(1, 4)) q;
select test.eq(test.pin1485('ana') || ' ' || test.pin1485('marta'), '4/open 4/open', '6 (R) Ana and Marta: 4 wrong tries each, not locked');
select test.calm485();
select test.eq(test.c485('t485-ta-c', 'local', '4826') ->> 'ok', 'true', '6 (R) Ana''s right code approves at till A');
select test.eq(test.c485('t485-ta-c', 'empleado', '4826', '6173') ->> 'beneficiary', 'Marta', '6 (R) ... and an Empleado for Marta');
select test.eq(test.pin1485('ana') || ' ' || test.pin1485('marta'), '4/open 4/open',
               '6 (R) ... both counters still 4: the window never resets (nor counts) a 0033 counter');
select test.dev485('t485-evil');
select public.access_unlock(test.staff('ana'), '4826') ->> 'ok', public.hours_for(test.staff('marta'), '6173', now(), now()) ->> 'ok';
select test.eq(test.pin1485('ana') || ' ' || test.pin1485('marta'), '0/open 0/open', '6 (R) (their next right PIN at a name-picked box clears them, as before)');

-- 7) resuming a stopped place (mecanismo §5.2 descuento_caja_reanudar, §8, §13.1 item 7) ----------------------------
select test.calm485();
select test.reg485('TC', 't485-tc1', 'ana', 'Caja C') ->> 'slot' as sc \gset
select test.s485('TC') as tc \gset
select test.s485('TA') as ta \gset
select test.s485('TB') as tb \gset
select test.tid485(:'ta') as ida \gset
-- (R) scenario B: one wrong employee code after Ana's code, then the place stops
select test.c485(:'ta', 'empleado', '4826', '0000') ->> 'error' as be \gset
select test.eq(test.last485('discount_code_wrong') ->> 'manager_name', 'Ana', '7 (R) a wrong employee code at till A, after Ana''s code: the row names Ana');
select test.eq(test.hammer485(:'ta', 11) ->> 'blocked', 'stopped', '7 ... then 11 more: place A stopped');
select test.dev485(:'tb');
select test.eq(public.descuento_caja_reanudar(:sa, test.p485('bea'), '3917'), '{"ok": false, "error": "owner_only"}'::jsonb,
               '7 without the owner areas: owner_only');
select test.eq(public.descuento_cajas(), '{"ok": false, "error": "owner_only"}'::jsonb, '7 ... and the approvals log''s block: owner_only');
select test.open485(:'tb', 'bea');
select test.eq(jsonb_build_array(public.descuento_caja_reanudar(0, test.p485('bea'), '3917'), public.descuento_caja_reanudar(4, test.p485('bea'), '3917'),
                                 public.descuento_caja_reanudar(null, test.p485('bea'), '3917')),
               (select jsonb_agg('{"ok": false, "error": "not_found"}'::jsonb) from generate_series(1, 3)), '7 places 0, 4 and none: not_found');
select test.eq(public.descuento_caja_reanudar(:sb, test.p485('bea'), '3917'), '{"ok": false, "error": "not_stopped"}'::jsonb,
               '7 an open place: not_stopped');
select test.c485(:'tc', 'local', '0000'), test.c485(:'tc', 'local', '0000'), test.c485(:'tc', 'local', '0000');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_caja_reanudar(:sc, test.p485('bea'), '3917'), '{"ok": false, "error": "not_stopped"}'::jsonb,
               '7 a waiting place: not_stopped too (a wait ends by itself)');
select public.descuento_cajas() as dc \gset
select test.eq(test.keys485(:'dc'::jsonb), 'alert cafe_wrong_24h limits me ok places resumes_cafe_24h shared_code unknown_24h',
               '7 descuento_cajas answers ok, places, resumes_cafe_24h, cafe_wrong_24h, unknown_24h, alert, me, shared_code, limits');
select test.eq(jsonb_path_query_array(:'dc'::jsonb, '$.places[*].slot'), '[1, 2, 3]'::jsonb, '7 ... the 3 places, in order');
select test.eq(((:'dc'::jsonb) -> 'places' -> (:sa - 1)) - 'until' - 'till',
               '{"slot": 0, "state": "stopped", "wait": "stop", "wrong_24h": 12, "counted": 12, "resumes_24h": 0}'::jsonb || jsonb_build_object('slot', :sa::int),
               '7 ... place A stopped with 12 wrong codes in 24 h, 12 counted, never resumed');
select test.eq(((:'dc'::jsonb) #> array['places', (:sa - 1)::text, 'till']) - 'since' - 'last_used',
               jsonb_build_object('id', :'ida', 'station', 'Caja A', 'by', 'Ana', 'this_device', false),
               '7 ... its till: id, station, who registered it, since, last use; not this device');
select test.eq((:'dc'::jsonb) #> array['places', (:sb - 1)::text, 'till', 'this_device'], 'true'::jsonb, '7 ... till B is this device');
select test.eq((:'dc'::jsonb) -> 'limits', '{"resume_cafe": 2, "resume_slot": 1, "places_person": 2, "ends_person": 3, "enrolls_person": 6}'::jsonb,
               '7 ... the caps');
select test.eq((:'dc'::jsonb) -> 'me', '{"places": 1, "ends_24h": 0, "enrolls_24h": 0}'::jsonb, '7 ... and where Bea, whose unlock this is, stands');
select test.ok((:'dc'::text) !~ 't485-' and (:'dc'::text) !~ test.tag485(:'ta') and (:'dc'::text) !~ test.tag485(:'tb')
               and not exists (select 1 from test.allkeys485 k where strpos(:'dc', k.key) > 0),
               '7 ... no session id, tag or key leaves the server');
select test.eq(jsonb_build_array(public.descuento_caja_reanudar(:sa), public.descuento_caja_reanudar(:sa, test.p485('bea'), ' ')),
               '[{"ok": false, "error": "unknown_staff"}, {"ok": false, "error": "unknown_staff"}]'::jsonb, '7 nobody picked, or no PIN: unknown_staff');
select test.eq(public.descuento_caja_reanudar(:sa, test.staff('luis'), '5284'), '{"ok": false, "error": "not_manager"}'::jsonb,
               '7 a staff member: not_manager');
select test.eq(public.descuento_caja_reanudar(:sa, test.p485('bea'), '0000'), '{"ok": false, "error": "bad_pin"}'::jsonb, '7 Bea''s wrong PIN: bad_pin');
select test.eq(test.pin1485('bea'), '1/open', '7 ... counted on Bea''s own counter');
select test.eq(test.wrong485(:sa), 12, '7 ... never as a discount code');
reset role;
update public.staff set active = false where id = test.p485('bea');
set role authenticated;
select test.open485(:'tb', 'ana');
select test.eq(public.descuento_caja_reanudar(:sa, test.staff('ana'), '4826', 'Caja B'), jsonb_build_object('ok', true, 'slot', :sa::int, 'station', 'Caja A'),
               '7 (R) scenario B: Ana, the only manager now, resumes it, though her code came before the wrong employee code');
select test.eq(test.last485('discount_till_resumed') #- '{details,until}',
               jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana', 'target_id', :sa::text, 'details',
                 jsonb_build_object('slot', :sa::int, 'till', :'ida', 'till_station', 'Caja A', 'how', 'manager', 'day_n', 12,
                                    'station', 'Caja B', 'by_login', :'cafe', 'account', 'cafe')),
               '7 ... audit discount_till_resumed names her, the place, its till and the count it ended');
reset role;
update public.staff set active = true where id = test.p485('bea');
set role authenticated;
select test.dev485(:'ta');
select test.eq(public.descuento_estado() #>> '{till,state}', 'ok', '7 the counts restart: till A calm');
select test.eq(test.c485(:'ta', 'local', '4826') ->> 'ok', 'true', '7 ... and approves');
select test.open485(:'tb', 'bea');
select test.eq((public.descuento_cajas() -> 'places' -> (:sa - 1)) - 'until' - 'till' - 'state' - 'wait',
               jsonb_build_object('slot', :sa::int, 'wrong_24h', 12, 'counted', 0, 'resumes_24h', 1),
               '7 ... the log still shows its 12 wrong codes in 24 h, none counted, one resume');
select test.eq(public.descuento_cajas() -> 'resumes_cafe_24h', '1'::jsonb, '7 ... one of the café''s two');
select test.eq(test.hammer485(:'ta', 12) ->> 'blocked', 'stopped', '7 12 more: stopped again');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_caja_reanudar(:sa, test.p485('bea'), '0000'), jsonb_build_object('ok', false, 'error', 'resume_limit', 'until', test.stopend485(:sa)),
               '7 a 2nd resume of that place in 24 h: resume_limit {until it ends by itself}');
select test.eq(test.pin1485('bea'), '0/open', '7 ... answered before the PIN (Bea''s wrong one did not count)');
select test.eq(test.wrong485(:sa), 24, '7 till A: 12 before and 12 after its one resume, in 24 h');
select test.eq(test.hammer485(:'tb', 12) ->> 'blocked', 'stopped', '7 till B stopped');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_caja_reanudar(:sb, test.p485('bea'), '3917') ->> 'ok', 'true', '7 the café''s 2nd resume (another place)');
select test.eq(test.hammer485(:'tc', 9) ->> 'blocked', 'stopped', '7 till C stopped');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_caja_reanudar(:sc, test.p485('bea'), '3917'), jsonb_build_object('ok', false, 'error', 'resume_limit', 'until', test.stopend485(:sc)),
               '7 the café''s 3rd: resume_limit');
select test.login('owner', 'aal2');
select test.eq(public.descuento_caja_reanudar(:sc) ->> 'error', 'resume_limit', '7 ... for the owner with the phone code too (it shares the caps)');
-- the owner's SQL Editor tool resumes every stopped (or waiting) place, held or free, outside the caps
reset role;
\o /dev/null
\ir ../../supabase/tools/descuento-cajas-reanudar.sql
\o
select test.eq((select string_agg((details ->> 'slot') || ':' || coalesce(manager_id::text, '-') || ':' || manager_name || ':' || (details ->> 'how') || ':' || test.keys485(details), ' ' order by details ->> 'slot')
                  from public.audit_log where action = 'discount_till_resumed' and details ->> 'how' = 'sql_editor'),
               :sa || ':-:owner (SQL Editor):sql_editor:day_n how slot till till_station until ' || :sc || ':-:owner (SQL Editor):sql_editor:day_n how slot till till_station until',
               '7 descuento-cajas-reanudar.sql resumed places A and C (stopped), not B (calm), as owner (SQL Editor)');
set role authenticated;
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_cajas() -> 'resumes_cafe_24h', '2'::jsonb, '7 ... outside the caps (the café still counts 2)');
select test.eq(public.descuento_cajas() #> array['places', (:sa - 1)::text, 'resumes_24h'], '1'::jsonb, '7 ... and place A its one');
select test.ok(test.c485(:'ta', 'local', '4826') ->> 'ok' = 'true' and test.c485(:'tc', 'local', '4826') ->> 'ok' = 'true', '7 ... and A and C approve');
select test.c485(:'tb', 'local', '0000'), test.c485(:'tb', 'local', '0000'), test.c485(:'tb', 'local', '0000');
reset role;
select public._discount_tills_resume_all('t485 tool') as ra \gset
select test.eq(test.keys485(:'ra'::jsonb) || ' ' || ((:'ra'::jsonb) ->> 'resumed'), 'ok places resumed 1', '7 the tool function also resumes a waiting place: 1');
select test.eq((select string_agg(test.keys485(x), ' | ') from jsonb_array_elements((:'ra'::jsonb) -> 'places') x),
               'enrolled_by_name held slot state station until wrong_24h | enrolled_by_name held slot state station until wrong_24h | enrolled_by_name held slot state station until wrong_24h',
               '7 ... and ends with a summary of the 3 places');
set role authenticated;
select test.eq(test.c485(:'tb', 'local', '4826') ->> 'ok', 'true', '7 ... till B approves at once');
select test.calm485();
select test.eq(test.hammer485(:'ta', 12) ->> 'blocked', 'stopped', '7 a day later, till A stopped again');
select test.login('owner', 'aal2');
select test.eq(public.descuento_caja_reanudar(:sa), jsonb_build_object('ok', true, 'slot', :sa::int, 'station', 'Caja A'),
               '7 the owner with the phone code resumes it, no PIN');
select test.eq(test.last485('discount_till_resumed') - 'details', jsonb_build_object('manager_id', null, 'manager_name', :'owner_label', 'target_id', :sa::text),
               '7 ... logged under the owner''s label');
select test.eq(test.last485('discount_till_resumed') #>> '{details,how}', 'owner_code', '7 ... how: owner_code');
-- (R) scenario E: a stopped place with no till is listed and can be resumed
select test.eq(test.hammer485(:'tc', 12) ->> 'blocked', 'stopped', '7 (R) till C stopped');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485(:'tc'), test.p485('bea'), '3917') ->> 'ok', 'true', '7 (R) ... and its registration removed');
select test.eq((public.descuento_cajas() -> 'places' -> (:sc - 1)) - 'until', jsonb_build_object('slot', :sc::int, 'state', 'stopped', 'wait', 'stop',
                 'wrong_24h', 12, 'counted', 12, 'resumes_24h', 0, 'till', null),
               '7 (R) the log lists it: «Puesto n: libre · Detenida»');
reset role;
select test.eq(public._discount_tills_resume_all('t485 tool') ->> 'resumed', '1', '7 (R) the owner''s tool resumes the free stopped place');
select test.eq(test.last485('discount_till_resumed') #>> '{details,till}', null, '7 (R) ... a resume without a till');
set role authenticated;
select test.reg485('TD', 't485-td1', 'ana', 'Caja D') ->> 'slot' as sd \gset
select test.eq(:sd::int, :sc::int, '7 (R) a new device lands in that free place');
select test.eq(test.hammer485('t485-td1', 12) ->> 'blocked', 'stopped', '7 (R) ... is stopped there');
select test.open485(:'tb', 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-td1'), test.p485('bea'), '3917') ->> 'ok', 'true', '7 (R) ... and removed');
select test.eq(public.descuento_caja_reanudar(:sc, test.p485('bea'), '3917'), jsonb_build_object('ok', true, 'slot', :sc::int, 'station', null),
               '7 (R) a manager resumes the free stopped place by its number');
reset role;

-- 8) endings (mecanismo §5.2 descuento_caja_quitar, §13.1 item 8; L1: no descuento_caja_cerrar) ----------------------
set role authenticated;
select test.fresh485();
select test.reg485('EA', 't485-ea1', 'ana', 'Caja A') ->> 'slot' as sa \gset
select test.reg485('EB', 't485-eb1', 'bea', 'Caja B') ->> 'slot' as sb \gset
select test.tid485('t485-ea1') as ida \gset
select test.n485('discount_till_enrolled') as ne8 \gset
select test.c485('t485-ea1', 'local', '0000'), test.c485('t485-ea1', 'local', '0000');
select test.dev485('t485-eb1');
select test.eq(public.descuento_caja_quitar(:'ida', test.p485('bea'), '3917'), '{"ok": false, "error": "owner_only"}'::jsonb,
               '8 without the owner areas: owner_only');
select test.open485('t485-eb1', 'bea');
select test.eq(public.descuento_caja_quitar(gen_random_uuid(), test.p485('bea'), '3917'), '{"ok": false, "error": "not_found"}'::jsonb,
               '8 a till that is not registered: not_found');
select test.eq(jsonb_build_array(public.descuento_caja_quitar(:'ida'), public.descuento_caja_quitar(:'ida', test.p485('bea'), '')),
               '[{"ok": false, "error": "unknown_staff"}, {"ok": false, "error": "unknown_staff"}]'::jsonb, '8 nobody picked, or no PIN: unknown_staff');
select test.eq(public.descuento_caja_quitar(:'ida', test.p485('bea'), '0000'), '{"ok": false, "error": "bad_pin"}'::jsonb, '8 a wrong PIN: bad_pin');
select test.ok(test.pin1485('bea') = '1/open' and test.tid485('t485-ea1') = :'ida', '8 ... counted on Bea, and nothing removed');
select test.eq(public.descuento_caja_quitar(:'ida', test.p485('bea'), '3917', 'Caja B'), jsonb_build_object('ok', true, 'station', 'Caja A', 'slot', :sa::int),
               '8 Bea removes till A''s registration');
select test.eq(test.till485(:'ida') - 'id' - 'enrolled_at' - 'last_used_at' - 'ended_at' - 'session_id' - 'login_id' - 'enrolled_by' - 'enrolled_by_name' - 'rebound_from',
               jsonb_build_object('slot', :sa::int, 'station', 'Caja A', 'key_hash', null, 'prev_key_hash', null, 'ended_by', test.p485('bea'),
                                  'ended_by_name', 'Bea', 'ended_how', 'manager'),
               '8 ... the row stays, ended by Bea (manager), its key spent');
select test.eq(test.last485('discount_till_ended'),
               jsonb_build_object('manager_id', test.p485('bea'), 'manager_name', 'Bea', 'target_id', :'ida', 'details',
                 jsonb_build_object('till', :'ida', 'slot', :sa::int, 'till_station', 'Caja A', 'how', 'manager', 'station', 'Caja B',
                                    'by_login', :'cafe', 'account', 'cafe')),
               '8 ... audit discount_till_ended {how: manager}');
select test.eq(test.c485('t485-ea1', 'local', '4826'), '{"ok": false, "error": "till_ended"}'::jsonb, '8 till A hears till_ended');
select test.eq(test.vol485('EA', 't485-ea2'), '{"ok": false, "error": "key_invalid"}'::jsonb, '8 ... and its key on its next sign-in: key_invalid');
select test.open485('t485-eb1', 'bea');
select test.eq(public.descuento_caja_quitar(:'ida', test.p485('bea'), '3917'), '{"ok": false, "error": "not_found"}'::jsonb, '8 removing it again: not_found');
select test.eq((public.descuento_cajas() -> 'places' -> (:sa - 1)) - 'until' - 'state' - 'wait' - 'resumes_24h',
               jsonb_build_object('slot', :sa::int, 'wrong_24h', 2, 'counted', 2, 'till', null), '8 its place keeps its count, free');
select test.eq(test.reg485('EA', 't485-ea1', 'ciro', 'Caja A') ->> 'slot', :'sa',
               '8 a manager registers that same sign-in again (a new row): back in its old place, the most used free one');
select test.dev485('t485-ea1');
select test.eq(public.descuento_estado() #>> '{till,by}', 'Ciro', '8 ... «registrada (Ciro, …)»');
select test.eq(test.n485('discount_till_enrolled') - :ne8, 1, '8 ... one registration more');
select test.login('owner', 'aal2');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-ea1')) ->> 'ok', 'true', '8 (removed again, with the phone code)');
set role authenticated;
-- Ana's 4th removal in 24 h: end_limit before the PIN, while Bea, under 3, removes at once
select test.reg485('X', 't485-x1', 'bea', 'Caja X');
select test.open485('t485-ea2', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-x1'), test.staff('ana'), '4826') ->> 'ok', 'true', '8 Ana removes X (1)');
select test.reg485('X', 't485-x2', 'bea', 'Caja X');
select test.open485('t485-ea2', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-x2'), test.staff('ana'), '4826') ->> 'ok', 'true', '8 ... (2)');
select test.reg485('X', 't485-x3', 'bea', 'Caja X');
select test.open485('t485-ea2', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-x3'), test.staff('ana'), '4826') ->> 'ok', 'true', '8 ... (3)');
select test.reg485('X', 't485-x4', 'bea', 'Caja X');
select test.open485('t485-ea2', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-x4'), test.staff('ana'), '0000'), '{"ok": false, "error": "end_limit"}'::jsonb,
               '8 her 4th: end_limit');
select test.ok(test.pin1485('ana') = '0/open' and test.tid485('t485-x4') is not null, '8 ... before the PIN, and nothing removed');
select test.open485('t485-eb1', 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-x4'), test.p485('bea'), '3917') ->> 'ok', 'true', '8 Bea removes it at once');
select test.login('owner', 'aal2');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-eb1')), jsonb_build_object('ok', true, 'station', 'Caja B', 'slot', :sb::int),
               '8 the owner with the phone code removes a till, no PIN, no cap');
select test.eq((select (x ->> 'ended_how') || ':' || coalesce(x ->> 'ended_by', '-') || ':' || (x ->> 'ended_by_name')
                  from (select test.rowof485('t485-eb1') x) q),
               'owner:-:' || :'owner_label', '8 ... ended owner, under the owner''s label');
select test.eq(test.last485('discount_till_ended') #>> '{details,how}', 'owner', '8 ... audit how owner');
-- _discount_tills_end_all: every live till ended and every key spent, signed-out ones too (a fixture row: no function
-- writes signed_out in this build, L1)
select test.reg485('Y1', 't485-y1a', 'ana', 'Caja Y1');
select test.reg485('Y2', 't485-y2a', 'ana', 'Caja Y2');
reset role;
insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by, enrolled_by_name, key_hash, ended_at, ended_how)
  select g, 't485-so0', :'cafe', 'Caja SO', test.staff('ana'), 'Ana', test.hash485(md5('t485-so0') || md5('t485-so0b')), now(), 'signed_out'
    from generate_series(1, 3) g where not exists (select 1 from public.discount_tills t where t.slot = g and t.ended_at is null) limit 1;
select test.eq(test.endall485('t485 end_all') - 'places', '{"ok": true, "ended": 2, "keys_spent": 3}'::jsonb,
               '8 _discount_tills_end_all: 2 tills ended, 3 keys spent (the signed-out row''s too)');
select test.eq((select count(*)::int from public.discount_tills where ended_at is null or key_hash is not null), 0, '8 ... no live till, no live key');
select test.eq((select string_agg(coalesce(manager_id::text, '-') || ':' || manager_name || ':' || test.keys485(details) || ':' || (details ->> 'how'), ' | ')
                  from (select * from public.audit_log where action = 'discount_till_ended' order by id desc limit 2) q),
               '-:t485 end_all:how slot till till_station:sql_editor | -:t485 end_all:how slot till till_station:sql_editor', '8 ... one row per till, how sql_editor');
set role authenticated;
select test.eq(jsonb_build_array(test.vol485('Y1', 't485-y1b'), test.vol485('Y2', 't485-y2b'), test.volk485('t485-so1', md5('t485-so0') || md5('t485-so0b'))),
               (select jsonb_agg('{"ok": false, "error": "key_invalid"}'::jsonb) from generate_series(1, 3)), '8 ... and every one of those keys: key_invalid');
select test.eq(test.endall485('t485 end_all') - 'places', '{"ok": true, "ended": 0, "keys_spent": 0}'::jsonb, '8 run again: nothing left');
select test.ok(to_regprocedure('public.descuento_caja_cerrar()') is null, '8 descuento_caja_cerrar is not built (L1: a signed-out tablet comes back by its key)');

-- 9) places keep their counts: no fresh budget by signing in again (mecanismo §1 item 3, §13.1 item 9, scenario D) -----
reset role;
-- each cycle: a new sign-in on the counter, then one wrong code there; (a) the page rebinds it by its key; (b) the key
-- is gone, the owner removes the stale registration and a manager registers the new sign-in
create function test.cyc485(p_dev text, p_n int, p_mode text) returns jsonb language plpgsql as $$
declare i int; r jsonb; w jsonb; s text; slots int[] := '{}'; errs text[] := '{}'; rem text[] := '{}';
begin
  for i in 1 .. p_n loop
    s := 't485-' || lower(p_dev) || '-' || p_mode || i;
    if p_mode = 'key' then
      r := test.vol485(p_dev, s);
    else
      update test.devs485 set key = null where dev = p_dev;
      perform test.login('owner', 'aal2');
      rem := rem || (public.descuento_caja_quitar(test.tid485(test.s485(p_dev))) ->> 'ok');
      r := test.reg485(p_dev, s, case i % 3 when 0 then 'ana' when 1 then 'bea' else 'ciro' end, 'Mostrador');
    end if;
    slots := slots || coalesce((r ->> 'slot')::int, 0);
    w := test.c485(s, 'local', '0000');
    errs := errs || coalesce(w ->> 'blocked', w ->> 'error');
    perform test.back485(interval '10 minutes 1 second');
  end loop;
  return jsonb_build_object('slots', to_jsonb(slots), 'answers', to_jsonb(errs), 'removed', to_jsonb(rem));
end $$;
set role authenticated;
select test.fresh485();
select test.reg485('CTR', 't485-ctr0', 'ana', 'Mostrador') ->> 'slot' as sp \gset
select test.reg485('IPD', 't485-ipd0', 'bea', 'iPad') ->> 'slot' as sq \gset
select test.eq(6 - :sp - :sq, 3, '9 the counter and the iPad in places 1 and 2; place 3 free');
select test.hammer485('t485-ctr0', 11);
select test.eq(test.wrong485(:sp), 11, '9 11 wrong codes at the counter');
select test.cyc485('CTR', 10, 'key') as cy \gset
select test.eq((:'cy'::jsonb) -> 'slots', (select jsonb_agg(:sp::int) from generate_series(1, 10)), '9 (a) 10 new sign-ins: the key brings it back to its own place every time');
select test.eq((:'cy'::jsonb) -> 'answers', '["stopped"]'::jsonb || (select jsonb_agg('till_stopped'::text) from generate_series(1, 9)),
               '9 (a) ... the first cycle''s wrong code stops the place, every later one is refused untested');
select test.eq(test.wrong485(:sp), 12, '9 (a) still exactly 12 in 24 h');
select test.eq(test.state485(:sp) ->> 'state', 'stopped', '9 (a) ... and the place is stopped');
-- the L1 residual (mecanismo §12 item 13): a tablet that lost its key while its old row stays live, registered again
-- by a manager while a clean place is free, starts there (the registration names that manager)
update test.devs485 set key = null where dev = 'CTR';
select test.eq(test.reg485('LOST', 't485-lost1', 'ana', 'Mostrador') ->> 'slot', '3', '9 L1 residual: the counter without its key, its stale row live, lands in free place 3');
select test.eq(test.last485('discount_till_enrolled') ->> 'manager_name', 'Ana', '9 ... and that registration names Ana');
select test.open485('t485-ipd0', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-lost1'), test.staff('ana'), '4826') ->> 'ok', 'true', '9 (removed again: place 3 free)');
-- (R) scenario D (b): the key is gone, the owner removes the stale row, a manager registers the new sign-in
select test.cyc485('CTR', 10, 'reg') as cy \gset
select test.eq((:'cy'::jsonb) -> 'removed', (select jsonb_agg('true'::text) from generate_series(1, 10)), '9 (b) each stale registration removed by the owner');
select test.eq((:'cy'::jsonb) -> 'slots', (select jsonb_agg(:sp::int) from generate_series(1, 10)),
               '9 (b) 10 registrations of a new sign-in: back in the stopped place every time (the most used free place), never the clean place 3');
select test.eq((:'cy'::jsonb) -> 'answers', (select jsonb_agg('till_stopped'::text) from generate_series(1, 10)), '9 (b) ... every wrong code refused untested');
select test.eq(test.wrong485(:sp) || ' ' || test.wrong485(3), '12 0', '9 (b) still 12 at the counter''s place, 0 in place 3');
select test.open485('t485-ipd0', 'bea');
select test.eq(public.descuento_caja_reanudar(:sp, test.p485('bea'), '3917') ->> 'ok', 'true', '9 (b) the counter''s place gets its one resume');
select test.eq(test.hammer485(test.s485('CTR'), 12) ->> 'blocked', 'stopped', '9 (b) ... 12 more stop it again');
select test.eq(test.wrong485(:sp) || ' ' || test.wrong485(3), '24 0', '9 (b) 24 wrong codes tested at that tablet in 24 h, and place 3 untouched');
select test.ok(test.tid485('t485-lost1') is null and not exists (select 1 from test.devs485 where sess like 't485-ctr-%' and test.slot485(sess) = 3),
               '9 (b) ... the counter never moved to place 3');
select test.open485('t485-ipd0', 'bea');
select test.eq(public.descuento_caja_reanudar(:sp, test.p485('bea'), '3917') ->> 'error', 'resume_limit', '9 (b) a 2nd resume of its place: resume_limit');
select test.eq(test.hammer485('t485-ipd0', 12) ->> 'blocked', 'stopped', '9 (b) the iPad stopped');
select test.open485('t485-ipd0', 'bea');
select test.eq(public.descuento_caja_reanudar(:sq, test.p485('bea'), '3917') ->> 'ok', 'true', '9 (b) ... can still be resumed (the café''s second)');

-- 13) the device key: global sign-outs never use anything up (scenario A1, mecanismo §4, §5.2 volver, §13.1 item 13) --
reset role;
create function test.round485(r int) returns text language plpgsql as $$
declare d text; old text; slot0 int; x jsonb; o jsonb; res text := '';
begin
  for d in select unnest(array['G1', 'G2', 'G3']) loop
    old := (select key from test.devs485 where dev = d);
    slot0 := test.slot485(test.s485(d));
    x := test.vol485(d, 't485-' || lower(d) || '-r' || r);
    o := test.volk485('t485-mint-r' || r || d, old);
    res := res || d || ':' || coalesce(x ->> 'error', 'ok') || ':' || case when (x ->> 'slot')::int = slot0 then 'same' else 'moved' end || ':'
           || case when x ->> 'key' ~ '^[0-9a-f]{64}$' and x ->> 'key' <> old then 'new' else 'old' end || ':' || (o ->> 'error') || ' ';
  end loop;
  return rtrim(res);
end $$;
set role authenticated;
select test.fresh485();
select test.reg485('G1', 't485-g1-r0', 'ana', 'Caja 1') ->> 'slot' as g1 \gset
select test.reg485('G2', 't485-g2-r0', 'ana', 'Caja 2') ->> 'slot' as g2 \gset
select test.reg485('G3', 't485-g3-r0', 'bea', 'iPad') ->> 'slot' as g3 \gset
select test.c485('t485-g1-r0', 'local', '0000'), test.c485('t485-g1-r0', 'local', '0000'), test.c485('t485-g2-r0', 'local', '0000');
select test.n485('discount_till_ended') as ne0 \gset
select test.n485('discount_till_rebound') as nr0 \gset
select test.dev485('t485-g1-pre');
select test.eq(public.descuento_estado() -> 'till', '{"registered": false, "ended": false}'::jsonb,
               '13 a new sign-in on till 1 before the page uses its key: descuento_estado says not registered (it never rebinds)');
select test.eq(test.n485('discount_till_rebound'), :nr0, '13 ... and wrote nothing');
select test.eq(test.round485(r), 'G1:ok:same:new:key_invalid G2:ok:same:new:key_invalid G3:ok:same:new:key_invalid',
               '13 (R) global sign-out, round ' || r || ': every tablet back in its place by its key, a new key, the old one spent')
  from generate_series(1, 5) r;
select test.eq(test.wrong485(:g1) || ' ' || test.wrong485(:g2) || ' ' || test.wrong485(:g3), '2 1 0', '13 (R) ... each place''s wrong-code count unchanged');
select test.eq(test.n485('discount_till_ended'), :ne0, '13 (R) ... no discount_till_ended row');
select test.eq(test.person485('ana') || ' ' || test.person485('bea'), '2/0/2 1/0/1', '13 (R) ... nothing counted on anyone (places, endings, registrations)');
select test.eq(test.n485('discount_till_rebound'), :nr0 + 15, '13 (R) ... 15 rebinds logged as discount_till_rebound');
reset role;
select test.eq((select string_agg(distinct test.keys485(details) || ':' || (details ->> 'how') || ':' || coalesce(manager_name, '-'), ' | ')
                  from public.audit_log where action = 'discount_till_rebound'),
               'account by_login how old_till session_tag slot till till_station:live:-', '13 (R) ... each with these keys only (no key, no session id)');
select test.ok((select bool_and(details ->> 'session_tag' = test.tag485(t.session_id) and t.rebound_from::text = details ->> 'old_till')
                  from public.audit_log a join public.discount_tills t on t.id::text = a.details ->> 'till' where a.action = 'discount_till_rebound'),
               '13 (R) ... naming the new row, the row it replaced and the new sign-in''s tag');
set role authenticated;
select test.eq(test.c485(test.s485('G1'), 'local', '4826') ->> 'ok', 'true', '13 (R) till 1 approves on its 6th sign-in');
select test.dev485(test.s485('G1'));
select test.eq((public.descuento_estado() -> 'till') - 'state' - 'until' - 'wait' - 'wait_s' - 'warn',
               jsonb_build_object('registered', true, 'slot', :g1::int, 'station', 'Caja 1', 'by', 'Ana',
                                  'since', (test.rowof485('t485-g1-r0') ->> 'enrolled_at')::timestamptz),
               '13 (R) ... still «registrada (Ana, …)» since its first registration (a rebind carries who and when)');
select test.eq(test.c485('t485-g1-r0', 'local', '4826'), '{"ok": false, "error": "till_ended"}'::jsonb, '13 (R) its first sign-in now hears till_ended');
select test.eq((select (x ->> 'ended_how') || ':' || (x ->> 'ended_by_name') || ':' || coalesce(x ->> 'key_hash', '-') from (select test.rowof485('t485-g1-r0') x) q),
               'rebound:rebind:-', '13 (R) ... its row ended rebound, its key spent');
select test.eq(test.reg485('G4', 't485-g4-r0', 'bea', 'Caja 4', test.tid485(test.s485('G3'))) ->> 'replaced', 'iPad',
               '13 (R) a manager can still register a new device during service (Bea replaces her own)');
-- the rebind rules
select test.eq(jsonb_build_array(test.volk485('t485-k1', null), test.volk485('t485-k1', repeat('a', 63)), test.volk485('t485-k1', upper((select key from test.devs485 where dev = 'G1'))),
                                 test.volk485('t485-k1', md5('t485-nokey') || md5('t485-nokey2'))),
               (select jsonb_agg('{"ok": false, "error": "key_invalid"}'::jsonb) from generate_series(1, 4)),
               '13 a minted sign-in with no key, a short key, a key in capitals or a wrong key: key_invalid');
select test.eq(test.vol485('G1', test.s485('G1')), jsonb_build_object('ok', true, 'already', true, 'station', 'Caja 1', 'slot', :g1::int),
               '13 a sign-in that is already live: already');
select test.login('owner', 'aal2');
select test.session('t485-own1');
select test.eq(public.descuento_caja_volver((select key from test.devs485 where dev = 'G1')), '{"ok": false, "error": "key_invalid"}'::jsonb,
               '13 the café''s key on another login (the owner''s): key_invalid (a key is bound to its login)');
select test.eq(test.vol485('G1', 't485-g1-r6') ->> 'slot', :'g1', '13 a 6th rebind of place ' || :g1 || ' within the hour');
select test.eq(test.vol485('G1', 't485-g1-r7'), jsonb_build_object('ok', false, 'error', 'rebind_limit', 'until', now() + interval '1 hour'),
               '13 the 7th: rebind_limit {until the oldest is an hour old}');
select test.ok(test.tid485('t485-g1-r6') is not null and test.tid485('t485-g1-r7') is null, '13 ... the till stays on its 6th sign-in');
select test.back485(interval '61 minutes');
select test.eq(test.vol485('G1', 't485-g1-r7') ->> 'slot', :'g1', '13 an hour later it rebinds again, in the same place');
select test.eq(test.hammer485(test.s485('G2'), 11) ->> 'blocked', 'stopped', '13 place ' || :g2 || ' stopped');
select test.vol485('G2', 't485-g2-r6') as rs \gset
select test.eq((:'rs'::jsonb) - 'key' - 'wait_s', jsonb_build_object('ok', true, 'station', 'Caja 2', 'slot', :g2::int, 'state', 'stopped',
                                                     'until', test.stopend485(:g2), 'wait', 'stop'),
               '13 a rebind into a stopped place: the place stays stopped, and the answer says so');
select test.eq(test.c485('t485-g2-r6', 'local', '4826') ->> 'error', 'till_stopped', '13 ... the new sign-in hears till_stopped');
select test.eq(test.vol485('G2', 't485-g2-r7', 'Caja dos') ->> 'station', 'Caja dos', '13 a rebind may rename the station (the page''s saved name)');
select test.eq(test.vol485('G2', 't485-g2-r8') ->> 'station', 'Caja dos', '13 ... and without one keeps the old');
-- a signed-out row's key (fixture rows: L1, no function writes signed_out; the server still honours one while its place
-- is free, and spends it once another device takes the place)
select test.open485(test.s485('G4'), 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485(test.s485('G2')), test.p485('bea'), '3917') ->> 'ok', 'true', '13 (place ' || :g2 || ' freed)');
reset role;
insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by, enrolled_by_name, key_hash, ended_at, ended_how)
  values (:g2, 't485-so1', :'cafe', 'Caja SO', test.staff('ana'), 'Ana', test.hash485(md5('t485-so1') || md5('t485-so1b')), now(), 'signed_out');
set role authenticated;
select test.volk485('t485-so1b', md5('t485-so1') || md5('t485-so1b')) as rso \gset
select test.eq((:'rso'::jsonb) - 'key' - 'until' - 'wait_s', jsonb_build_object('ok', true, 'station', 'Caja SO', 'slot', :g2::int, 'state', 'stopped', 'wait', 'stop'),
               '13 a signed-out row''s key while its place is free: back in that place, which keeps its stop');
select test.eq(test.last485('discount_till_rebound') #>> '{details,how}', 'signed_out', '13 ... logged how signed_out');
select test.eq((select (x ->> 'ended_how') || ':' || coalesce(x ->> 'key_hash', '-') from (select test.rowof485('t485-so1') x) q), 'signed_out:-',
               '13 ... the old row keeps its ending, its key spent');
reset role;
insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by, enrolled_by_name, key_hash, ended_at, ended_how)
  values (:g1, 't485-so2', :'cafe', 'Caja SO', test.staff('ana'), 'Ana', test.hash485(md5('t485-so2') || md5('t485-so2b')), now(), 'signed_out');
set role authenticated;
select test.eq(test.volk485('t485-so2b', md5('t485-so2') || md5('t485-so2b')), '{"ok": false, "error": "key_invalid"}'::jsonb,
               '13 a signed-out row''s key while another device holds its place: key_invalid');
select test.open485(test.s485('G4'), 'bea');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-so1b'), test.p485('bea'), '3917') ->> 'ok', 'true', '13 (place ' || :g2 || ' freed again)');
reset role;
insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by, enrolled_by_name, key_hash, ended_at, ended_how)
  values (:g2, 't485-so3', :'cafe', 'Caja SO', test.staff('ana'), 'Ana', test.hash485(md5('t485-so3') || md5('t485-so3b')), now(), 'signed_out');
set role authenticated;
select test.eq(test.reg485('G5', 't485-g5-r0', 'ciro', 'Caja 5') ->> 'slot', :'g2', '13 another device registers into that free place');
select test.eq(coalesce(test.rowof485('t485-so3') ->> 'key_hash', '-'), '-', '13 ... which spends the signed-out row''s key');
select test.eq(test.volk485('t485-so3b', md5('t485-so3') || md5('t485-so3b')), '{"ok": false, "error": "key_invalid"}'::jsonb, '13 ... so it no longer works');

-- 14) one person cannot hold the café (scenario A2, mecanismo §3, §8, §13.1 item 14) --------------------------------
reset role;
create function test.held485(p_who text) returns int language sql stable security definer as $$
  select count(*)::int from public.discount_tills where ended_at is null and enrolled_by = test.p485(p_who) $$;
set role authenticated;
select test.fresh485();
select test.reg485('H1', 't485-h1-0', 'bea', 'Mostrador') ->> 'slot' as h1 \gset
select test.eq(test.reg485('M1', 't485-mint-m1', 'ana', 'M1') ->> 'ok', 'true', '14 (R) Ana, with the café password and her PIN, registers a minted sign-in');
select test.eq(test.reg485('M2', 't485-mint-m2', 'ana', 'M2') ->> 'ok', 'true', '14 (R) ... and a second');
select test.eq(test.reg485('M3', 't485-mint-m3', 'ana', 'M3') ->> 'error', 'person_limit', '14 (R) ... a third: person_limit');
select test.eq(test.reg485('M3', 't485-mint-m3', 'ana', 'M3', test.tid485('t485-h1-0')) ->> 'error', 'person_limit',
               '14 (R) ... nor can she replace the honest till Bea registered');
select test.eq(test.held485('ana') || ' ' || coalesce(test.slot485('t485-h1-0')::text, 'gone'), '2 ' || :h1, '14 (R) she holds 2; the honest till is untouched');
select test.open485('t485-mint-m1', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-mint-m2'), test.staff('ana'), '4826') ->> 'ok', 'true', '14 (R) she removes one of hers (1)');
select test.eq(test.reg485('M3', 't485-mint-m3', 'ana', 'M3') ->> 'ok', 'true', '14 (R) ... registers another');
select test.open485('t485-mint-m3', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-mint-m1'), test.staff('ana'), '4826') ->> 'ok', 'true', '14 (R) ... removes one more (2)');
select test.reg485('H2', 't485-h2-0', 'bea', 'iPad') ->> 'slot' as h2 \gset
select test.eq(test.reg485('M4', 't485-mint-m4', 'ana', 'M4'),
               jsonb_build_object('ok', false, 'error', 'till_full', 'places', test.places485(test.staff('ana'), false)),
               '14 (R) the café full: her next registration is till_full, and no till ends by itself');
select test.eq(test.reg485('M4', 't485-mint-m4', 'ana', 'M4', test.tid485('t485-h1-0')) ->> 'replaced', 'Mostrador',
               '14 (R) only an explicit replacement naming the honest till ends it (3)');
select test.eq(test.person485('ana'), '2/3/4', '14 (R) ... counted on her: 2 places, 3 endings, 4 registrations');
select test.eq(test.last485('discount_till_ended') ->> 'manager_name', 'Ana', '14 (R) ... and the log names her');
select test.eq(test.reg485('M5', 't485-mint-m5', 'ana', 'M5', test.tid485('t485-h2-0')) ->> 'error', 'person_limit', '14 (R) at 2 places she cannot replace the iPad');
select test.eq(test.reg485('M5', 't485-mint-m5', 'ana', 'M5', test.tid485('t485-mint-m3')) ->> 'error', 'end_limit', '14 (R) ... nor one of her own: end_limit');
select test.open485('t485-mint-m3', 'ana');
select test.eq(public.descuento_caja_quitar(test.tid485('t485-h2-0'), test.staff('ana'), '4826') ->> 'error', 'end_limit', '14 (R) ... nor remove the iPad: end_limit');
select test.eq(test.held485('ana'), 2, '14 (R) she never held more than 2 places');
select test.eq(test.reg485('H1', 't485-h1-1', 'bea', 'Mostrador', test.tid485('t485-mint-m4')) ->> 'replaced', 'M4',
               '14 (R) Bea, with her own allowance, puts the counter back in place of Ana''s');
reset role;
\o /dev/null
\ir ../../supabase/tools/descuento-cajas-quitar-todas.sql
\o
select test.eq((select count(*)::int from public.discount_tills where ended_at is null or key_hash is not null), 0,
               '14 (R) the owner runs descuento-cajas-quitar-todas.sql: no live till, no live key');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_till_ended' and manager_name = 'owner (SQL Editor)' and details ->> 'how' = 'sql_editor'), 3,
               '14 (R) ... one row per till, by owner (SQL Editor)');
set role authenticated;
select test.eq(jsonb_build_array(test.vol485('M3', 't485-mint-m3b'), test.vol485('M4', 't485-mint-m4b')),
               '[{"ok": false, "error": "key_invalid"}, {"ok": false, "error": "key_invalid"}]'::jsonb, '14 (R) Ana''s old keys: key_invalid');
select test.eq((test.reg485('H1', 't485-h1-2', 'bea', 'Mostrador') ->> 'ok') || (test.reg485('H2', 't485-h2-2', 'bea', 'iPad') ->> 'ok'), 'truetrue',
               '14 (R) Bea registers the honest tablets into the freed places at once');

-- the café-wide signal that pauses nothing, and what the log shows (mecanismo §1 item 8, §3, §5.2 descuento_cajas) ---
select test.calm485();
select test.reg485('H3', 't485-h3-2', 'ciro', 'Terraza') ->> 'slot' as h3 \gset
select test.n485('discount_alert') as na0 \gset
select test.c485(s, 'local', '0000') from (values ('t485-h1-2'), ('t485-h2-2'), ('t485-h3-2')) v(s), generate_series(1, 3);
select test.eq(test.n485('discount_alert'), :na0, '15 9 wrong codes across the café in 24 h: no alert');
select test.back485(interval '31 seconds');
select test.c485('t485-h1-2', 'local', '0000');
select test.eq(test.n485('discount_alert'), :na0 + 1, '15 the 10th: one discount_alert row');
select test.eq(test.last485('discount_alert'), jsonb_build_object('manager_id', null, 'manager_name', null, 'target_id', null,
                                                                  'details', jsonb_build_object('cafe_24h', 10, 'by_login', :'cafe')),
               '15 ... with the café''s count and the login');
select test.back485(interval '1 minute 1 second');
select test.c485('t485-h2-2', 'local', '0000');
select test.eq(test.n485('discount_alert'), :na0 + 1, '15 the 11th: no second alert within 24 h');
select test.back485(interval '5 minutes 1 second');
select test.eq(test.c485('t485-h3-2', 'local', '4826') ->> 'ok', 'true', '15 ... and it pauses nothing: a till approves');
select test.c485('t485-mint-15' || i, 'local', '4826') from generate_series(1, 3) i;
select test.open485('t485-h3-2', 'ciro');
select public.descuento_cajas() as dc \gset
select test.eq((:'dc'::jsonb) -> 'alert', jsonb_build_object('at', test.lastat485('discount_alert'), 'cafe_24h', 10),
               '15 the approvals log shows the alert');
select test.eq((:'dc'::jsonb) -> 'cafe_wrong_24h', '11'::jsonb, '15 ... the café''s wrong codes in 24 h');
select test.eq((:'dc'::jsonb) -> 'unknown_24h', '3'::jsonb, '15 ... and the codes typed on unregistered devices (3)');
select test.calm485();
select test.eq(public.descuento_cajas() -> 'alert', 'null'::jsonb, '15 a day later: no alert');
select test.back485(interval '8 days');
select test.open485('t485-h3-2', 'ciro');
select test.eq(public.descuento_cajas() -> 'shared_code', 'null'::jsonb, '15 a week after the last pin_duplicate row: no shared-code notice');
select test.login('owner', 'aal2');
select test.eq(public.descuento_cajas() -> 'me', 'null'::jsonb, '15 with the phone code, no «Usted» part (me null)');
select test.session('t485-own3');
select test.eq(public.descuento_caja_registrar('Teléfono del dueño', test.tid485('t485-h3-2')) - 'key' - 'slot' - 'state' - 'until' - 'wait' - 'wait_s',
               '{"ok": true, "station": "Teléfono del dueño", "by": "Dueño", "replaced": "Terraza"}'::jsonb,
               '15 the owner, with the phone code on a device of their own login, registers it in place of a till: by Dueño, outside every cap');
select test.eq(test.last485('discount_till_enrolled') ->> 'manager_name', :'owner_label', '15 ... logged under the owner''s label');
select test.eq(test.last485('discount_till_ended') - 'target_id' - 'details', jsonb_build_object('manager_id', null, 'manager_name', :'owner_label'),
               '15 ... and so is the replacement');
select test.ok(test.till485(test.tid485('t485-own3')) ->> 'enrolled_by' is null, '15 ... it is nobody''s per-person allowance');
select test.eq(test.till485(test.tid485('t485-own3')) ->> 'login_id', '0e000000-0000-4000-8000-000000000002', '15 ... and is bound to the owner''s login');
reset role;

-- 16) a long argument costs no more work than a short one (review, security): no statement timeout can tell a wrong
--     code from a right one, and a wrong code always counts. Before the fix the whole page-reported station was cleaned
--     (NFKC) before anything, and once more on the wrong-code path only: with 5 MB of U+FDFA (18 characters each after
--     NFKC) a wrong code ran into Supabase's 8-second statement timeout and rolled its own count back
set role authenticated;
select test.fresh485();
select test.reg485('L', 't485-l1', 'ana', 'Caja L') ->> 'slot' as sl \gset
select test.wrong485(:sl) as lw0 \gset
set local statement_timeout = '3s';
select test.c485('t485-l1', 'local', '4826', p_station => repeat(U&'\FDFA', 1700000)) as lr1 \gset
select test.c485('t485-l1', 'empleado', '4826', '5284', p_station => repeat(U&'\FDFA', 1700000)) as lr2 \gset
select test.c485('t485-l1', 'local', '0000', p_station => repeat(U&'\FDFA', 1700000)) as lw1 \gset
select test.c485('t485-l1', 'empleado', '4826', '0001', p_station => repeat(U&'\FDFA', 1700000)) as lw2 \gset
select test.c485('t485-l1', 'local', repeat('9', 2000000), p_station => repeat(U&'\FDFA', 1700000)) as lw3 \gset
select test.c485('t485-l1', 'guia', '7391', p_comp => repeat(U&'\FDFA', 1700000)) as lg \gset
select test.c485('t485-l1', repeat(U&'\FDFA', 1700000), '4826') as lc \gset
select test.c485('t485-l-mint', 'local', '4826', p_station => repeat(U&'\FDFA', 1700000)) as lm \gset
select public.descuento_caja_volver(repeat('ab', 32), repeat(U&'\FDFA', 1700000)) ->> 'error' as lv \gset
select test.open485('t485-l1', 'ana');
select public.descuento_caja_registrar(repeat(U&'\FDFA', 1700000)) as lreg \gset
insert into test.allkeys485 values ((:'lreg'::jsonb) ->> 'key') on conflict do nothing;
select public.descuento_caja_reanudar(:sl, test.p485('ana'), '4826', repeat(U&'\FDFA', 1700000)) ->> 'error' as lres \gset
select public.descuento_caja_quitar(gen_random_uuid(), test.p485('ana'), '4826', repeat(U&'\FDFA', 1700000)) ->> 'error' as lq \gset
select public.descuento_quitar_cuenta(gen_random_uuid(), 1000, repeat(U&'\FDFA', 1700000)) ->> 'error' as lqc \gset
select public.descuento_cupo_devolver(gen_random_uuid(), test.p485('ana'), '4826', repeat(U&'\FDFA', 1700000)) ->> 'error' as lcd \gset
set local statement_timeout = 0;
select test.eq((:'lw1'::jsonb) ->> 'error' || '|' || ((:'lw2'::jsonb) ->> 'error') || '|' || ((:'lw3'::jsonb) ->> 'error'), 'bad_pin|bad_employee|bad_pin',
               '16 a 5 MB station on a wrong manager code, a wrong employee code and a 2-million-digit code: each answered well within 3 s');
select test.eq(test.wrong485(:sl), :lw0 + 3, '16 ... and each counted (none rolled back by a timeout)');
select test.ok((:'lr1'::jsonb) ->> 'ok' = 'true' and ((:'lr2'::jsonb) ->> 'ok' = 'true' or (:'lr2'::jsonb) ->> 'error' = 'daily_used'),
               '16 the right codes with the same station, before them, in the same time: Local approved; the Empleado tested both codes (approved, or Luis''s day already used in this file)');
select test.eq((select count(*)::int || ':' || bool_and(char_length(details ->> 'station') between 1 and 24) from public.audit_log
                 where action = 'discount_code_wrong' and details ->> 'till' = test.tid485('t485-l1')::text), '3:true',
               '16 ... the three wrong-code rows keep the station cleaned and cut (at most 24 characters)');
select test.ok((select char_length(station) between 1 and 40 from public.discount_approvals where id = ((:'lr1'::jsonb) ->> 'id')::uuid),
               '16 ... and so does the approval (at most 40)');
select test.eq((:'lg'::jsonb) ->> 'error' || '|' || ((:'lc'::jsonb) ->> 'error') || '|' || ((:'lm'::jsonb) ->> 'error'),
               'missing_company|bad_discount|till_not_enrolled',
               '16 a 5 MB company, a 5 MB category, an unregistered sign-in with a 5 MB station: refused at once, nothing tested');
select test.ok((select coalesce(char_length(details ->> 'station'), 0) <= 24 from public.audit_log where action = 'discount_till_unknown' order by id desc limit 1),
               '16 ... the unregistered device''s log row keeps at most 24 characters of its station');
select test.eq(:'lv' || '|' || ((:'lreg'::jsonb) ->> 'already') || '|' || :'lres' || '|' || :'lq' || '|' || :'lqc' || '|' || :'lcd',
               'key_invalid|true|not_stopped|not_found|not_found|not_freeable',
               '16 a 5 MB station on every other 0038 call that takes one (volver, registrar, reanudar, quitar, quitar_cuenta, cupo_devolver): answered at once');
reset role;
select test.ok(test.src485(:'aut') !~ ('_staff_by_code\(.*(_discount_clean|_discount_station|_discount_company)\('),
               '16 descuento_autorizar cleans no text after the first code is compared (no attacker-sized work there)');
select test.ok(test.src485(p) !~ '(_discount_clean|_discount_station)\(', '16 ' || p || ' cleans nothing again (it takes the caller''s cleaned station)')
  from unnest(array['public._discount_wrong(public.discount_tills,text,text,text,text,uuid,text)', 'public._discount_till_unknown(text,text)']) p;
select test.eq((select count(*)::int from regexp_matches(test.src485(:'aut'), '_discount_(wrong|till_unknown)\([^;]*p_station', 'g')), 0,
               '16 ... and descuento_autorizar never hands them the raw station');
select test.ok(test.src485(p) !~ '_discount_clean\((?!left\(p_\w+, *[0-9]+\))', '16 ' || p || ': every text it cleans is cut to a fixed length first')
  from unnest(array[:'aut', 'public.descuento_quitar_cuenta(uuid,integer,text,uuid,text,text,uuid)', 'public.descuento_cupo_devolver(uuid,uuid,text,text)',
                    'public._discount_station(text)']) p;
select test.ok(position('_discount_station(' in test.src485(p)) between 1 and position('canopy.discount_tills''' in test.src485(p)),
               '16 ' || p || ': the station is cleaned before the registration lock B')
  from unnest(array['public.descuento_caja_registrar(text,uuid)', 'public.descuento_caja_volver(text,text)',
                    'public.descuento_caja_reanudar(integer,uuid,text,text)', 'public.descuento_caja_quitar(uuid,uuid,text,text)']) p;
set role authenticated;

-- 17) a lost reply never strands a tablet (review, locks): the server committed a rebind or a registration, the reply
--     carrying the new key never reached the page (a Wi-Fi drop), and the page still holds its spent key, or none.
--     Before the fix every retry answered «already» with no key, and the next sign-in found the tablet unregistered
--     while its dead row kept the place
select test.fresh485();
select test.reg485('K', 't485-k1', 'ana', 'Terraza') ->> 'slot' as sk \gset
select key as k0 from test.devs485 where dev = 'K' \gset
select test.n485('discount_till_rebound') as kr0 \gset
select test.n485('discount_till_enrolled') as ke0 \gset
select test.person485('ana') as kp0 \gset
-- a new sign-in: the page sends K0, the server rebinds (the old row ends rebound, K0 is spent, K1 is made) and the reply is lost
select test.volk485('t485-k2', :'k0') as klost \gset
select test.eq((:'klost'::jsonb) ->> 'ok' || '|' || ((:'klost'::jsonb) ->> 'slot'), 'true|' || :sk, '17 the rebind committed: the new sign-in holds the place');
-- the page, still holding K0, sends it again on the same sign-in
select test.volk485('t485-k2', :'k0') as kagain \gset
select test.eq(test.keys485(:'kagain'::jsonb), 'already key ok slot state station until wait wait_s',
               '17 the retry with the key that brought this sign-in here: already, with a key again, and the place''s state');
select test.eq((:'kagain'::jsonb) - 'key', jsonb_build_object('ok', true, 'already', true, 'station', 'Terraza', 'slot', :sk::int,
                                                             'state', 'ok', 'until', null, 'wait', null, 'wait_s', null),
               '17 ... the same place and station, calm');
select test.ok((:'kagain'::jsonb) ->> 'key' ~ '^[0-9a-f]{64}$' and (:'kagain'::jsonb) ->> 'key' not in (:'k0', (:'klost'::jsonb) ->> 'key'),
               '17 ... a new key, neither the old one nor the lost one');
select test.eq(test.till485(test.tid485('t485-k2')) ->> 'key_hash', test.hash485((:'kagain'::jsonb) ->> 'key'),
               '17 ... the place''s row keeps only its sha256: the lost key is spent');
select test.eq(test.volk485('t485-k2', repeat('ab', 32)), jsonb_build_object('ok', true, 'already', true, 'station', 'Terraza', 'slot', :sk::int),
               '17 any other key on that sign-in: already, no key, nothing changes');
-- the next sign-in comes back with the key the retry gave, to the same place
select test.volk485('t485-k3', (:'kagain'::jsonb) ->> 'key') as knext \gset
select test.eq((:'knext'::jsonb) ->> 'ok' || '|' || ((:'knext'::jsonb) ->> 'slot') || '|' || coalesce((:'knext'::jsonb) ->> 'already', '-'),
               'true|' || :sk || '|-', '17 the next sign-in comes back by that key, in the same place, with no manager');
select test.eq(test.volk485('t485-k4', (:'klost'::jsonb) ->> 'key') ->> 'error' || '|' || (test.volk485('t485-k4', :'k0') ->> 'error')
               || '|' || (test.volk485('t485-k3', :'k0') - 'station' - 'slot')::text,
               'key_invalid|key_invalid|{"ok": true, "already": true}',
               '17 the lost key and the old one are spent everywhere: key_invalid on another sign-in, nothing on the one that holds the place');
select test.eq(test.n485('discount_till_rebound') || ' ' || test.n485('discount_till_enrolled') || ' ' || test.person485('ana'),
               (:kr0 + 2) || ' ' || :ke0 || ' ' || :'kp0', '17 two rebinds logged (no row for a re-sent key), no registration, nothing counted on Ana');
-- the reply of a registration lost: «Registrar» again on that sign-in (the owner areas still open there) sends a key
select test.reg485('K2', 't485-k5', 'bea', 'Barra') ->> 'key' as kreg1 \gset
select public.descuento_caja_registrar('Barra') as kreg2 \gset
select test.ok((:'kreg2'::jsonb) ->> 'already' = 'true' and (:'kreg2'::jsonb) ->> 'key' ~ '^[0-9a-f]{64}$' and (:'kreg2'::jsonb) ->> 'key' <> :'kreg1',
               '17 a registration whose reply was lost: «Registrar» again answers already, with a new key');
insert into test.allkeys485 values ((:'kreg2'::jsonb) ->> 'key') on conflict do nothing;
select test.volk485('t485-k6', (:'kreg2'::jsonb) ->> 'key') as kreg3 \gset
select test.eq((:'kreg3'::jsonb) ->> 'ok' || '|' || ((:'kreg3'::jsonb) ->> 'slot'), 'true|' || test.slot485('t485-k6'),
               '17 ... with it the next sign-in comes back to that place');
select test.eq(test.slot485('t485-k6'), (test.rowof485('t485-k5') ->> 'slot')::int, '17 ... the same place');
select test.eq(test.volk485('t485-k7', :'kreg1') ->> 'error', 'key_invalid', '17 ... and the first key is spent');

-- 18) the windows keep rolling past a stop (review, spec; mecanismo §1 item 4 and its Bound: at most 12 wrong codes in
--     ANY 24 hours, no fresh budget when a stop ends). 12 wrong codes 11 minutes apart (longer than any wait) stop the
--     till; when the oldest is 24 hours old the stop ends by itself, and the very next wrong code is the 12th in 24
--     hours again: it stops the till until the 2nd code is 24 hours old (11 minutes later). A rule that counted afresh
--     after a stop ended would give 12 more there
reset role;
create function test.spaced485(p_sess text, n int, gap interval) returns jsonb language plpgsql as $$
declare i int; r jsonb;
begin
  for i in 1 .. n loop
    if i > 1 then perform test.back485(gap); end if;
    r := test.c485(p_sess, 'local', '0000');
  end loop;
  return r;
end $$;
set role authenticated;
select test.fresh485();
select test.reg485('RW', 't485-rw1', 'ana', 'Caja R') ->> 'slot' as sr \gset
select test.spaced485('t485-rw1', 12, interval '11 minutes') ->> 'blocked' as rw12 \gset
select test.eq(:'rw12' || '|' || test.wrong485(:sr), 'stopped|12', '18 12 wrong codes 11 minutes apart: the 12th stops the till');
select test.back485((test.stopend485(:sr) - now()) + interval '1 second');
select test.eq(test.state485(:sr) ->> 'state' || '|' || test.wrong485(:sr), 'ok|11', '18 a second after the oldest is 24 h old: calm, 11 in 24 h');
reset role;
select at + interval '24 hours' as rw_until from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = :'sr'
   and at > now() - interval '24 hours' order by at asc, id asc limit 1 \gset
set role authenticated;
select test.c485('t485-rw1', 'local', '0000') as rw13 \gset
select test.eq((:'rw13'::jsonb) - 'wait_s', jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', 'manager', 'warn', null, 'blocked', 'stopped',
                                                               'until', :'rw_until'::timestamptz, 'wait', 'stop'),
               '18 the next wrong code is the 12th in 24 h again: stopped until the 2nd code is 24 h old (no fresh 12)');
select test.ok(((:'rw13'::jsonb) ->> 'until')::timestamptz - now() between interval '10 minutes' and interval '11 minutes',
               '18 ... about 11 minutes from now');
select test.eq(test.c485('t485-rw1', 'local', '0000') ->> 'error' || '|' || (test.c485('t485-rw1', 'local', '4826') ->> 'error'),
               'till_stopped|till_stopped', '18 ... after it a wrong and a right code: till_stopped, untested');
select test.eq(test.wrong485(:sr), 12, '18 ... still at most 12 wrong codes tested in the last 24 hours');
select test.back485(interval '11 minutes');
select test.eq(test.c485('t485-rw1', 'local', '0000') ->> 'blocked', 'stopped', '18 11 minutes later the 3rd code leaves: one more wrong code, stopped again');
select test.eq(test.wrong485(:sr), 12, '18 ... 12 in 24 h, never 13');
reset role;

-- 12) a short simulation (24 h in 10-minute steps; mecanismo §13.1 item 12, §14 sim.test.sql) ---------------------------
-- an attacker at till A types 2 wrong codes every 10 minutes, day and night; honest service 07:00-21:00 every 30
-- minutes at A and B (at B one typo in 10, and once three typos in a row); a sign-in minted with the café password
-- tries a manager's right code every step. S1: nobody resumes A; S2: a manager resumes A whenever it is stopped
-- the simulation's time travel moves only the rows a window can still see (the last 26 hours): every window of the
-- control is 24 hours or shorter, so this is test.back for it, without rewriting the whole log at each of 288 steps
create function test.simback485(d interval) returns void language sql security definer as $$
  update public.audit_log set at = at - d where (action like 'discount%' or action = 'pin_duplicate') and at > now() - interval '26 hours';
  update public.discount_tills set enrolled_at = enrolled_at - d, last_used_at = last_used_at - d, ended_at = ended_at - d
   where ended_at is null or ended_at > now() - interval '26 hours' $$;
create function test.sim485(p_scen text, p_resume boolean) returns void language plpgsql as $$
declare st int; i int; r jsonb; hod int; code text; k int := 0; sa text := 't485-sa-' || p_scen; sb text := 't485-sb-' || p_scen; slot_a int;
begin
  perform test.fresh485();
  perform test.reg485('SA' || p_scen, sa, 'ana', 'Caja A');
  perform test.reg485('SB' || p_scen, sb, 'bea', 'Caja B');
  slot_a := test.slot485(sa);
  for st in 0 .. 143 loop
    hod := (st * 10 / 60) % 24;
    for i in 1 .. 2 loop
      code := lpad(((st * 7919 + i * 104729) % 10000)::text, 4, '0');
      if code in ('4826', '5284', '6173', '7391', '3917', '3918', '8521', '8522') then code := '0001'; end if;
      r := test.c485(sa, 'local', code, p_station => 'Caja A');
      insert into test.ev485 values (p_scen, st, 'attacker', r ->> 'error');
    end loop;
    if hod between 7 and 20 and st % 3 = 0 then
      k := k + 1;
      if k % 10 = 0 or st = 60 then
        for i in 1 .. case when st = 60 then 3 else 1 end loop
          r := test.c485(sb, 'local', '0002', p_station => 'Caja B');
          insert into test.ev485 values (p_scen, st, 'b_typo', coalesce(r ->> 'error', 'ok') || coalesce('/' || (r ->> 'blocked'), ''));
        end loop;
      end if;
      r := test.c485(sb, 'local', '4826', p_station => 'Caja B');
      insert into test.ev485 values (p_scen, st, 'b', coalesce(r ->> 'error', 'ok'));
      r := test.c485(sa, 'local', '4826', p_station => 'Caja A');
      insert into test.ev485 values (p_scen, st, 'a_honest', coalesce(r ->> 'error', 'ok'));
    end if;
    r := test.c485('t485-mint-' || p_scen || '-' || st, 'local', '4826', p_station => 'Teléfono');
    insert into test.ev485 values (p_scen, st, 't3', r ->> 'error');
    if p_resume and test.state485(slot_a) ->> 'state' = 'stopped' then
      perform test.open485(sb, 'bea');
      r := public.descuento_caja_reanudar(slot_a, test.p485('bea'), '3917', 'Caja B');
      insert into test.ev485 values (p_scen, st, 'resume', coalesce(r ->> 'error', 'ok'));
    end if;
    perform test.simback485(interval '10 minutes');
  end loop;
end $$;
set role authenticated;
select test.pin1485('ana') as ana_pin \gset
select test.sim485('S1', false);
reset role;
select test.tid485('t485-sa-S1') as sim_a \gset
select test.tid485('t485-sb-S1') as sim_b \gset
set role authenticated;
select test.sim485('S2', true);
reset role;
select test.eq((select count(*)::int from test.ev485 where scen = 'S1' and who = 'attacker' and res = 'bad_pin'), 12,
               '12 S1: in 24 hours the attacker got exactly 12 wrong codes tested at till A, never more (the 12th stopped it)');
select test.eq((select count(*)::int from test.ev485 where scen = 'S2' and who = 'attacker' and res = 'bad_pin'), 24,
               '12 S2: 24 with its one resume');
select test.eq((select string_agg(res || ':' || n, ' ' order by res) from (select res, count(*) n from test.ev485 where scen = 'S2' and who = 'resume' group by res) q),
               'ok:1 resume_limit:' || (select count(*) - 1 from test.ev485 where scen = 'S2' and who = 'resume'),
               '12 S2: one resume a place a day; every later try resume_limit');
select test.eq((select count(*)::int from test.ev485 where who = 't3' and res <> 'till_not_enrolled'), 0, '12 minted sign-ins: 288 of 288 refused, nothing tested');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_code_wrong' and details ->> 'station' = 'Teléfono'), 0,
               '12 ... no wrong code counted from any of them');
select test.eq((select count(*)::int from test.ev485 e where e.who = 'b' and e.res <> 'ok'
                  and not exists (select 1 from test.ev485 t where t.scen = e.scen and t.step = e.step and t.who = 'b_typo' and t.res like '%/wait')), 0,
               '12 till B: every honest right code approved while A was attacked, except right after B''s own 3rd typo in an hour');
select test.eq((select string_agg(scen || ':' || res || ':' || n, ' ' order by scen, res) from (select scen, res, count(*) n from test.ev485 where who = 'b' group by 1, 2) q),
               'S1:ok:27 S1:till_wait:1 S2:ok:27 S2:till_wait:1', '12 ... 27 approvals a day at B, and the one wait its own 3 typos caused');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_code_wrong' and details ->> 'till' = :'sim_b'),
               (select count(*)::int from test.ev485 where scen = 'S1' and who = 'b_typo'),
               '12 nothing typed at A counted on B (B''s rows are B''s own 5 typos)');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_code_wrong' and details ->> 'till' = :'sim_a'), 12,
               '12 ... and A''s 12 rows are the attacker''s');
select test.eq(test.pin1485('ana'), :'ana_pin', '12 Ana''s 0033 counter never moved through 600 calls');

-- 10) structure and grants (mecanismo §4, §5, §7, §13.1 item 10; api-0038 §6) ------------------------------------------
select test.ok(not has_table_privilege('authenticated', 'public.discount_tills', 'select') and not has_table_privilege('authenticated', 'public.discount_tills', 'insert')
               and not has_table_privilege('authenticated', 'public.discount_tills', 'update') and not has_table_privilege('authenticated', 'public.discount_tills', 'delete')
               and not has_table_privilege('anon', 'public.discount_tills', 'select'),
               '10 discount_tills is closed to the café and to anon: functions only');
select test.ok((select relrowsecurity from pg_class where oid = 'public.discount_tills'::regclass)
               and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'discount_tills'), '10 ... row level security on, no policy');
select test.eq((select string_agg(attname, ' ' order by attnum) from pg_attribute where attrelid = 'public.discount_tills'::regclass and attnum > 0 and not attisdropped),
               'id slot session_id login_id station enrolled_at enrolled_by enrolled_by_name last_used_at key_hash rebound_from prev_key_hash ended_at ended_by ended_by_name ended_how',
               '10 its columns: a key is kept only as its sha256 (key_hash, and prev_key_hash for a lost reply), never in plain');
select test.eq((select string_agg(indexname, ' ' order by indexname) from pg_indexes where tablename = 'discount_tills' and indexdef ~ 'UNIQUE' and indexdef ~ 'WHERE'),
               'discount_tills_key discount_tills_live_session discount_tills_live_slot', '10 one live row per sign-in, one per place, each key once');
select test.eq((select string_agg(indexname, ' ' order by indexname) from pg_indexes where tablename = 'audit_log' and indexname like 'audit_log_discount%'),
               'audit_log_discount_admin audit_log_discount_removed_paid audit_log_discount_slot audit_log_discount_wrong',
               '10 the counts read the log through its three indexes (and the report its removals after a payment through a fourth)');
select test.eq((select confdeltype::text from pg_constraint where conrelid = 'public.discount_approvals'::regclass and contype = 'f'
                   and confrelid = 'public.discount_tills'::regclass), 'n', '10 discount_approvals.till_id: on delete set null');
select test.eq((select to_jsonb(l) from public._discount_till_limits() l),
               '{"slots": 3, "hour_win": "01:00:00", "wait3": "00:00:30", "wait4": "00:01:00", "wait5": "00:05:00", "wait6": "00:10:00", "day_max": 12, "day_win": "24:00:00",
                 "resume_slot": 1, "resume_cafe": 2, "places_person": 2, "ends_person": 3, "enrolls_person": 6, "rebind_h": 6, "alert_n": 10, "unknown_cafe_h": 20}'::jsonb,
               '10 the constants of mecanismo §3');
select test.ok(has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
               and not has_function_privilege('public', p.oid, 'execute') and p.prosecdef,
               '10 ' || p.proname || ': security definer, the café login may run it, anon and PUBLIC may not')
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('descuento_estado', 'descuento_autorizar', 'descuento_caja_registrar', 'descuento_caja_volver', 'descuento_cajas',
                     'descuento_caja_reanudar', 'descuento_caja_quitar');
select test.eq((select count(*)::int from pg_proc where pronamespace = 'public'::regnamespace
                   and proname in ('descuento_estado', 'descuento_autorizar', 'descuento_caja_registrar', 'descuento_caja_volver', 'descuento_cajas',
                                   'descuento_caja_reanudar', 'descuento_caja_quitar')), 7, '10 (those 7, once each)');
select test.ok(not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
               and not has_function_privilege('public', p.oid, 'execute'), '10 internal ' || p.oid::regprocedure::text || ': revoked from everyone')
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and (p.proname like '\_discount\_%' or p.proname in ('_staff_by_code', '_pin_locks_clear_all'));
select test.ok(prosrc ~ '(is_cafe|is_owner|is_true_owner|sales_open|inventory_open|auth\.uid\(\)|mfa_ok|account_kind|can_read|owner_with_code|_books_allowed|_insights_allowed|_pay_staff_allowed|_ap_allowed|_receipts_allowed)'
               and regexp_replace(substr(prosrc, strpos(prosrc, E'\nbegin\n') + 7), '^(\s*--[^\n]*\n|\s*\n)*\s*', '')
                   like 'if not public.is\_cafe() then return jsonb\_build\_object(''ok'', false, ''error'', ''no\_account''); end if;%',
               '10 ' || proname || ' starts with the account check (and the snapshot''s rule finds one)')
  from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('descuento_estado', 'descuento_autorizar', 'descuento_caja_registrar', 'descuento_caja_volver', 'descuento_cajas',
                   'descuento_caja_reanudar', 'descuento_caja_quitar');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype and p.prosecdef
                   and has_function_privilege('anon', p.oid, 'execute')),
               'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', '10 anon_can_run unchanged: the same five names');
select test.eq((select count(*)::int from regexp_matches((select prosrc from pg_proc where oid = 'public._staff_by_code(text)'::regprocedure), 'crypt\(', 'g')), 1,
               '10 _staff_by_code makes exactly one bcrypt pass (one crypt)');
select test.ok(test.src485(:'aut') !~ '_verify_pin' and test.src485(:'aut') !~ 'access_unlock' and test.src485(:'aut') !~ 'failed_pins'
               and test.src485(:'aut') !~ 'locked_until', '10 descuento_autorizar never calls _verify_pin, never touches access_unlock(s), failed_pins or locked_until');
select test.ok(position('canopy.discount_request:' in test.src485(:'aut')) > 0
               and position('canopy.discount_request:' in test.src485(:'aut')) < position('canopy.discount_slot:' in test.src485(:'aut'))
               and position('canopy.discount_slot:' in test.src485(:'aut')) < position('_staff_by_code' in test.src485(:'aut')),
               '10 descuento_autorizar: the request lock A, then the place lock C, then the first code');
select test.ok(position('_discount_till_mine' in test.src485(:'aut')) between 1 and position('canopy.discount_slot:' in test.src485(:'aut')),
               '10 ... the sign-in''s registration is looked up before the place lock (an unregistered sign-in takes none)');
select test.ok(test.src485(p) !~ '(discount_tills|_discount_slot_state|_discount_till_mine|_discount_session)',
               '10 the order trigger ' || p || ' never consults the tills (selling never stops)')
  from unnest(array['public._order_discount_check()', 'public._order_discount_after()', 'public._order_discount_flags()']) p;
select test.ok(test.src485(:'aut') !~ 'canopy\.discount_tills''' and test.src485(:'aut') !~ 'canopy\.discount_code',
               '10 ... and never the café-wide registration lock B, nor any café-wide code lock');
select test.eq((select count(*)::int from regexp_matches(test.src485(:'aut'), '_discount_take_staff\(', 'g')) || ' '
               || (select count(*)::int from regexp_matches(test.src485(:'aut'), '_discount_staff_state\(', 'g')), '1 1',
               '10 (R) it locks one staff row (_discount_take_staff, once) and reads the employee without a lock (_discount_staff_state, once)');
select test.eq((select string_agg(a.attname, ' ' order by a.attname) from pg_constraint c
                   join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
                  where c.conrelid = 'public.discount_approvals'::regclass and c.contype = 'f' and c.confrelid = 'public.staff'::regclass),
               'approved_by',
               '10 (R) the window locks one staff row, the authorizer''s: an approval references no other staff row (a foreign key to the employee locks the employee''s row FOR KEY SHARE at the insert, while the authorizer''s is held FOR UPDATE: the deadlock of concurrency-descuentos.sh)');
select test.ok(replace(test.src485('public._discount_take_staff(uuid)'), 'for update', '') !~* '\mupdate\M'
               and test.src485('public._discount_staff_state(uuid)') !~* '\mupdate\M'
               and test.src485('public._discount_take_staff(uuid)') ~ 'for update'
               and test.src485('public._discount_staff_state(uuid)') !~ 'for update',
               '10 (R) neither writes anything; only _discount_take_staff takes a row lock');
select test.ok(position('canopy.discount_tills''' in test.src485(p)) > 0
               and position('canopy.discount_tills''' in test.src485(p)) < position('canopy.discount_slot:' in test.src485(p))
               and (p !~ '(reanudar|quitar)' or position('canopy.discount_slot:' in test.src485(p)) < position('_verify_pin' in test.src485(p))),
               '10 ' || p || ': lock B, then lock C' || case when p ~ '(reanudar|quitar)' then ', then the PIN' else '' end)
  from unnest(array['public.descuento_caja_registrar(text,uuid)', 'public.descuento_caja_volver(text,text)',
                    'public.descuento_caja_reanudar(integer,uuid,text,text)', 'public.descuento_caja_quitar(uuid,uuid,text,text)']) p;
select test.ok(test.src485(p) !~ 'canopy\.discount_slot:' and test.src485(p) !~ 'canopy\.discount_tills''' and test.src485(p) !~ 'for update',
               '10 ' || p || ' takes no lock')
  from unnest(array['public.descuento_estado(text)', 'public.descuento_cajas()']) p;
select test.ok(test.src485(p) !~ 'crypt\(' and test.src485(p) !~ '_verify_pin', '10 ' || p || ' tests no PIN')
  from unnest(array['public.descuento_caja_registrar(text,uuid)', 'public.descuento_caja_volver(text,text)', 'public.descuento_estado(text)',
                    'public.descuento_cajas()']) p;

-- 11) no PIN, no session id, no key in the log (mecanismo §9, §13.1 item 11; api-0038 §8) ---------------------------
select test.eq((select count(*)::int from public.audit_log a, jsonb_path_query(a.details, 'strict $.**') v
                 where (a.action like 'discount%' or a.action = 'pin_duplicate') and jsonb_typeof(v) in ('string', 'number')
                   and v #>> '{}' in ('4826', '5284', '6173', '7391', '3917', '3918', '8521', '8522', '0000', '0001', '0002', '1234')), 0,
               '11 no discount%/pin_duplicate log value is a PIN or a code typed in this file');
select test.eq((select count(*)::int from public.audit_log a, jsonb_each(a.details) d
                 where (a.action like 'discount%' or a.action = 'pin_duplicate')
                   and d.key not in ('subtotal_crc', 'discount_crc', 'total_crc', 'discount_kept', 'approved_subtotal', 'approved_discount')
                   and d.value #>> '{}' ~ '^[0-9]{4,8}$'), 0,
               '11 ... nor anything that looks like one (amounts aside)');
select test.eq((select count(*)::int from public.audit_log a where to_jsonb(a)::text ~ 't485-'), 0,
               '11 no log row holds a sign-in id of this file (only the s+7-hex tags)');
select test.eq((select count(*)::int from public.audit_log a, test.allkeys485 k where strpos(to_jsonb(a)::text, k.key) > 0), 0,
               '11 no log row holds a device key (' || (select count(*) from test.allkeys485) || ' keys handed out)');
select test.eq((select count(*)::int from public.discount_tills t, test.allkeys485 k where strpos(to_jsonb(t)::text, k.key) > 0), 0,
               '11 ... nor any till row (only the sha256)');
select test.eq((select count(*)::int from test.ans485 where j ->> 'error' in ('bad_pin', 'bad_employee')
                   and test.keys485(j) <> 'blocked error ok step until wait wait_s warn'), 0,
               '11 every counted wrong-code answer (' || (select count(*) from test.ans485 where j ->> 'error' in ('bad_pin', 'bad_employee'))
               || ') carries exactly ok, error, step, warn, blocked, until, wait, wait_s: never a count, a session or a name');
select test.eq((select count(*)::int from test.ans485 where j ->> 'error' in ('till_wait', 'till_stopped') and test.keys485(j) <> 'error ok until wait wait_s'), 0,
               '11 every till_wait/till_stopped answer (' || (select count(*) from test.ans485 where j ->> 'error' in ('till_wait', 'till_stopped'))
               || ') carries exactly ok, error, until, wait, wait_s');
select test.eq((select count(*)::int from test.ans485 where j ->> 'wait_s' is not null
                   and abs((j ->> 'wait_s')::int - greatest(1, ceil(extract(epoch from (j ->> 'until')::timestamptz - ck)))) > 1), 0,
               '11 in every answer with a wait (' || (select count(*) from test.ans485 where j ->> 'wait_s' is not null)
               || '), wait_s is within 1 s of until − the server''s clock');
select test.eq((select count(*)::int from test.ans485 where j ->> 'error' in ('bad_pin', 'bad_employee', 'till_wait', 'till_stopped')
                   and ((j ->> 'wait_s' is null) <> (j ->> 'until' is null) or (j ->> 'wait_s' is null) <> (j ->> 'wait' is null)
                        or (j ->> 'blocked' is not null) <> (j ->> 'error' in ('bad_pin', 'bad_employee') and j ->> 'until' is not null))), 0,
               '11 until, wait and wait_s come together, and blocked exactly when a wrong code started a wait or a stop');

-- 15) the log's sources: who can write what the approvals log shows in its main list (mecanismo §10.3, §13.1 item 15) --
select test.eq(test.n485('discount_till_signed_out'), 0, '15 (R) no discount_till_signed_out row in this build (L1)');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_till_ended'
                   and (manager_name is null or details ->> 'how' not in ('manager', 'owner', 'replaced', 'sql_editor'))), 0,
               '15 (R) every discount_till_ended row is a removal, a replacement or the owner''s tool, and names who (never a rebind)');
select test.eq((select count(*)::int from public.audit_log a where a.action = 'discount_till_ended'
                   and a.details ->> 'how' in ('manager', 'replaced') and a.manager_id is null and a.manager_name <> :'owner_label'), 0,
               '15 (R) ... a manager''s ending always carries that manager''s id (their allowance); only the phone code''s carries none');
select test.eq((select count(*)::int from public.audit_log where action in ('discount_till_enrolled', 'discount_till_resumed') and manager_name is null), 0,
               '15 (R) every registration and resume names a PIN-holder, the owner''s label or the owner''s tool');
select test.eq(test.n485('discount_till_rebound'), (select count(*)::int from public.discount_tills where rebound_from is not null),
               '15 (R) every rebind wrote one discount_till_rebound row and nothing else');
select test.eq((select count(*)::int from public.discount_tills where ended_how = 'rebound')
               + (select count(*)::int from public.discount_tills t where ended_how = 'signed_out' and exists (select 1 from public.discount_tills n where n.rebound_from = t.id)),
               test.n485('discount_till_rebound'), '15 (R) ... each ending the row it replaced as rebound (or a signed-out row)');
select test.eq((select count(*)::int from public.discount_tills),
               test.n485('discount_till_enrolled') + test.n485('discount_till_rebound') + (select count(*)::int from public.discount_tills where ended_how = 'signed_out'),
               '15 no till row was ever deleted: one per registration and one per rebind (plus the 4 signed-out fixtures)');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_till_stopped' and (details ->> 'day_n')::int <> 12), 0,
               '15 (R) a discount_till_stopped row is only ever written by the 12th wrong code of a place');

reset role;
select test.done();
rollback;
