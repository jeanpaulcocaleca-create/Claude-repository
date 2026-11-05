-- Migration 0038 (D-065): the four discounts of the till and what guards them (proposal §2.1-2.6 and §5.1 items 1, 2,
-- 4, 5, 7, 14, 15 and 17; the owner's adjustments 1 and 4; build plan L2, L3 and L5; mecanismo-intentos §6 for the
-- codes; api-0038 §1-§6). The server fixes the rate (Empleado 30 %, Local and Huésped 10 %, Guía Turista 100 %) and the
-- label, and a table rule makes any other row impossible. The authorizer is found by the code alone; Empleado sends the
-- employee's code in the same call, never for the authorizer themselves. Guía ships off behind pos_discount_guia (its
-- guard is the accountant's confirmation A-13) and needs the owner's code, which never opens the owner areas, creates
-- no unlock and touches no PIN counter. A code two people share authorizes nobody. The old free window
-- (approve_discount) works behind pos_free_discount, but a free reason can no longer read as a category. Only the café
-- login (and the owner) can call the new functions; anon, PUBLIC and the backup account cannot. Old rows are untouched.
-- Everything goes through the real functions as the café login (authenticated, with a session_id) on a registered till
-- (the ladder of wrong codes is 485's: here every code is judged on a calm place, see test.a480).
begin;

-- one test-only person besides the seed (Ana manager 4826, Luis staff 5284, Marta staff 6173, Dueño owner 7391):
-- Nico, staff, inactive (test PIN 8301)
insert into public.staff (id, name, role, active, pin_hash)
  values ('b4800000-0000-4000-8000-000000000001', 'Nico', 'staff', false, extensions.crypt('8301', extensions.gen_salt('bf', 4)));

-- helpers (test schema; the readers are definer functions so the café login can call them between its own calls)
-- every counted wrong code moved 25 hours back, so each code below is judged on a place with no recent mistake
create function test.calm480() returns void language sql security definer as $$ select test.back(interval '25 hours') $$;
-- the window's call at this till, as pos.html sends it, on a calm place
create function test.a480(cat text, pin text, sub int, emp text default null, comp text default null, req uuid default null)
returns jsonb language plpgsql as $$
begin
  perform test.calm480();
  return public.descuento_autorizar(cat, pin, sub, emp, comp, null, null, req, 'Caja 480');
end $$;
create function test.wrong480() returns int language sql stable security definer as $$
  select count(*)::int from public.audit_log where action = 'discount_code_wrong' $$;
create function test.n480(act text) returns int language sql stable security definer as $$
  select count(*)::int from public.audit_log where action = act $$;
create function test.cats480() returns int language sql stable security definer as $$
  select count(*)::int from public.discount_approvals where category is not null $$;
create function test.olds480() returns int language sql stable security definer as $$
  select count(*)::int from public.discount_approvals where category is null $$;
create function test.keys480(j jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(k, ' ' order by k), '') from jsonb_object_keys(j) k $$;
-- how many scalar values anywhere in a JSON value are one of the test PINs (exact values, not substrings: a uuid may
-- contain any four digits)
create function test.pins480(j jsonb) returns int language sql immutable as $$
  select count(*)::int from jsonb_path_query(coalesce(j, 'null'), 'strict $.**') v
   where jsonb_typeof(v) in ('string', 'number') and v #>> '{}' in ('4826', '5284', '6173', '7391', '8301') $$;
-- an approval row as stored, without its id and time
create function test.row480(p_id text) returns jsonb language sql stable security definer as $$
  select to_jsonb(a) - 'id' - 'created_at' from public.discount_approvals a where a.id = p_id::uuid $$;
-- what a category approval made at a till must hold (the spec's rates and labels, the till's station, sign-in and place)
create function test.expect480(cat text, by_id uuid, by_name text, role text, sub int, amt int, ben uuid, ben_name text,
                               comp text, sess text, till uuid, req uuid default null) returns jsonb language sql stable as $$
  select jsonb_build_object('approved_by', by_id, 'approved_name', by_name, 'kind', 'percent',
    'value', case cat when 'empleado' then 30 when 'guia' then 100 else 10 end,
    'reason', case cat when 'empleado' then 'Employee' when 'local' then 'Local' when 'huesped' then 'Hotel guest' else 'Tour guide' end,
    'station', 'Caja 480', 'order_id', null, 'used_at', null, 'subtotal_crc', sub, 'amount_crc', amt, 'base_crc', null,
    'base_used_crc', null, 'category', cat, 'beneficiary_id', ben, 'beneficiary_name', ben_name, 'company', comp,
    'cr_day', public.cr_today(), 'approver_role', role, 'bill_id', null, 'login_id', 'c0000000-0000-4000-8000-000000000001'::uuid,
    'session_id', sess, 'request_id', req, 'freed_at', null, 'freed_how', null, 'till_id', till) $$;
-- a counted wrong code on a calm place answers exactly this (only these keys: never a count, a name or a session)
create function test.wrongans480(err text, step text) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'error', err, 'step', step, 'warn', null, 'blocked', null, 'until', null,
                            'wait', null, 'wait_s', null) $$;
-- a direct insert into discount_approvals (a valid Local approval, changed by p): 'inserted' (then undone), or the
-- name of the CHECK it breaks
create function test.ins480(p jsonb) returns text language plpgsql as $$
declare r public.discount_approvals; c text;
begin
  r := jsonb_populate_record(null::public.discount_approvals, jsonb_build_object(
         'id', gen_random_uuid(), 'created_at', now(), 'approved_by', test.staff('ana'), 'approved_name', 'Ana',
         'kind', 'percent', 'value', 10, 'reason', 'Local', 'station', 'Caja 480', 'subtotal_crc', 1000, 'amount_crc', 100,
         'category', 'local', 'cr_day', public.cr_today() - 30, 'approver_role', 'manager') || p);
  begin
    insert into public.discount_approvals select r.*;
    raise exception using errcode = 'P0001', message = 'test480:inserted';
  exception
    when check_violation then get stacked diagnostics c = constraint_name; return c;
    when others then if sqlerrm = 'test480:inserted' then return 'inserted'; end if; return sqlstate || ' ' || sqlerrm;
  end;
end $$;
-- an error's sqlstate and message, or 'no error'
create function test.err480(sql text) returns text language plpgsql as $$
begin
  execute sql;
  return 'no error';
exception when others then return sqlstate || ':' || sqlerrm;
end $$;
-- the first statement of a function body (after its first begin, comments skipped)
create function test.first480(src text) returns text language sql immutable as $$
  select regexp_replace(substr(src, strpos(src, E'\nbegin\n') + 7), '^(\s*--[^\n]*\n|\s*\n)*\s*', '') $$;
-- is this transaction holding the advisory lock of that key (390's pattern)
create function test.locked480(k text) returns boolean language sql stable as $$
  select exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1
                   and classid::bigint = (hashtextextended(k, 0) >> 32) & 4294967295
                   and objid::bigint = hashtextextended(k, 0) & 4294967295) $$;

-- the tills: the café sign-in till-480 is the registered till of place 1 (test.till is the fixture; registering
-- through descuento_caja_registrar is 485's)
select test.login('cafe'); select test.session('till-480');
select test.eq(test.till('Caja 480'), 1, 'fixture: the café sign-in till-480 is the registered till of place 1');
select id as till from public.discount_tills where session_id = 'till-480' and ended_at is null \gset
\set cafe 'c0000000-0000-4000-8000-000000000001'

-- 0) the two settings (0008's mechanism; L2, D2) --------------------------------------------------------------------
select test.eq((select kind || ' ' || choices::text || ' ' || default_value::text || ' ' || coalesce(guard, '-')
                  from canopy.setting_defs where key = 'pos_free_discount'), 'choice {on,off} "on" -',
               '0 pos_free_discount: a choice on/off, "on" by default, no guard (older pages keep working until the owner turns it off)');
select test.eq((select kind || ' ' || choices::text || ' ' || default_value::text || ' ' || coalesce(guard, '-')
                  from canopy.setting_defs where key = 'pos_discount_guia'), 'choice {off,on} "off" courtesy_iva_confirmed',
               '0 pos_discount_guia: a choice off/on, "off" by default, guarded by courtesy_iva_confirmed (adjustment 4)');
select test.eq((select description from canopy.setting_defs where key = 'pos_discount_guia'),
               'Cortesía Guía Turista 100 %: apagada hasta que el contador confirme el tratamiento del IVA (A-13) y el dueño lo '
               'registre con compliance_confirm(''courtesy_iva_confirmed'', …); luego el dueño la enciende con el código del teléfono.',
               '0 pos_discount_guia carries the Spanish description of L2');
select test.eq((select description from canopy.setting_defs where key = 'pos_free_discount'),
               'Ventana de descuento libre de la Caja anterior (porcentaje o monto con el PIN de un encargado). on = sigue '
               'funcionando para las cajas que todavía no se recargaron, como hoy; off = solo los cuatro descuentos nuevos. '
               'Se apaga al final de la activación (docs/ACTIVACION-DESCUENTOS.md §4).',
               '0 pos_free_discount carries the Spanish description of proposal §2.1');
select test.eq(public.setting('pos_free_discount') || public.setting('pos_discount_guia'), '"on"'::jsonb || '"off"'::jsonb,
               '0 as applied: the old window on, Guía Turista off');
select test.ok(not exists (select 1 from public.compliance_confirmations where key = 'courtesy_iva_confirmed'),
               '0 nobody has confirmed the courtesies'' IVA yet (A-13 is open)');
set role authenticated;
select public.settings_get() as sg \gset
select public.descuento_estado() as es0 \gset
reset role;
select test.eq((select x ->> 'locked' || ' ' || (x ->> 'value') from jsonb_array_elements(:'sg'::jsonb) x where x ->> 'key' = 'pos_discount_guia'),
               'true off', '0 the settings list shows Guía Turista off and locked behind its confirmation');
select test.eq((select x ->> 'locked' || ' ' || (x ->> 'value') from jsonb_array_elements(:'sg'::jsonb) x where x ->> 'key' = 'pos_free_discount'),
               'false on', '0 and the old window on, not locked');
select test.eq(test.keys480(:'es0'::jsonb), 'guia_enabled ok owner_ready session till',
               '0 descuento_estado answers ok, owner_ready, guia_enabled, session and till');
select test.eq((:'es0'::jsonb) - 'till', '{"ok": true, "owner_ready": true, "guia_enabled": false, "session": true}'::jsonb,
               '0 descuento_estado: the owner has a PIN, Guía is off (guia_enabled false), this sign-in has a session');
select test.eq(((:'es0'::jsonb) -> 'till') - 'since',
               '{"registered": true, "slot": 1, "station": "Caja 480", "by": "test fixture", "state": "ok", "until": null, "wait": null, "wait_s": null, "warn": null}'::jsonb,
               '0 and this till: registered in place 1, calm');

-- 1) rates and labels fixed by the server ---------------------------------------------------------------------------
select test.eq((select string_agg(coalesce(c, '-') || '=' || coalesce(public._discount_rate(c)::text, 'null') || ':' || coalesce(public._discount_label(c), 'null'), ' ' order by o)
                  from unnest(array['empleado', 'local', 'huesped', 'guia', 'vip', null]) with ordinality u(c, o)),
               'empleado=30:Employee local=10:Local huesped=10:Hotel guest guia=100:Tour guide vip=null:null -=null:null',
               '1 the rates (30/10/10/100) and the English labels (lang.js shows Empleado, Local, Huésped, Guía Turista); nothing else');
select test.eq(pg_get_function_arguments('public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text)'::regprocedure),
               'p_category text, p_pin text, p_subtotal integer, p_employee_pin text DEFAULT NULL::text, p_company text DEFAULT NULL::text, '
               'p_order_id uuid DEFAULT NULL::uuid, p_expect integer DEFAULT NULL::integer, p_request_id uuid DEFAULT NULL::uuid, p_station text DEFAULT NULL::text',
               '1 the page never sends a rate, an amount or a person: only the category, the codes, the list value (and bill, request, station)');

-- 2) Local and Huésped: the authorizer by the code alone, 10 % of the list value rounded (proposal §5.1 item 1) ----
\set req_l1 'e4800000-0000-4000-8000-000000000001'
set role authenticated;
select test.a480('local', '4826', 12345, null, null, :'req_l1') as l1 \gset
select test.a480('local', '4826', 12344) as l2 \gset
select test.a480('huesped', '4826', 9995) as h1 \gset
select test.a480('local', '7391', 20000) as l3 \gset
select test.a480(' HUESPED ', '7391', 3000) as h2 \gset
select test.wrong480() as w0 \gset
select test.a480('local', '4826', 3000, '0001', 'Selvatura Tours') as l4 \gset
select test.wrong480() as w1 \gset
select test.cats480() as c0 \gset
select test.a480('local', '5284', 12345) as lb1 \gset
select test.a480('local', '0000', 12345) as lb2 \gset
select test.a480('huesped', '6173', 12345) as hb1 \gset
select test.wrong480() as w2 \gset
select test.cats480() as c1 \gset
reset role;
select (:'l1'::jsonb) ->> 'id' as l1_id, (:'h1'::jsonb) ->> 'id' as h1_id, (:'l3'::jsonb) ->> 'id' as l3_id,
       (:'l4'::jsonb) ->> 'id' as l4_id \gset
select test.eq((:'l1'::jsonb) - 'id' - 'at',
               jsonb_build_object('ok', true, 'request_id', :'req_l1', 'category', 'local', 'amount', 1235, 'subtotal', 12345,
                                  'reason', 'Local', 'name', 'Ana', 'role', 'manager', 'beneficiary', null, 'company', null, 'prior', null),
               '2 Local with Ana''s code alone: ok, 10 % of 12345 rounded half up = 1235, Ana as manager, label Local');
select test.eq(((:'l1'::jsonb) ->> 'at')::timestamptz, (select created_at from public.discount_approvals where id = :'l1_id'),
               '2 the answer''s id and time are the stored approval''s');
select test.eq(test.row480(:'l1_id'),
               test.expect480('local', test.staff('ana'), 'Ana', 'manager', 12345, 1235, null, null, null, 'till-480', :'till', :'req_l1'),
               '2 the Local approval as stored: percent 10, Local, Ana (manager), today''s Costa Rica day, the till, its sign-in and the request id; unused');
select test.eq((:'l2'::jsonb) ->> 'amount', '1234', '2 12344 → 1234 (1234.4 rounds down)');
select test.eq((:'h1'::jsonb) - 'id' - 'at',
               jsonb_build_object('ok', true, 'request_id', null, 'category', 'huesped', 'amount', 1000, 'subtotal', 9995,
                                  'reason', 'Hotel guest', 'name', 'Ana', 'role', 'manager', 'beneficiary', null, 'company', null, 'prior', null),
               '2 Huésped with Ana''s code: 10 % of 9995 = 999.5 → 1000, label Hotel guest');
select test.eq(test.row480(:'h1_id'),
               test.expect480('huesped', test.staff('ana'), 'Ana', 'manager', 9995, 1000, null, null, null, 'till-480', :'till'),
               '2 the Huésped approval as stored');
select test.eq((:'l3'::jsonb) ->> 'name' || ' ' || ((:'l3'::jsonb) ->> 'role') || ' ' || ((:'l3'::jsonb) ->> 'amount'), 'Dueño owner 2000',
               '2 the owner''s code authorizes Local too, as owner');
select test.eq(test.row480(:'l3_id'),
               test.expect480('local', test.staff('dueno'), 'Dueño', 'owner', 20000, 2000, null, null, null, 'till-480', :'till'),
               '2 stored with approver_role owner');
select test.eq((:'h2'::jsonb) ->> 'category' || ' ' || ((:'h2'::jsonb) ->> 'amount'), 'huesped 300',
               '2 the category is read lower-cased and trimmed (" HUESPED ")');
select test.eq((:'l4'::jsonb) ->> 'ok' || ' ' || coalesce((:'l4'::jsonb) ->> 'beneficiary', 'null') || ' ' || coalesce((:'l4'::jsonb) ->> 'company', 'null'),
               'true null null', '2 Local ignores an employee code and a company sent with it');
select test.eq(jsonb_build_array(test.row480(:'l4_id') -> 'beneficiary_id', test.row480(:'l4_id') -> 'beneficiary_name', test.row480(:'l4_id') -> 'company'),
               '[null, null, null]'::jsonb, '2 and stores neither');
select test.eq(:w1 - :w0, 0, '2 the employee code sent with Local is never tested (a wrong one counts nothing)');
select test.eq(:'lb1'::jsonb, test.wrongans480('bad_pin', 'manager'),
               '2 Luis''s code (staff) at the manager step: bad_pin, step manager, nothing else in the answer');
select test.eq(:'lb2'::jsonb, :'lb1'::jsonb, '2 a code of nobody: the very same answer (a staff code looks like any wrong code)');
select test.eq((:'hb1'::jsonb) ->> 'error' || ' ' || ((:'hb1'::jsonb) ->> 'step'), 'bad_pin manager', '2 Marta''s code (staff) for Huésped: bad_pin');
select test.eq(:w2 - :w1, 3, '2 the three wrong codes are counted (one discount_code_wrong row each)');
select test.eq((select string_agg(details ->> 'step' || ':' || (details ->> 'why') || ':' || (details ->> 'category') || ':'
                                  || coalesce(manager_id::text, '-') || ':' || coalesce(details ->> 'authorizer', '-'), ' ' order by id)
                  from (select * from public.audit_log where action = 'discount_code_wrong' order by id desc limit 3) x),
               'manager:not_allowed:local:-:- manager:no_match:local:-:- manager:not_allowed:huesped:-:-',
               '2 counted as the manager step: Luis not allowed, nobody matched, Marta not allowed; no authorizer named');
select test.eq((select count(*)::int from (select * from public.audit_log where action = 'discount_code_wrong' order by id desc limit 3) x
                 where target_id = :'till' and details ->> 'till' = :'till' and details ->> 'slot' = '1'
                   and details ->> 'session_tag' ~ '^s[0-9a-f]{7}$' and details ->> 'station' = 'Caja 480'
                   and details ->> 'till_station' = 'Caja 480' and details ->> 'by_login' = :'cafe' and details ->> 'account' = 'cafe'),
               3, '2 each wrong row names the till, its place, the sign-in only as a tag, the stations and the login');
select test.eq(:c1 - :c0, 0, '2 a wrong code makes no approval');
select test.eq((select manager_id::text || ' ' || manager_name || ' ' || summary from public.audit_log
                 where action = 'discount_approved' and target_id = :'l1_id'), test.staff('ana')::text || ' Ana Local',
               '2 the approval is logged (discount_approved) naming Ana, with the label as summary');
select test.eq((select details from public.audit_log where action = 'discount_approved' and target_id = :'l1_id'),
               jsonb_build_object('kind', 'percent', 'value', 10, 'subtotal_crc', 12345, 'discount_crc', 1235, 'station', 'Caja 480',
                                  'category', 'local', 'beneficiary_name', null, 'company', null, 'approver_role', 'manager',
                                  'bill', null, 'prior', null, 'till', :'till', 'slot', 1, 'person_locked', false,
                                  'employee_locked', false, 'by_login', :'cafe'),
               '2 its details: the old keys (kind, value, subtotal, discount, station) and the category''s');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.calm480();
select public.descuento_autorizar('local', '4826', 4000, null, null, null, null, null,
                                  '  Caja' || chr(160) || chr(160) || 'principal ' || repeat('x', 40)) ->> 'id' as st_id \gset
reset role;
select test.eq((select station from public.discount_approvals where id = :'st_id'), 'Caja principal ' || repeat('x', 25),
               '2 the page''s station is stored cleaned (blanks collapsed, ends trimmed) and cut to 40 characters');

-- 3) every refusal of the request itself comes before any code is tested (nothing counted) -----------------------
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.wrong480() as w0 \gset
select test.n480('discount_till_unknown') as u0 \gset
select test.a480('vip', '0000', 5000) as q1 \gset
select test.a480(null, '0000', 5000) as q2 \gset
select test.a480('local', '0000', 0) as q3 \gset
select test.a480('local', '0000', -5) as q4 \gset
select test.a480('local', '0000', null) as q5 \gset
select test.a480('empleado', '0000', 5000) as q6 \gset
select test.a480('empleado', '0000', 5000, '   ') as q7 \gset
select test.a480('vip', '0000', 0) as q8 \gset
select test.a480('empleado', '0000', 0) as q9 \gset
select test.a480('local', '', 5000) as q10 \gset
select test.a480('vip', '   ', 0) as q11 \gset
select test.a480('local', null, 5000) as q12 \gset
select test.a480('local', '', 5000, null, null, 'e4800000-0000-4000-8000-000000000009') as q12b \gset
select test.wrong480() as w1 \gset
reset role;
select test.eq(:'q1'::jsonb, '{"ok": false, "error": "bad_discount"}'::jsonb, '3 an unknown category: bad_discount');
select test.eq((:'q2'::jsonb) ->> 'error', 'bad_discount', '3 no category: bad_discount');
select test.eq((:'q3'::jsonb) ->> 'error' || ' ' || ((:'q4'::jsonb) ->> 'error') || ' ' || ((:'q5'::jsonb) ->> 'error'), 'empty empty empty',
               '3 a list value of 0, below 0 or missing: empty');
select test.eq(:'q6'::jsonb, '{"ok": false, "error": "missing_employee"}'::jsonb, '3 Empleado without the employee code: missing_employee');
select test.eq((:'q7'::jsonb) ->> 'error', 'missing_employee', '3 a blank employee code too');
select test.eq((:'q8'::jsonb) ->> 'error' || ' ' || ((:'q9'::jsonb) ->> 'error'), 'bad_discount empty',
               '3 in order: the category, then the list value, then the employee code');
select test.eq(:'q10'::jsonb, '{"ok": false, "error": "no_request"}'::jsonb, '3 an empty code: no_request (tests nothing)');
select test.eq((:'q11'::jsonb) ->> 'error' || ' ' || ((:'q12'::jsonb) ->> 'error') || ' ' || ((:'q12b'::jsonb) ->> 'error'),
               'no_request no_request no_request',
               '3 a blank or missing code: no_request, before anything else is looked at (with a request id nobody used, too)');
select test.eq(:w1 - :w0, 0, '3 none of these refusals counts the wrong code that came with it');
-- the same answers on a sign-in that is not a registered till, and on a token without a session: they come before the till
select test.login('cafe'); select test.session('tablet-480-n'); set role authenticated;
select test.a480('vip', '4826', 5000) as q13 \gset
select test.a480('local', '4826', 0) as q14 \gset
select test.a480('empleado', '4826', 5000) as q15 \gset
reset role;
select test.login('cafe'); set role authenticated;
select test.a480('vip', '4826', 5000) as q16 \gset
reset role;
select test.eq((:'q13'::jsonb) ->> 'error' || ' ' || ((:'q14'::jsonb) ->> 'error') || ' ' || ((:'q15'::jsonb) ->> 'error') || ' ' || ((:'q16'::jsonb) ->> 'error'),
               'bad_discount empty missing_employee bad_discount',
               '3 on an unregistered sign-in and without a session the request is refused first (not till_not_enrolled / no_session)');
select test.eq(test.n480('discount_till_unknown') - :u0, 0, '3 and those refusals log no code typed on an unregistered device');
select test.login('cafe'); select test.session('tablet-480-n'); set role authenticated;
select test.a480('local', '4826', 5000) as q17 \gset
reset role;
select test.eq((:'q17'::jsonb) ->> 'error' || ' ' || (test.n480('discount_till_unknown') - :u0), 'till_not_enrolled 1',
               '3 (control) a complete request there reaches the till check: till_not_enrolled, one discount_till_unknown row');
select test.login('accountant', 'aal2'); set role authenticated;
select public.descuento_autorizar('vip', '', 0) as q18 \gset
reset role;
select test.eq(:'q18'::jsonb, '{"ok": false, "error": "no_account"}'::jsonb, '3 the account first: the accountant gets no_account, whatever the request');

-- 4) Empleado: both codes in one call, the manager's first; one a day (proposal §5.1 item 2) ------------------------
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.a480('empleado', '4826', 1005, '5284') as e1 \gset
select test.wrong480() as w0 \gset
select test.cats480() as c0 \gset
select test.a480('empleado', '4826', 10001, '5284') as e2 \gset
select test.wrong480() as w1 \gset
select test.cats480() as c1 \gset
select test.a480('empleado', '4826', 10001, '6173') as e3 \gset
reset role;
select (:'e1'::jsonb) ->> 'id' as e1_id, (:'e3'::jsonb) ->> 'id' as e3_id \gset
select test.eq((:'e1'::jsonb) - 'id' - 'at',
               jsonb_build_object('ok', true, 'request_id', null, 'category', 'empleado', 'amount', 302, 'subtotal', 1005,
                                  'reason', 'Employee', 'name', 'Ana', 'role', 'manager', 'beneficiary', 'Luis', 'company', null, 'prior', null),
               '4 Luis''s code and Ana''s in one call: ok, 30 % of 1005 = 301.5 → 302, beneficiary Luis, authorized by Ana');
select test.eq(test.row480(:'e1_id'),
               test.expect480('empleado', test.staff('ana'), 'Ana', 'manager', 1005, 302, test.staff('luis'), 'Luis', null, 'till-480', :'till'),
               '4 stored: percent 30, Employee, Luis (id and name), Ana (manager), today''s Costa Rica day (cr_day)');
select test.eq((select manager_name || ' ' || summary || ' ' || (details ->> 'category') || ' ' || (details ->> 'value') || ' '
                       || (details ->> 'beneficiary_name') || ' ' || (details ->> 'approver_role') || ' ' || (details ->> 'discount_crc')
                       || ' ' || (details ->> 'employee_locked') from public.audit_log where action = 'discount_approved' and target_id = :'e1_id'),
               'Ana Employee empleado 30 Luis manager 302 false', '4 logged (discount_approved) naming Ana, with Luis as beneficiary');
select test.eq((:'e2'::jsonb) - 'until',
               '{"ok": false, "error": "daily_used", "beneficiary": "Luis", "pending": true, "station": "Caja 480"}'::jsonb,
               '4 a second Empleado for Luis the same day: daily_used, pending (the first is not used yet) and where it waits');
select test.eq(((:'e2'::jsonb) ->> 'until')::timestamptz, (select created_at + interval '30 minutes' from public.discount_approvals where id = :'e1_id'),
               '4 until = the first approval''s time + 30 minutes');
select test.eq((select manager_id::text || ' ' || manager_name || ' ' || target_id || ' ' || (details ->> 'beneficiary_name') || ' '
                       || (details ->> 'beneficiary') || ' ' || (details ->> 'approval') || ' ' || (details ->> 'pending')
                       || ' ' || (details ->> 'category') || ' ' || (details ->> 'till') || ' ' || (details ->> 'station')
                  from public.audit_log where action = 'discount_daily_refused' and target_id = :'e1_id'),
               test.staff('ana')::text || ' Ana ' || :'e1_id' || ' Luis ' || test.staff('luis')::text || ' ' || :'e1_id' || ' true empleado ' || :'till' || ' Caja 480',
               '4 the refusal is logged (discount_daily_refused) naming Ana and Luis, and the approval that holds his day');
select test.eq(:w1 - :w0, 0, '4 daily_used comes after two valid codes: not counted');
select test.eq(:c1 - :c0, 0, '4 and no second approval for Luis');
select test.eq((:'e3'::jsonb) ->> 'beneficiary' || ' ' || ((:'e3'::jsonb) ->> 'amount'), 'Marta 3000', '4 Marta the same day: ok (10001 → 3000)');
-- once a sale used Marta's, the second answer has nothing pending
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', 'd4800000-0000-4000-8000-000000000001', 'created_at', now(), 'total_crc', 7001,
          'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'station', 'Caja 480', 'guest_name', 'Ticket 480',
          'subtotal_crc', 10001, 'discount_crc', 3000, 'discount_id', :'e3_id',
          'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 10001, 'qty', 1)))) ->> 'ok', 'true',
               '4 (fixture) a sale uses Marta''s approval');
select test.a480('empleado', '4826', 5000, '6173') as e4 \gset
reset role;
select test.eq(:'e4'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Marta", "pending": false}'::jsonb,
               '4 then a second one for Marta: daily_used, not pending, no station or time');
-- the employee code is tested only after a valid manager code, and every wrong one is counted naming that manager
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.wrong480() as w0 \gset
select test.cats480() as c0 \gset
select test.a480('empleado', '4826', 5000, '0000') as eb1 \gset
select test.a480('empleado', '4826', 5000, '7391') as eb2 \gset
select test.a480('empleado', '4826', 5000, '8301') as eb3 \gset
select test.a480('empleado', '0000', 5000, '5284') as eb4 \gset
select test.a480('empleado', '5284', 5000, '6173') as eb5 \gset
select test.wrong480() as w1 \gset
select test.cats480() as c1 \gset
reset role;
select test.eq(:'eb1'::jsonb, test.wrongans480('bad_employee', 'employee'),
               '4 a wrong employee code with Ana''s right code: bad_employee, step employee, nothing else in the answer');
select test.eq(:'eb2'::jsonb, test.wrongans480('bad_employee', 'employee'),
               '4 the owner''s code at the employee step: bad_employee (the owner is not an employee beneficiary)');
select test.eq(:'eb3'::jsonb, test.wrongans480('bad_employee', 'employee'), '4 an inactive person''s code: bad_employee (nobody active has it)');
select test.eq(:'eb4'::jsonb, test.wrongans480('bad_pin', 'manager'), '4 a wrong manager code with Luis''s right code: bad_pin at the manager step');
select test.eq(:'eb5'::jsonb, test.wrongans480('bad_pin', 'manager'), '4 a staff code at the manager step of Empleado: bad_pin');
select test.eq(:w1 - :w0, 5, '4 five wrong codes, five rows: the employee code after a wrong manager code is never tested');
select test.eq((select string_agg(details ->> 'step' || ':' || (details ->> 'why') || ':' || coalesce(manager_name, '-') || ':'
                                  || coalesce(details ->> 'authorizer', '-'), ' ' order by id)
                  from (select * from public.audit_log where action = 'discount_code_wrong' order by id desc limit 5) x),
               'employee:no_match:Ana:' || test.staff('ana') || ' employee:owner_beneficiary:Ana:' || test.staff('ana')
               || ' employee:no_match:Ana:' || test.staff('ana') || ' manager:no_match:-:- manager:not_allowed:-:-',
               '4 the employee-step rows name Ana (whose code came first); the manager-step rows name nobody');
select test.eq((select count(*)::int from (select * from public.audit_log where action = 'discount_code_wrong' order by id desc limit 5) x
                 where details ->> 'step' = 'employee' and manager_id = test.staff('ana') and details ->> 'category' = 'empleado'), 3,
               '4 with Ana as manager_id on each employee-step row');
select test.eq(:c1 - :c0, 0, '4 none of them made an approval');

-- 5) never for oneself (proposal §5.1 item 4) ----------------------------------------------------------------------
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.wrong480() as w0 \gset
select test.n480('discount_self_refused') as sr0 \gset
select test.a480('empleado', '4826', 5000, '4826') as s1 \gset
select test.a480('empleado', '7391', 5000, '7391') as s2 \gset
select test.wrong480() as w1 \gset
select test.n480('discount_self_refused') as sr1 \gset
select test.a480('empleado', '7391', 5000, '4826') as s3 \gset
reset role;
select (:'s3'::jsonb) ->> 'id' as s3_id \gset
select test.eq(:'s1'::jsonb, '{"ok": false, "error": "not_self"}'::jsonb, '5 Ana''s code as manager and as employee: not_self');
select test.eq(:'s2'::jsonb, '{"ok": false, "error": "not_self"}'::jsonb, '5 the owner for the owner: not_self too');
select test.eq(:w1 - :w0, 0, '5 not_self is not counted (it tells the typist nothing they do not know)');
select test.eq(:sr1 - :sr0, 2, '5 each is logged (discount_self_refused)');
select test.eq((select manager_id::text || ' ' || manager_name || ' ' || target_id || ' ' || (details ->> 'category') || ' ' || (details ->> 'till')
                       || ' ' || (details ->> 'slot') || ' ' || (details ->> 'station') || ' ' || (details ->> 'by_login')
                  from public.audit_log where action = 'discount_self_refused' order by id desc offset 1 limit 1),
               test.staff('ana')::text || ' Ana ' || :'till' || ' empleado ' || :'till' || ' 1 Caja 480 ' || :'cafe',
               '5 Ana''s row names her, the till, its place and the station');
select test.eq((:'s3'::jsonb) ->> 'name' || ' ' || ((:'s3'::jsonb) ->> 'role') || ' ' || ((:'s3'::jsonb) ->> 'beneficiary'), 'Dueño owner Ana',
               '5 the owner for Ana: ok');
select test.eq(test.row480(:'s3_id'),
               test.expect480('empleado', test.staff('dueno'), 'Dueño', 'owner', 5000, 1500, test.staff('ana'), 'Ana', null, 'till-480', :'till'),
               '5 stored with the owner as authorizer and Ana as beneficiary');
select test.eq((select count(*)::int from public.discount_approvals where beneficiary_id = test.staff('ana')), 1,
               '5 the refused self-discount left no approval for Ana');

-- 6) the table rule: no other rate, amount, self-discount or Guía without the owner (proposal §2.2; items 4 and 5) --
select test.eq(test.ins480('{}'), 'inserted', '6 (control) a well-formed Local row goes in');
select test.eq(test.ins480(jsonb_build_object('category', 'empleado', 'value', 30, 'reason', 'Employee', 'amount_crc', 300,
                                              'beneficiary_id', test.staff('luis'), 'beneficiary_name', 'Luis')), 'inserted',
               '6 (control) a well-formed Empleado row goes in');
select test.eq(test.ins480(jsonb_build_object('category', 'guia', 'value', 100, 'reason', 'Tour guide', 'amount_crc', 1000,
                                              'approved_by', test.staff('dueno'), 'approved_name', 'Dueño', 'approver_role', 'owner',
                                              'company', 'Selvatura Tours')), 'inserted', '6 (control) a well-formed Guía row goes in');
select test.eq(test.ins480('{"category": null, "kind": "amount", "value": 700, "reason": "Promotion", "subtotal_crc": null, "amount_crc": null, "cr_day": null, "approver_role": null}'),
               'inserted', '6 an old-kind row (no category) is not concerned by the rule');
select test.eq(test.ins480('{"value": 15, "amount_crc": 150}'), 'discount_approvals_categoria', '6 Local at 15 %: refused');
select test.eq(test.ins480('{"kind": "amount", "amount_crc": 10, "value": 10}'), 'discount_approvals_categoria', '6 a category as an amount: refused');
select test.eq(test.ins480('{"amount_crc": 99}'), 'discount_approvals_categoria', '6 an amount that is not 10 % of the list value: refused');
select test.eq(test.ins480('{"amount_crc": 101}'), 'discount_approvals_categoria', '6 nor one colón more');
select test.eq(test.ins480('{"subtotal_crc": 0, "amount_crc": 0}'), 'discount_approvals_categoria', '6 a list value of 0: refused');
select test.eq(test.ins480('{"subtotal_crc": null, "amount_crc": null}'), 'discount_approvals_categoria',
               '6 a category row without a list value and an amount: refused (the rule fixes the amount; §2.3, §2.9)');
select test.eq(test.ins480('{"amount_crc": null}'), 'discount_approvals_categoria',
               '6 a category row with a list value and no amount: refused (the rule fixes the amount; §2.3, §2.9)');
select test.eq(test.ins480('{"cr_day": null}'), 'discount_approvals_categoria', '6 without its Costa Rica day: refused');
select test.eq(test.ins480('{"approver_role": null}'), 'discount_approvals_categoria', '6 without the authorizer''s role: refused');
select test.eq(test.ins480(jsonb_build_object('beneficiary_id', test.staff('luis'), 'beneficiary_name', 'Luis')), 'discount_approvals_categoria',
               '6 a Local with a beneficiary: refused (only Empleado has one)');
select test.eq(test.ins480('{"company": "Selvatura Tours"}'), 'discount_approvals_categoria', '6 a Local with a company: refused (only Guía has one)');
select test.eq(test.ins480('{"category": "huesped", "value": 100, "amount_crc": 1000}'), 'discount_approvals_categoria', '6 Huésped at 100 %: refused');
select test.eq(test.ins480(jsonb_build_object('category', 'empleado', 'value', 10, 'amount_crc', 100, 'beneficiary_id', test.staff('luis'),
                                              'beneficiary_name', 'Luis')), 'discount_approvals_categoria', '6 Empleado at 10 %: refused');
select test.eq(test.ins480('{"category": "empleado", "value": 30, "amount_crc": 300}'), 'discount_approvals_categoria',
               '6 Empleado without the employee''s name: refused');
select test.eq(test.ins480(jsonb_build_object('category', 'empleado', 'value', 30, 'amount_crc', 300, 'beneficiary_id', test.staff('ana'),
                                              'beneficiary_name', 'Ana')), 'discount_approvals_categoria',
               '6 Empleado authorized by the beneficiary (Ana for Ana): refused by the rule too');
select test.eq(test.ins480(jsonb_build_object('category', 'empleado', 'value', 30, 'amount_crc', 300, 'approved_by', null,
                                              'beneficiary_id', test.staff('ana'), 'beneficiary_name', 'Ana')), 'inserted',
               '6 the ids are compared only while both exist (a staff row removed later sets one to null)');
select test.eq(test.ins480(jsonb_build_object('category', 'guia', 'value', 100, 'amount_crc', 1000, 'company', 'Selvatura Tours',
                                              'approver_role', 'manager')), 'discount_approvals_categoria',
               '6 Guía with approver_role manager: refused (item 5)');
select test.eq(test.ins480(jsonb_build_object('category', 'guia', 'value', 100, 'amount_crc', 1000, 'approver_role', 'owner')),
               'discount_approvals_categoria', '6 Guía without a company: refused');
select test.eq(test.ins480(jsonb_build_object('category', 'guia', 'value', 100, 'amount_crc', 1000, 'approver_role', 'owner', 'company', 'T')),
               'discount_approvals_categoria', '6 Guía with a 1-character company: refused');
select test.eq(test.ins480(jsonb_build_object('category', 'guia', 'value', 100, 'amount_crc', 1000, 'approver_role', 'owner', 'company', repeat('a', 81))),
               'discount_approvals_categoria', '6 Guía with an 81-character company: refused');
select test.eq(test.ins480(jsonb_build_object('category', 'guia', 'value', 10, 'amount_crc', 100, 'approver_role', 'owner', 'company', 'Selvatura Tours')),
               'discount_approvals_categoria', '6 Guía at 10 %: refused');
select test.eq(test.ins480('{"category": "vip"}'), 'discount_approvals_category_check', '6 a fifth category: refused');
select test.eq(test.ins480('{"approver_role": "staff"}'), 'discount_approvals_approver_role_check', '6 a staff role as authorizer: refused');
select test.eq(test.ins480('{"freed_at": "2026-01-01T00:00:00Z", "freed_how": "deleted"}'), 'discount_approvals_freed_how_check',
               '6 an unknown way of freeing: refused');

-- 7) Guía Turista ships off (adjustment 4, L2): refused before anything else, nothing counted, nothing locked --------
select test.login('cafe'); select test.session('till-480-o');
select test.eq(test.till('Caja 480 O'), 2, 'fixture: the café sign-in till-480-o is the registered till of place 2');
set role authenticated;
select test.wrong480() as w0 \gset
select test.n480('discount_till_unknown') as u0 \gset
select test.cats480() as c0 \gset
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as g1 \gset
select test.locked480('canopy.discount_slot:2') as lock3a \gset
select test.a480('guia', '0000', 12345, null, 'Selvatura Tours') as g2 \gset
select test.a480('guia', '7391', 12345) as g3 \gset
select test.a480('guia', '7391', 12345, null, E'\u200b\u200b') as g4 \gset
select test.wrong480() as w1 \gset
reset role;
select test.eq(:'g1'::jsonb, '{"ok": false, "error": "guia_off"}'::jsonb, '7 Guía with the owner''s right code while off: guia_off');
select test.eq(:'lock3a'::text, 'f', '7 answered before the till''s place lock (lock C) is taken');
select test.eq(:'g2'::jsonb, '{"ok": false, "error": "guia_off"}'::jsonb, '7 and the same answer with a wrong code: the code is never tested');
select test.eq((:'g3'::jsonb) ->> 'error' || ' ' || ((:'g4'::jsonb) ->> 'error'), 'missing_company missing_company',
               '7 the company is a request check: missing_company comes first, off or on');
select test.eq(:w1 - :w0, 0, '7 nothing counted while off');
select test.eq(test.cats480() - :c0, 0, '7 no approval');
select test.login('cafe'); select test.session('tablet-480-n'); set role authenticated;
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as g5 \gset
reset role;
select test.login('cafe'); set role authenticated;
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as g6 \gset
reset role;
update public.staff set active = false where id = test.staff('dueno');
select test.login('cafe'); select test.session('till-480-o'); set role authenticated;
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as g7 \gset
reset role;
update public.staff set active = true where id = test.staff('dueno');
select test.eq((:'g5'::jsonb) ->> 'error' || ' ' || ((:'g6'::jsonb) ->> 'error') || ' ' || ((:'g7'::jsonb) ->> 'error'), 'guia_off guia_off guia_off',
               '7 off comes before the till checks (unregistered sign-in, no session) and before no_owner');
select test.eq(test.n480('discount_till_unknown') - :u0, 0, '7 and logs no code typed on an unregistered device');
select test.login('cafe'); select test.session('till-480-o'); set role authenticated;
select test.a480('local', '4826', 3000) as g8 \gset
select test.locked480('canopy.discount_slot:2') as lock3b \gset
reset role;
select test.eq((:'g8'::jsonb) ->> 'ok' || ' ' || :'lock3b', 'true t', '7 (control) a Local at that till does take place 2''s lock');
-- only the owner with the phone code turns it on, and only after the accountant's confirmation is recorded
select test.login('cafe'); select test.session('tablet-480-u'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select public.setting_set('pos_discount_guia', '"on"') as so1 \gset
select public.compliance_confirm('courtesy_iva_confirmed', 'Contador (prueba)', 'A-13 (prueba)') as cc1 \gset
reset role;
select test.eq((:'so1'::jsonb) ->> 'error' || ' ' || ((:'cc1'::jsonb) ->> 'error'), 'owner_only owner_only',
               '7 the owner''s PIN on a tablet does not open settings: setting_set and compliance_confirm answer owner_only');
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('pos_discount_guia', '"on"') as so2 \gset
select public.compliance_confirm('courtesy_iva_confirmed', 'Contador (prueba)', 'A-13 (prueba)') as cc2 \gset
select public.setting_set('pos_discount_guia', '"si"') as so3 \gset
select public.setting_set('pos_discount_guia', '"on"') as so4 \gset
reset role;
select test.eq(:'so2'::jsonb, '{"ok": false, "error": "needs_confirmation", "guard": "courtesy_iva_confirmed"}'::jsonb,
               '7 the owner with the phone code, before the confirmation: needs_confirmation (courtesy_iva_confirmed)');
select test.eq(:'cc2'::jsonb, '{"ok": true}'::jsonb, '7 compliance_confirm accepts courtesy_iva_confirmed (a setting names it as guard)');
select test.eq((:'so3'::jsonb) ->> 'error', 'bad_value', '7 only on or off');
select test.eq(:'so4'::jsonb, '{"ok": true, "value": "on"}'::jsonb, '7 then setting_set turns Guía on');
select test.eq(public.setting('pos_discount_guia'), '"on"'::jsonb, '7 pos_discount_guia = on');
select test.eq((select summary || ' | ' || details::text from public.audit_log where action = 'setting_change' and target_id = 'pos_discount_guia'),
               'pos_discount_guia: off → on | {"after": "on", "before": "off"}', '7 the change is logged (setting_change), once');

-- 8) Guía Turista on: the owner's code only, 100 %, the company cleaned (proposal §5.1 item 5) ----------------------
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select public.descuento_estado() ->> 'guia_enabled' as ge \gset
select test.wrong480() as w0 \gset
select test.cats480() as c0 \gset
select test.a480('guia', '7391', 12345) as gc1 \gset
select test.a480('guia', '7391', 12345, null, '') as gc2 \gset
select test.a480('guia', '7391', 12345, null, '   ') as gc3 \gset
select test.a480('guia', '7391', 12345, null, E'\u200b\u200b') as gc4 \gset
select test.a480('guia', '7391', 12345, null, E'\u00a0\u3000\u2003') as gc5 \gset
select test.a480('guia', '7391', 12345, null, 'T') as gc6 \gset
select test.a480('guia', '7391', 12345, null, '--') as gc7 \gset
select test.a480('guia', '7391', 12345, null, repeat('a', 81)) as gc8 \gset
select test.a480('guia', '7391', 12345, null, E'T\u200bo') as gc9 \gset
select test.wrong480() as w1 \gset
select test.cats480() as c1 \gset
reset role;
select test.eq(:'ge'::text, 'true', '8 descuento_estado: guia_enabled true');
select test.eq(:'gc1'::jsonb, '{"ok": false, "error": "missing_company"}'::jsonb, '8 no company: missing_company');
select test.eq((select string_agg(x ->> 'error', ' ') from jsonb_array_elements(jsonb_build_array(:'gc2'::jsonb, :'gc3'::jsonb, :'gc4'::jsonb,
                  :'gc5'::jsonb, :'gc6'::jsonb, :'gc7'::jsonb, :'gc8'::jsonb)) x),
               'missing_company missing_company missing_company missing_company missing_company missing_company missing_company',
               '8 empty, blank, zero-width only, other blanks only, 1 character, no letter or digit, 81 characters: missing_company');
select test.eq((:'gc9'::jsonb) ->> 'company', 'To', '8 a zero-width character inside is removed (T\u200bo → To, 2 characters: ok)');
select test.eq(:w1 - :w0, 0, '8 a missing company never tests the code');
select test.eq(:c1 - :c0, 1, '8 only the 2-character company made an approval');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as gd1 \gset
select test.a480('guia', '7391', 8000, null, E'  Tours\u202eXY  ') as gd2 \gset
select test.a480('guia', '7391', 8000, null, U&'\FF34\FF4F\FF55\FF52\FF53') as gd3 \gset
select test.a480('guia', '7391', 8000, null, E'Monteverde\u00a0\u00a0 Cloud\u2003\tTours') as gd4 \gset
select test.a480('guia', '7391', 8000, null, E'Selva\u00adtura\ufeff') as gd5 \gset
select test.a480('guia', '7391', 8000, null, repeat('a', 80)) as gd6 \gset
select test.a480('guia', '7391', 8000, null, E'Gui\u0301a Café') as gd7 \gset
select test.a480('guia', '7391', 8000, '5284', 'Sky Tours') as gd8 \gset
reset role;
select (:'gd1'::jsonb) ->> 'id' as gd1_id, (:'gd2'::jsonb) ->> 'id' as gd2_id \gset
select test.eq((:'gd1'::jsonb) - 'id' - 'at',
               jsonb_build_object('ok', true, 'request_id', null, 'category', 'guia', 'amount', 12345, 'subtotal', 12345,
                                  'reason', 'Tour guide', 'name', 'Dueño', 'role', 'owner', 'beneficiary', null,
                                  'company', 'Selvatura Tours', 'prior', null),
               '8 Guía with the owner''s code: ok, 100 % (amount = list value), label Tour guide, the owner, the company');
select test.eq(test.row480(:'gd1_id'),
               test.expect480('guia', test.staff('dueno'), 'Dueño', 'owner', 12345, 12345, null, null, 'Selvatura Tours', 'till-480', :'till'),
               '8 stored: percent 100, Tour guide, the owner (approver_role owner), the company');
select test.eq((select details ->> 'company' || ' ' || (details ->> 'approver_role') || ' ' || (details ->> 'value') from public.audit_log
                 where action = 'discount_approved' and target_id = :'gd1_id'), 'Selvatura Tours owner 100', '8 logged with the company and the role');
select test.eq((:'gd2'::jsonb) ->> 'company', 'ToursXY', '8 "  Tours\u202eXY  " is stored "ToursXY" (bidi control removed, ends trimmed)');
select test.eq((select company from public.discount_approvals where id = :'gd2_id'), 'ToursXY', '8 the same in the table');
select test.eq((:'gd3'::jsonb) ->> 'company', 'Tours', '8 full-width letters fold to plain ones (NFKC)');
select test.eq((:'gd4'::jsonb) ->> 'company', 'Monteverde Cloud Tours', '8 every kind of blank becomes one space');
select test.eq((:'gd5'::jsonb) ->> 'company', 'Selvatura', '8 the soft hyphen and the byte-order mark are removed');
select test.eq((:'gd6'::jsonb) ->> 'company', repeat('a', 80), '8 80 characters: kept whole');
select test.eq((:'gd7'::jsonb) ->> 'company', E'Guía Café', '8 stored as typed after cleaning: case and accents kept (a combining accent composed)');
select test.eq((:'gd8'::jsonb) ->> 'ok' || ' ' || coalesce((:'gd8'::jsonb) ->> 'beneficiary', 'null'), 'true null',
               '8 Guía ignores an employee code sent with it');
-- only the owner's code
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.wrong480() as w0 \gset
select test.cats480() as c0 \gset
select test.a480('guia', '4826', 12345, null, 'Selvatura Tours') as go1 \gset
select test.a480('guia', '5284', 12345, null, 'Selvatura Tours') as go2 \gset
select test.a480('guia', '0000', 12345, null, 'Selvatura Tours') as go3 \gset
select test.wrong480() as w1 \gset
select test.cats480() as c1 \gset
reset role;
select test.eq(:'go1'::jsonb, test.wrongans480('bad_pin', 'owner'), '8 Ana''s (a manager''s) code for Guía: bad_pin with step owner');
select test.eq(:'go2'::jsonb, test.wrongans480('bad_pin', 'owner'), '8 Luis''s code: the same');
select test.eq(:'go3'::jsonb, test.wrongans480('bad_pin', 'owner'), '8 nobody''s code: the same');
select test.eq(:w1 - :w0, 3, '8 each counted');
select test.eq((select string_agg(details ->> 'step' || ':' || (details ->> 'why') || ':' || (details ->> 'category'), ' ' order by id)
                  from (select * from public.audit_log where action = 'discount_code_wrong' order by id desc limit 3) x),
               'owner:not_allowed:guia owner:not_allowed:guia owner:no_match:guia', '8 as the owner step: not allowed, not allowed, no match');
select test.eq(:c1 - :c0, 0, '8 and no approval');
-- no active owner with a PIN: no_owner, before any till check or code
update public.staff set active = false where id = test.staff('dueno');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.wrong480() as w0 \gset
select test.n480('discount_till_unknown') as u0 \gset
select public.descuento_estado() ->> 'owner_ready' as or1 \gset
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as gn1 \gset
select test.a480('guia', '0000', 12345, null, 'Selvatura Tours') as gn2 \gset
reset role;
select test.login('cafe'); select test.session('tablet-480-n'); set role authenticated;
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as gn3 \gset
reset role;
update public.staff set active = true where id = test.staff('dueno');
select pin_hash as dueno_hash from public.staff where id = test.staff('dueno') \gset
update public.staff set pin_hash = null where id = test.staff('dueno');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select public.descuento_estado() ->> 'owner_ready' as or2 \gset
select test.a480('guia', '7391', 12345, null, 'Selvatura Tours') as gn4 \gset
select test.wrong480() as w1 \gset
reset role;
update public.staff set pin_hash = :'dueno_hash' where id = test.staff('dueno');
select test.eq(:'or1' || ' ' || :'or2', 'false false', '8 descuento_estado: owner_ready false with the owner inactive, and with the owner''s PIN missing');
select test.eq(:'gn1'::jsonb, '{"ok": false, "error": "no_owner"}'::jsonb, '8 the owner inactive: Guía answers no_owner');
select test.eq((:'gn2'::jsonb) ->> 'error' || ' ' || ((:'gn3'::jsonb) ->> 'error') || ' ' || ((:'gn4'::jsonb) ->> 'error'), 'no_owner no_owner no_owner',
               '8 with a wrong code, on an unregistered sign-in, and with the owner''s PIN missing: no_owner');
select test.eq(:w1 - :w0, 0, '8 no_owner tests no code: no discount_code_wrong row');
select test.eq(test.n480('discount_till_unknown') - :u0, 0, '8 and comes before the till checks');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.eq(public.descuento_estado() ->> 'owner_ready', 'true', '8 (control) the owner back: owner_ready true');
reset role;

-- 9) the owner's code for Guía never unlocks anything (adjustment 1, L3; mecanismo rule 5) -------------------------
-- 0033 counters with something in them, from another sign-in: two wrong unlock tries for the owner, one for Ana
select test.login('cafe'); select test.session('tablet-480-x'); set role authenticated;
select public.access_unlock(test.staff('dueno'), '0001') ->> 'error' as x1, public.access_unlock(test.staff('dueno'), '0002') ->> 'error' as x2,
       public.access_unlock(test.staff('ana'), '0003') ->> 'error' as x3 \gset
reset role;
select test.eq(:'x1' || ' ' || :'x2' || ' ' || :'x3', 'bad_pin bad_pin bad_pin', 'fixture: three wrong unlock tries');
select failed_pins as dueno_fp, coalesce(locked_until::text, 'none') as dueno_lu from public.staff where id = test.staff('dueno') \gset
select failed_pins as ana_fp, coalesce(locked_until::text, 'none') as ana_lu from public.staff where id = test.staff('ana') \gset
select test.eq(:'dueno_fp' || ' ' || :'ana_fp', '2 1', 'fixture: the owner''s counter at 2, Ana''s at 1');
select count(*) as unl0 from public.access_unlocks \gset
select test.n480('access_open') as ao0 \gset
select test.login('cafe'); select test.session('till-480-g');
select test.eq(test.till('Caja 480 G'), 3, 'fixture: the café sign-in till-480-g is the registered till of place 3 (never unlocked)');
set role authenticated;
select test.a480('guia', '7391', 8000, null, 'Sky Tours') as gl1 \gset
select test.a480('guia', '4826', 8000, null, 'Sky Tours') as gl2 \gset
select test.a480('local', '4826', 8000) as gl3 \gset
select test.a480('huesped', '7391', 8000) as gl4 \gset
select coalesce(public.access_level(), 'null') as lvl, public.is_owner() as io, public.is_true_owner() as ito,
       public._unlocked_any_device() as uad \gset
select count(*) as visible from public.discount_approvals \gset
select public.descuento_cajas() ->> 'error' as cj, public.descuento_cupo_devolver((:'gl1'::jsonb ->> 'id')::uuid) ->> 'error' as cd,
       public.setting_set('pos_free_discount', '"off"') ->> 'error' as ss, public.descuentos_informe(null, null) ->> 'error' as di \gset
reset role;
select test.eq((:'gl1'::jsonb) ->> 'ok' || ' ' || ((:'gl1'::jsonb) ->> 'name') || ' ' || ((:'gl1'::jsonb) ->> 'role'), 'true Dueño owner',
               '9 Guía approved with the owner''s code on a café sign-in');
select test.eq((:'gl2'::jsonb) ->> 'error' || ' ' || ((:'gl3'::jsonb) ->> 'ok') || ' ' || ((:'gl4'::jsonb) ->> 'ok'), 'bad_pin true true',
               '9 then a wrong code for Guía, a Local with Ana''s code and a Huésped with the owner''s');
select test.eq(:'lvl'::text, 'null', '9 access_level() is still null on that sign-in');
select test.eq(:'io' || ' ' || :'ito' || ' ' || :'uad', 'f f f', '9 is_owner(), is_true_owner() and _unlocked_any_device() are false');
select test.eq(:'visible'::text, '0', '9 the approvals table stays unreadable (it shows only with the owner areas open)');
select test.eq(:'cj' || ' ' || :'cd' || ' ' || :'ss' || ' ' || :'di', 'owner_only owner_only owner_only not_allowed',
               '9 the approvals log, the give-back and settings answer owner_only; the report not_allowed');
select test.eq((select count(*)::int from public.access_unlocks where session_id = 'till-480-g'), 0, '9 no access_unlocks row for that sign-in');
select test.eq((select count(*)::int from public.access_unlocks), :unl0, '9 nor anywhere');
select test.eq(test.n480('access_open') - :ao0, 0, '9 no access_open row: the owner areas were never opened');
select test.eq((select failed_pins || ' ' || coalesce(locked_until::text, 'none') from public.staff where id = test.staff('dueno')),
               :'dueno_fp' || ' ' || :'dueno_lu', '9 the owner''s 0033 counter is untouched by his right code (2 before, 2 after: no reset)');
select test.eq((select failed_pins || ' ' || coalesce(locked_until::text, 'none') from public.staff where id = test.staff('ana')),
               :'ana_fp' || ' ' || :'ana_lu', '9 Ana''s too, by her wrong code for Guía and her right one for Local (no count, no reset)');
select test.eq(test.keys480(:'gl1'::jsonb), 'amount at beneficiary category company id name ok prior reason request_id role subtotal',
               '9 the answer carries no token, no level and no PIN: only the approval');
select test.eq(test.pins480(:'gl1'::jsonb) + test.pins480(:'gl2'::jsonb) + test.pins480(:'gl3'::jsonb) + test.pins480(:'gl4'::jsonb), 0,
               '9 no answer echoes a code');
select test.ok((select prosrc !~ '(_verify_pin|access_unlock|failed_pins|update public\.staff)'
                  from pg_proc where oid = 'public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text)'::regprocedure),
               '9 descuento_autorizar never calls _verify_pin or access_unlock, never touches access_unlocks or a PIN counter');
select test.ok((select bool_and(replace(prosrc, 'for update', '') !~* '\mupdate\M' and prosrc !~* 'access_unlock') from pg_proc
                 where oid in ('public._staff_by_code(text)'::regprocedure, 'public._discount_take_staff(uuid, text, text)'::regprocedure,
                               'public._discount_staff_state(uuid, text)'::regprocedure)),
               '9 nor do the code lookup and the two staff reads it uses (they write nothing)');
select test.eq((select (length(prosrc) - length(replace(prosrc, 'crypt(', ''))) / length('crypt(') from pg_proc
                 where oid = 'public._staff_by_code(text)'::regprocedure), 1, '9 the code lookup is one bcrypt pass over every active PIN');

-- 10) a code two people share authorizes nobody (proposal §5.1 item 7, as mecanismo §6 6e-6f answers it) ----------
select pin_hash as luis_hash from public.staff where id = test.staff('luis') \gset
select pin_hash as marta_hash from public.staff where id = test.staff('marta') \gset
update public.staff set pin_hash = (select pin_hash from public.staff where id = test.staff('ana')) where id = test.staff('luis');   -- a pre-0033 duplicate
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.wrong480() as w0 \gset
select test.n480('pin_duplicate') as pd0 \gset
select test.cats480() as c0 \gset
select test.a480('local', '4826', 5000) as d1 \gset
select test.a480('empleado', '7391', 5000, '4826') as d2 \gset
reset role;
update public.staff set pin_hash = :'luis_hash' where id = test.staff('luis');
update public.staff set pin_hash = (select pin_hash from public.staff where id = test.staff('dueno')) where id = test.staff('marta');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.a480('guia', '7391', 5000, null, 'Selvatura Tours') as d3 \gset
select test.wrong480() as w1 \gset
select test.cats480() as c1 \gset
reset role;
update public.staff set pin_hash = :'marta_hash' where id = test.staff('marta');
select test.eq(:'d1'::jsonb, test.wrongans480('bad_pin', 'manager'),
               '10 Ana''s code while Luis has the same PIN: bad_pin at the manager step, exactly like any wrong code (no pin_ambiguous)');
select test.eq(:'d2'::jsonb, test.wrongans480('bad_employee', 'employee'), '10 that code at the employee step (the owner authorizing): bad_employee');
select test.eq(:'d3'::jsonb, test.wrongans480('bad_pin', 'owner'), '10 the owner''s code while Marta has the same PIN: bad_pin at the Guía (owner) step');
select test.eq(:w1 - :w0, 3, '10 each counted as a wrong code');
select test.eq(:c1 - :c0, 0, '10 nobody was authorized and nobody got a discount');
select test.eq((select string_agg(details ->> 'step' || ':' || (details ->> 'why') || ':' || coalesce(manager_name, '-'), ' ' order by id)
                  from (select * from public.audit_log where action = 'discount_code_wrong' order by id desc limit 3) x),
               'manager:ambiguous:- employee:ambiguous:Dueño owner:ambiguous:-',
               '10 counted with why ambiguous; the employee-step row names the owner whose code came first');
select test.eq(test.n480('pin_duplicate') - :pd0, 3, '10 three pin_duplicate rows');
select test.eq((select string_agg(x.details ->> 'step' || ':' || to_jsonb(d.staff_ids)::text, ' ' order by x.id)
                  from (select * from public.audit_log where action = 'pin_duplicate' order by id desc limit 3) x
                  join public.discount_pin_shared d on d.audit_id = x.id),
               'manager:["' || test.staff('ana') || '", "' || test.staff('luis') || '"] employee:["' || test.staff('ana') || '", "'
               || test.staff('luis') || '"] owner:["' || test.staff('marta') || '", "' || test.staff('dueno') || '"]',
               '10 each names the step, and the two people who share the code (Ana and Luis; Marta and the owner) only in discount_pin_shared');
select test.eq((select string_agg(test.keys480(details) || '|' || target_id || '|' || (details ->> 'till') || '|' || (details ->> 'by_login'), ' / ')
                  from (select * from public.audit_log where action = 'pin_duplicate' order by id desc limit 3) x),
               'by_login step till|' || :'till' || '|' || :'till' || '|' || :'cafe' || ' / by_login step till|' || :'till' || '|'
               || :'till' || '|' || :'cafe' || ' / by_login step till|' || :'till' || '|' || :'till' || '|' || :'cafe',
               '10 and the log row only the step, the till and the login: never the code, never the people (a manager reads the log)');
select test.ok(not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'pin_ambiguous'
                             and proname ~ '^(descuento|_discount|_staff_by_code)'), '10 no function answers pin_ambiguous any more');

-- 11) the old free window behind pos_free_discount; a free reason never reads as a category (item 14, §2.6a, W2) --
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 480') as od1 \gset
select public.approve_discount(test.staff('ana'), '4826', 'amount', 700, 5000, 'Promotion', 'Caja 480') as od2 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 20, 3000, 'Team member', 'Caja 480') as od3 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Courtesy for a mistake or a wait', 'Caja 480') as od4 \gset
reset role;
select (:'od1'::jsonb) ->> 'id' as od1_id, (:'od3'::jsonb) ->> 'id' as od3_id, (:'od4'::jsonb) ->> 'id' as od4_id \gset
select test.eq((:'od1'::jsonb) - 'id' - 'at', '{"ok": true, "amount": 500, "name": "Ana", "reason": "Regular customer"}'::jsonb,
               '11 switch on: the 7-argument approve_discount works as today, percent (10 % of 5000 = 500, Ana)');
select test.eq(test.keys480(:'od1'::jsonb), 'amount at id name ok reason', '11 with today''s answer and nothing more');
select test.eq((:'od2'::jsonb) ->> 'ok' || ' ' || ((:'od2'::jsonb) ->> 'amount'), 'true 700', '11 and an amount (700)');
select test.eq((select to_jsonb(a) - 'id' - 'created_at' from public.discount_approvals a where id = :'od1_id'),
               jsonb_build_object('approved_by', test.staff('ana'), 'approved_name', 'Ana', 'kind', 'percent', 'value', 10,
                                  'reason', 'Regular customer', 'station', 'Caja 480', 'order_id', null, 'used_at', null,
                                  'subtotal_crc', 5000, 'amount_crc', 500, 'base_crc', null, 'base_used_crc', null, 'category', null,
                                  'beneficiary_id', null, 'beneficiary_name', null, 'company', null, 'cr_day', null,
                                  'approver_role', null, 'bill_id', null, 'login_id', null, 'session_id', null, 'request_id', null,
                                  'freed_at', null, 'freed_how', null, 'till_id', null),
               '11 an old-kind row as today: no category and none of the new columns (the report calls it free_old_after_0038)');
select test.eq((select details from public.audit_log where action = 'discount_approved' and target_id = :'od1_id'),
               '{"kind": "percent", "value": 10, "station": "Caja 480", "discount_crc": 500, "subtotal_crc": 5000}'::jsonb,
               '11 logged with today''s keys');
select test.eq((select string_agg(proname, ' ' order by proname) from pg_proc where prosrc ~ 'pos_free_discount'), 'approve_discount',
               '11 pos_free_discount is read by approve_discount only (the new window never looks at it)');
select test.eq((select string_agg(proname, ' ' order by proname) from pg_proc where prosrc ~ 'pos_discount_guia'), 'descuento_autorizar descuento_estado',
               '11 pos_discount_guia by the window and its state only');
select prosrc as ad_0038 from pg_proc where oid = 'public.approve_discount(uuid, text, text, int, int, text, text)'::regprocedure \gset
-- reserved reasons (verifier S2) and those that pass
create temp table r480 (o serial, reason text, reserved boolean);
grant select on r480 to authenticated;
insert into r480 (reason, reserved) values
  ('Tour guide', true), ('Tour  guide', true), (E'Tour\u00a0guide', true), ('tour guide', true), (E'Tour \u200bguide', true),
  ('Tour guide · x', true), ('x · Employee', true), ('Tour guide:', true), ('Employee discount', true), ('Guía Turista', true),
  ('Huesped', true), ('Empleado', true), ('Local', true), ('Hotel guest', true), ('Tour guide courtesy', true),
  ('Local discount', true), ('Hotel guest discount', true), ('Descuento Empleado', true), ('Descuento Local', true),
  ('Descuento Huésped', true), ('Cortesía Guía Turista', true), ('Huésped', true), ('LOCAL', true), ('Other · Local', true),
  ('Regular customer · Local', true), ('Other · Guía Turista', true), ('Other · Empleado', true), ('Tour guide…', true),
  ('Local...', true), (U&'\FF2C\FF4F\FF43\FF41\FF4C', true), (E'Tour\tguide', true), (E'Tour\u3000guide', true),
  (E'Lo\u00adcal', true), (E'Gui\u0301a Turista', true), (E'\u202eEmpleado', true), ('  Local  ', true),
  ('Tour guides', false), ('Local band', false), ('Team member', false), ('Regular customer', false), ('Promotion', false),
  ('Courtesy for a mistake or a wait', false), ('Other · Cliente de la zona', false), ('Localidad', false),
  ('Employee of the month', false), ('Guía', false);
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.olds480() as o0 \gset
select test.eq(public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, reason, 'Caja 480') ->> 'error', 'missing_reason',
               '11 a reason that reads as a category is refused, even with a right PIN: ' || reason)
  from r480 where reserved order by o;
select test.olds480() as o1 \gset
select test.eq(public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, reason, 'Caja 480') ->> 'ok', 'true',
               '11 a free reason that does not read as a category is approved: ' || reason)
  from r480 where not reserved order by o;
select test.olds480() as o2 \gset
select public.approve_discount(test.staff('ana'), '0000', 'percent', 10, 5000, 'Other · Local', 'Caja 480') ->> 'error' as rw \gset
reset role;
select test.eq(:o1 - :o0, 0, '11 the refused reasons made no approval');
select test.eq(:o2 - :o1, (select count(*)::int from r480 where not reserved), '11 each free reason made one');
select test.eq(:'rw'::text, 'missing_reason', '11 a reserved reason with a wrong PIN: missing_reason, the PIN is not tested…');
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 0, '11 …so Ana''s counter does not move');
select test.ok((select bool_and(public._discount_reserved(reason) = reserved) from r480), '11 _discount_reserved agrees with every case');
select test.eq(coalesce(public._discount_reserved(null)::text, 'null') || ' ' || public._discount_reserved('')::text || ' ' || public._discount_reserved(' · ')::text,
               'false false false', '11 nothing (no reason, an empty one, a lone ·) is reserved');
-- the bill and the sale that will carry old approvals made with the switch on
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', 'd4800000-0000-4000-8000-000000000003', 'created_at', now(), 'total_crc', 10000,
          'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja 480', 'source', 'front', 'guest_name', 'Mesa 480',
          'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
                                     jsonb_build_object('item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) ->> 'ok', 'true',
               '11 (fixture) an open bill of 10000');
reset role;
-- off, with the owner's SQL Editor tool (L6)
\o /dev/null
\ir ../../supabase/tools/descuento-libre-apagar.sql
\o
select test.eq(public.setting('pos_free_discount'), '"off"'::jsonb, '11 descuento-libre-apagar.sql: pos_free_discount = off');
select test.eq((select updated_by from public.settings where key = 'pos_free_discount'), 'owner (SQL Editor)', '11 the setting names the SQL Editor');
select test.eq((select coalesce(manager_id::text, '-') || ' ' || manager_name || ' | ' || summary || ' | ' || details::text
                  from public.audit_log where action = 'setting_change' and target_id = 'pos_free_discount'),
               '- owner (SQL Editor) | pos_free_discount: on → off | {"how": "sql_editor", "after": "off", "before": "on"}',
               '11 and writes the same setting_change line Home writes (who, before → after)');
\o /dev/null
\ir ../../supabase/tools/descuento-libre-apagar.sql
\o
select test.eq((select count(*)::int from public.audit_log where action = 'setting_change' and target_id = 'pos_free_discount'), 1,
               '11 run again while off: nothing written');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.err480($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 480')$$) as off1 \gset
select test.err480($$select public.approve_discount(test.staff('ana'), '0000', 'percent', 10, 5000, 'Regular customer', 'Caja 480')$$) as off2 \gset
select test.err480($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, '', 'Caja 480')$$) as off3 \gset
select test.olds480() as o3 \gset
-- an old approval made before the switch still finishes its sale, and its bill
select test.eq(public.pos_record_sale(jsonb_build_object('id', 'd4800000-0000-4000-8000-000000000002', 'created_at', now(), 'total_crc', 2400,
          'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'station', 'Caja 480', 'guest_name', 'Ticket 480',
          'subtotal_crc', 3000, 'discount_crc', 600, 'discount_id', :'od3_id',
          'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 3000, 'qty', 1)))) ->> 'ok', 'true',
               '11 switch off: a sale carrying an old approval made before it is still accepted');
select public.tab_set_discount('d4800000-0000-4000-8000-000000000003', :'od4_id', 10000, 'Caja 480') as tb1 \gset
select public.tab_set_discount('d4800000-0000-4000-8000-000000000003', null, 9000, 'Caja 480') as tb2 \gset
select test.a480('local', '4826', 5000) ->> 'ok' as nw \gset
reset role;
select test.eq(:'off1'::text, 'P0001:approve_discount_off', '11 switch off: approve_discount raises approve_discount_off (the old page shows its reload text)');
select test.eq(:'off2' || ' ' || :'off3', 'P0001:approve_discount_off P0001:approve_discount_off', '11 before testing the PIN, and before the reason');
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 0, '11 so the wrong PIN counted nothing');
select test.eq(:o3 - :o2, 0, '11 and nothing was approved');
select test.eq((select discount_reason || ' ' || discount_by || ' ' || discount_crc || ' ' || total_crc from public.orders
                 where id = 'd4800000-0000-4000-8000-000000000002'), 'Team member Ana 600 2400', '11 recorded as today: its reason, Ana, 600 off');
select test.eq((select order_id::text from public.discount_approvals where id = :'od3_id'), 'd4800000-0000-4000-8000-000000000002',
               '11 and the old approval is used by it');
select test.eq(:'tb1'::jsonb, '{"ok": true, "total": 9000, "discount": 1000}'::jsonb, '11 tab_set_discount with an old approval still works (10 % of the bill)');
select test.eq(:'tb2'::jsonb, '{"ok": true, "total": 10000, "discount": 0}'::jsonb, '11 and takes it off as today');
select test.eq(:'nw'::text, 'true', '11 off = only the four discounts: Local still works');
\o /dev/null
\ir ../../supabase/tools/descuento-libre-encender.sql
\o
select test.eq(public.setting('pos_free_discount'), '"on"'::jsonb, '11 descuento-libre-encender.sql: on again');
select test.eq((select summary || ' | ' || details::text from public.audit_log where action = 'setting_change' and target_id = 'pos_free_discount'
                 order by id desc limit 1),
               'pos_free_discount: off → on | {"how": "sql_editor", "after": "on", "before": "off"}', '11 logged the same way');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.eq(public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 480') ->> 'ok', 'true',
               '11 and the old window approves again');
select public.setting_set('pos_free_discount', '"off"') ->> 'error' as sc \gset
reset role;
select test.eq(:'sc'::text, 'owner_only', '11 the café login cannot change it');
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('pos_free_discount', '"maybe"') ->> 'error' as sb \gset
select public.setting_set('pos_free_discount', '"off"') as sf1 \gset
select public.setting_set('pos_free_discount', '"on"') as sf2 \gset
reset role;
select test.eq(:'sb'::text, 'bad_value', '11 setting_set: only on or off');
select test.eq((:'sf1'::jsonb) ->> 'ok' || ' ' || ((:'sf2'::jsonb) ->> 'ok'), 'true true', '11 the owner with the phone code turns it off and on in Home');
select test.eq((select string_agg(summary, ' / ' order by id) from public.audit_log where action = 'setting_change' and target_id = 'pos_free_discount'),
               'pos_free_discount: on → off / pos_free_discount: off → on / pos_free_discount: on → off / pos_free_discount: off → on',
               '11 every change, by the tools and by setting_set, is a setting_change line');

-- 12) grants and account checks (item 15) ----------------------------------------------------------------------------
create temp table f480 (sig text primary key, public_rpc boolean not null);
insert into f480 values
  ('descuento_estado(text)', true), ('descuento_autorizar(text,text,integer,text,text,uuid,integer,uuid,text)', true),
  ('descuento_liberar(uuid,uuid)', true), ('descuento_quitar_cuenta(uuid,integer,text,uuid,text,text,uuid)', true),
  ('descuento_cupo_devolver(uuid,uuid,text,text)', true), ('descuentos_informe(date,date)', true),
  ('descuento_caja_registrar(text,uuid)', true), ('descuento_caja_volver(text,text)', true), ('descuento_cajas()', true),
  ('descuento_caja_reanudar(integer,uuid,text,text)', true), ('descuento_caja_quitar(uuid,uuid,text,text)', true),
  ('_discount_rate(text)', false), ('_discount_label(text)', false), ('_discount_clean(text)', false),
  ('_discount_company(text)', false), ('_discount_reserved(text)', false), ('_staff_by_code(text)', false),
  ('_discount_till_limits()', false), ('_discount_session()', false), ('_discount_tag(text)', false),
  ('_discount_station(text)', false), ('_discount_key_hash(text)', false), ('_discount_new_key()', false),
  ('_discount_till_mine()', false), ('_discount_slot_state(integer)', false), ('_discount_take_staff(uuid,text,text)', false),
  ('_discount_staff_state(uuid,text)', false), ('_discount_person(uuid)', false), ('_discount_places(uuid)', false),
  ('_discount_wrong(discount_tills,text,text,text,text,uuid,text)', false), ('_discount_till_unknown(text,text)', false),
  ('_discount_answer(discount_approvals)', false), ('_discount_bill_problem(uuid,integer,integer,boolean)', false),
  ('_discount_retake_day(uuid,date)', false), ('_discount_freeable(discount_approvals)', false),
  ('_discount_places_summary()', false), ('_discount_tills_resume_all(text)', false), ('_discount_tills_end_all(text)', false),
  ('_pin_locks_clear_all(text)', false), ('_order_discount_flags()', false), ('_order_discount_after()', false),
  ('_discount_pin_changed()', false);
create temp view v480 as
  select p.oid, p.oid::regprocedure::text as sig, f.public_rpc, p.prosecdef, p.prosrc, p.proconfig, p.prorettype
    from pg_proc p join f480 f on f.sig = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace;
select test.eq((select string_agg(p.oid::regprocedure::text, ' ' order by p.oid::regprocedure::text) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace
                   and p.proname ~ '^(descuento|_discount_|_staff_by_code$|_pin_locks_clear_all$|_order_discount_(flags|after)$)'),
               (select string_agg(sig, ' ' order by sig) from f480),
               '12 0038''s new functions are exactly the 11 public ones, the 28 internal ones and the 3 trigger functions (42)');
select test.eq((select count(*)::int from v480), 42, '12 all 42 exist');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where has_function_privilege('anon', oid, 'execute')), '',
               '12 anon can run none of them');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where has_function_privilege('public', oid, 'execute')), '',
               '12 PUBLIC can run none of them');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where has_function_privilege('canopy_backup', oid, 'execute')), '',
               '12 the backup account can run none of them (030''s rule)');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where not public_rpc and has_function_privilege('authenticated', oid, 'execute')), '',
               '12 the internal ones are not executable by authenticated (signed-in pages)');
select test.eq((select count(*)::int from v480 where public_rpc and has_function_privilege('authenticated', oid, 'execute')), 11,
               '12 the 11 public ones are, for the signed-in pages');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where public_rpc and not (prosecdef and proconfig @> array['search_path=public, extensions'])), '',
               '12 each public one is security definer with search_path public, extensions');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where public_rpc
                 and prosrc !~ '(is_cafe|is_owner|is_true_owner|sales_open|inventory_open|auth\.uid\(\)|mfa_ok|account_kind|can_read|owner_with_code|_books_allowed|_insights_allowed|_pay_staff_allowed|_ap_allowed|_receipts_allowed)'),
               '', '12 the snapshot''s rule finds an account check in every new public body');
select test.eq((select coalesce(string_agg(sig, ' '), '') from v480 where public_rpc and sig <> 'descuentos_informe(date,date)'
                 and not starts_with(test.first480(prosrc), 'if not public.is_cafe() then return jsonb_build_object(''ok'', false, ''error'', ''no_account''); end if;')),
               '', '12 every public body but the report''s starts with the café-account check (no_account)');
select test.ok((select starts_with(test.first480(prosrc), 'if not public._insights_allowed() then return jsonb_build_object(''ok'', false, ''error'', ''not_allowed''); end if;')
                  from v480 where sig = 'descuentos_informe(date,date)'),
               '12 the report starts with _insights_allowed (no is_cafe: the accountant reads it)');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype and p.prosecdef
                   and has_function_privilege('anon', p.oid, 'execute')),
               'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', '12 what a visitor runs is unchanged (the same five)');
select test.eq((select string_agg(p.oid::regprocedure::text || ':' || p.prosecdef || ':' || has_function_privilege('anon', p.oid, 'execute') || ':'
                                  || has_function_privilege('authenticated', p.oid, 'execute'), ' ' order by p.oid::regprocedure::text) from pg_proc p
                 where p.oid in ('public.approve_discount(uuid, text, text, int, int, text, text)'::regprocedure,
                                 'public.tab_set_discount(uuid, uuid, int, text)'::regprocedure)),
               'approve_discount(uuid,text,text,integer,integer,text,text):true:false:true tab_set_discount(uuid,uuid,integer,text):true:false:true',
               '12 approve_discount and tab_set_discount keep their signatures and grants');
select test.eq((select relrowsecurity::text || ' ' || has_table_privilege('authenticated', c.oid, 'select') || ' '
                       || has_table_privilege('authenticated', c.oid, 'insert,update,delete') || ' ' || has_table_privilege('anon', c.oid, 'select')
                       || ' ' || (select string_agg(polname || ':' || polcmd::text || ':' || pg_get_expr(polqual, polrelid), ',') from pg_policy where polrelid = c.oid)
                  from pg_class c where c.oid = 'public.discount_approvals'::regclass),
               'true true false false discounts read:r:( SELECT is_owner() AS is_owner)',
               '12 discount_approvals: rules and grants unchanged (read with the owner areas open, written only by the functions)');
select test.eq((select relrowsecurity::text || ' ' || (select count(*) from pg_policy where polrelid = c.oid) || ' '
                       || has_table_privilege('authenticated', c.oid, 'select,insert,update,delete') || ' '
                       || has_table_privilege('anon', c.oid, 'select,insert,update,delete') || ' '
                       || has_table_privilege('public', c.oid, 'select,insert,update,delete')
                  from pg_class c where c.oid = 'public.discount_tills'::regclass), 'true 0 false false false',
               '12 discount_tills: row rules on, no policy, no rights for anyone but the functions');
select test.eq((select relrowsecurity::text || ' ' || (select count(*) from pg_policy where polrelid = c.oid) || ' '
                       || has_table_privilege('authenticated', c.oid, 'select,insert,update,delete') || ' '
                       || has_table_privilege('anon', c.oid, 'select,insert,update,delete') || ' '
                       || has_table_privilege('public', c.oid, 'select,insert,update,delete')
                  from pg_class c where c.oid = 'public.discount_pin_shared'::regclass), 'true 0 false false false',
               '12 discount_pin_shared (who shares a code): row rules on, no policy, no rights: only the owner reads it, through descuento_cajas');
select test.eq((select coalesce(string_agg(proname, ' ' order by proname), '') from pg_proc where pronamespace = 'public'::regnamespace
                 and proname in ('descuento_pausa_levantar', '_discount_codes_locked', '_discount_code_failed', '_discount_codes_clear',
                                 'descuento_caja_cerrar', 'descuento_empleado')), '',
               '12 not built: the café-wide pause (replaced by the registered tills), descuento_caja_cerrar (L1), Option B');
select test.ok(to_regclass('public.discount_claims') is null, '12 nor Option B''s table');
-- anon is refused by the database itself
select test.login('anon'); set role anon;
select test.err480($$select public.descuento_autorizar('local', '4826', 5000)$$) as an1 \gset
select test.err480($$select public.descuento_estado()$$) as an2 \gset
select test.err480($$select public.descuento_cupo_devolver(gen_random_uuid())$$) as an3 \gset
select test.err480($$select public.descuento_caja_registrar()$$) as an4 \gset
select test.err480($$select public.descuentos_informe(null, null)$$) as an5 \gset
select test.err480($$select public.approve_discount(gen_random_uuid(), '4826', 'percent', 10, 5000, 'x', 'x')$$) as an6 \gset
reset role;
select test.eq(:'an1' || ' | ' || :'an2' || ' | ' || :'an3' || ' | ' || :'an4' || ' | ' || :'an5' || ' | ' || :'an6',
               '42501:permission denied for function descuento_autorizar | 42501:permission denied for function descuento_estado | '
               '42501:permission denied for function descuento_cupo_devolver | 42501:permission denied for function descuento_caja_registrar | '
               '42501:permission denied for function descuentos_informe | 42501:permission denied for function approve_discount',
               '12 anon: permission denied for the window, the state, the give-back, registering, the report and the old window');
-- the accountant: no_account from every function of the till; the report is theirs
select test.login('accountant', 'aal2'); set role authenticated;
select jsonb_build_array(public.descuento_estado(), public.descuento_autorizar('local', '4826', 5000), public.descuento_liberar(gen_random_uuid()),
         public.descuento_quitar_cuenta(gen_random_uuid(), 1000), public.descuento_cupo_devolver(gen_random_uuid()),
         public.descuento_caja_registrar(), public.descuento_caja_volver(repeat('a', 64)), public.descuento_cajas(),
         public.descuento_caja_reanudar(1), public.descuento_caja_quitar(gen_random_uuid()),
         public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'x'),
         public.tab_set_discount(gen_random_uuid(), null)) as acc \gset
select public.descuentos_informe(null, null) ->> 'ok' as acc_rep \gset
reset role;
select test.eq((select string_agg(x ->> 'error', ' ') from jsonb_array_elements(:'acc'::jsonb) x),
               'no_account no_account no_account no_account no_account no_account no_account no_account no_account no_account no_account no_account',
               '12 the accountant: no_account from the ten functions of the till and the two old ones');
select test.eq(:'acc_rep'::text, 'true', '12 and reads the report');
-- the café login without the owner areas open
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select jsonb_build_array(public.descuento_cupo_devolver(:'e1_id'), public.descuento_cajas(), public.descuento_caja_reanudar(1),
         public.descuento_caja_quitar(:'till'), public.descuento_caja_registrar('Caja 480')) as own \gset
reset role;
select test.eq((select string_agg(x ->> 'error', ' ') from jsonb_array_elements(:'own'::jsonb) x), 'owner_only owner_only owner_only owner_only owner_only',
               '12 the café login with the owner areas closed: owner_only from the give-back and the tills'' management');

-- 13) no code is ever stored, logged or echoed ---------------------------------------------------------------------
select test.eq((select count(*)::int from public.audit_log where test.pins480(details) > 0
                   or summary ~ '(^|[^0-9a-f])(4826|5284|6173|7391|8301)([^0-9a-f]|$)'), 0,
               '13 no audit row holds a code (every detail value and every summary)');
select test.eq((select count(*)::int from public.discount_approvals a where test.pins480(to_jsonb(a)) > 0), 0, '13 no approval row holds a code');
select test.eq(test.pins480(jsonb_build_array(:'l1'::jsonb, :'lb1'::jsonb, :'e1'::jsonb, :'e2'::jsonb, :'eb1'::jsonb, :'eb2'::jsonb,
                 :'s1'::jsonb, :'gd1'::jsonb, :'go1'::jsonb, :'gn1'::jsonb, :'d1'::jsonb, :'d2'::jsonb, :'d3'::jsonb, :'od1'::jsonb)), 0,
               '13 no answer echoes one');

-- 14) old data untouched: rows made by the old window before 0038 are the same, byte for byte, after it (item 17) --
-- the database before 0038 (the reversal keeps every row and column), the café's old discounts made with the old
-- functions, then 0038 again
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\ir ../../supabase/tools/reversion-0039.sql
\ir ../../supabase/tools/reversion-0038.sql
\o
select test.eq(public.canopy_schema_version(), 37, '14 (fixture) the reversal: the database is at 37, the old functions back');
select test.eq((select prosrc from pg_proc where oid = 'public.approve_discount(uuid, text, text, int, int, text, text)'::regprocedure),
               regexp_replace(regexp_replace(:'ad_0038',
                 '\n  -- 0038: the old free window[^\n]*\n  if public\.setting\(''pos_free_discount''\) #>> ''\{\}'' = ''off'' then\n    raise exception ''approve_discount_off'' using errcode = ''P0001'';\n  end if;', ''),
                 '\n  -- 0038: a reason that would read[^\n]*\n  if public\._discount_reserved\(why\) then return jsonb_build_object\(''ok'', false, ''error'', ''missing_reason''\); end if;', ''),
               '14 0038''s approve_discount is the old body byte for byte plus its two checks (the switch, the reserved reason)');
select test.login('cafe'); set role authenticated;
select public.approve_discount(test.staff('ana'), '4826', 'percent', 15, 8000, 'Regular customer', 'Caja vieja') as old1 \gset
select public.approve_discount(test.staff('ana'), '4826', 'amount', 900, 9000, 'Other · Local', 'Caja vieja') as old2 \gset
select test.eq((:'old1'::jsonb) ->> 'ok' || ' ' || ((:'old2'::jsonb) ->> 'ok'), 'true true',
               '14 before 0038 the old window approves any reason, Other · Local included');
select test.eq(public.pos_record_sale(jsonb_build_object('id', 'd4800000-0000-4000-8000-000000000004', 'created_at', now(), 'total_crc', 6800,
          'payment_method', 'card', 'paid', true, 'status', 'done', 'station', 'Caja vieja', 'guest_name', 'Ticket viejo',
          'subtotal_crc', 8000, 'discount_crc', 1200, 'discount_id', (:'old1'::jsonb) ->> 'id',
          'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 8000, 'qty', 1)))) ->> 'ok', 'true',
               '14 and a sale carries one of them');
reset role;
create temp table fp480 as
  select (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.discount_approvals t where t.category is null) as old_rows,
         (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.discount_approvals t) as all_rows,
         (select md5(coalesce(string_agg(id || ':' || discount_crc || ':' || coalesce(discount_id::text, ''), ',' order by id), ''))
            from public.orders where discount_crc <> 0) as discounts_md5,
         (select count(*) || ':' || md5(string_agg(o::text, ',' order by o.id)) from public.orders o where o.discount_id is not null or o.discount_crc <> 0) as orders,
         (select md5(string_agg(s::text, ',' order by s.key)) from public.settings s) as settings;
\o /dev/null
\ir ../../supabase/migrations/0038_descuentos_caja.sql
\o
select test.eq(public.canopy_schema_version(), 38, '14 0038 applied over that data');
select test.eq((select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.discount_approvals t where t.category is null),
               (select old_rows from fp480), '14 the old approvals are the same, row for row and column for column (no backfill: category stays empty)');
select test.eq((select md5(coalesce(string_agg(id || ':' || discount_crc || ':' || coalesce(discount_id::text, ''), ',' order by id), ''))
                  from public.orders where discount_crc <> 0), (select discounts_md5 from fp480), '14 consistency-check''s discounts_md5 is the same');
select test.eq((select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.discount_approvals t),
               (select all_rows from fp480), '14 so is every approval, the category ones included');
select test.eq((select count(*) || ':' || md5(string_agg(o::text, ',' order by o.id)) from public.orders o where o.discount_id is not null or o.discount_crc <> 0),
               (select orders from fp480), '14 and every discounted order');
select test.eq((select md5(string_agg(s::text, ',' order by s.key)) from public.settings s), (select settings from fp480),
               '14 and the settings as the owner left them');
select test.eq((select reason || ' ' || coalesce(category, 'null') from public.discount_approvals where id = ((:'old2'::jsonb) ->> 'id')::uuid),
               'Other · Local null', '14 an old typed reason is never rewritten');
select test.login('cafe'); select test.session('till-480'); set role authenticated;
select test.eq(test.a480('local', '4826', 5000) ->> 'reason', 'Local', '14 (control) the four discounts work again on the till');
reset role;

select test.done();
rollback;
