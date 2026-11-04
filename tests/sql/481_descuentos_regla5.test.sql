-- Migration 0038 (D-065), rule 5 of the discount window (mecanismo-intentos §1 item 5, §6 6e-6f; api-0038 §4.1): the
-- owner's question of 2026-11-04, proved cell by cell. A TEMPORARY lock from failed attempts (0033: 5 wrong tries at a
-- name-picked PIN box → 10 minutes) never stops discounts: a locked person's right code still approves at the window,
-- which never reads a 0033 counter for a decision, never resets it and never counts it, so one person who locks every
-- manager at the name-picked boxes cannot stop the tills (the owner's adjustment 2). A PIN REVOKED or DEACTIVATED for
-- security never approves: a deactivated person, an old PIN after a new one was given, a PIN taken away, a role lowered
-- (manager → staff, owner → manager), a staff code, a manager's code for Guía, a code two active people share, an
-- inactive person's code. The window answers those as any wrong code and counts them on that till only, also when the
-- revocation commits while the code is being checked (the row is judged again under its lock, B 11). The name-picked
-- PIN boxes that remain (descuento_quitar_cuenta after a payment, descuento_cupo_devolver, descuento_caja_reanudar,
-- descuento_caja_quitar and the old window approve_discount) go through 0033's _verify_pin: inactive, not_manager and
-- locked there, as 0033 always did. Money already taken is never refused: an approval given before a deactivation and
-- rung after it is recorded. A revocation also reaches what the PIN already opened: a new or removed PIN ends that
-- person's owner-area unlocks on every other device (0038's trigger staff_pin_changed), a deactivation or a lowered role
-- through 0033's own live check, and a temporary lock ends none. No window call writes, changes or removes an
-- access_unlocks row or moves a 0033 counter; only 0033's own path moves one.
-- Everything goes through the real functions as the café login (authenticated, with a session_id) on tills registered
-- with descuento_caja_registrar; every revocation is made in Equipo (manager_save_staff) by the owner with the phone code.
-- The direct writes are fixtures for states no function leaves, each said so where it is made.
-- A revocation committed between a call's code lookup and its row lock needs two connections: concurrency-descuentos.sh
-- 6 makes that race; here (B 11) the window's two staff checks are called with the row as that lookup saw it.
begin;

-- the people of this file besides the seed (Ana manager 4826, Luis 5284 and Marta 6173 staff, Dueño owner 7391). Test
-- PINs only; cost 4 keeps each code's single bcrypt pass over every active PIN short. Each case has a person of its own:
--   Bea   manager, locked by 0033 (A)            Ciro  manager (third till; A)       Dora  manager, deactivated (B)
--   Eloy  manager, given a new PIN (B)           Fabi  manager, PIN taken away (B)   Gael  manager lowered to staff (B)
--   Hugo  manager, a lock that ended (A)         Kira  manager, approves then is deactivated (C)
--   Olga  a second owner, deactivated (B)        Pia   a third owner, lowered to manager (B)
--   Quino manager deactivated long ago with Ana's PIN (B; possible: two ACTIVE people never share a PIN, D-053)
--   Nico  staff deactivated long ago, a PIN nobody active has (B)
--   Rosa, Sol staff locked by 0033 (A)           Teo staff deactivated (B)           Uri staff given a new PIN (B)
--   Vale  staff, PIN taken away (B)              Yago staff, a lock that ended (A)   Zoe staff (beneficiary)
--   Wen (staff) and Xavi (manager) share one code (D-053: people reactivated between 0028 and 0033)
--   Lina  manager, locked then deactivated (B)   Mo    manager, locked then lowered to staff (B)
--   Ines  a fourth owner, locked then lowered to manager (B)    Jon  manager whose unlocks a new PIN ends (B)
create table test.t481_people (name text primary key, id uuid not null, pin text);
grant select on test.t481_people to authenticated;
insert into test.t481_people (name, id, pin)
  select n, ('0b481000-0000-4000-8000-' || lpad(o::text, 12, '0'))::uuid, p
    from (values (1, 'bea', '3921'), (2, 'ciro', '3922'), (3, 'dora', '3923'), (4, 'eloy', '3924'), (5, 'fabi', '3925'),
                 (6, 'gael', '3926'), (7, 'hugo', '3927'), (8, 'kira', '3928'), (9, 'olga', '3929'), (10, 'pia', '3930'),
                 (11, 'quino', '4826'), (12, 'nico', '8531'), (13, 'rosa', '8521'), (14, 'sol', '8522'), (15, 'teo', '8523'),
                 (16, 'uri', '8524'), (17, 'vale', '8525'), (18, 'wen', '3940'), (19, 'xavi', '3940'), (20, 'yago', '8527'),
                 (21, 'zoe', '8528'), (22, 'lina', '3951'), (23, 'mo', '3952'), (24, 'ines', '3953'),
                 (25, 'jon', '3954')) v(o, n, p);
insert into public.staff (id, name, role, active, pin_hash)
  select id, initcap(name),
         case when name in ('olga', 'pia', 'ines') then 'owner'
              when name in ('bea', 'ciro', 'dora', 'eloy', 'fabi', 'gael', 'hugo', 'kira', 'quino', 'xavi', 'lina', 'mo', 'jon') then 'manager'
              else 'staff' end,
         name not in ('quino', 'nico'), extensions.crypt(pin, extensions.gen_salt('bf', 4))
    from test.t481_people;
insert into test.t481_people values ('ana', test.staff('ana'), '4826'), ('luis', test.staff('luis'), '5284'),
                                    ('marta', test.staff('marta'), '6173'), ('dueno', test.staff('dueno'), '7391');
create function test.p481(n text) returns uuid language sql stable as $$ select id from test.t481_people where name = n $$;
-- each person's PIN hash before any revocation: what the code lookup of a call made at that moment matched (B 11)
create table test.h481 (name text primary key, h text);
insert into test.h481 select p.name, s.pin_hash from test.t481_people p join public.staff s on s.id = p.id;
create function test.k481(n text) returns text language sql stable as $$ select pin from test.t481_people where name = n $$;
-- Guía Turista on, as 485 does (A-13 stays open in production: the switch ships off; here it is on to test the owner's code)
insert into public.compliance_confirmations (key, confirmed_by, reference) values ('courtesy_iva_confirmed', 'test', 'test');
insert into public.settings (key, value) values ('pos_discount_guia', '"on"');

-- the devices: their sign-in and the device key the page keeps; the bitácora device's unlock header
create table test.devs481 (dev text primary key, sess text not null, key text);
create table test.hdr481 (dev text primary key, h jsonb not null);
-- every window call (descuento_autorizar) and every name-picked PIN box call of this file, with what each one changed
create table test.win481 (n serial primary key, sess text, cat text, calm boolean, ans jsonb, pins_same boolean,
                          pins_diff text, unl_delta int, open_delta int, unl_same boolean, wrong text);
create table test.pin481 (n serial primary key, fn text, who text, ans jsonb, diff text, unl_delta int, unl_same boolean);
grant all on test.devs481, test.hdr481, test.win481, test.pin481 to authenticated;
grant usage on sequence test.win481_n_seq, test.pin481_n_seq to authenticated;

-- readers and time travel, as the test superuser (definer), so the café login can use them between its own calls.
-- None is STABLE: a stable function reads with its calling statement's snapshot, so test.ap481(test.w481(...)) would
-- not see the approval the window had just written in that same statement
-- every counted wrong code moved 25 hours back: each code below is judged on a calm place (as 480's test.a480)
create function test.calm481() returns void language sql security definer as $$ select test.back(interval '25 hours') $$;
create function test.back481(d interval) returns void language sql security definer as $$ select test.back(d) $$;
-- every person's 0033 counter and lock, and what changed since a snapshot (by id: no collation involved)
create function test.pins481() returns jsonb language sql security definer as $$
  select jsonb_object_agg(id::text, jsonb_build_array(failed_pins, locked_until)) from public.staff $$;
create function test.pindiff481(b jsonb) returns text language sql security definer as $$
  select coalesce(string_agg(s.name || ':' || coalesce(b -> s.id::text ->> 0, '-') || '>' || s.failed_pins
                             || case when (b -> s.id::text -> 1) is distinct from (jsonb_build_array(s.locked_until) -> 0) then '/lock' else '' end,
                             ' ' order by s.id), '')
    from public.staff s where (b -> s.id::text) is distinct from jsonb_build_array(s.failed_pins, s.locked_until) $$;
create function test.pin1481(p_who text) returns text language sql security definer as $$
  select failed_pins || '/' || case when locked_until > now() then 'locked' when locked_until is not null then 'ended' else 'open' end
    from public.staff where id = test.p481(p_who) $$;
create function test.locked481() returns text language sql security definer as $$
  select coalesce(string_agg(name, ' ' order by id), '') from public.staff where locked_until > now() $$;
create function test.role481(p_who text) returns text language sql security definer as $$
  select role from public.staff where id = test.p481(p_who) $$;
create function test.name481(p_who text) returns text language sql security definer as $$
  select name from public.staff where id = test.p481(p_who) $$;
create function test.unl481() returns int language sql security definer as $$ select count(*)::int from public.access_unlocks $$;
-- every access_unlocks row with every column, as one fingerprint: a row added, changed (its person, role, sign-in,
-- expiry) or removed changes it. (access_level() on a till proves nothing: test.login clears the unlock header)
create function test.unlfp481() returns text language sql security definer as $$
  select md5(coalesce(string_agg(to_jsonb(u)::text, '|' order by u.token_hash), '')) from public.access_unlocks u $$;
create function test.n481(p_act text) returns int language sql security definer as $$
  select count(*)::int from public.audit_log where action = p_act $$;
create function test.maxid481() returns bigint language sql security definer as $$ select coalesce(max(id), 0) from public.audit_log $$;
-- the wrong codes counted after an audit id: who the row names @ place : step : why
create function test.wrong481(p_after bigint) returns text language sql security definer as $$
  select coalesce(string_agg(coalesce(manager_name, '-') || '@' || (details ->> 'slot') || ':' || (details ->> 'step') || ':'
                             || (details ->> 'why'), ' ' order by id), '')
    from public.audit_log where action = 'discount_code_wrong' and id > p_after $$;
-- an approval as stored and logged: place, authorizer, role, category, beneficiary, person_locked/employee_locked
create function test.ap481(p_id text) returns text language sql security definer as $$
  select 'slot:' || t.slot || ' ' || a.approved_name || ' ' || a.approver_role || ' ' || a.category || ' '
         || coalesce(a.beneficiary_name, '-') || ' ' || (l.details ->> 'person_locked') || '/' || (l.details ->> 'employee_locked')
    from public.discount_approvals a join public.audit_log l on l.action = 'discount_approved' and l.target_id = a.id::text
    left join public.discount_tills t on t.id = a.till_id
   where a.id = p_id::uuid $$;
create function test.ncat481() returns int language sql security definer as $$
  select count(*)::int from public.discount_approvals where category is not null $$;
create function test.tid481(p_sess text) returns uuid language sql security definer as $$
  select id from public.discount_tills where session_id = p_sess and ended_at is null $$;
create function test.state481(p_slot int) returns text language sql security definer as $$
  select state from public._discount_slot_state(p_slot) $$;
create function test.shared481() returns text language sql security definer as $$
  select (select string_agg(x::text, ' ' order by x) from unnest(d.staff_ids) x) from public.discount_pin_shared d
   order by d.audit_id desc limit 1 $$;
-- the active managers and owners (by id), for the attack of adjustment 2
create function test.bosses481() returns setof uuid language sql security definer as $$
  select id from public.staff where active and role in ('manager', 'owner') order by id $$;

-- a device as the café login: test.login resets the claims and the unlock header, test.session gives the sign-in its id
create function test.dev481(p_sess text) returns void language plpgsql as $$
begin
  perform test.login('cafe');
  perform test.session(p_sess);
end $$;
-- Reloj de marcas › Bitácora › «Registrar este dispositivo para descuentos», with p_who's unlock on that very sign-in
create function test.reg481(p_dev text, p_sess text, p_who text, p_station text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform test.dev481(p_sess);
  perform test.unlock(test.p481(p_who), test.k481(p_who));
  r := public.descuento_caja_registrar(p_station);
  if r ? 'key' then insert into test.devs481 values (p_dev, p_sess, r ->> 'key'); end if;
  return r;
end $$;
-- a new sign-in on a registered tablet: the page brings it back with its key (descuento_caja_volver, no PIN)
create function test.vol481(p_dev text, p_sess text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform test.dev481(p_sess);
  r := public.descuento_caja_volver((select key from test.devs481 where dev = p_dev));
  if r ? 'key' then update test.devs481 set sess = p_sess, key = r ->> 'key' where dev = p_dev; end if;
  return r;
end $$;
create function test.s481(p_dev text) returns text language sql stable as $$ select sess from test.devs481 where dev = p_dev $$;
-- the approvals log on the bitácora device: the owner areas open there (Ana's unlock, made once in §0)
create function test.bit481() returns void language plpgsql as $$
begin
  perform test.dev481('t481-bit');
  perform set_config('request.headers', (select h from test.hdr481 where dev = 'bit')::text, false);
end $$;
-- Equipo: the owner (own login with the phone code) saves a person: a new PIN, active on/off, a role
create function test.equipo481(p_who text, p_pin text, p_active boolean, p_role text) returns jsonb language plpgsql as $$
begin
  perform test.login('owner', 'aal2');
  return public.manager_save_staff(null, null, test.p481(p_who), test.name481(p_who), p_pin, p_active, p_role);
end $$;
-- 0033's temporary lock, made the real way from a minted sign-in: 5 wrong tries at a name-picked box (the unlock box for
-- managers and owners, the time clock's box for staff). Returns the person's counter and lock afterwards
create function test.lock481(p_who text) returns text language plpgsql as $$
declare i int; st boolean := test.role481(p_who) = 'staff';
begin
  perform test.dev481('t481-evil');
  for i in 1 .. 5 loop
    if st then perform public.hours_for(test.p481(p_who), '0000', now(), now());
    else perform public.access_unlock(test.p481(p_who), '0000'); end if;
  end loop;
  return test.pin1481(p_who);
end $$;
-- the window's call on a till, as pos.html sends it (Local at ₡1000 unless told otherwise), on a calm place unless told
-- otherwise; every call is logged with what it changed (0033 counters, unlocks, owner areas, counted wrong codes)
create function test.w481(p_sess text, p_cat text, p_pin text, p_emp text default null, p_comp text default null,
                          p_sub int default 1000, p_bill uuid default null, p_expect int default null, p_calm boolean default true)
returns jsonb language plpgsql as $$
declare r jsonb; b jsonb; u int; ao int; w0 bigint; f text;
begin
  if p_calm then perform test.calm481(); end if;
  b := test.pins481(); u := test.unl481(); ao := test.n481('access_open'); w0 := test.maxid481(); f := test.unlfp481();
  perform test.dev481(p_sess);
  r := public.descuento_autorizar(p_cat, p_pin, p_sub, p_emp, p_comp, p_bill, p_expect, null, 'Caja 481');
  insert into test.win481 (sess, cat, calm, ans, pins_same, pins_diff, unl_delta, open_delta, unl_same, wrong)
    values (p_sess, p_cat, p_calm, r, test.pins481() = b, test.pindiff481(b), test.unl481() - u,
            test.n481('access_open') - ao, test.unlfp481() = f, test.wrong481(w0));
  return r;
end $$;
-- the same call's answer plus what it counted ('counted': who@place:step:why, '' when nothing)
create function test.wc481(p_sess text, p_cat text, p_pin text, p_emp text default null, p_comp text default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  r := test.w481(p_sess, p_cat, p_pin, p_emp, p_comp);
  return r || jsonb_build_object('counted', (select wrong from test.win481 order by n desc limit 1));
end $$;
-- n wrong codes at one till, waiting out each wait (10 minutes 1 second after each, as 485's test.hammer485)
create function test.hammer481(p_sess text, n int) returns text language plpgsql as $$
declare i int; r jsonb;
begin
  for i in 1 .. n loop
    r := test.w481(p_sess, 'local', '0000', p_calm => false);
    perform test.back481(interval '10 minutes 1 second');
  end loop;
  return r ->> 'blocked';
end $$;
-- a counted wrong code on a calm place answers exactly this (api-0038 §4.1: only these keys), plus what was counted
create function test.bad481(p_err text, p_step text, p_counted text) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'error', p_err, 'step', p_step, 'warn', null, 'blocked', null, 'until', null,
                            'wait', null, 'wait_s', null, 'counted', p_counted) $$;
-- a name-picked PIN box (0033's _verify_pin): the person picked from the list and their PIN. The owner-area ones on the
-- bitácora device, the others on till 1. Logged with what it changed
create function test.v481(p_fn text, p_who text, p_target text default null, p_pin text default null, p_expect int default null)
returns jsonb language plpgsql as $$
declare r jsonb; b jsonb; u int; f text; pin text := coalesce(p_pin, test.k481(p_who)); sid uuid := test.p481(p_who);
begin
  if p_fn in ('cupo', 'reanudar', 'quitar_caja') then perform test.bit481(); else perform test.dev481(test.s481('T1')); end if;
  b := test.pins481(); u := test.unl481(); f := test.unlfp481();
  if p_fn = 'quitar_cuenta' then
    r := public.descuento_quitar_cuenta(p_target::uuid, p_expect, 'Caja 481', sid, pin, 'El cliente pidió quitarlo');
  elsif p_fn = 'cupo' then r := public.descuento_cupo_devolver(p_target::uuid, sid, pin, 'Bitácora');
  elsif p_fn = 'reanudar' then r := public.descuento_caja_reanudar(p_target::int, sid, pin, 'Bitácora');
  elsif p_fn = 'quitar_caja' then r := public.descuento_caja_quitar(p_target::uuid, sid, pin, 'Bitácora');
  elsif p_fn = 'approve' then r := public.approve_discount(sid, pin, 'percent', 10, 1000, 'Cliente frecuente', 'Caja 481');
  else raise exception 'test.v481: unknown box %', p_fn; end if;
  insert into test.pin481 (fn, who, ans, diff, unl_delta, unl_same)
    values (p_fn, p_who, r, test.pindiff481(b), test.unl481() - u, test.unlfp481() = f);
  return r;
end $$;
-- the window's two staff checks as a call makes them under the row lock (_discount_take_staff for the authorizer,
-- _discount_staff_state for the employee), given the PIN hash its code lookup matched: the file's first one (test.h481)
-- unless p_now (the current one). That is what a call answers when a revocation commits between its code lookup and its
-- row lock (concurrency-descuentos.sh 6 makes that race). An error (a helper missing, or with other arguments) is
-- returned as the answer, so an old helper fails the assertion instead of stopping the file
create function test.take481(p_who text, p_need text, p_now boolean default false) returns jsonb
language plpgsql security definer as $$
declare r jsonb;
begin
  execute 'select to_jsonb(x) from public._discount_take_staff($1, $2, $3) x' into r
    using test.p481(p_who), case when p_now then (select pin_hash from public.staff where id = test.p481(p_who))
                                 else (select h from test.h481 where name = p_who) end, p_need;
  return r;
exception when others then return to_jsonb(sqlerrm);
end $$;
create function test.emp481(p_who text) returns jsonb language plpgsql security definer as $$
declare r jsonb;
begin
  execute 'select to_jsonb(x) from public._discount_staff_state($1, $2) x' into r
    using test.p481(p_who), (select h from test.h481 where name = p_who);
  return r;
exception when others then return to_jsonb(sqlerrm);
end $$;
-- a device of this file (sign-in t481-<dev>) with the unlock header kept for it, and its owner-area level now
create function test.at481(p_dev text) returns void language plpgsql as $$
begin
  perform test.dev481('t481-' || p_dev);
  perform set_config('request.headers', coalesce((select h from test.hdr481 where dev = p_dev), '{}'::jsonb)::text, false);
end $$;
create function test.lvl481(p_dev text) returns text language plpgsql as $$
begin
  perform test.at481(p_dev);
  return coalesce(public.access_level(), 'none');
end $$;
-- p_who opens the owner areas on device p_dev with p_pin (their own PIN unless told): the unlock box, its header kept.
-- Answers the level it opened, or the box's refusal (then nothing is kept)
create function test.open481(p_dev text, p_who text, p_pin text default null) returns text language plpgsql as $$
declare r jsonb; h jsonb;
begin
  perform test.dev481('t481-' || p_dev);
  r := public.access_unlock(test.p481(p_who), coalesce(p_pin, test.k481(p_who)));
  if not coalesce((r ->> 'ok')::boolean, false) then return 'refused:' || (r ->> 'error'); end if;
  h := jsonb_build_object('x-hg-unlock', r ->> 'token');
  perform set_config('request.headers', h::text, false);
  insert into test.hdr481 values (p_dev, h) on conflict (dev) do update set h = excluded.h;
  return coalesce(public.access_level(), 'none');
end $$;
-- bills and tickets as pos.html records them (pos_record_sale): a «Pay later» bill Latte 4000 + Ham & Cheese 6000
create function test.o481(n int) returns uuid language sql immutable as $$ select ('d4810000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.item481(p_bill uuid, n int) returns uuid language sql immutable as $$ select md5(p_bill::text || '-' || n)::uuid $$;
create function test.bill481(p_bill uuid, guest text) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p_bill, 'created_at', now(), 'total_crc', 10000,
           'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja 481', 'source', 'front', 'guest_name', guest,
           'items', jsonb_build_array(
              jsonb_build_object('id', test.item481(p_bill, 1), 'item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
              jsonb_build_object('id', test.item481(p_bill, 2), 'item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) $$;
create function test.payitem481(p_bill uuid) returns jsonb language sql as $$
  select public.tab_pay(p_bill, 'cash_crc', jsonb_build_array(jsonb_build_object('item_id', test.item481(p_bill, 1), 'qty', 1)),
                        null, 'Caja 481') $$;
-- a paid ticket carrying an approval: one line at the subtotal, the discount the page computed
create function test.sale481(oid uuid, appr text, sub int, disc int) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', now(), 'total_crc', sub - disc,
           'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'needs_kitchen', false, 'station', 'Caja 481',
           'guest_name', 'Ticket 481', 'subtotal_crc', sub, 'discount_crc', disc, 'discount_id', appr,
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', sub, 'qty', 1)))) $$;
create function test.order481(oid uuid) returns jsonb language sql security definer as $$
  select jsonb_build_object('total', o.total_crc, 'subtotal', o.subtotal_crc, 'discount', o.discount_crc,
                            'discount_id', o.discount_id, 'reason', o.discount_reason, 'by', o.discount_by, 'paid', o.paid,
                            'discount_flags', to_jsonb(array(select f from unnest(coalesce(o.flags, '{}')) f where f like 'discount%' order by f)),
                            'approval_order', (select a.order_id from public.discount_approvals a where a.id = o.discount_id),
                            'discount_rows', (select count(*)::int from public.audit_log l
                                               where l.target_id = o.id::text and l.action like 'discount%'))
    from public.orders o where o.id = oid $$;
create function test.billnow481(p_bill uuid) returns jsonb language sql security definer as $$
  select jsonb_build_object('total', total_crc, 'discount', discount_crc, 'discount_id', discount_id, 'reason', discount_reason,
                            'parts', parts_crc)
    from public.orders where id = p_bill $$;

-- 0) the tills and the bitácora device ------------------------------------------------------------------------------
set role authenticated;
select test.eq(test.reg481('T1', 't481-t1', 'ana', 'Caja 1') ->> 'slot', '1', '0 fixture: Ana registers till 1 (descuento_caja_registrar, her unlock on that sign-in)');
select test.eq(test.reg481('T2', 't481-t2', 'ana', 'Caja 2') ->> 'slot', '2', '0 fixture: Ana registers till 2');
select test.eq(test.reg481('T3', 't481-t3', 'ciro', 'Caja 3') ->> 'slot', '3', '0 fixture: Ciro registers till 3');
select test.dev481('t481-bit');
select test.unlfp481() as fp0 \gset
select test.unlock(test.staff('ana'), '4826') as hbit \gset
select test.ok(test.unlfp481() <> :'fp0', '0 the access_unlocks fingerprint sees a new unlock (so an unchanged one means no row was added, changed or removed)');
insert into test.hdr481 values ('bit', :'hbit'::jsonb);
select test.bit481();
select test.eq(public.access_level(), 'manager', '0 fixture: the owner areas open on the bitácora device (Ana)');
select test.s481('T1') as t1, test.s481('T2') as t2, test.s481('T3') as t3 \gset
select test.pins481() as pins0 \gset
select test.eq(test.locked481(), '', '0 nobody is locked yet');

-- A) A TEMPORARY LOCK NEVER STOPS DISCOUNTS (rule 5) ------------------------------------------------------------------
-- a manager, the owner and two employees locked by 0033 from a minted sign-in (5 wrong tries each at a name-picked box)
select test.eq(test.lock481('bea') || ' ' || test.lock481('dueno') || ' ' || test.lock481('rosa') || ' ' || test.lock481('sol'),
               '5/locked 5/locked 5/locked 5/locked',
               'A fixture: 5 wrong tries lock Bea and the owner (unlock box) and Rosa and Sol (time clock), 0033''s real path');
select test.dev481(:'t1');
select test.eq(public.access_unlock(test.p481('bea'), test.k481('bea')) ->> 'error', 'locked',
               'A the name-picked box says Bea is locked even with her right PIN (0033 unchanged)');
select test.pins481() as pinsa \gset
select test.n481('discount_code_wrong') as wa \gset
-- (1) the locked manager approves Local and Huésped and authorizes Empleado
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('bea')) ->> 'id'), 'slot:1 Bea manager local - true/false',
               'A locked manager: Bea''s right code approves Local at till 1, the approval says person_locked');
select test.eq(test.ap481(test.w481(:'t1', 'huesped', test.k481('bea')) ->> 'id'), 'slot:1 Bea manager huesped - true/false',
               'A locked manager: ... and Huésped');
select test.eq(test.ap481(test.w481(:'t1', 'empleado', test.k481('bea'), test.k481('luis')) ->> 'id'),
               'slot:1 Bea manager empleado Luis true/false', 'A locked manager: ... and authorizes Empleado for Luis');
select test.eq(test.pin1481('bea'), '5/locked', 'A locked manager: Bea''s counter is still 5 and her lock still on (never cleared, never raised)');
-- (2) the locked owner approves Guía (and Local)
select test.eq(test.ap481(test.w481(:'t2', 'guia', test.k481('dueno'), p_comp => 'Tours Monteverde') ->> 'id'),
               'slot:2 Dueño owner guia - true/false', 'A locked owner: the owner''s right code approves Guía at till 2, person_locked');
select test.eq(test.ap481(test.w481(:'t2', 'local', test.k481('dueno')) ->> 'id'), 'slot:2 Dueño owner local - true/false',
               'A locked owner: ... and Local (as owner)');
select test.eq(test.pin1481('dueno'), '5/locked', 'A locked owner: the owner''s counter and lock unchanged');
-- (3) locked employees receive Empleado, with the authorizer free or locked too
select test.eq(test.ap481(test.w481(:'t1', 'empleado', '4826', test.k481('rosa')) ->> 'id'), 'slot:1 Ana manager empleado Rosa false/true',
               'A locked employee: Ana''s code and locked Rosa''s give Rosa her Empleado, the approval says employee_locked');
select test.eq(test.ap481(test.w481(:'t3', 'empleado', test.k481('bea'), test.k481('sol')) ->> 'id'),
               'slot:3 Bea manager empleado Sol true/true', 'A both locked: Bea''s and Sol''s codes give Sol her Empleado at till 3, both flags true');
select test.eq(test.pin1481('rosa') || ' ' || test.pin1481('sol'), '5/locked 5/locked', 'A locked employees: their counters and locks unchanged');
-- a wrong code typed while Bea is locked is the till's business only
select test.eq(test.wc481(:'t2', 'local', '0000'), test.bad481('bad_pin', 'manager', '-@2:manager:no_match'),
               'A a wrong code while people are locked: bad_pin, counted on till 2 only (why no_match), with no 0033 effect');
select test.eq(test.pins481(), :'pinsa'::jsonb, 'A after all of this every 0033 counter and lock is exactly as it was');
select test.eq(test.n481('discount_code_wrong') - :wa, 1, 'A ... and the only counted code was the wrong one: no right code of a locked person was counted');
select test.eq((select count(*)::int from test.win481 where not unl_same or unl_delta <> 0 or open_delta <> 0), 0,
               'A no call added, changed or removed an access_unlocks row (every row, every column) or opened the owner areas');
-- (4) a lock that ended behaves like no lock: Hugo (manager) and Yago (staff) locked the real way, then their 10 minutes
-- are over. Fixture: now() is fixed inside one transaction, so the lock's end is moved back instead (as test.back does
-- for the log); failed_pins stays 5, as 0033 leaves it when a lock runs out
select test.lock481('hugo') || ' ' || test.lock481('yago') as hy \gset
reset role;
update public.staff set locked_until = now() - interval '1 second' where id in (test.p481('hugo'), test.p481('yago'));
set role authenticated;
select test.eq(:'hy' || ' | ' || test.pin1481('hugo') || ' ' || test.pin1481('yago'), '5/locked 5/locked | 5/ended 5/ended',
               'A fixture: Hugo and Yago locked by 5 wrong tries, then their locks ended (counter still 5)');
select test.pins481() as pinse \gset
select test.eq(test.ap481(test.w481(:'t3', 'local', test.k481('hugo')) ->> 'id'), 'slot:3 Hugo manager local - false/false',
               'A lock ended: Hugo''s code approves Local, person_locked false');
select test.eq(test.ap481(test.w481(:'t3', 'empleado', '4826', test.k481('yago')) ->> 'id'), 'slot:3 Ana manager empleado Yago false/false',
               'A lock ended: Yago receives Empleado, employee_locked false');
select test.eq(test.pins481(), :'pinse'::jsonb, 'A lock ended: their counters stay 5 and their past locks as they were (the window resets nothing)');

-- B) A REVOKED, DEACTIVATED OR UNAUTHORIZED PIN NEVER APPROVES: the window ----------------------------------------------
-- each case: the code works first, the owner revokes it in Equipo, then the same code is refused like any wrong code
-- (bad_pin / bad_employee with only the keys of api §4.1) and counted on that till only
select test.ncat481() as cat_b0, (select coalesce(max(n), 0) from test.win481) as wn_b0 \gset
-- (1) a deactivated manager
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('dora')) ->> 'id'), 'slot:1 Dora manager local - false/false',
               'B fixture: Dora''s code approves Local while she is active');
select test.eq(test.equipo481('dora', null, false, 'manager') ->> 'ok', 'true', 'B fixture: the owner deactivates Dora in Equipo');
select test.eq(test.wc481(:'t1', 'local', test.k481('dora')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B deactivated manager: her right code for Local is bad_pin, counted on till 1 only as a code nobody active has');
select test.eq(test.wc481(:'t2', 'huesped', test.k481('dora')), test.bad481('bad_pin', 'manager', '-@2:manager:no_match'),
               'B deactivated manager: ... Huésped at till 2 the same, counted on till 2 only');
select test.eq(test.wc481(:'t1', 'empleado', test.k481('dora'), test.k481('zoe')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B deactivated manager: ... Empleado stops at the manager step (the employee code is never tested)');
-- (2) a deactivated owner (another owner stays)
select test.eq(test.ap481(test.w481(:'t2', 'guia', test.k481('olga'), p_comp => 'Tours Monteverde') ->> 'id'),
               'slot:2 Olga owner guia - false/false', 'B fixture: Olga (a second owner) approves Guía while active');
select test.eq(test.equipo481('olga', null, false, 'owner') ->> 'ok', 'true', 'B fixture: the owner (with the phone code) deactivates Olga');
select test.eq(test.wc481(:'t2', 'guia', test.k481('olga'), p_comp => 'Tours Monteverde'), test.bad481('bad_pin', 'owner', '-@2:owner:no_match'),
               'B deactivated owner: her code for Guía is bad_pin at the owner step, counted on till 2');
select test.eq(test.wc481(:'t1', 'local', test.k481('olga')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B deactivated owner: ... and for Local too');
select test.eq(test.ap481(test.w481(:'t2', 'guia', test.k481('dueno'), p_comp => 'Tours Monteverde') ->> 'id'),
               'slot:2 Dueño owner guia - true/false', 'B deactivated owner: the other owner''s code still gives Guía');
-- (3) a deactivated employee
select test.eq(test.ap481(test.w481(:'t1', 'empleado', '4826', test.k481('teo')) ->> 'id'), 'slot:1 Ana manager empleado Teo false/false',
               'B fixture: Teo receives Empleado while active');
select test.eq(test.equipo481('teo', null, false, 'staff') ->> 'ok', 'true', 'B fixture: the owner deactivates Teo');
select test.eq(test.wc481(:'t1', 'empleado', '4826', test.k481('teo')), test.bad481('bad_employee', 'employee', 'Ana@1:employee:no_match'),
               'B deactivated employee: bad_employee (not daily_used), counted on till 1, the row naming Ana');
-- (4) a new PIN given: the old one is revoked, the new one works
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('eloy')) ->> 'id'), 'slot:1 Eloy manager local - false/false',
               'B fixture: Eloy''s PIN approves Local');
select test.eq(test.equipo481('eloy', '3934', true, 'manager') ->> 'ok', 'true', 'B fixture: the owner gives Eloy a new PIN in Equipo');
select test.eq(test.wc481(:'t1', 'local', test.k481('eloy')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B PIN changed: Eloy''s OLD code is bad_pin, counted like any wrong code');
select test.eq(test.ap481(test.w481(:'t1', 'local', '3934') ->> 'id'), 'slot:1 Eloy manager local - false/false',
               'B PIN changed: ... and his NEW code approves');
select test.w481(:'t1', 'empleado', '4826', test.k481('uri')) ->> 'id' as uri1 \gset
select test.eq(test.ap481(:'uri1'), 'slot:1 Ana manager empleado Uri false/false', 'B fixture: Uri''s PIN receives Empleado');
select test.dev481(:'t1');
select test.eq(public.descuento_liberar(:'uri1'::uuid) ->> 'ok', 'true', 'B fixture: the till lets that approval go (×), Uri''s day is free');
select test.eq(test.equipo481('uri', '8534', true, 'staff') ->> 'ok', 'true', 'B fixture: the owner gives Uri a new PIN');
select test.eq(test.wc481(:'t1', 'empleado', '4826', test.k481('uri')), test.bad481('bad_employee', 'employee', 'Ana@1:employee:no_match'),
               'B PIN changed: Uri''s OLD code at the employee step is bad_employee');
select test.eq(test.ap481(test.w481(:'t1', 'empleado', '4826', '8534') ->> 'id'), 'slot:1 Ana manager empleado Uri false/false',
               'B PIN changed: ... and his NEW code receives Empleado');
-- (5) a PIN taken away (pin_hash null)
select test.eq(test.ap481(test.w481(:'t2', 'local', test.k481('fabi')) ->> 'id'), 'slot:2 Fabi manager local - false/false',
               'B fixture: Fabi''s PIN approves Local');
select test.w481(:'t2', 'empleado', '4826', test.k481('vale')) ->> 'id' as vale1 \gset
select test.dev481(:'t2');
select test.eq(public.descuento_liberar(:'vale1'::uuid) ->> 'ok', 'true', 'B fixture: Vale receives Empleado, then the till lets it go');
-- fixture: no function takes a PIN away (Equipo only gives new ones); a person whose PIN was removed, written directly
reset role;
update public.staff set pin_hash = null where id in (test.p481('fabi'), test.p481('vale'));
set role authenticated;
select test.eq(test.wc481(:'t2', 'local', test.k481('fabi')), test.bad481('bad_pin', 'manager', '-@2:manager:no_match'),
               'B PIN removed: Fabi''s former code matches nobody: bad_pin, counted on till 2');
select test.eq(test.wc481(:'t2', 'empleado', '4826', test.k481('vale')), test.bad481('bad_employee', 'employee', 'Ana@2:employee:no_match'),
               'B PIN removed: Vale''s former code at the employee step: bad_employee');
-- (6) a role lowered: manager → staff
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('gael')) ->> 'id'), 'slot:1 Gael manager local - false/false',
               'B fixture: Gael (manager) approves Local');
select test.eq(test.equipo481('gael', null, true, 'staff') ->> 'role', 'staff', 'B fixture: the owner lowers Gael to staff in Equipo');
select test.eq(test.wc481(:'t1', 'local', test.k481('gael')), test.bad481('bad_pin', 'manager', '-@1:manager:not_allowed'),
               'B role lowered to staff: Gael''s code is bad_pin at the manager step, counted as not_allowed (his role read now)');
select test.eq(test.wc481(:'t1', 'empleado', test.k481('gael'), test.k481('zoe')), test.bad481('bad_pin', 'manager', '-@1:manager:not_allowed'),
               'B role lowered to staff: ... nor can he authorize Empleado');
select test.eq(test.ap481(test.w481(:'t1', 'empleado', '4826', test.k481('gael')) ->> 'id'), 'slot:1 Ana manager empleado Gael false/false',
               'B role lowered to staff: ... he can still receive Empleado (a staff member)');
-- (6b) the owner role taken away: owner → manager
select test.eq(test.ap481(test.w481(:'t3', 'guia', test.k481('pia'), p_comp => 'Tours Monteverde') ->> 'id'),
               'slot:3 Pia owner guia - false/false', 'B fixture: Pia (a third owner) approves Guía');
select test.eq(test.wc481(:'t3', 'empleado', '4826', test.k481('pia')), test.bad481('bad_employee', 'employee', 'Ana@3:employee:owner_beneficiary'),
               'B fixture: as an owner Pia cannot receive Empleado (owner_beneficiary)');
select test.eq(test.equipo481('pia', null, true, 'manager') ->> 'role', 'manager', 'B fixture: the owner (with the phone code) lowers Pia to manager');
select test.eq(test.wc481(:'t3', 'guia', test.k481('pia'), p_comp => 'Tours Monteverde'), test.bad481('bad_pin', 'owner', '-@3:owner:not_allowed'),
               'B owner lowered to manager: Pia''s code for Guía is refused at the owner step, counted as not_allowed');
select test.eq(test.ap481(test.w481(:'t3', 'local', test.k481('pia')) ->> 'id'), 'slot:3 Pia manager local - false/false',
               'B owner lowered to manager: ... and accepted for Local, as a manager');
select test.eq(test.ap481(test.w481(:'t3', 'empleado', '4826', test.k481('pia')) ->> 'id'), 'slot:3 Ana manager empleado Pia false/false',
               'B owner lowered to manager: ... and she can now receive Empleado');
-- (7) people who never could
select test.eq(test.wc481(:'t1', 'local', '5284'), test.bad481('bad_pin', 'manager', '-@1:manager:not_allowed'),
               'B a staff code (Luis) as the authorizer: bad_pin, not_allowed');
select test.eq(test.wc481(:'t1', 'empleado', '5284', test.k481('zoe')), test.bad481('bad_pin', 'manager', '-@1:manager:not_allowed'),
               'B ... nor for Empleado');
select test.eq(test.wc481(:'t2', 'guia', '4826', p_comp => 'Tours Monteverde'), test.bad481('bad_pin', 'owner', '-@2:owner:not_allowed'),
               'B a manager''s code (Ana) for Guía: bad_pin at the owner step, not_allowed');
-- (8) a code two active people share (Wen, staff, and Xavi, manager): it authorizes nobody, at any step
select test.n481('pin_duplicate') as dup0 \gset
select test.eq(test.wc481(:'t1', 'local', '3940'), test.bad481('bad_pin', 'manager', '-@1:manager:ambiguous'),
               'B shared code: bad_pin at the manager step, exactly like any wrong code, counted as ambiguous');
select test.eq(test.shared481(), (select string_agg(x::text, ' ' order by x) from unnest(array[test.p481('wen'), test.p481('xavi')]) x),
               'B shared code: ... and discount_pin_shared names both people (ids only)');
select test.eq(test.wc481(:'t1', 'empleado', '4826', '3940'), test.bad481('bad_employee', 'employee', 'Ana@1:employee:ambiguous'),
               'B shared code at the employee step: bad_employee, ambiguous');
select test.eq(test.wc481(:'t1', 'guia', '3940', p_comp => 'Tours Monteverde'), test.bad481('bad_pin', 'owner', '-@1:owner:ambiguous'),
               'B shared code for Guía: bad_pin at the owner step, ambiguous');
select test.eq(test.n481('pin_duplicate') - :dup0, 3, 'B shared code: one pin_duplicate row each time');
-- (9) inactive people's PINs
select test.eq(test.wc481(:'t1', 'local', test.k481('nico')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B an inactive person''s code that nobody active has: no match at the manager step');
select test.eq(test.wc481(:'t1', 'empleado', '4826', test.k481('nico')), test.bad481('bad_employee', 'employee', 'Ana@1:employee:no_match'),
               'B ... and at the employee step');
select test.n481('pin_duplicate') as dup1 \gset
select test.eq(test.ap481(test.w481(:'t1', 'local', '4826') ->> 'id'), 'slot:1 Ana manager local - false/false',
               'B Ana''s code while inactive Quino has the same PIN: approved as Ana (an inactive PIN never counts, not even as a share)');
select test.eq(test.n481('pin_duplicate') - :dup1, 0, 'B ... and no pin_duplicate row');
-- (10) locked AND revoked: a person locked by 0033 who is then deactivated or lowered is refused like anyone revoked (the
-- lock is no pass), and neither the window nor Equipo moves the lock. Each opened the owner areas on a device first
select test.eq(test.open481('l', 'lina') || ' ' || test.open481('m', 'mo') || ' ' || test.open481('i', 'ines'), 'manager manager owner',
               'B fixture: Lina and Mo (managers) and Ines (a fourth owner) open the owner areas, each on a device of their own');
select test.eq(test.lock481('lina') || ' ' || test.lock481('mo') || ' ' || test.lock481('ines'), '5/locked 5/locked 5/locked',
               'B fixture: then 5 wrong tries lock each of them (0033''s real path)');
select test.eq(test.lvl481('l') || ' ' || test.lvl481('m') || ' ' || test.lvl481('i'), 'manager manager owner',
               'B a temporary lock is not a revocation: their unlocks stay open');
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('lina')) ->> 'id'), 'slot:1 Lina manager local - true/false',
               'B fixture: locked Lina''s code approves Local (rule 5)');
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('mo')) ->> 'id'), 'slot:1 Mo manager local - true/false',
               'B fixture: locked Mo''s too');
select test.eq(test.ap481(test.w481(:'t2', 'guia', test.k481('ines'), p_comp => 'Tours Monteverde') ->> 'id'),
               'slot:2 Ines owner guia - true/false', 'B fixture: locked Ines gives Guía');
select test.eq((test.equipo481('lina', null, false, 'manager') ->> 'ok') || ' ' || (test.equipo481('mo', null, true, 'staff') ->> 'role')
               || ' ' || (test.equipo481('ines', null, true, 'manager') ->> 'role'), 'true staff manager',
               'B fixture: the owner deactivates Lina, lowers Mo to staff and Ines to manager in Equipo (no new PIN)');
select test.eq(test.wc481(:'t1', 'local', test.k481('lina')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B locked and deactivated: Lina''s code is bad_pin, counted like any code nobody active has');
select test.eq(test.wc481(:'t1', 'local', test.k481('mo')), test.bad481('bad_pin', 'manager', '-@1:manager:not_allowed'),
               'B locked and lowered to staff: Mo''s code is bad_pin, not_allowed');
select test.eq(test.ap481(test.w481(:'t1', 'empleado', '4826', test.k481('mo')) ->> 'id'), 'slot:1 Ana manager empleado Mo false/true',
               'B ... while Mo, a locked staff member now, still receives Empleado (employee_locked)');
select test.eq(test.wc481(:'t2', 'guia', test.k481('ines'), p_comp => 'Tours Monteverde'), test.bad481('bad_pin', 'owner', '-@2:owner:not_allowed'),
               'B locked and lowered to manager: Ines''s code for Guía is bad_pin, not_allowed');
select test.eq(test.ap481(test.w481(:'t2', 'local', test.k481('ines')) ->> 'id'), 'slot:2 Ines manager local - true/false',
               'B ... and her Local approves as a manager, still person_locked');
select test.eq(test.pin1481('lina') || ' ' || test.pin1481('mo') || ' ' || test.pin1481('ines'), '5/locked 5/locked 5/locked',
               'B their 0033 counters and locks are as the 5 tries left them (neither the window nor Equipo touched them)');
select test.eq(test.lvl481('l') || ' ' || test.lvl481('m') || ' ' || test.lvl481('i'), 'none none manager',
               'B the revocations reached their unlocks at once (0033''s live check): Lina''s and Mo''s closed, Ines''s manager-level only');
-- (11) the race, as the window judges it under the row lock, given the hash its code lookup matched a moment before the
-- revocation committed (concurrency-descuentos.sh 6 makes the race itself): a new or removed PIN → no_match, a
-- deactivation → inactive, a role that may not authorize → not_allowed, exactly what the same code gets a moment later;
-- the approval takes the role read under the lock. A 0033 lock alone passes
select test.eq(test.take481('eloy', 'manager'), '{"ok": false, "why": "no_match", "srole": "manager", "locked": false}'::jsonb,
               'B race: Eloy''s code matched his old PIN, under the lock his PIN is new → no_match, no approval');
select test.eq(test.take481('eloy', 'manager', true), '{"ok": true, "why": null, "srole": "manager", "locked": false}'::jsonb,
               'B race: ... with his new PIN''s hash he passes');
select test.eq(test.take481('fabi', 'manager'), '{"ok": false, "why": "no_match", "srole": "manager", "locked": false}'::jsonb,
               'B race: Fabi''s PIN removed meanwhile → no_match');
select test.eq(test.take481('dora', 'manager'), '{"ok": false, "why": "inactive", "srole": "manager", "locked": false}'::jsonb,
               'B race: Dora deactivated meanwhile → inactive');
select test.eq(test.take481('olga', 'owner'), '{"ok": false, "why": "inactive", "srole": "owner", "locked": false}'::jsonb,
               'B race: Olga (an owner) deactivated meanwhile → inactive at the owner step');
select test.eq(test.take481('gael', 'manager'), '{"ok": false, "why": "not_allowed", "srole": "staff", "locked": false}'::jsonb,
               'B race: Gael lowered to staff meanwhile → not_allowed');
select test.eq(test.take481('pia', 'owner'), '{"ok": false, "why": "not_allowed", "srole": "manager", "locked": false}'::jsonb,
               'B race: Pia lowered to manager meanwhile → not_allowed for Guía');
select test.eq(test.take481('pia', 'manager'), '{"ok": true, "why": null, "srole": "manager", "locked": false}'::jsonb,
               'B race: ... for Local she passes as the manager she is now (the approval stores the role read under the lock)');
select test.eq(test.take481('luis', 'manager'), '{"ok": false, "why": "not_allowed", "srole": "staff", "locked": false}'::jsonb,
               'B race: a staff member never passes the manager step');
select test.eq(test.take481('ana', 'owner'), '{"ok": false, "why": "not_allowed", "srole": "manager", "locked": false}'::jsonb,
               'B race: nor a manager the owner step');
select test.eq(test.take481('bea', 'manager'), '{"ok": true, "why": null, "srole": "manager", "locked": true}'::jsonb,
               'B race: 0033-locked Bea passes under the lock too (rule 5), locked carried to the approval');
select test.eq(test.take481('lina', 'manager'), '{"ok": false, "why": "inactive", "srole": "manager", "locked": true}'::jsonb,
               'B race: locked and deactivated Lina → inactive (the lock is no pass)');
select test.eq(test.take481('mo', 'manager'), '{"ok": false, "why": "not_allowed", "srole": "staff", "locked": true}'::jsonb,
               'B race: locked and lowered Mo → not_allowed');
select test.eq(test.take481('ines', 'owner'), '{"ok": false, "why": "not_allowed", "srole": "manager", "locked": true}'::jsonb,
               'B race: locked Ines, lowered to manager → not_allowed for Guía');
select test.eq(test.emp481('uri'), '{"ok": false, "why": "no_match", "locked": false}'::jsonb,
               'B race, employee step: Uri''s code matched his old PIN, now new → no_match');
select test.eq(test.emp481('vale'), '{"ok": false, "why": "no_match", "locked": false}'::jsonb, 'B race, employee step: Vale''s PIN removed → no_match');
select test.eq(test.emp481('teo'), '{"ok": false, "why": "inactive", "locked": false}'::jsonb, 'B race, employee step: Teo deactivated → inactive');
select test.eq(test.emp481('dueno'), '{"ok": false, "why": "owner_beneficiary", "locked": true}'::jsonb,
               'B race, employee step: an owner never receives Empleado (locked or not)');
select test.eq(jsonb_build_array(test.emp481('rosa'), test.emp481('gael'), test.emp481('pia')),
               '[{"ok": true, "why": null, "locked": true}, {"ok": true, "why": null, "locked": false}, {"ok": true, "why": null, "locked": false}]'::jsonb,
               'B race, employee step: locked Rosa, Gael (staff now) and Pia (a manager now) pass');
select test.ok((select prosrc ~ '_discount_take_staff\(a\.sid, a\.hash, need\)' and prosrc ~ '_discount_staff_state\(e\.sid, e\.hash\)'
                       and prosrc ~ '_discount_wrong\(t, need, k\.why,' and prosrc ~ '_discount_wrong\(t, ''employee'', es\.why,'
                       and prosrc ~ 'arole := case when k\.srole = ''owner'''
                  from pg_proc where oid = 'public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text)'::regprocedure),
               'B race: descuento_autorizar hands each check the hash its lookup matched, counts the check''s why and stores the role read under the lock');
-- (12) a new or removed PIN ends the unlocks opened with the old one, on every device but the one that made the change
-- (0038's trigger staff_pin_changed). The case: someone saw Jon's PIN at a till and opened the owner areas with it on a
-- tablet (x). Until 0038 that unlock outlived a new PIN for up to 15 minutes: enough to give Jon a PIN of their own in
-- Equipo (a manager edits their own row with only the unlock) and approve with it in his name
select test.eq(test.open481('x', 'jon'), 'manager', 'B fixture: a tablet (x) opens the owner areas with Jon''s PIN');
select test.eq(test.lock481('jon') || ' ' || test.lvl481('x'), '5/locked manager',
               'B a temporary lock ends no unlock: Jon locked by 5 wrong tries elsewhere, tablet x still open');
select test.eq(test.ap481(test.w481(:'t1', 'local', test.k481('jon')) ->> 'id'), 'slot:1 Jon manager local - true/false',
               'B ... and his code still approves at the window (rule 5)');
select test.unl481() as ux0 \gset
select test.eq(test.equipo481('jon', '3958', true, 'manager') ->> 'ok', 'true', 'B fixture: the owner gives Jon a new PIN in Equipo');
select test.eq(test.lvl481('x') || ' ' || (:ux0 - test.unl481()), 'none 1',
               'B new PIN: the unlock opened with Jon''s old PIN is gone (tablet x closed, its row deleted)');
select test.at481('x');
select test.eq(public.manager_save_staff(null, null, test.p481('jon'), 'Jon', '3959', true, 'manager') ->> 'error', 'owner_only',
               'B ... so tablet x cannot give Jon a PIN of its own in Equipo');
select test.at481('x');
select test.eq(public.descuento_caja_registrar('Caja X') ->> 'error', 'owner_only', 'B ... nor register itself as a till for discounts');
select test.eq(test.wc481(:'t1', 'local', test.k481('jon')), test.bad481('bad_pin', 'manager', '-@1:manager:no_match'),
               'B ... and Jon''s old code is bad_pin at the window');
select test.eq(test.ap481(test.w481(:'t1', 'local', '3958') ->> 'id'), 'slot:1 Jon manager local - false/false',
               'B ... while his new code approves (the new PIN also took his 0033 lock off, as Equipo always did)');
select test.eq(test.open481('y', 'jon', '3958') || ' ' || test.open481('z', 'jon', '3958'), 'manager manager',
               'B fixture: Jon opens the owner areas with his new PIN on his own tablet (y) and on another one (z)');
select test.unl481() as uy0 \gset
select test.at481('y');
select test.eq(public.manager_save_staff(null, null, test.p481('jon'), 'Jon', '3959', true, 'manager') ->> 'ok', 'true',
               'B fixture: on y, Jon gives himself a new PIN in Equipo (his unlock is enough for his own row)');
select test.eq(test.lvl481('y') || ' ' || test.lvl481('z') || ' ' || (:uy0 - test.unl481()), 'manager none 1',
               'B his own change: the tablet that made it stays open (its unlock made the change), the other one closes');
-- fixture: no function takes a PIN away (Equipo only gives new ones); Jon's removed, written directly from no device
select test.dev481('t481-none');
reset role;
update public.staff set pin_hash = null where id = test.p481('jon');
set role authenticated;
select test.eq(test.lvl481('y'), 'none', 'B PIN removed: Jon''s last unlock (y) ends too');
-- every refusal of B approved nothing: the approvals made are exactly the calls answered ok
select test.eq(test.ncat481() - :cat_b0, (select count(*)::int from test.win481 where n > :wn_b0 and ans ->> 'ok' = 'true'),
               'B the category approvals made in B are exactly its calls answered ok: no refusal left one');

-- B) ... and at the name-picked PIN boxes (0033's _verify_pin), where a person is picked from the list ---------------
-- Rule 5 is the window's own rule (descuento_autorizar). These boxes keep 0033's rule: a locked person is refused there
-- ('locked'), an inactive one 'inactive', a staff member 'not_manager' (api-0038 §4.4, §4.5, §4.10, §4.11; mecanismo
-- §5.2: "_verify_pin → bad_pin / locked / not_manager / inactive, counted on that person's own 0033 counter, never as a
-- discount code"). Only a wrong PIN (or a right one) touches that person's counter, by 0033's own path
-- a bill with a Local discount, then one item paid: taking the discount off needs a manager's PIN and a reason
select test.dev481(:'t1');
select test.eq(test.bill481(test.o481(1), 'Mesa 481') ->> 'ok', 'true', 'B fixture: an open bill of 10000');
select test.eq(test.ap481(test.w481(:'t1', 'local', '4826', p_sub => 10000, p_bill => test.o481(1), p_expect => 10000) ->> 'id'),
               'slot:1 Ana manager local - false/false', 'B fixture: Ana''s Local on the bill');
select test.dev481(:'t1');
select test.eq(test.payitem481(test.o481(1)) ->> 'ok', 'true', 'B fixture: one guest pays the Latte by item');
select (test.billnow481(test.o481(1)) ->> 'total')::int as tot1 \gset
select test.eq(test.v481('quitar_cuenta', 'dora', test.o481(1)::text, p_expect => :tot1), '{"ok": false, "error": "inactive"}'::jsonb,
               'B descuento_quitar_cuenta after a payment: deactivated Dora → inactive');
select test.eq(test.v481('quitar_cuenta', 'olga', test.o481(1)::text, p_expect => :tot1), '{"ok": false, "error": "inactive"}'::jsonb,
               'B descuento_quitar_cuenta: deactivated owner Olga → inactive');
select test.eq(test.v481('quitar_cuenta', 'gael', test.o481(1)::text, p_expect => :tot1), '{"ok": false, "error": "not_manager"}'::jsonb,
               'B descuento_quitar_cuenta: Gael lowered to staff → not_manager');
select test.eq(test.v481('quitar_cuenta', 'luis', test.o481(1)::text, p_expect => :tot1), '{"ok": false, "error": "not_manager"}'::jsonb,
               'B descuento_quitar_cuenta: Luis (staff) → not_manager');
select test.eq(test.v481('quitar_cuenta', 'eloy', test.o481(1)::text, p_expect => :tot1), '{"ok": false, "error": "bad_pin"}'::jsonb,
               'B descuento_quitar_cuenta: Eloy''s OLD PIN → bad_pin (counted on his own 0033 counter: 0033''s path)');
select test.eq(test.v481('quitar_cuenta', 'bea', test.o481(1)::text, p_expect => :tot1), '{"ok": false, "error": "locked"}'::jsonb,
               'B descuento_quitar_cuenta: 0033-locked Bea with her right PIN → locked (0033''s rule at the name-picked boxes)');
select test.eq(test.billnow481(test.o481(1)) ->> 'reason', 'Local', 'B descuento_quitar_cuenta: after every refusal the discount is still on the bill');
select test.eq(test.v481('quitar_cuenta', 'ana', test.o481(1)::text, p_expect => :tot1) ->> 'paid', 'true',
               'B descuento_quitar_cuenta: Ana''s PIN takes it off (the box itself works)');
-- an Empleado taken off its bill with nothing paid: giving the day back needs a manager's PIN in the owner areas
select test.dev481(:'t1');
select test.eq(test.bill481(test.o481(2), 'Mesa Marta') ->> 'ok', 'true', 'B fixture: a second open bill');
select test.w481(:'t1', 'empleado', '4826', '6173', p_sub => 10000, p_bill => test.o481(2), p_expect => 10000) ->> 'id' as marta1 \gset
select test.dev481(:'t1');
select test.eq(public.descuento_quitar_cuenta(test.o481(2), 7000, 'Caja 481') ->> 'ok', 'true',
               'B fixture: Marta''s Empleado on that bill, taken off with nothing paid (no PIN)');
select test.eq(test.v481('cupo', 'dora', :'marta1'), '{"ok": false, "error": "inactive"}'::jsonb, 'B descuento_cupo_devolver: deactivated Dora → inactive');
select test.eq(test.v481('cupo', 'olga', :'marta1'), '{"ok": false, "error": "inactive"}'::jsonb, 'B descuento_cupo_devolver: deactivated owner Olga → inactive');
select test.eq(test.v481('cupo', 'gael', :'marta1'), '{"ok": false, "error": "not_manager"}'::jsonb, 'B descuento_cupo_devolver: Gael lowered → not_manager');
select test.eq(test.v481('cupo', 'luis', :'marta1'), '{"ok": false, "error": "not_manager"}'::jsonb, 'B descuento_cupo_devolver: Luis (staff) → not_manager');
select test.eq(test.v481('cupo', 'bea', :'marta1'), '{"ok": false, "error": "locked"}'::jsonb,
               'B descuento_cupo_devolver: 0033-locked Bea → locked (0033''s rule)');
select test.eq(test.v481('cupo', 'ana', :'marta1') ->> 'how', 'bill_removed', 'B descuento_cupo_devolver: Ana''s PIN gives Marta''s day back');
-- a stopped place: resuming it needs a manager's PIN in the owner areas
select test.calm481();
select test.eq(test.hammer481(:'t3', 12) || ' ' || test.state481(3), 'stopped stopped', 'B fixture: 12 wrong codes stop place 3');
select test.eq(test.v481('reanudar', 'dora', '3'), '{"ok": false, "error": "inactive"}'::jsonb, 'B descuento_caja_reanudar: deactivated Dora → inactive');
select test.eq(test.v481('reanudar', 'gael', '3'), '{"ok": false, "error": "not_manager"}'::jsonb, 'B descuento_caja_reanudar: Gael lowered → not_manager');
select test.eq(test.v481('reanudar', 'fabi', '3', '3925'), '{"ok": false, "error": "bad_pin"}'::jsonb,
               'B descuento_caja_reanudar: Fabi''s PIN taken away → bad_pin (0033''s path)');
select test.eq(test.v481('reanudar', 'bea', '3'), '{"ok": false, "error": "locked"}'::jsonb,
               'B descuento_caja_reanudar: 0033-locked Bea → locked (0033''s rule: E-lock, recovery uses manager PINs)');
select test.eq(test.state481(3), 'stopped', 'B descuento_caja_reanudar: after every refusal the place is still stopped');
select test.eq(test.v481('reanudar', 'ana', '3') ->> 'ok', 'true', 'B descuento_caja_reanudar: Ana''s PIN resumes it');
-- removing a till's registration
select test.eq(test.v481('quitar_caja', 'dora', test.tid481(:'t1')::text), '{"ok": false, "error": "inactive"}'::jsonb,
               'B descuento_caja_quitar: deactivated Dora → inactive');
select test.eq(test.v481('quitar_caja', 'gael', test.tid481(:'t1')::text), '{"ok": false, "error": "not_manager"}'::jsonb,
               'B descuento_caja_quitar: Gael lowered → not_manager');
select test.eq(test.v481('quitar_caja', 'bea', test.tid481(:'t1')::text), '{"ok": false, "error": "locked"}'::jsonb,
               'B descuento_caja_quitar: 0033-locked Bea → locked (0033''s rule)');
select test.eq(test.tid481(:'t1') is not null, true, 'B descuento_caja_quitar: till 1 is still registered');
-- the old window (approve_discount, on while pos_free_discount is on): 0033 exactly
select test.eq(test.v481('approve', 'dora'), '{"ok": false, "error": "inactive"}'::jsonb, 'B approve_discount: deactivated Dora → inactive');
select test.eq(test.v481('approve', 'olga'), '{"ok": false, "error": "inactive"}'::jsonb, 'B approve_discount: deactivated owner Olga → inactive');
select test.eq(test.v481('approve', 'gael'), '{"ok": false, "error": "not_manager"}'::jsonb, 'B approve_discount: Gael lowered → not_manager');
select test.eq(test.v481('approve', 'bea'), '{"ok": false, "error": "locked"}'::jsonb, 'B approve_discount: 0033-locked Bea → locked (as 0033)');
select test.eq(test.v481('approve', 'lina'), '{"ok": false, "error": "inactive"}'::jsonb,
               'B approve_discount: locked and deactivated Lina → inactive (0033 asks for active before the lock)');
select test.eq(test.v481('approve', 'mo'), '{"ok": false, "error": "not_manager"}'::jsonb, 'B approve_discount: locked and lowered Mo → not_manager');
select test.eq(test.v481('approve', 'ines'), '{"ok": false, "error": "locked"}'::jsonb,
               'B approve_discount: locked Ines, a manager now → locked (0033''s rule at the old window)');
select test.eq(test.v481('approve', 'eloy'), '{"ok": false, "error": "bad_pin"}'::jsonb, 'B approve_discount: Eloy''s OLD PIN → bad_pin');
select test.eq(test.v481('approve', 'fabi', p_pin => '3925'), '{"ok": false, "error": "bad_pin"}'::jsonb,
               'B approve_discount: Fabi''s PIN taken away → bad_pin');
select test.eq(test.v481('approve', 'eloy', p_pin => '3934') ->> 'name', 'Eloy', 'B approve_discount: Eloy''s NEW PIN approves (the old window works)');
select test.eq((select count(*)::int from test.pin481 where ans ->> 'ok' = 'true'), 4,
               'B at the PIN boxes only the four valid people''s calls went through (Ana three times, Eloy''s new PIN once)');

-- C) MONEY IS NEVER REFUSED: an approval given, its authorizer deactivated, then the sale ---------------------------
select test.w481(:'t2', 'local', test.k481('kira')) ->> 'id' as kira1 \gset
select test.eq(test.ap481(:'kira1'), 'slot:2 Kira manager local - false/false', 'C fixture: Kira approves a Local (₡1000, ₡100 off) at till 2');
select test.v481('approve', 'kira') as kira2j \gset
select test.eq((:'kira2j'::jsonb) ->> 'name', 'Kira', 'C fixture: ... and an old-window discount (10 %, Cliente frecuente)');
select (:'kira2j'::jsonb) ->> 'id' as kira2 \gset
select test.eq(test.equipo481('kira', null, false, 'manager') ->> 'ok', 'true', 'C fixture: the owner deactivates Kira before either is rung');
select test.eq(test.wc481(:'t2', 'local', test.k481('kira')), test.bad481('bad_pin', 'manager', '-@2:manager:no_match'),
               'C from now on Kira''s code approves nothing at the window');
select test.eq(test.v481('approve', 'kira'), '{"ok": false, "error": "inactive"}'::jsonb, 'C ... nor at the old window');
select test.dev481(:'t2');
select test.eq(test.sale481(test.o481(3), :'kira1', 1000, 100) ->> 'ok', 'true',
               'C the ticket carrying Kira''s earlier Local is recorded (the server never refuses money already taken)');
select test.eq(test.order481(test.o481(3)),
               jsonb_build_object('total', 900, 'subtotal', 1000, 'discount', 100, 'discount_id', :'kira1', 'reason', 'Local',
                                  'by', 'Kira', 'paid', true, 'discount_flags', '[]'::jsonb, 'approval_order', test.o481(3),
                                  'discount_rows', 0),
               'C ... as charged and linked as verified: Local by Kira, no flag, no discount_not_verified row (the approval was valid when given)');
select test.eq(test.sale481(test.o481(4), :'kira2', 1000, 100) ->> 'ok', 'true',
               'C the ticket carrying Kira''s earlier old-window discount is recorded too');
select test.eq(test.order481(test.o481(4)),
               jsonb_build_object('total', 900, 'subtotal', 1000, 'discount', 100, 'discount_id', :'kira2', 'reason', 'Cliente frecuente',
                                  'by', 'Kira', 'paid', true, 'discount_flags', '[]'::jsonb, 'approval_order', test.o481(4),
                                  'discount_rows', 0),
               'C ... linked as before 0038: Cliente frecuente by Kira');

-- A) ... every manager locked at once (the attack of adjustment 2): every registered till still approves -------------
select count(*) from (select test.lock481(name) from test.t481_people p where p.id in (select test.bosses481())) q;
select test.eq((select count(*)::int from test.bosses481() b where not exists (select 1 from test.t481_people p where p.id = b)), 0,
               'A fixture: every active manager and owner is one of this file''s people');
select test.eq((select string_agg(test.pin1481(p.name), ' ' order by p.id) from test.t481_people p where p.id in (select test.bosses481())),
               (select string_agg(case when p.name in ('hugo') then '6/locked' else '5/locked' end, ' ' order by p.id)
                  from test.t481_people p where p.id in (select test.bosses481())),
               'A fixture: every active manager and owner is now locked at the name-picked boxes (Hugo relocked by one try)');
select test.pins481() as pinsall \gset
select test.n481('discount_code_wrong') as wall \gset
select test.eq(test.ap481(test.w481(:'t1', 'local', '4826') ->> 'id'), 'slot:1 Ana manager local - true/false',
               'A everyone locked: Ana''s code approves at till 1');
select test.eq(test.ap481(test.w481(:'t2', 'local', test.k481('ciro')) ->> 'id'), 'slot:2 Ciro manager local - true/false',
               'A everyone locked: Ciro''s at till 2');
select test.eq(test.ap481(test.w481(:'t3', 'guia', test.k481('dueno'), p_comp => 'Tours Monteverde') ->> 'id'),
               'slot:3 Dueño owner guia - true/false', 'A everyone locked: the owner''s Guía at till 3');
select test.eq(test.ap481(test.w481(:'t3', 'empleado', test.k481('pia'), test.k481('zoe')) ->> 'id'),
               'slot:3 Pia manager empleado Zoe true/false', 'A everyone locked: Pia authorizes Zoe''s Empleado at till 3');
select test.eq(test.vol481('T2', 't481-t2b') ->> 'slot', '2', 'A everyone locked: till 2 signs in again and comes back by its key (no PIN)');
select test.eq(test.ap481(test.w481('t481-t2b', 'local', '3934') ->> 'id'), 'slot:2 Eloy manager local - true/false',
               'A everyone locked: ... and Eloy''s new code approves there');
select test.eq(test.pins481(), :'pinsall'::jsonb, 'A everyone locked: every 0033 counter and lock exactly as it was');
select test.eq(test.n481('discount_code_wrong') - :wall, 0, 'A everyone locked: nothing counted');
select test.dev481('t481-new');
select test.eq(public.access_unlock(test.staff('ana'), '4826') ->> 'error', 'locked',
               'A everyone locked: what waits is a NEW device: it cannot open the owner areas (0033), so it cannot be registered (runbook E-lock)');

-- D) NOTHING IN A-C WROTE AN UNLOCK OR MOVED A 0033 COUNTER, except 0033's own path ---------------------------------
select test.eq((select count(*)::int from test.win481), 80, 'D the window was called 80 times in this file');
select test.eq((select count(*)::int from test.win481 where not pins_same), 0,
               'D not one window call changed any person''s failed_pins or locked_until (never cleared, never raised)');
select test.eq((select coalesce(sum(unl_delta), 0)::int + coalesce(sum(open_delta), 0)::int from test.win481), 0,
               'D not one window call wrote an access_unlocks row or opened the owner areas');
select test.eq((select count(*)::int from test.win481 where not unl_same), 0,
               'D every window call left access_unlocks exactly as it was (every row, every column: the fingerprint of §0)');
select test.eq((select count(*)::int from test.win481 where ans ->> 'ok' = 'true'), test.ncat481(),
               'D every category approval in the café is one of the window calls answered ok');
select test.eq((select coalesce(sum(unl_delta), 0)::int from test.pin481), 0, 'D the name-picked boxes wrote no access_unlocks row either');
select test.eq((select count(*)::int from test.pin481 where not unl_same), 0, 'D ... and changed or removed none');
select test.eq((select count(*)::int from test.win481 where ans::text ~ '\$2[abxy]\$') + (select count(*)::int from test.pin481 where ans::text ~ '\$2[abxy]\$'), 0,
               'D no answer carries a PIN hash (the hash the code lookup matched stays inside the call)');
select test.eq((select count(*)::int from test.pin481 where diff <> '' and ans ->> 'error' in ('inactive', 'not_manager', 'locked', 'unknown_staff')), 0,
               'D their refusals inactive, not_manager and locked wrote nothing (0033 refuses before comparing)');
select test.eq((select string_agg(fn || ' ' || who || ' ' || coalesce(ans ->> 'error', 'ok') || ' ' || diff, ' | ' order by n)
                  from test.pin481 where diff <> ''),
               'quitar_cuenta eloy bad_pin Eloy:0>1 | reanudar fabi bad_pin Fabi:0>1 | approve eloy bad_pin Eloy:1>2 | approve fabi bad_pin Fabi:1>2 | approve eloy ok Eloy:2>0',
               'D the only counters that moved are the picked person''s own, by 0033''s path: a wrong PIN counts, a right one clears');
select test.eq(test.n481('access_open') - test.unl481(), 3,
               'D every access_unlocks row of this file came from access_unlock itself (one access_open row each), less the 3 a new or removed PIN ended (B 12)');
-- structural: 0038's functions (the new ones and the three it replaces)
select '^(descuento|_discount_|_staff_by_code$|_pin_locks_clear_all$|_order_discount_(flags|after|check)$|approve_discount$|tab_set_discount$)' as re38 \gset
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ :'re38' and p.prosrc ~* '\mupdate\s+(public\.)?staff\M'),
               '_pin_locks_clear_all', 'D among 0038''s functions only the owner''s SQL tool _pin_locks_clear_all writes a staff row');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ :'re38' and p.prosrc ~ 'failed_pins'),
               '_pin_locks_clear_all', 'D ... and only it names failed_pins');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ :'re38' and p.prosrc ~ 'locked_until'),
               '_discount_staff_state _discount_take_staff _pin_locks_clear_all _staff_by_code',
               'D locked_until is read only by the code lookup and the two staff checks (into locked, carried to the approval) and the tool');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ :'re38' and p.prosrc ~* 'access_unlocks'),
               '_discount_pin_changed', 'D the only 0038 function that touches access_unlocks is the trigger that ends a replaced PIN''s unlocks');
select test.ok((select prosrc ~* 'delete\s+from\s+public\.access_unlocks' and prosrc !~* '\m(insert|update)\M'
                  from pg_proc where oid = to_regprocedure('public._discount_pin_changed()')), 'D ... and it only deletes');
select test.eq((select string_agg(tgname || ' ' || (pg_get_triggerdef(oid) ~ 'AFTER UPDATE OF pin_hash ON public\.staff FOR EACH ROW WHEN \(\(old\.pin_hash IS DISTINCT FROM new\.pin_hash\)\)')::text, ' ')
                  from pg_trigger where tgrelid = 'public.staff'::regclass and tgfoid = to_regprocedure('public._discount_pin_changed()')),
               'staff_pin_changed true', 'D the trigger staff_pin_changed fires after a staff row''s PIN hash changes, and only then');
select test.eq(test.n481('pin_lock_cleared'), 0, 'D no lock was cleared by anything in this file');

select test.done();
rollback;
