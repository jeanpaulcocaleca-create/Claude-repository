-- Migration 0038 (D-065): a category discount on a bill, and what keeps every discount whole and single (proposal §5.1
-- items 8, 9, 10, 11 and 13; §2.5b steps 2-11, §2.5d, §2.6b-c, §2.7; api-0038 §4.2-4.4 and §5; build plan L5 «484»;
-- mecanismo-intentos §6 for where the bill's checks sit). Bill mode: descuento_autorizar with p_order_id puts the
-- discount on the whole bill in the same call, only before any payment, never over a combo or another discount
-- (has_parts, combo_first, already_discounted, changed). Those refusals come before any code is tested (nothing
-- counted, no lock, nothing written, even from a sign-in that is no till), and again under the bill's lock after the
-- codes (then logged as discount_refused). A refusal of tab_set_discount inside the call leaves no approval and no used
-- day (the M6 stub, only inside a savepoint: W4). The same request sent again answers the stored approval with the
-- bill as it is now (replay); another login's request id, or one older than 30 minutes caught by the unique index,
-- answers bad_request. Tickets: a sale carrying the approved amount is linked as verified; anything else is recorded as
-- charged and flagged, never refused; an approval already used never goes on a second order. Time window: a late
-- category sale is flagged discount_late, an old-kind one is refused as before 0038. Taking it off:
-- descuento_quitar_cuenta (no PIN with nothing paid; a manager's PIN and a reason after any payment, decided under the
-- bill's lock), and the legacy tab_set_discount, which takes a category discount off only while nothing is paid (W3)
-- and never puts one on. Everything goes through the real functions as the café login (authenticated, with a
-- session_id) on a registered till; the few direct writes are fixtures for states no function leaves, each said so.
begin;

-- people: the seed (Ana manager 4826, Luis 5284 and Marta 6173 staff, Dueño owner 7391) plus test-only staff, one
-- employee per case so no case shares a day with another. Test PINs only: Bea 4941, Hal 4942, Gil 4943 (inactive)
-- are managers; the employees 8404-8430 by their place in the list
create table test.t484_people (name text primary key, id uuid not null, pin text not null);
grant select on test.t484_people to authenticated;
insert into test.t484_people values
  ('ana', test.staff('ana'), '4826'), ('luis', test.staff('luis'), '5284'), ('marta', test.staff('marta'), '6173'),
  ('dueno', test.staff('dueno'), '7391');
insert into test.t484_people (name, id, pin)
  select n, ('b4840000-0000-4000-8000-' || lpad(o::text, 12, '0'))::uuid,
         case n when 'bea' then '4941' when 'hal' then '4942' when 'gil' then '4943' else (8400 + o)::text end
    from unnest(array['bea', 'hal', 'gil', 'abel', 'eva', 'fede', 'iris', 'gus', 'hugo', 'kai', 'olga', 'pablo', 'quim',
                      'raul', 'sara', 'tomas', 'uma', 'vera', 'yago', 'zoe', 'nora', 'omar', 'ines', 'jose', 'mia', 'leo',
                      'lia', 'cora', 'dani', 'elsa']) with ordinality u(n, o);
insert into public.staff (id, name, role, active, pin_hash)
  select id, initcap(name), case when name in ('bea', 'hal', 'gil') then 'manager' else 'staff' end, name <> 'gil',
         extensions.crypt(pin, extensions.gen_salt('bf', 4))
    from test.t484_people where name not in ('ana', 'luis', 'marta', 'dueno');
create function test.p484(n text) returns uuid language sql stable as $$ select id from test.t484_people where name = n $$;
create function test.k484(n text) returns text language sql stable as $$ select pin from test.t484_people where name = n $$;
-- order ids, request ids and line ids of this file
create function test.o484(n int) returns uuid language sql immutable as $$ select ('d4840000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.r484(n int) returns uuid language sql immutable as $$ select ('e4840000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.item484(p_bill uuid, n int) returns uuid language sql immutable as $$ select md5(p_bill::text || '-' || n)::uuid $$;
-- this file's café sign-in: the registered till «Caja 1» (test.login resets the claims and the unlock header)
create function test.cafe484(sid text default 'till-484') returns void language sql as $$
  select test.login('cafe'); select test.session(sid) $$;

-- an open «Pay later» bill as pos.html records it (pos_record_sale): by default two lines, Latte 4000 + Ham & Cheese
-- 6000 = 10000; extra overrides the order's fields (the page's fallback, a paid ticket)
create function test.bill484(p_bill uuid, guest text, lines jsonb default null, extra jsonb default '{}') returns jsonb
language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p_bill, 'created_at', now(), 'total_crc', x.tot,
           'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja 1', 'source', 'front',
           'guest_name', guest, 'items', x.items) || extra)
    from (select jsonb_agg(e || jsonb_build_object('id', test.item484(p_bill, o::int)) order by o) as items,
                 sum((e ->> 'price_crc')::int * (e ->> 'qty')::int)::int as tot
            from jsonb_array_elements(coalesce(lines, jsonb_build_array(
                   jsonb_build_object('item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
                   jsonb_build_object('item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) with ordinality l(e, o)) x $$;
-- a bill with a combo: Latte 4000 + Butter Croissant 1500 + the menu's combo line -500 = 5000
create function test.combo484() returns jsonb language sql immutable as $$
  select jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
                           jsonb_build_object('item_name', 'Butter Croissant', 'price_crc', 1500, 'qty', 1),
                           jsonb_build_object('item_name', 'Combo discount · coffee + pastry', 'price_crc', -500, 'qty', 1)) $$;
-- one guest pays line n by item (a part of its own), or an amount on account (a part with no line)
create function test.payitem484(p_bill uuid, n int default 1) returns jsonb language sql as $$
  select public.tab_pay(p_bill, 'cash_crc', jsonb_build_array(jsonb_build_object('item_id', test.item484(p_bill, n), 'qty', 1)),
                        null, 'Caja 1') $$;
create function test.payacct484(p_bill uuid, amt int) returns jsonb language sql as $$
  select public.tab_pay(p_bill, 'cash_crc', null, amt, 'Caja 1') $$;
-- the window's call as pos.html sends it: an Empleado (the manager's code, Ana's by default, then the employee's), or
-- one code for Local / Huésped; on a bill when p_bill is given
create function test.emp484(who text, p_bill uuid default null, expect int default null, auth text default '4826',
                            req uuid default null, sub int default 10000) returns jsonb language sql as $$
  select public.descuento_autorizar('empleado', auth, sub, test.k484(who), null, p_bill, expect, req, 'Caja 1') $$;
create function test.cat484(cat text, p_bill uuid default null, expect int default null, auth text default '4826',
                            req uuid default null, sub int default 10000) returns jsonb language sql as $$
  select public.descuento_autorizar(cat, auth, sub, null, null, p_bill, expect, req, 'Caja 1') $$;
-- a ticket carrying an approval, as pos.html sends it (pos_record_sale): one line (the subtotal by default), paid cash
create function test.sale484(p_id uuid, appr text, sub int, disc int, lines int default null, total int default null,
                             at timestamptz default now()) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p_id, 'created_at', at, 'total_crc', coalesce(total, sub - disc),
           'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'station', 'Caja 1', 'guest_name', 'Ticket 484',
           'subtotal_crc', sub, 'discount_crc', disc, 'discount_id', appr,
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', coalesce(lines, sub, 10000), 'qty', 1)))) $$;
-- the first look for a right and a wrong code (Ana's, or 0000; Empleado with Abel's code, or 0001): each one's error
-- when the answer is exactly {ok: false, error}, else the whole answer
create function test.both484(cat text, p_bill uuid, sub int, expect int) returns text language plpgsql as $$
declare a jsonb; b jsonb;
begin
  a := public.descuento_autorizar(cat, '4826', sub, case when cat = 'empleado' then test.k484('abel') end, null, p_bill, expect, null, 'Caja 1');
  b := public.descuento_autorizar(cat, '0000', sub, case when cat = 'empleado' then '0001' end, null, p_bill, expect, null, 'Caja 1');
  return case when a = jsonb_build_object('ok', false, 'error', a ->> 'error') then a ->> 'error' else a::text end || '|'
      || case when b = jsonb_build_object('ok', false, 'error', b ->> 'error') then b ->> 'error' else b::text end;
end $$;

-- readers (definer functions, so the café login can call them between its own calls)
create function test.bill_now484(p_bill uuid) returns jsonb language sql stable security definer as $$
  select jsonb_build_object('total', total_crc, 'subtotal', subtotal_crc, 'discount', discount_crc, 'discount_id', discount_id,
                            'reason', discount_reason, 'by', discount_by, 'parts', parts_crc, 'flags', to_jsonb(flags),
                            'paid', paid, 'status', status, 'voided', voided_at is not null)
    from public.orders where id = p_bill $$;
create function test.appr484(p_id text) returns jsonb language sql stable security definer as $$
  select jsonb_build_object('category', category, 'value', value, 'subtotal', subtotal_crc, 'amount', amount_crc,
                            'reason', reason, 'by', approved_name, 'role', approver_role, 'beneficiary', beneficiary_name,
                            'bill_id', bill_id, 'order_id', order_id, 'used', used_at = now(), 'base', base_crc,
                            'base_used', base_used_crc, 'freed', freed_how, 'station', station, 'request_id', request_id,
                            'login', login_id, 'session', session_id, 'till', till_id, 'today', cr_day = public.cr_today())
    from public.discount_approvals where id = p_id::uuid $$;
-- an approval's day ('counts' while it holds the day) and its order
create function test.day484(p_id text) returns text language sql stable security definer as $$
  select coalesce(freed_how, 'counts') || '|' || coalesce(order_id::text, 'no order')
    from public.discount_approvals where id = p_id::uuid $$;
create function test.n484(act text) returns int language sql stable security definer as $$
  select count(*)::int from public.audit_log where action = act $$;
create function test.wrong484() returns int language sql stable security definer as $$
  select count(*)::int from public.audit_log where action = 'discount_code_wrong' $$;
create function test.cats484() returns int language sql stable security definer as $$
  select count(*)::int from public.discount_approvals $$;
create function test.last484() returns bigint language sql stable security definer as $$
  select coalesce(max(id), 0) from public.audit_log $$;
-- the actions of the audit rows written after row n, in order; and the distinct ones
create function test.since484(n bigint) returns text language sql stable security definer as $$
  select coalesce(string_agg(action, ',' order by id), '') from public.audit_log where id > n $$;
create function test.kinds484(n bigint) returns text language sql stable security definer as $$
  select coalesce(string_agg(distinct action, ',' order by action), '') from public.audit_log where id > n $$;
-- the audit rows of one action about one target, each as {manager_id, manager_name, summary} + details, oldest first
create function test.log484(act text, target text) returns jsonb language sql stable security definer as $$
  select coalesce(jsonb_agg(jsonb_build_object('manager_id', manager_id, 'manager_name', manager_name, 'summary', summary)
                            || details order by id), '[]')
    from public.audit_log where action = act and target_id = target $$;
-- one employee's approvals and discount_approved rows (by name)
create function test.emp_rows484(ben text) returns jsonb language sql stable security definer as $$
  select jsonb_build_object('approvals', (select count(*) from public.discount_approvals where beneficiary_name = ben),
                            'approved', (select count(*) from public.audit_log
                                          where action = 'discount_approved' and details ->> 'beneficiary_name' = ben)) $$;
-- every order, line and approval as text: a refusal must leave all of them exactly as they were
create function test.fp484() returns text language sql stable security definer as $$
  select md5(coalesce(string_agg(t, '|' order by t), '')) from (
    select o::text from public.orders o union all select i::text from public.order_items i
    union all select a::text from public.discount_approvals a) x(t) $$;
-- the till's last use (step 6d writes it, after the place's lock), and a sentinel to see whether a call got that far
create function test.used484() returns timestamptz language sql stable security definer as $$
  select last_used_at from public.discount_tills where session_id = 'till-484' and ended_at is null $$;
create function test.mark484() returns void language sql security definer as $$
  update public.discount_tills set last_used_at = '2000-01-01 00:00:00+00' where session_id = 'till-484' and ended_at is null $$;
-- every counted wrong code (and the till's times) moved 25 hours back: each code below is judged on a calm place
create function test.calm484() returns void language sql security definer as $$ select test.back(interval '25 hours') $$;
-- is this transaction holding the advisory lock of that key (480's pattern)
create function test.locked484(k text) returns boolean language sql stable as $$
  select exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1
                   and classid::bigint = (hashtextextended(k, 0) >> 32) & 4294967295
                   and objid::bigint = hashtextextended(k, 0) & 4294967295) $$;
-- the transaction-local mark that lets tab_set_discount take a category approval (set only inside the two functions)
create function test.mark_call484() returns text language sql stable as $$
  select coalesce(current_setting('canopy.discount_call', true), '') $$;
-- an error's sqlstate and message, or 'no error' (480's pattern; runs in its own subtransaction)
create function test.err484(sql text) returns text language plpgsql as $$
begin
  execute sql;
  return 'no error';
exception when others then return sqlstate || ':' || sqlerrm;
end $$;
-- how many values anywhere in a JSON value are one of this file's test PINs (exact values: a uuid may hold any digits)
create function test.pins484(j jsonb) returns int language sql stable as $$
  select count(*)::int from jsonb_path_query(coalesce(j, 'null'), 'strict $.**') v
   where jsonb_typeof(v) in ('string', 'number') and v #>> '{}' in (select pin from test.t484_people) $$;

-- the till: this sign-in is a registered till (test.till is the fixture for files that only need one)
select test.cafe484();
select test.eq(test.till('Caja 1'), 1, '0 fixture: the café sign-in till-484 is the registered till of place 1');
select id as till_id from public.discount_tills where session_id = 'till-484' and ended_at is null \gset
select public._discount_tag('till-484') as tag \gset
select id as tea from public.menu_items where name = 'Tea' \gset
select test.last484() as audit_start \gset
\set cafe 'c0000000-0000-4000-8000-000000000001'
select test.eq(test.locked484('canopy.discount_slot:1'), false, '0 before any call of this file, place 1''s lock is not held');

-- 1) every bill refusal comes before any code is tested: a right and a wrong code get the same answer, nothing is
--    counted, nothing is locked, nothing is written, even from a sign-in that is no till (proposal §2.5b step 5 and
--    §5.1 item 8; mecanismo §6 "steps 1-5 ... none counts"; api §4.2 step 5) --------------------------------------------
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(10), 'Mesa limpia') ->> 'ok' as f10 \gset
select test.bill484(test.o484(11), 'Mesa a cuenta') ->> 'ok' as f11 \gset
select test.payacct484(test.o484(11), 2000) ->> 'part_id' as part11 \gset
select test.bill484(test.o484(12), 'Mesa anulada') ->> 'ok' as f12 \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o484(12), 'mesa equivocada') ->> 'ok' as v12 \gset
select test.bill484(test.o484(13), 'Mesa cancelada') ->> 'ok' as f13 \gset
select public.cancel_unpaid_order(test.o484(13)) ->> 'ok' as c13 \gset
select test.bill484(test.o484(14), 'Mesa pagada') ->> 'ok' as f14 \gset
select public.tab_pay(test.o484(14), 'card', null, null, 'Caja 1') ->> 'closed' as p14 \gset
select test.bill484(test.o484(15), 'Ticket pagado', null, '{"paid": true, "payment_method": "cash_crc", "status": "done"}') ->> 'ok' as f15 \gset
select test.bill484(test.o484(16), 'Mesa por producto') ->> 'ok' as f16 \gset
select test.payitem484(test.o484(16)) ->> 'amount' as p16 \gset
select test.bill484(test.o484(17), 'Mesa combo', test.combo484()) ->> 'ok' as f17 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old19 \gset
select test.bill484(test.o484(19), 'Mesa descuento viejo') ->> 'ok' as f19 \gset
select public.tab_set_discount(test.o484(19), :'old19', 10000, 'Caja 1') ->> 'total' as t19 \gset
-- the page's fallback for a discount it could not confirm (pos.html qSaveRpc): the money as charged, no discount, a note
select test.bill484(test.o484(20), 'Mesa sin verificar', null, '{"total_crc": 7000, "notes": "Employee · not verified"}') ->> 'ok' as f20 \gset
select test.bill484(test.o484(21), 'Mesa nota', null, '{"notes": "Cliente frecuente · not verified"}') ->> 'ok' as f21 \gset
select test.bill484(test.o484(22), 'Mesa aviso') ->> 'ok' as f22 \gset
select test.bill484(test.o484(23), 'Mesa descuadrada', null, '{"total_crc": 9000}') ->> 'ok' as f23 \gset
select test.bill484(test.o484(24), 'Mesa monto') ->> 'ok' as f24 \gset
select test.bill484(test.o484(25), 'Mesa combo pagada', test.combo484()) ->> 'ok' as f25 \gset
select test.payitem484(test.o484(25)) ->> 'amount' as p25 \gset
select test.bill484(test.o484(26), 'Mesa combo viejo', test.combo484()) ->> 'ok' as f26 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 1') ->> 'id' as old26 \gset
select public.tab_set_discount(test.o484(26), :'old26', 5000, 'Caja 1') ->> 'total' as t26 \gset
select test.bill484(test.o484(27), 'Ticket anulado', null, '{"paid": true, "payment_method": "cash_crc", "status": "done"}') ->> 'ok' as f27 \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o484(27), 'cobrado dos veces') ->> 'ok' as v27 \gset
reset role;
-- two states no function leaves on their own, written as the test superuser (fixtures, not the code under test): the
-- flag without its note, and a discount amount without an approval
update public.orders set flags = flags || '{discount_not_verified}'::text[] where id = test.o484(22);
update public.orders set discount_crc = 500 where id = test.o484(24);
select test.eq(concat_ws('|', :'f10', :'f11', :'f12', :'v12', :'f13', :'c13', :'f14', :'p14', :'f15', :'f16', :'p16', :'f17',
                         :'f19', :'t19', :'f20', :'f21', :'f22', :'f23', :'f24', :'f25', :'p25', :'f26', :'t26'),
               'true|true|true|true|true|true|true|true|true|true|4000|true|true|9000|true|true|true|true|true|true|4000|true|4500',
               '1 fixtures: the bills are recorded, voided, cancelled, paid in full, paid by item, discounted the old way');
select test.eq(concat_ws(' ', test.bill_now484(test.o484(20)) ->> 'flags', test.bill_now484(test.o484(21)) ->> 'flags',
                         test.bill_now484(test.o484(23)) ->> 'flags'),
               '["discount_not_verified"] [] ["total_mismatch"]',
               '1 fixtures: the page''s fallback bill is flagged discount_not_verified by the server; a note alone is not; a total below the items is total_mismatch');
select test.ok(:'part11' ~ '^[0-9a-f-]{36}$', '1 fixture: the payment on account is a part of its own');

select test.calm484(); select test.mark484();
select test.wrong484() as w1, test.cats484() as a1, test.last484() as l1, test.fp484() as fp1 \gset
select test.cafe484(); set role authenticated;
select test.both484('local', test.o484(999), 10000, 10000) as nf1 \gset
select test.both484('local', :'part11', 2000, 2000) as nf2 \gset
select test.both484('local', test.o484(12), 10000, 10000) as cn1 \gset
select test.both484('local', test.o484(13), 10000, 10000) as cn2 \gset
select test.both484('local', test.o484(14), 10000, 0) as ap1 \gset
select test.both484('local', test.o484(15), 10000, 10000) as ap2 \gset
select test.both484('local', test.o484(16), 10000, 6000) as hp1 \gset
select test.both484('empleado', test.o484(16), 10000, 6000) as hp2 \gset
select test.both484('local', test.o484(11), 10000, 8000) as hp3 \gset
select test.both484('local', test.o484(17), 5000, 5000) as cb1 \gset
select test.both484('local', test.o484(19), 10000, 9000) as ad1 \gset
select test.both484('local', test.o484(20), 10000, 7000) as ad2 \gset
select test.both484('local', test.o484(21), 10000, 10000) as ad3 \gset
select test.both484('local', test.o484(22), 10000, 10000) as ad4 \gset
select test.both484('local', test.o484(23), 10000, 9000) as ad5 \gset
select test.both484('local', test.o484(24), 10000, 10000) as ad6 \gset
select test.both484('local', test.o484(10), 10000, null) as ch1 \gset
select test.both484('local', test.o484(10), 10000, 9999) as ch2 \gset
select test.both484('local', test.o484(10), 9000, 10000) as ch3 \gset
select test.both484('empleado', test.o484(10), 10000, 7000) as ch4 \gset
select test.both484('local', test.o484(25), 5000, 1000) as pr1 \gset
select test.both484('local', test.o484(26), 5000, 1) as pr2 \gset
select test.both484('local', test.o484(19), 10000, 1) as pr3 \gset
select test.both484('local', test.o484(27), 10000, 10000) as pr5 \gset
select public.descuento_autorizar('empleado', '4826', 10000, null, null, test.o484(999), 10000, null, 'Caja 1') as rq1 \gset
select public.descuento_autorizar('local', '4826', 0, null, null, test.o484(16), 6000, null, 'Caja 1') as rq2 \gset
select public.descuento_autorizar('cumple', '4826', 10000, null, null, test.o484(16), 6000, null, 'Caja 1') as rq3 \gset
reset role;
select test.eq(:'nf1'::text, 'not_found|not_found', '1 no such bill: not_found, for a right code and for a wrong one');
select test.eq(:'nf2'::text, 'not_found|not_found', '1 a part of a bill (a payment on account) is not a bill: not_found');
select test.eq(:'cn1'::text, 'cancelled|cancelled', '1 a voided bill: cancelled');
select test.eq(:'cn2'::text, 'cancelled|cancelled', '1 a cancelled bill: cancelled');
select test.eq(:'ap1'::text, 'already_paid|already_paid', '1 a bill paid in full: already_paid');
select test.eq(:'ap2'::text, 'already_paid|already_paid', '1 a paid ticket: already_paid');
select test.eq(:'hp1'::text, 'has_parts|has_parts', '1 one item paid by item: has_parts (a discount covers the whole bill, only before any payment)');
select test.eq(:'hp2'::text, 'has_parts|has_parts', '1 the same for an Empleado with both codes: has_parts, before either code is tested');
select test.eq(:'hp3'::text, 'has_parts|has_parts', '1 an amount paid on account (parts_crc, no line paid): has_parts');
select test.eq(:'cb1'::text, 'combo_first|combo_first', '1 a bill with a combo line: combo_first');
select test.eq(:'ad1'::text, 'already_discounted|already_discounted', '1 a bill with an old-kind discount: already_discounted (never stacked)');
select test.eq(:'ad2'::text, 'already_discounted|already_discounted', '1 the page''s "not verified" fallback bill (note, flag, total below the items): already_discounted');
select test.eq(:'ad3'::text, 'already_discounted|already_discounted', '1 a note "not verified" alone: already_discounted');
select test.eq(:'ad4'::text, 'already_discounted|already_discounted', '1 the flag discount_not_verified alone: already_discounted');
select test.eq(:'ad5'::text, 'already_discounted|already_discounted', '1 total + parts different from the items alone: already_discounted');
select test.eq(:'ad6'::text, 'already_discounted|already_discounted', '1 a discount amount alone (no approval): already_discounted');
select test.eq(:'ch1'::text, 'changed|changed', '1 p_expect null: changed');
select test.eq(:'ch2'::text, 'changed|changed', '1 p_expect not the bill''s total: changed');
select test.eq(:'ch3'::text, 'changed|changed', '1 the subtotal not the items'' value: changed');
select test.eq(:'ch4'::text, 'changed|changed', '1 an Empleado sending the discounted total as p_expect: changed');
select test.eq(:'pr1'::text, 'has_parts|has_parts', '1 a combo bill with an item paid: has_parts comes before combo_first');
select test.eq(:'pr2'::text, 'combo_first|combo_first', '1 a combo bill with an old discount and a wrong total: combo_first comes before already_discounted');
select test.eq(:'pr3'::text, 'already_discounted|already_discounted', '1 a discounted bill with a wrong total: already_discounted comes before changed');
select test.eq(:'f27' || '|' || :'v27' || '|' || :'pr5', 'true|true|cancelled|cancelled', '1 a paid ticket that was voided: cancelled comes before already_paid');
select test.eq(:'rq1'::jsonb, '{"ok": false, "error": "missing_employee"}'::jsonb, '1 the request''s own checks come before the bill: missing_employee on no such bill');
select test.eq(:'rq2'::jsonb, '{"ok": false, "error": "empty"}'::jsonb, '1 a subtotal of 0 on a bill with parts: empty');
select test.eq(:'rq3'::jsonb, '{"ok": false, "error": "bad_discount"}'::jsonb, '1 an unknown category on a bill with parts: bad_discount');
-- the same from a sign-in that is no till, and from a token without session_id: still the bill's answer
select test.cafe484('no-till-484'); set role authenticated;
select test.both484('local', test.o484(16), 10000, 6000) as nt1 \gset
select test.both484('local', test.o484(20), 10000, 7000) as nt2 \gset
select test.n484('discount_till_unknown') as unk1 \gset
select test.both484('local', test.o484(10), 10000, 10000) as nt3 \gset
select test.n484('discount_till_unknown') as unk2 \gset
select test.login('cafe'); set role authenticated;
select test.both484('local', test.o484(16), 10000, 6000) as ns1 \gset
select test.both484('local', test.o484(10), 10000, 10000) as ns2 \gset
reset role;
select test.eq(:'nt1'::text || ' ' || :'nt2', 'has_parts|has_parts already_discounted|already_discounted',
               '1 from a sign-in that is no till: the bill''s answer (the bill is looked at before the till)');
select test.eq(:unk1, 0, '1 and those calls wrote no discount_till_unknown row: nothing about a code was looked at');
select test.eq(:'nt3'::text, 'till_not_enrolled|till_not_enrolled', '1 control: a clean bill from that sign-in reaches the till check: till_not_enrolled');
select test.ok(:unk2 > :unk1, '1 control: and that one is logged as a code typed on an unregistered device');
select test.eq(:'ns1'::text || ' ' || :'ns2', 'has_parts|has_parts no_session|no_session',
               '1 a token without session_id: the bill''s answer first, no_session only for a clean bill');
select test.eq(test.wrong484() - :w1, 0, '1 none of those wrong codes was counted (no discount_code_wrong row)');
select test.eq(test.cats484() - :a1, 0, '1 no approval was made');
select test.eq(test.kinds484(:l1), 'discount_till_unknown', '1 the only audit rows written are the unregistered device''s (no refusal logged, no pin_duplicate)');
select test.eq(test.fp484(), :'fp1'::text, '1 no order, line or approval changed');
select test.eq(test.used484(), '2000-01-01 00:00:00+00'::timestamptz, '1 no call reached the till''s place (its last use is untouched: step 6d never ran)');
select test.eq(test.locked484('canopy.discount_slot:1'), false, '1 no call took the place''s lock');
select test.eq(test.locked484('canopy.discount_employee:' || test.p484('abel')), false, '1 the Empleado refused at the first look took no per-employee lock');
-- control: a wrong code on a clean bill is tested, counted, and takes the place's lock
select test.cafe484(); set role authenticated;
select public.descuento_autorizar('local', '0000', 10000, null, null, test.o484(10), 10000, null, 'Caja 1') as ctl \gset
reset role;
select test.eq(concat_ws('|', (:'ctl'::jsonb) ->> 'error', (:'ctl'::jsonb) ->> 'step', coalesce((:'ctl'::jsonb) ->> 'blocked', 'none')),
               'bad_pin|manager|none', '1 control: a wrong code on a clean bill is tested: bad_pin at the manager step');
select test.eq(test.wrong484() - :w1, 1, '1 control: and counted (one discount_code_wrong row)');
select test.eq(test.used484(), now(), '1 control: it reached the till''s place (its last use is now)');
select test.eq(test.locked484('canopy.discount_slot:1'), true, '1 control: and took the place''s lock');
select test.eq(test.bill_now484(test.o484(10)) ->> 'total', '10000', '1 control: the bill is unchanged');
-- a bill that already carries a category discount (made through the window here, after the lock checks above)
select test.calm484();
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(18), 'Mesa Local') ->> 'ok' as f18 \gset
select test.cat484('local', test.o484(18), 10000) ->> 'total' as t18 \gset
select test.wrong484() as w1b, test.cats484() as a1b \gset
select test.both484('local', test.o484(18), 10000, 9000) as ad7 \gset
select test.both484('empleado', test.o484(18), 10000, 9000) as ad8 \gset
select test.both484('local', test.o484(18), 10000, 1) as pr4 \gset
reset role;
select test.eq(:'f18' || '|' || :'t18', 'true|9000', '1 fixture: a Local on a bill through the window (10000 - 10 %)');
select test.eq(:'ad7'::text, 'already_discounted|already_discounted', '1 a second Local on a bill with a category discount: already_discounted (never stacked)');
select test.eq(:'ad8'::text, 'already_discounted|already_discounted', '1 an Empleado on that bill: already_discounted');
select test.eq(:'pr4'::text, 'already_discounted|already_discounted', '1 with a wrong total too: already_discounted before changed');
select test.eq((test.wrong484() - :w1b) || '|' || (test.cats484() - :a1b), '0|0', '1 nothing counted, no approval made');

-- 2) the whole bill in one call (proposal §5.1 item 8; §2.5b steps 9-11; api §4.2 answer) ---------------------------
select test.calm484();
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(1), 'Mesa Eva') ->> 'ok' as b1 \gset
select test.last484() as l2 \gset
select test.emp484('eva', test.o484(1), 10000, '4826', test.r484(1)) as eva1 \gset
select test.since484(:l2) as eva1_rows, test.mark_call484() as eva1_mark \gset
select test.bill484(test.o484(2), 'Mesa Huésped', '[{"item_name": "Latte", "price_crc": 4000, "qty": 1}, {"item_name": "Casado", "price_crc": 8345, "qty": 1}]') ->> 'ok' as b2 \gset
select test.cat484('huesped', test.o484(2), 12345, '4826', null, 12345) as hu1 \gset
reset role;
select (:'eva1'::jsonb) ->> 'id' as eva1_id, (:'hu1'::jsonb) ->> 'id' as hu1_id \gset
select test.eq(:'b1' || '|' || :'b2', 'true|true', '2 fixtures: two «Pay later» bills');
select test.eq(:'eva1'::jsonb, jsonb_build_object('ok', true, 'id', :'eva1_id', 'request_id', test.r484(1), 'category', 'empleado',
                 'amount', 3000, 'subtotal', 10000, 'reason', 'Employee', 'name', 'Ana', 'role', 'manager', 'beneficiary', 'Eva',
                 'company', null, 'at', now(), 'prior', null, 'order_id', test.o484(1), 'total', 7000, 'discount', 3000),
               '2 an Empleado on Eva''s bill in one call: approved, and the answer carries the bill (10000 - 30 % = 7000)');
select test.eq(test.bill_now484(test.o484(1)), jsonb_build_object('total', 7000, 'subtotal', 10000, 'discount', 3000,
                 'discount_id', :'eva1_id', 'reason', 'Employee', 'by', 'Ana', 'parts', 0, 'flags', '[]'::jsonb, 'paid', false,
                 'status', 'ready', 'voided', false),
               '2 the bill carries it: subtotal 10000, discount 3000, total 7000, «Employee» by Ana, still open');
select test.eq(test.appr484(:'eva1_id'), jsonb_build_object('category', 'empleado', 'value', 30, 'subtotal', 10000, 'amount', 3000,
                 'reason', 'Employee', 'by', 'Ana', 'role', 'manager', 'beneficiary', 'Eva', 'bill_id', test.o484(1),
                 'order_id', test.o484(1), 'used', true, 'base', 0, 'base_used', 0, 'freed', null, 'station', 'Caja 1',
                 'request_id', test.r484(1), 'login', :'cafe', 'session', 'till-484', 'till', :'till_id', 'today', true),
               '2 the approval is used by the bill at once (bill_id = order_id; base 0: nothing was paid before)');
select test.eq(:'eva1_rows'::text, 'discount_approved', '2 the call wrote one audit row, discount_approved (putting it on the bill writes none)');
select test.eq(test.log484('discount_approved', :'eva1_id'), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'Employee', 'kind', 'percent', 'value', 30, 'subtotal_crc', 10000,
                 'discount_crc', 3000, 'station', 'Caja 1', 'category', 'empleado', 'beneficiary_name', 'Eva', 'company', null,
                 'approver_role', 'manager', 'bill', test.o484(1), 'prior', null, 'till', :'till_id', 'slot', 1,
                 'person_locked', false, 'employee_locked', false, 'by_login', :'cafe')),
               '2 discount_approved names Ana, Eva, the bill and the till');
select test.eq(:'eva1_mark'::text, '', '2 the mark that lets tab_set_discount take a category approval is cleared after the call');
select test.eq((:'hu1'::jsonb) - 'id' - 'at', jsonb_build_object('ok', true, 'request_id', null, 'category', 'huesped', 'amount', 1235,
                 'subtotal', 12345, 'reason', 'Hotel guest', 'name', 'Ana', 'role', 'manager', 'beneficiary', null, 'company', null,
                 'prior', null, 'order_id', test.o484(2), 'total', 11110, 'discount', 1235),
               '2 Huésped on a bill of 12345: 10 % rounded (1235) on the whole bill, total 11110');
select test.eq(test.bill_now484(test.o484(2)) - 'flags' - 'paid' - 'status' - 'voided', jsonb_build_object('total', 11110,
                 'subtotal', 12345, 'discount', 1235, 'discount_id', :'hu1_id', 'reason', 'Hotel guest', 'by', 'Ana', 'parts', 0),
               '2 the Huésped bill carries it');
select test.eq(test.wrong484() - :w1b, 0, '2 a valid call counts nothing');
select test.eq(test.locked484('canopy.discount_request:' || test.r484(1)), true, '2 the call took its request lock (A)');
select test.eq(test.locked484('canopy.discount_employee:' || test.p484('eva')), true, '2 and Eva''s per-employee lock');
select test.eq(test.locked484('canopy.discount_tills'), false, '2 never the café-wide tills lock (B)');
select test.eq(test.locked484('canopy.discount_code'), false, '2 nor the proposal''s café-wide code lock, which the registered tills replaced');

-- 3) the bill changed on another device between the first look and the codes: checked again under the bill's lock,
--    refused, logged as discount_refused after a valid code, never counted (proposal §2.5b step 7, §2.4 point 4). In one
--    session a test trigger on the till's last use (step 6d, between the two looks) plays the other device, with the
--    real tab_add_items, tab_pay and cancel_unpaid_order
create function test.meanwhile484() returns trigger language plpgsql as $$
declare v text := coalesce(current_setting('test.m484', true), ''); b uuid; r jsonb;
begin
  if v = '' then return null; end if;
  perform set_config('test.m484', '', true);
  b := split_part(v, '|', 1)::uuid;
  r := case split_part(v, '|', 2)
         when 'add' then public.tab_add_items(b, jsonb_build_array(jsonb_build_object('menu_item_id', split_part(v, '|', 3), 'qty', 1)))
         when 'pay' then public.tab_pay(b, 'cash_crc', jsonb_build_array(jsonb_build_object('item_id', test.item484(b, 1), 'qty', 1)),
                                        null, 'Caja 2')
         when 'cancel' then public.cancel_unpaid_order(b) end;
  perform set_config('test.m484r', coalesce(r::text, 'null'), true);
  return null;
end $$;
create trigger t484_meanwhile after update of last_used_at on public.discount_tills for each row execute function test.meanwhile484();
select test.calm484();
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(30), 'Mesa Fede') ->> 'ok' as b30 \gset
select test.bill484(test.o484(31), 'Mesa Iris') ->> 'ok' as b31 \gset
select test.bill484(test.o484(32), 'Mesa Local cancelada') ->> 'ok' as b32 \gset
select test.wrong484() as w3, test.cats484() as a3 \gset
select set_config('test.m484', test.o484(30) || '|add|' || :'tea', true) is not null as armed \gset
select test.emp484('fede', test.o484(30), 10000, '4826', test.r484(30)) as fede1 \gset
select current_setting('test.m484r', true) as fede_add \gset
select public.descuento_autorizar('empleado', '', 10000, null, null, test.o484(30), 10000, test.r484(30), 'Caja 1') as fede1r \gset
select set_config('test.m484', test.o484(31) || '|pay', true) is not null as armed \gset
select test.emp484('iris', test.o484(31), 10000) as iris1 \gset
select current_setting('test.m484r', true) as iris_pay \gset
select set_config('test.m484', test.o484(32) || '|cancel', true) is not null as armed \gset
select test.cat484('local', test.o484(32), 10000) as loc32 \gset
select current_setting('test.m484r', true) as loc_cancel \gset
select test.wrong484() as w3b, test.cats484() as a3b, test.mark_call484() as m3 \gset
-- then the same request again, with the bill's new total; and Iris's day was never taken
select test.emp484('fede', test.o484(30), 11000, '4826', test.r484(30), 11000) as fede2 \gset
select test.emp484('iris') ->> 'ok' as iris2 \gset
reset role;
drop trigger t484_meanwhile on public.discount_tills;
select test.eq(concat_ws('|', :'b30', :'b31', :'b32', (:'fede_add'::jsonb) ->> 'total', (:'iris_pay'::jsonb) ->> 'ok',
                         (:'loc_cancel'::jsonb) ->> 'ok'), 'true|true|true|11000|true|true',
               '3 fixtures: the other device added a Tea to Fede''s bill, paid Iris''s Latte, cancelled the Local bill, each between the two looks');
select test.eq(:'fede1'::jsonb, '{"ok": false, "error": "changed"}'::jsonb, '3 an item added meanwhile: changed (found under the bill''s lock)');
select test.eq(:'iris1'::jsonb, '{"ok": false, "error": "has_parts"}'::jsonb, '3 an item paid meanwhile: has_parts');
select test.eq(:'loc32'::jsonb, '{"ok": false, "error": "cancelled"}'::jsonb, '3 the bill cancelled meanwhile: cancelled');
select test.eq((:w3b - :w3) || '|' || (:a3b - :a3), '0|0', '3 none of them was counted, and no approval was made');
select test.eq(:'m3'::text, '', '3 the mark was never set');
select test.eq(test.log484('discount_refused', test.o484(30)::text), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'discount refused after a valid code: changed', 'why', 'changed',
                 'category', 'empleado', 'authorizer', 'Ana', 'role', 'manager', 'beneficiary', 'Fede', 'bill', test.o484(30),
                 'till', :'till_id', 'slot', 1, 'by_login', :'cafe', 'session_tag', :'tag', 'station', 'Caja 1')),
               '3 the refusal after a valid code is logged: discount_refused {why: changed} naming Ana and Fede (a sign-in only as its tag)');
select test.eq(test.log484('discount_refused', test.o484(31)::text) -> 0 ->> 'why', 'has_parts', '3 discount_refused {why: has_parts} for Iris''s bill');
select test.eq(test.log484('discount_refused', test.o484(32)::text) -> 0, jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'discount refused after a valid code: cancelled', 'why', 'cancelled',
                 'category', 'local', 'authorizer', 'Ana', 'role', 'manager', 'beneficiary', null, 'bill', test.o484(32),
                 'till', :'till_id', 'slot', 1, 'by_login', :'cafe', 'session_tag', :'tag', 'station', 'Caja 1'),
               '3 discount_refused {why: cancelled} for the Local bill, with no beneficiary');
select test.eq(:'fede1r'::jsonb, '{"ok": false, "error": "no_request"}'::jsonb,
               '3 the refused attempt stored nothing: its request id with the codes wiped answers no_request');
select test.eq((:'fede2'::jsonb) - 'id' - 'at', jsonb_build_object('ok', true, 'request_id', test.r484(30), 'category', 'empleado',
                 'amount', 3300, 'subtotal', 11000, 'reason', 'Employee', 'name', 'Ana', 'role', 'manager', 'beneficiary', 'Fede',
                 'company', null, 'prior', null, 'order_id', test.o484(30), 'total', 7700, 'discount', 3300),
               '3 the same request with the bill''s new total is a new attempt: approved on the whole bill (11000 - 30 %), no replay');
select test.eq(:'iris2'::text, 'true', '3 Iris''s day was never taken: a ticket Empleado for her is approved');

-- 4) a refusal of tab_set_discount inside the call leaves no approval and no used day (money 6, verifier M6/P6). After
--    step 7 no real refusal is reachable, so a stub makes one; it lives only inside a savepoint (W4, the pattern of
--    270_production_followup): the values are captured, the savepoint is rolled back, and only then asserted
select test.calm484();
select md5(prosrc) as tsd_md5, prosecdef::text as tsd_definer, coalesce(proacl::text, '') as tsd_acl
  from pg_proc where oid = 'public.tab_set_discount(uuid, uuid, int, text)'::regprocedure \gset
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(40), 'Mesa Luis') ->> 'ok' as b40 \gset
reset role;
select test.n484('discount_refused') as ref40, test.emp_rows484('Luis') as luis_before \gset
savepoint stub;
create or replace function public.tab_set_discount(p_order_id uuid, p_discount_id uuid, p_expect int default null,
                                                   p_station text default null)
returns jsonb language sql as $$ select '{"ok": false, "error": "refund_first"}'::jsonb $$;
set role authenticated;
select test.emp484('luis', test.o484(40), 10000) as stub_bill \gset
select test.mark_call484() as stub_mark, test.emp_rows484('Luis') as stub_rows,
       test.log484('discount_refused', test.o484(40)::text) as stub_refused, test.bill_now484(test.o484(40)) as stub_state \gset
select test.emp484('luis') as stub_ticket \gset
reset role;
rollback to savepoint stub;
select test.eq(:'b40' || '|' || (:'luis_before'::jsonb)::text, 'true|{"approved": 0, "approvals": 0}', '4 fixture: a clean bill, and Luis has no approval yet');
select test.eq(:'stub_bill'::jsonb, '{"ok": false, "error": "refund_first"}'::jsonb,
               '4 tab_set_discount refusing inside the call (a stub answering refund_first): the call answers refund_first');
select test.eq(:'stub_rows'::jsonb, '{"approvals": 0, "approved": 0}'::jsonb,
               '4 no approval row and no discount_approved row for Luis: both rolled back with the refusal');
select test.eq(:'stub_refused'::jsonb, jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'), 'manager_name', 'Ana',
                 'summary', 'discount refused after a valid code: refund_first', 'why', 'refund_first', 'category', 'empleado',
                 'authorizer', 'Ana', 'role', 'manager', 'beneficiary', 'Luis', 'bill', test.o484(40), 'till', :'till_id',
                 'slot', 1, 'by_login', :'cafe', 'session_tag', :'tag', 'station', 'Caja 1')),
               '4 one discount_refused row {why: refund_first} naming Ana and Luis, written after the rollback');
select test.eq((:'stub_state'::jsonb) - 'flags' - 'paid' - 'status' - 'voided', '{"by": null, "parts": 0, "total": 10000, "reason": null, "discount": 0, "subtotal": null, "discount_id": null}'::jsonb,
               '4 the bill is unchanged');
select test.eq(:'stub_mark'::text, '', '4 the mark went with the refusal (it never outlives the call)');
select test.eq((:'stub_ticket'::jsonb) ->> 'ok' || '|' || ((:'stub_ticket'::jsonb) ->> 'beneficiary'), 'true|Luis',
               '4 with the stub still in place, an Empleado for Luis on a ticket is approved: the failed attempt left no used day');
select test.eq((select md5(prosrc) || '|' || prosecdef::text || '|' || coalesce(proacl::text, '') from pg_proc
                 where oid = 'public.tab_set_discount(uuid, uuid, int, text)'::regprocedure),
               :'tsd_md5' || '|' || :'tsd_definer' || '|' || :'tsd_acl',
               '4 after the rollback tab_set_discount is the real one again (same text hash, definer, grants)');
select test.ok((select prosrc like '%tab_set_discount_category%' and prosrc like '%canopy.discount_call%' from pg_proc
                 where oid = 'public.tab_set_discount(uuid, uuid, int, text)'::regprocedure),
               '4 and it is 0038''s text (its category guard and the mark are in it)');
select test.eq(test.emp_rows484('Luis'), '{"approvals": 0, "approved": 0}'::jsonb,
               '4 the ticket approval of the stub case went with the savepoint: Luis''s day is free for section 9');
select test.eq(test.n484('discount_refused') - :ref40, 0, '4 and so did the stub''s discount_refused row');

-- 5) the same request sent again (a lost reply), and request ids that are not this attempt's (proposal §5.1 items 8
--    and 13; §2.5b step 2 and the backstop of step 10; api §4.2 steps 2-3 and 9) -------------------------------------
select test.calm484();
select test.cafe484(); set role authenticated;
select test.wrong484() as w5, test.cats484() as a5, test.last484() as l5 \gset
select public.descuento_autorizar('empleado', '', 10000, null, null, test.o484(1), 10000, test.r484(1), 'Caja 1') as rp1 \gset
select test.emp484('eva', test.o484(1), 10000, '4826', test.r484(1)) as rp2 \gset
select public.descuento_autorizar('empleado', '0000', 10000, '0001', null, test.o484(1), 10000, test.r484(1), 'Caja 1') as rp3 \gset
select test.since484(:l5) as rp_rows, test.wrong484() - :w5 as rp_wrong, test.cats484() - :a5 as rp_new \gset
select public.tab_add_items(test.o484(1), jsonb_build_array(jsonb_build_object('menu_item_id', :'tea', 'qty', 1))) ->> 'total' as add1 \gset
select public.descuento_autorizar('empleado', '', 10000, null, null, test.o484(1), 7000, test.r484(1), 'Caja 1') as rp4 \gset
select test.cafe484('no-till-484'); set role authenticated;
select public.descuento_autorizar('empleado', '', 10000, null, null, test.o484(1), 8000, test.r484(1), 'Caja 2') as rp5 \gset
reset role;
select test.eq(:'rp1'::jsonb, (:'eva1'::jsonb) || '{"replay": true}', '5 the same request with the codes wiped: the stored answer, with replay');
select test.eq(:'rp2'::jsonb, (:'eva1'::jsonb) || '{"replay": true}', '5 the same request with the codes again: the same answer, no second approval');
select test.eq(:'rp3'::jsonb, (:'eva1'::jsonb) || '{"replay": true}', '5 the same request with wrong codes: the same answer, no code tested');
select test.eq(:'rp_rows' || '|' || :rp_wrong || '|' || :rp_new, '|0|0', '5 the replays wrote no audit row, counted nothing, made no approval');
select test.eq((select count(*)::int from public.discount_approvals where request_id = test.r484(1)), 1, '5 one approval for that request id');
select test.eq(:'add1'::text, '8000', '5 fixture: a Tea added to Eva''s bill is charged in full (7000 + 1000)');
select test.eq(:'rp4'::jsonb, (:'eva1'::jsonb) || '{"total": 8000, "replay": true}',
               '5 a replay carries the bill as it is now (total 8000, discount 3000), and comes before the bill''s checks');
select test.eq(:'rp5'::jsonb, (:'eva1'::jsonb) || '{"total": 8000, "replay": true}',
               '5 the replay is per login: another sign-in of the café login (no till) gets the same stored answer');
-- a request that never committed, sent with the codes wiped: no_request, nothing counted
select test.cafe484(); set role authenticated;
select test.wrong484() as w5b, test.last484() as l5b, test.fp484() as fp5b \gset
select public.descuento_autorizar('empleado', '', 10000, null, null, test.o484(10), 10000, test.r484(55), 'Caja 1') as nr1 \gset
select public.descuento_autorizar('local', '   ', 10000, null, null, test.o484(10), 10000, null, 'Caja 1') as nr2 \gset
reset role;
select test.eq(:'nr1'::jsonb, '{"ok": false, "error": "no_request"}'::jsonb, '5 a request that never committed, codes wiped: no_request');
select test.eq(:'nr2'::jsonb, '{"ok": false, "error": "no_request"}'::jsonb, '5 a blank code without a request id: no_request');
select test.eq((test.wrong484() - :w5b) || '|' || test.since484(:l5b) || '|' || (test.fp484() = :'fp5b'), '0||true',
               '5 nothing counted, nothing written, nothing changed');
-- another login's request id: bad_request, nothing tested
select test.login('owner', 'aal2'); select test.session('owner-484');
select test.eq(test.till('Oficina'), 2, '5 fixture: the owner login''s sign-in owner-484 is the registered till of place 2');
set role authenticated;
select test.cat484('local', null, null, '4826', test.r484(56), 5000) as own1 \gset
reset role;
select test.cafe484(); set role authenticated;
select test.wrong484() as w5c, test.cats484() as a5c, test.last484() as l5c, test.fp484() as fp5c \gset
select test.cat484('local', test.o484(10), 10000, '4826', test.r484(56)) as br1 \gset
select test.cat484('local', test.o484(10), 10000, '0000', test.r484(56)) as br2 \gset
select public.descuento_autorizar('local', '', 10000, null, null, test.o484(10), 10000, test.r484(56), 'Caja 1') as br3 \gset
reset role;
select test.eq((:'own1'::jsonb) ->> 'ok' || '|' || (test.appr484((:'own1'::jsonb) ->> 'id') ->> 'login'),
               'true|0e000000-0000-4000-8000-000000000002', '5 fixture: an approval of the owner login with its own request id');
select test.eq(:'br1'::jsonb, '{"ok": false, "error": "bad_request"}'::jsonb, '5 that request id from the café login with a right code: bad_request');
select test.eq(:'br2'::jsonb, '{"ok": false, "error": "bad_request"}'::jsonb, '5 with a wrong code: bad_request');
select test.eq(:'br3'::jsonb, '{"ok": false, "error": "bad_request"}'::jsonb, '5 with the codes wiped: bad_request (before no_request)');
select test.eq((test.wrong484() - :w5c) || '|' || (test.cats484() - :a5c) || '|' || test.since484(:l5c) || '|' || (test.fp484() = :'fp5c'),
               '0|0||true', '5 nothing tested, counted, written or changed');
-- 29 and 31 minutes: a replay holds for 30 minutes; after that the request id is a new attempt
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(53), 'Mesa vieja') ->> 'ok' as b53 \gset
select test.cat484('local', test.o484(53), 10000, '4826', test.r484(53)) as old53 \gset
reset role;
-- (fixture: the approval made 29 minutes ago; now() does not move inside one transaction)
update public.discount_approvals set created_at = now() - interval '29 minutes' where request_id = test.r484(53);
select test.cafe484(); set role authenticated;
select public.descuento_autorizar('local', '', 10000, null, null, test.o484(53), 9000, test.r484(53), 'Caja 1') as rp29 \gset
reset role;
update public.discount_approvals set created_at = now() - interval '31 minutes' where request_id = test.r484(53);
select test.cafe484(); set role authenticated;
select test.wrong484() as w5d \gset
select public.descuento_autorizar('local', '', 10000, null, null, test.o484(53), 9000, test.r484(53), 'Caja 1') as rp31 \gset
select test.cat484('local', test.o484(53), 9000, '4826', test.r484(53)) as rp31b \gset
reset role;
select test.eq(:'rp29'::jsonb, (:'old53'::jsonb) || jsonb_build_object('at', now() - interval '29 minutes', 'replay', true),
               '5 a request of this login made 29 minutes ago, codes wiped: its stored answer (replay)');
select test.eq(:'rp31'::jsonb, '{"ok": false, "error": "no_request"}'::jsonb, '5 made 31 minutes ago, codes wiped: no replay any more, no_request');
select test.eq(:'rp31b'::jsonb, '{"ok": false, "error": "already_discounted"}'::jsonb,
               '5 made 31 minutes ago, with a code: a new attempt, refused by the bill that already carries it');
select test.eq(test.wrong484() - :w5d, 0, '5 nothing counted');
-- the backstop of the request index (proposal §5.1 item 13): an approval row of this login with that request id, 31
-- minutes old, inserted as the test superuser (a fixture: step 2's replay does not find it)
insert into public.discount_approvals (created_at, approved_by, approved_name, kind, value, reason, station, subtotal_crc,
                                       amount_crc, category, cr_day, approver_role, login_id, session_id, request_id)
  values (now() - interval '31 minutes', test.staff('ana'), 'Ana', 'percent', 10, 'Local', 'Caja 1', 1000, 100, 'local',
          public.cr_today(), 'manager', :'cafe', 'till-484', test.r484(54));
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(54), 'Mesa Yago') ->> 'ok' as b54 \gset
select test.wrong484() as w5e, test.cats484() as a5e, test.last484() as l5e \gset
select test.emp484('yago', test.o484(54), 10000, '4826', test.r484(54)) as bs1 \gset
select test.since484(:l5e) as bs_rows, test.wrong484() - :w5e as bs_wrong, test.cats484() - :a5e as bs_new,
       test.bill_now484(test.o484(54)) ->> 'total' as bs_total, test.mark_call484() as bs_mark,
       test.emp_rows484('Yago') ->> 'approvals' as bs_yago \gset
select test.emp484('yago', test.o484(54), 10000, '4826', test.r484(57)) ->> 'total' as bs2 \gset
reset role;
select test.eq(:'bs1'::jsonb, '{"ok": false, "error": "bad_request"}'::jsonb,
               '5 the insert hits the request index (the row is this login''s but 31 minutes old): bad_request, never an error 23505');
select test.eq(concat_ws('|', :'bs_rows', :'bs_wrong', :'bs_new', :'bs_total', :'bs_mark', :'bs_yago'), 'discount_refused|0|0|10000||0',
               '5 one discount_refused row; nothing counted; no new approval; the bill unchanged; the mark cleared; none for Yago');
select test.eq(test.log484('discount_refused', test.o484(54)::text), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'discount refused after a valid code: bad_request', 'why', 'bad_request',
                 'category', 'empleado', 'authorizer', 'Ana', 'role', 'manager', 'beneficiary', 'Yago', 'bill', test.o484(54),
                 'till', :'till_id', 'slot', 1, 'by_login', :'cafe', 'session_tag', :'tag', 'station', 'Caja 1')),
               '5 discount_refused {why: bad_request} names Ana, Yago and the bill');
select test.eq(:'bs2'::text, '7000', '5 Yago''s day was never taken and the bill is clean: a new request is approved on it');
-- the page lets a lost reply go by its request id: an approval already on its bill stays there
select test.cafe484(); set role authenticated;
select public.descuento_liberar(null, test.r484(1)) as lib1 \gset
select public.descuento_liberar(:'eva1_id') as lib2 \gset
reset role;
select test.eq(:'lib1'::jsonb, jsonb_build_object('ok', false, 'error', 'discount_used', 'id', :'eva1_id'),
               '5 descuento_liberar by the request id of a bill-mode approval: discount_used (it is on the bill)');
select test.eq(:'lib2'::jsonb, jsonb_build_object('ok', false, 'error', 'discount_used', 'id', :'eva1_id'), '5 by its id: discount_used');
select test.eq(test.day484(:'eva1_id') || '|' || (test.bill_now484(test.o484(1)) ->> 'discount_id'),
               'counts|' || test.o484(1) || '|' || :'eva1_id', '5 the bill keeps it and Eva''s day still counts');

-- 6) one Empleado a day, in bill mode (proposal §5.1 item 13; §2.5b step 8 and its backstop) ------------------------
select test.calm484();
select test.cafe484(); set role authenticated;
select test.emp484('marta') as m1 \gset
select test.bill484(test.o484(60), 'Mesa Marta') ->> 'ok' as b60 \gset
select test.bill484(test.o484(61), 'Mesa Eva 2') ->> 'ok' as b61 \gset
select test.wrong484() as w6, test.cats484() as a6 \gset
select test.emp484('marta', test.o484(60), 10000) as m2 \gset
select test.emp484('eva', test.o484(61), 10000) as e2 \gset
select test.wrong484() - :w6 as d_wrong, test.cats484() - :a6 as d_new, test.bill_now484(test.o484(60)) ->> 'total' as t60,
       test.bill_now484(test.o484(61)) ->> 'total' as t61 \gset
reset role;
select (:'m1'::jsonb) ->> 'id' as m1_id \gset
select test.eq((:'m1'::jsonb) ->> 'ok', 'true', '6 fixture: a ticket Empleado for Marta, not used yet');
select test.eq((:'m2'::jsonb) - 'until', '{"ok": false, "error": "daily_used", "beneficiary": "Marta", "pending": true, "station": "Caja 1"}'::jsonb,
               '6 then an Empleado for Marta on a bill: daily_used, pending (the first is not used yet), and its station');
select test.eq(((:'m2'::jsonb) ->> 'until')::timestamptz, now() + interval '30 minutes', '6 until = the first approval''s time + 30 minutes');
select test.eq(:'e2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Eva", "pending": false}'::jsonb,
               '6 a second Empleado for Eva, whose first is on a bill: daily_used, not pending');
select test.eq(concat_ws('|', :'d_wrong', :'d_new', :'t60', :'t61'), '0|0|10000|10000', '6 nothing counted, no approval, both bills unchanged');
select test.eq(test.log484('discount_daily_refused', :'m1_id'), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'employee discount already used today: Marta', 'beneficiary_name', 'Marta',
                 'beneficiary', test.staff('marta'), 'approval', :'m1_id', 'pending', true, 'category', 'empleado',
                 'till', :'till_id', 'by_login', :'cafe', 'station', 'Caja 1')),
               '6 discount_daily_refused names Ana, Marta and the approval that holds the day');
select test.eq(jsonb_array_length(test.log484('discount_daily_refused', :'eva1_id')), 1, '6 and one for Eva''s, against her bill''s approval');
-- the backstop of discount_employee_once: in one session step 8's read always answers first, so a test trigger slips a
-- rival live approval in right before the insert (a second device, in production); the handler answers daily_used
create function test.rival484() returns trigger language plpgsql as $$
begin
  if new.request_id = test.r484(62) then
    insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, subtotal_crc, amount_crc, category,
                                           beneficiary_id, beneficiary_name, cr_day, approver_role)
      values (test.staff('ana'), 'Ana', 'percent', 30, 'Employee', 1000, 300, 'empleado', new.beneficiary_id, new.beneficiary_name,
              new.cr_day, 'manager');
  end if;
  return new;
end $$;
create trigger t484_rival before insert on public.discount_approvals for each row execute function test.rival484();
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(62), 'Mesa Gus') ->> 'ok' as b62 \gset
select test.last484() as l6b, test.cats484() as a6b \gset
select test.emp484('gus', test.o484(62), 10000, '4826', test.r484(62)) as gus1 \gset
select test.since484(:l6b) as gus_rows, test.cats484() - :a6b as gus_new, test.bill_now484(test.o484(62)) ->> 'total' as t62,
       test.mark_call484() as gus_mark \gset
reset role;
drop trigger t484_rival on public.discount_approvals;
select test.cafe484(); set role authenticated;
select test.emp484('gus', test.o484(62), 10000, '4826', test.r484(63)) ->> 'total' as gus2 \gset
reset role;
select test.eq(:'gus1'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Gus"}'::jsonb,
               '6 the insert hits discount_employee_once: daily_used, never an error 23505');
select test.eq(concat_ws('|', :'gus_rows', :'gus_new', :'t62', :'gus_mark'), 'discount_daily_refused|0|10000|',
               '6 one discount_daily_refused row, no approval left, the bill unchanged, the mark cleared');
select test.eq(test.log484('discount_daily_refused', test.o484(62)::text), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'employee discount already used today: Gus', 'beneficiary_name', 'Gus',
                 'beneficiary', test.p484('gus'), 'category', 'empleado', 'till', :'till_id', 'by_login', :'cafe',
                 'station', 'Caja 1', 'backstop', true)),
               '6 the backstop''s row: against the bill, backstop true, no approval named');
select test.eq(:'gus2'::text, '7000', '6 (in one session the rival rolled back with the insert: the next request is approved)');

-- 7) a ticket: the whole order, never stacked (proposal §5.1 item 9; §2.6c; D5, D6) ----------------------------------
select test.calm484();
select test.cafe484(); set role authenticated;
select test.emp484('hugo') ->> 'id' as hugo1 \gset
select test.cat484('local') ->> 'id' as loc71 \gset
select test.emp484('kai') ->> 'id' as kai1 \gset
select test.cat484('local') ->> 'id' as loc73 \gset
select test.cat484('local') ->> 'id' as loc74 \gset
select test.cat484('local') ->> 'id' as loc76 \gset
select test.cat484('local') ->> 'id' as loc77 \gset
select test.sale484(test.o484(70), :'hugo1', 10000, 3000) ->> 'ok' as s70 \gset
select test.sale484(test.o484(71), :'loc71', 10000, 1000) ->> 'ok' as s71 \gset
select test.sale484(test.o484(72), :'kai1', 10000, 2000) ->> 'ok' as s72 \gset
select public.descuento_liberar(:'kai1') as lib72 \gset
select test.sale484(test.o484(73), :'loc73', 12000, 1000) ->> 'ok' as s73 \gset
select test.sale484(test.o484(74), :'loc74', 10000, 5000) ->> 'ok' as s74 \gset
select test.sale484(test.o484(75), :'hugo1', 10000, 3000) as s75 \gset
select test.throws(format('select test.sale484(%L, %L, null, 1000, 10000, 9000)', test.o484(76), :'loc76'), '^discount_no_subtotal$',
                   '7 a sale with a discount and no subtotal: discount_no_subtotal (a malformed sale is refused as before)');
select test.throws(format('select test.sale484(%L, %L, 10000, 1000, 10000, 9500)', test.o484(76), :'loc76'), '^discount_total$',
                   '7 a total that is not subtotal - discount: discount_total');
reset role;
select test.eq(concat_ws('|', :'s70', :'s71', :'s72', :'s73', :'s74'), 'true|true|true|true|true', '7 every sale is recorded');
select test.eq(test.bill_now484(test.o484(70)), jsonb_build_object('total', 7000, 'subtotal', 10000, 'discount', 3000,
                 'discount_id', :'hugo1', 'reason', 'Employee', 'by', 'Ana', 'parts', 0, 'flags', '[]'::jsonb, 'paid', true,
                 'status', 'done', 'voided', false),
               '7 the exact subtotal and amount: linked, «Employee», discount_by Ana, no flag');
select test.eq(test.day484(:'hugo1'), 'counts|' || test.o484(70), '7 and the approval is used by that sale');
select test.eq(test.bill_now484(test.o484(71)) ->> 'reason' || '|' || (test.bill_now484(test.o484(71)) ->> 'by')
               || '|' || (test.bill_now484(test.o484(71)) ->> 'flags'), 'Local|Ana|[]', '7 a Local the same: «Local» by Ana');
select test.eq(test.bill_now484(test.o484(72)), jsonb_build_object('total', 8000, 'subtotal', 10000, 'discount', 2000,
                 'discount_id', :'kai1', 'reason', 'Employee · not verified', 'by', null, 'parts', 0,
                 'flags', '["discount_not_verified"]'::jsonb, 'paid', true, 'status', 'done', 'voided', false),
               '7 a smaller discount: linked, the money as charged, «Employee · not verified», discount_by null, one flag');
select test.eq(test.log484('discount_not_verified', test.o484(72)::text), jsonb_build_array(jsonb_build_object('manager_id', null,
                 'manager_name', 'Caja 1', 'summary', 'Employee · not the approved amount', 'order', test.o484(72),
                 'approval', :'kai1', 'category', 'empleado', 'why', 'mismatch', 'subtotal_crc', 10000, 'discount_crc', 2000,
                 'approved_subtotal', 10000, 'approved_discount', 3000)),
               '7 and audit discount_not_verified {why: mismatch} with what was approved');
select test.eq(:'lib72'::jsonb, jsonb_build_object('ok', false, 'error', 'discount_used', 'id', :'kai1'),
               '7 the approval was consumed by that sale: descuento_liberar answers discount_used (security 3)');
select test.eq(test.bill_now484(test.o484(73)) - 'paid' - 'status' - 'voided' - 'parts', jsonb_build_object('total', 11000,
                 'subtotal', 12000, 'discount', 1000, 'discount_id', :'loc73', 'reason', 'Local · not verified', 'by', null,
                 'flags', '["discount_not_verified"]'::jsonb),
               '7 another subtotal (12000 for an approval of 10000): linked, as charged, not verified, only that flag');
select test.eq(test.bill_now484(test.o484(74)) ->> 'total' || '|' || (test.bill_now484(test.o484(74)) ->> 'discount') || '|'
               || (test.bill_now484(test.o484(74)) ->> 'reason'), '5000|5000|Local · not verified',
               '7 a bigger discount than approved is recorded as charged and flagged, never refused (the money is already taken)');
select test.eq(:'s75'::jsonb, '{"ok": true, "already": false, "other_lines": false}'::jsonb,
               '7 the same approval on a second order: the sale is recorded, no error 23505');
select test.eq(test.bill_now484(test.o484(75)), jsonb_build_object('total', 7000, 'subtotal', 10000, 'discount', 3000,
                 'discount_id', null, 'reason', 'Employee · not verified', 'by', null, 'parts', 0,
                 'flags', '["discount_not_verified"]'::jsonb, 'paid', true, 'status', 'done', 'voided', false),
               '7 the second order: the money as charged, unlinked, discount_by null (never "Ana", security 5), flagged');
select test.eq(test.log484('discount_not_verified', test.o484(75)::text), jsonb_build_array(jsonb_build_object('manager_id', null,
                 'manager_name', 'Caja 1', 'summary', 'Employee · approval already used', 'order', test.o484(75),
                 'approval', :'hugo1', 'category', 'empleado', 'why', 'used_by_other', 'subtotal_crc', 10000, 'discount_crc', 3000)),
               '7 audit discount_not_verified {why: used_by_other}');
select test.eq(test.day484(:'hugo1'), 'counts|' || test.o484(70), '7 the approval stays with its first sale');
select test.eq((select count(*)::int from public.orders where id = test.o484(76)) || '|' || test.day484(:'loc76'), '0|counts|no order',
               '7 the refused malformed sales left no order, and their approval unused');
-- an unexpected error inside the check (a test trigger on discount_approvals): the sale is kept as charged, unverified
create function test.boom484() returns trigger language plpgsql as $$
begin
  if new.id::text = coalesce(current_setting('test.boom484', true), '') then raise exception 'test484 forced error'; end if;
  return new;
end $$;
create trigger t484_boom before update on public.discount_approvals for each row execute function test.boom484();
select set_config('test.boom484', :'loc77', true) is not null as armed \gset
select test.cafe484(); set role authenticated;
select test.sale484(test.o484(77), :'loc77', 10000, 1000) as s77 \gset
reset role;
drop trigger t484_boom on public.discount_approvals;
select set_config('test.boom484', '', true) is not null as disarmed \gset
select test.eq((:'s77'::jsonb) ->> 'ok', 'true', '7 an error inside the check never refuses the sale');
select test.eq(test.bill_now484(test.o484(77)) - 'paid' - 'status' - 'voided' - 'parts', jsonb_build_object('total', 9000,
                 'subtotal', 10000, 'discount', 1000, 'discount_id', null, 'reason', 'Local · not verified', 'by', null,
                 'flags', '["discount_not_verified"]'::jsonb),
               '7 it is recorded as charged, unlinked, not verified');
select test.eq(test.log484('discount_check_error', test.o484(77)::text), jsonb_build_array(jsonb_build_object('manager_id', null,
                 'manager_name', 'Caja 1', 'summary', 'discount check failed, sale kept', 'order', test.o484(77), 'sqlstate', 'P0001')),
               '7 audit discount_check_error with the sqlstate only');
select test.eq(test.day484(:'loc77'), 'counts|no order', '7 and the approval is left unused');

-- 8) the time window (proposal §5.1 item 10; §2.6c; D-045's clock case). The approvals' times are moved by the test
--    superuser (a fixture: now() does not move inside one transaction); the sales are rung now ----------------------
select test.calm484();
select test.cafe484(); set role authenticated;
select test.cat484('local') ->> 'id' as late1 \gset
select test.emp484('olga') ->> 'id' as late2 \gset
select test.cat484('local') ->> 'id' as edge1 \gset
select test.cat484('local') ->> 'id' as edge2 \gset
select test.cat484('local') ->> 'id' as edge3 \gset
select test.cat484('local') ->> 'id' as edge4 \gset
select test.cat484('local') ->> 'id' as late3 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old1 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old2 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old3 \gset
reset role;
update public.discount_approvals set created_at = now() - interval '2 hours' where id in (:'late1', :'late2', :'late3', :'old1');
update public.discount_approvals set created_at = now() - interval '30 minutes' where id = :'edge1';
update public.discount_approvals set created_at = now() - interval '30 minutes 1 second' where id = :'edge2';
update public.discount_approvals set created_at = now() + interval '10 minutes' where id = :'edge3';
update public.discount_approvals set created_at = now() + interval '10 minutes 1 second' where id = :'edge4';
update public.discount_approvals set created_at = now() + interval '11 minutes' where id = :'old2';
select test.cafe484(); set role authenticated;
select test.sale484(test.o484(80), :'late1', 10000, 1000) ->> 'ok' as s80 \gset
select test.sale484(test.o484(81), :'late2', 10000, 3000) ->> 'ok' as s81 \gset
select test.sale484(test.o484(82), :'edge1', 10000, 1000) ->> 'ok' as s82 \gset
select test.sale484(test.o484(83), :'edge2', 10000, 1000) ->> 'ok' as s83 \gset
select test.sale484(test.o484(84), :'edge3', 10000, 1000) ->> 'ok' as s84 \gset
select test.sale484(test.o484(85), :'edge4', 10000, 1000) ->> 'ok' as s85 \gset
select test.sale484(test.o484(86), :'late3', 10000, 500) ->> 'ok' as s86 \gset
select test.throws(format('select test.sale484(%L, %L, 10000, 1000)', test.o484(87), :'old1'), '^discount_expired$',
                   '8 an old-kind sale rung 2 hours after its approval: discount_expired, as before 0038');
select test.throws(format('select test.sale484(%L, %L, 10000, 1000)', test.o484(88), :'old2'), '^discount_expired$',
                   '8 an old-kind sale rung 11 minutes before its approval: discount_expired, as before 0038');
select test.sale484(test.o484(89), :'old3', 10000, 1000) ->> 'ok' as s89 \gset
select test.emp484('olga') as olga2 \gset
reset role;
select test.eq(concat_ws('|', :'s80', :'s81', :'s82', :'s83', :'s84', :'s85', :'s86', :'s89'), 'true|true|true|true|true|true|true|true',
               '8 every category sale is recorded, however late (never a refusal)');
select test.eq(test.bill_now484(test.o484(80)) - 'paid' - 'status' - 'voided' - 'parts', jsonb_build_object('total', 9000,
                 'subtotal', 10000, 'discount', 1000, 'discount_id', :'late1', 'reason', 'Local', 'by', 'Ana',
                 'flags', '["discount_late"]'::jsonb),
               '8 a Local sale rung 2 hours late: linked and verified, plus the flag discount_late');
select test.eq(test.bill_now484(test.o484(81)) ->> 'flags' || '|' || (test.bill_now484(test.o484(81)) ->> 'reason') || '|'
               || test.day484(:'late2'), '["discount_late"]|Employee|counts|' || test.o484(81),
               '8 an Empleado sale rung 2 hours late: linked, discount_late, and it holds the day');
select test.eq(:'olga2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Olga", "pending": false}'::jsonb,
               '8 so a new Empleado for Olga is daily_used');
select test.eq(concat_ws(' ', test.bill_now484(test.o484(82)) ->> 'flags', test.bill_now484(test.o484(83)) ->> 'flags',
                         test.bill_now484(test.o484(84)) ->> 'flags', test.bill_now484(test.o484(85)) ->> 'flags'),
               '[] ["discount_late"] [] ["discount_late"]',
               '8 the window''s edges: 30 minutes after is on time, 30 min 1 s is late; 10 minutes before is on time, 10 min 1 s is late');
select test.eq(test.bill_now484(test.o484(86)) ->> 'flags', '["discount_not_verified", "discount_late"]',
               '8 late and not the approved amount: both flags');
select test.eq((select count(*)::int from public.orders where id in (test.o484(87), test.o484(88))) || '|' || test.day484(:'old1')
               || '|' || test.day484(:'old2'), '0|counts|no order|counts|no order', '8 the refused old-kind sales left no order');
select test.eq(test.bill_now484(test.o484(89)) - 'paid' - 'status' - 'voided' - 'parts', jsonb_build_object('total', 9000,
                 'subtotal', 10000, 'discount', 1000, 'discount_id', :'old3', 'reason', 'Regular customer', 'by', 'Ana',
                 'flags', '[]'::jsonb),
               '8 an old-kind sale on time: linked as before 0038');

-- 9) taking it off a bill, and the legacy tab_set_discount guard (proposal §5.1 item 11; §2.5d, §2.6b, W3, V5) ------
-- a) descuento_quitar_cuenta's refusals: each leaves the bill as it was
select test.calm484();
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(90), 'Mesa Pablo') ->> 'ok' as b90 \gset
select test.emp484('pablo', test.o484(90), 10000) ->> 'id' as pablo1 \gset
reset role;
select failed_pins as bea0 from public.staff where id = test.p484('bea') \gset
select test.login('accountant', 'aal2'); set role authenticated;
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1') as q_acct \gset
reset role;
select test.cafe484(); set role authenticated;
select test.fp484() as fp9, test.last484() as l9, test.wrong484() as w9 \gset
select public.descuento_quitar_cuenta(test.o484(90), null, 'Caja 1') as q_null \gset
select public.descuento_quitar_cuenta(test.o484(90), null, 'Caja 1', test.p484('bea'), '0000', 'x') as q_null_pin \gset
select public.descuento_quitar_cuenta(test.o484(999), 10000, 'Caja 1') as q_nf \gset
select public.descuento_quitar_cuenta(:'part11', 2000, 'Caja 1') as q_part \gset
select public.descuento_quitar_cuenta(test.o484(12), 10000, 'Caja 1') as q_void \gset
select public.descuento_quitar_cuenta(test.o484(13), 10000, 'Caja 1') as q_canc \gset
select public.descuento_quitar_cuenta(test.o484(14), 0, 'Caja 1') as q_paid \gset
select public.descuento_quitar_cuenta(test.o484(90), 10000, 'Caja 1') as q_changed \gset
select public.descuento_quitar_cuenta(test.o484(10), 10000, 'Caja 1') as q_none \gset
select public.descuento_quitar_cuenta(test.o484(19), 9000, 'Caja 1') as q_old \gset
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1', null, '4826', 'x') as q_noid \gset
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1', test.o484(998), '4826', 'x') as q_unknown \gset
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1', test.p484('gil'), '4943', 'x') as q_inactive \gset
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1', test.staff('luis'), '5284', 'x') as q_staff \gset
select public.descuento_quitar_cuenta(test.o484(999), 7000, 'Caja 1', test.p484('bea'), '0000', 'x') as q_badpin \gset
select string_agg(public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1', test.p484('hal'), '0000', 'x') ->> 'error', ',') as hal5
  from generate_series(1, 5) \gset
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1', test.p484('hal'), '4942', 'x') as q_locked \gset
select test.fp484() as fp9b, test.kinds484(:l9) as q_rows, test.wrong484() - :w9 as q_wrong \gset
reset role;
select failed_pins as bea1 from public.staff where id = test.p484('bea') \gset
select test.eq(:'q_acct'::jsonb, '{"ok": false, "error": "no_account"}'::jsonb, '9a the accountant login: no_account');
select test.eq(:'q_null'::jsonb, '{"ok": false, "error": "changed"}'::jsonb, '9a p_expect null: changed, nothing removed (V5)');
select test.eq(:'q_null_pin'::jsonb, '{"ok": false, "error": "changed"}'::jsonb, '9a p_expect null with a PIN: changed, before the PIN is tested');
select test.eq(:'q_nf'::jsonb, '{"ok": false, "error": "not_found"}'::jsonb, '9a no such bill: not_found');
select test.eq(:'q_part'::jsonb, '{"ok": false, "error": "not_found"}'::jsonb, '9a a part of a bill: not_found');
select test.eq(:'q_void'::jsonb, '{"ok": false, "error": "cancelled"}'::jsonb, '9a a voided bill: cancelled');
select test.eq(:'q_canc'::jsonb, '{"ok": false, "error": "cancelled"}'::jsonb, '9a a cancelled bill: cancelled');
select test.eq(:'q_paid'::jsonb, '{"ok": false, "error": "already_paid"}'::jsonb, '9a a paid bill: already_paid');
select test.eq(:'q_changed'::jsonb, '{"ok": false, "error": "changed"}'::jsonb, '9a a total the bill no longer has: changed');
select test.eq(:'q_none'::jsonb, '{"ok": false, "error": "not_category"}'::jsonb, '9a a bill with no discount: not_category');
select test.eq(:'q_old'::jsonb, '{"ok": false, "error": "not_category"}'::jsonb, '9a a bill with an old-kind discount: not_category (the page uses tab_set_discount as today)');
select test.eq(:'q_noid'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb, '9a a PIN with no person picked: unknown_staff');
select test.eq(:'q_unknown'::jsonb, '{"ok": false, "error": "unknown_staff"}'::jsonb, '9a a person who is not on the team: unknown_staff');
select test.eq(:'q_inactive'::jsonb, '{"ok": false, "error": "inactive"}'::jsonb, '9a an inactive manager: inactive');
select test.eq(:'q_staff'::jsonb, '{"ok": false, "error": "not_manager"}'::jsonb, '9a Luis (staff) with his own PIN: not_manager');
select test.eq(:'q_badpin'::jsonb, '{"ok": false, "error": "bad_pin"}'::jsonb, '9a a wrong PIN: bad_pin (the PIN is checked before the bill)');
select test.eq(:bea1 - :bea0, 1, '9a the wrong PIN counts on Bea''s own 0033 counter, once (the p_expect-null call never tested it)');
select test.eq(:'hal5'::text || '|' || (:'q_locked'::jsonb ->> 'error'), 'bad_pin,bad_pin,bad_pin,bad_pin,bad_pin|locked',
               '9a five wrong PINs lock Hal (0033); then his right PIN answers locked');
select test.eq(:'fp9b'::text, :'fp9'::text, '9a no order, line or approval changed');
select test.eq(:'q_rows' || '|' || :q_wrong, 'pin_locked|0', '9a the only audit row is Hal''s pin_locked; no discount_code_wrong');
-- b) nothing paid, an Empleado: no PIN, the whole discount comes off, the day still counts (W1, L4)
select test.cafe484(); set role authenticated;
select test.last484() as l9b \gset
select public.descuento_quitar_cuenta(test.o484(90), 7000, 'Caja 1') as q90 \gset
select test.kinds484(:l9b) as q90_rows, test.mark_call484() as q90_mark, test.bill_now484(test.o484(90)) as st90 \gset
select test.emp484('pablo') as pablo2 \gset
select test.cat484('local', test.o484(90), 10000) ->> 'total' as loc90 \gset
reset role;
select test.eq(:'q90'::jsonb, '{"ok": true, "total": 10000, "discount": 0, "paid": false, "beneficiary": "Pablo", "counts": true}'::jsonb,
               '9b descuento_quitar_cuenta with nothing paid: no PIN, the bill back to 10000, counts: true');
select test.eq((:'st90'::jsonb) - 'flags' - 'paid' - 'status' - 'voided', '{"by": null, "parts": 0, "total": 10000, "reason": null, "discount": 0, "subtotal": null, "discount_id": null}'::jsonb,
               '9b the bill carries no discount any more');
select test.eq(test.day484(:'pablo1'), 'counts|' || test.o484(90), '9b the approval keeps its bill, and Pablo''s day still counts');
select test.eq(:'q90_rows' || '|' || :'q90_mark', 'discount_not_freed,tab_discount_removed|', '9b it writes tab_discount_removed and discount_not_freed; the mark is cleared');
select test.eq(test.log484('tab_discount_removed', test.o484(90)::text), jsonb_build_array(jsonb_build_object('manager_id', null,
                 'manager_name', 'Caja 1', 'summary', 'Mesa Pablo', 'discount_crc', 3000, 'total_crc', 10000, 'bill', 'Mesa Pablo',
                 'reason', 'Employee', 'station', 'Caja 1')),
               '9b tab_discount_removed: 3000 taken off, total 10000');
select test.eq(test.log484('discount_not_freed', :'pablo1'), jsonb_build_array(jsonb_build_object('manager_id', null,
                 'manager_name', 'Caja 1', 'summary', 'employee discount still counts until a manager gives the day back',
                 'why', 'needs_manager', 'how', 'bill_removed', 'approval', :'pablo1', 'order', test.o484(90),
                 'beneficiary_name', 'Pablo', 'by_login', :'cafe')),
               '9b discount_not_freed {why: needs_manager, how: bill_removed}');
select test.eq(jsonb_array_length(test.log484('discount_removed_paid', test.o484(90)::text)), 0, '9b and no discount_removed_paid');
select test.eq(:'pablo2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Pablo", "pending": false}'::jsonb,
               '9b a new Empleado for Pablo: daily_used');
select test.eq(:'loc90'::text, '9000', '9b the bill is clean again: a new discount goes on the whole bill (remove, then authorize again)');
-- c) nothing paid, a Local: the answer has no beneficiary, and no day is involved
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(91), 'Mesa Local 2') ->> 'ok' as b91 \gset
select test.cat484('local', test.o484(91), 10000) ->> 'id' as loc91 \gset
select public.descuento_quitar_cuenta(test.o484(91), 9000, 'Caja 1') as q91 \gset
select test.cat484('local') ->> 'id' as tk91 \gset
select test.throws(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o484(91), :'tk91', 'Caja 1'), '^tab_set_discount_category$',
                   '9c right after descuento_quitar_cuenta on this bill, the legacy call still cannot use a category approval on it (the mark does not outlive the call)');
reset role;
select test.eq(:'q91'::jsonb, '{"ok": true, "total": 10000, "discount": 0, "paid": false}'::jsonb, '9c a Local with nothing paid: removed, no beneficiary or counts');
select test.eq(jsonb_array_length(test.log484('discount_not_freed', :'loc91')), 0, '9c no discount_not_freed for a Local (no daily slot)');
select test.eq(test.day484(:'tk91'), 'counts|no order', '9c the ticket approval stayed unused');
-- c2) a late answer taken back by its own approval (p_discount_id, pos.html discTakeBack): only while the bill still
--     carries it. Tablet 1 lost both replies of Local X; tablet 2 took X off with × and put Huésped Y on (the same
--     amount); tablet 1's replay of X's request then gets X's answer with the bill's CURRENT total and discount
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(108), 'Mesa Dos Tabletas') ->> 'ok' as b108 \gset
select test.cat484('local', test.o484(108), 10000, '4826', test.r484(108)) ->> 'id' as x108 \gset
select public.descuento_quitar_cuenta(test.o484(108), 9000, 'Caja 2') ->> 'ok' as off108 \gset
select test.cat484('huesped', test.o484(108), 10000, '4826', test.r484(109)) ->> 'id' as y108 \gset
select public.descuento_autorizar('local', null, 10000, null, null, test.o484(108), 10000, test.r484(108), 'Caja 1') as rep108 \gset
select public.descuento_quitar_cuenta(test.o484(108), (:'rep108'::jsonb ->> 'total')::int, 'Caja 1', null, null, null, :'x108'::uuid) as tb108 \gset
select test.bill_now484(test.o484(108)) as st108 \gset
select public.descuento_quitar_cuenta(test.o484(108), 9000, 'Caja 1', null, null, null, :'y108'::uuid) as tb108y \gset
select test.bill_now484(test.o484(108)) as st108y \gset
reset role;
select test.eq(concat_ws(' ', :'b108', :'off108', ((:'rep108'::jsonb) ->> 'id' = :'x108')::text, (:'rep108'::jsonb) ->> 'replay',
                         (:'rep108'::jsonb) ->> 'total', (:'rep108'::jsonb) ->> 'discount'),
               'true true true true 9000 1000', '9c2 (fixture) X taken off, Y on; the replay of X''s request answers X with the bill''s total now (Y''s)');
select test.eq(:'tb108'::jsonb, '{"ok": false, "error": "not_on_bill"}'::jsonb,
               '9c2 taking the late X back by its id while the bill carries Y: not_on_bill (p_expect alone matched Y''s total)');
select test.eq(concat_ws(' ', ((:'st108'::jsonb) ->> 'discount_id' = :'y108')::text, (:'st108'::jsonb) ->> 'total', (:'st108'::jsonb) ->> 'reason'),
               'true 9000 Hotel guest', '9c2 ... and tablet 2''s Huésped stays on the bill');
select test.eq(concat_ws(' ', (:'tb108y'::jsonb) ->> 'ok', (:'st108y'::jsonb) ->> 'total', coalesce((:'st108y'::jsonb) ->> 'discount_id', '-')),
               'true 10000 -', '9c2 with the id the bill does carry, it comes off as before (and with no id at all, as the older pages send it, too: 9b)');
-- a PIN sent with nothing paid is checked (a wrong one refuses, on that person's own counter), and a right one changes
-- nothing else: removed as without it, no discount_removed_paid (api §4.4)
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(107), 'Mesa Local 4') ->> 'ok' as b107 \gset
select test.cat484('local', test.o484(107), 10000) ->> 'total' as t107 \gset
select public.descuento_quitar_cuenta(test.o484(107), 9000, 'Caja 1', test.p484('bea'), '0000', 'x') as q107a \gset
select test.bill_now484(test.o484(107)) ->> 'total' as t107a \gset
select public.descuento_quitar_cuenta(test.o484(107), 9000, 'Caja 1', test.p484('bea'), '4941', 'x') as q107 \gset
reset role;
select test.eq(:'b107' || '|' || :'t107', 'true|9000', '9c fixture: a Local on a bill (9000), nothing paid');
select test.eq(:'q107a'::jsonb || jsonb_build_object('total', :'t107a'::int), '{"ok": false, "error": "bad_pin", "total": 9000}'::jsonb,
               '9c a wrong PIN sent with nothing paid: bad_pin, nothing removed');
select test.eq(:'q107'::jsonb, '{"ok": true, "total": 10000, "discount": 0, "paid": false}'::jsonb, '9c Bea''s right PIN with nothing paid: removed, paid false');
select test.eq(jsonb_array_length(test.log484('discount_removed_paid', test.o484(107)::text)), 0, '9c and no discount_removed_paid row');
select test.eq((select failed_pins from public.staff where id = test.p484('bea')), 0, '9c the PIN was verified (a right PIN clears Bea''s 0033 count)');
-- d) after one item paid by item: a manager's PIN and a reason; the paid item keeps its share; the day stays used
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(92), 'Mesa Luis') ->> 'ok' as b92 \gset
select test.emp484('luis', test.o484(92), 10000) ->> 'id' as luis1 \gset
select test.payitem484(test.o484(92)) ->> 'amount' as p92 \gset
select public.descuento_quitar_cuenta(test.o484(92), 4200, 'Caja 1') as q92a \gset
select public.descuento_quitar_cuenta(test.o484(92), 4200, 'Caja 1', test.staff('ana'), '4826') as q92b \gset
select public.descuento_quitar_cuenta(test.o484(92), 4200, 'Caja 1', test.staff('ana'), '4826', '   ') as q92c \gset
select test.bill_now484(test.o484(92)) as st92a, test.last484() as l92 \gset
select public.descuento_quitar_cuenta(test.o484(92), 4200, 'Caja 1', test.staff('ana'), '4826', '  el cliente se quejó  ') as q92 \gset
select test.bill_now484(test.o484(92)) as st92, test.kinds484(:l92) as q92_rows \gset
select test.emp484('luis') as luis2 \gset
select test.both484('local', test.o484(92), 10000, 6000) as again92 \gset
reset role;
select test.eq(:'b92' || '|' || :'p92', 'true|2800', '9d fixture: Luis''s bill, the Latte paid by item (4000 less its 30 %)');
select test.eq(:'q92a'::jsonb, '{"ok": false, "error": "needs_pin"}'::jsonb, '9d without a PIN: needs_pin');
select test.eq(:'q92b'::jsonb, '{"ok": false, "error": "missing_reason"}'::jsonb, '9d Ana''s PIN, no reason: missing_reason');
select test.eq(:'q92c'::jsonb, '{"ok": false, "error": "missing_reason"}'::jsonb, '9d a blank reason: missing_reason');
select test.eq((:'st92a'::jsonb) ->> 'discount_id' || '|' || ((:'st92a'::jsonb) ->> 'total'), :'luis1' || '|4200', '9d after those refusals the bill still carries it');
select test.eq(:'q92'::jsonb, '{"ok": true, "total": 6000, "discount": 1200, "paid": true, "beneficiary": "Luis", "counts": true}'::jsonb,
               '9d with Ana''s PIN and a reason: removed; the paid Latte keeps its 1200; counts: true');
select test.eq((:'st92'::jsonb) - 'flags' - 'paid' - 'status' - 'voided', jsonb_build_object('total', 6000, 'subtotal', 10000,
                 'discount', 1200, 'discount_id', null, 'reason', 'Employee', 'by', 'Ana', 'parts', 2800),
               '9d the bill: unlinked, the 1200 the paid item got stays, the rest charged in full (6000 left)');
select test.eq(:'q92_rows'::text, 'discount_not_freed,discount_removed_paid,tab_discount_removed', '9d it writes discount_removed_paid, tab_discount_removed and discount_not_freed');
select test.eq(test.log484('discount_removed_paid', test.o484(92)::text), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'el cliente se quejó', 'approval', :'luis1', 'category', 'empleado',
                 'beneficiary_name', 'Luis', 'reason', 'el cliente se quejó', 'discount_kept', 1200, 'total_crc', 6000,
                 'bill', 'Mesa Luis', 'station', 'Caja 1', 'by_login', :'cafe')),
               '9d discount_removed_paid names Ana, the trimmed reason and what the paid item kept');
select test.eq(test.log484('discount_not_freed', :'luis1') -> 0 ->> 'why', 'paid', '9d discount_not_freed {why: paid}');
select test.eq(test.day484(:'luis1'), 'counts|' || test.o484(92), '9d the day stays used');
select test.eq(:'luis2'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Luis", "pending": false}'::jsonb,
               '9d a new Empleado for Luis: daily_used (security 4)');
select test.eq(:'again92'::text, 'has_parts|has_parts', '9d and that bill takes no new discount: has_parts');
-- e) paid on account only (no line paid): a PIN too; nothing is kept by the money on account
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(93), 'Mesa a cuenta 2') ->> 'ok' as b93 \gset
select test.cat484('local', test.o484(93), 10000) ->> 'id' as loc93 \gset
select test.payacct484(test.o484(93), 2000) ->> 'left' as p93 \gset
select public.descuento_quitar_cuenta(test.o484(93), 7000, 'Caja 1') as q93a \gset
select public.descuento_quitar_cuenta(test.o484(93), 7000, 'Caja 1', test.staff('ana'), '4826', 'pagó aparte ' || repeat('x', 200)) as q93 \gset
reset role;
select test.eq(:'b93' || '|' || :'p93', 'true|7000', '9e fixture: a Local bill (9000), 2000 paid on account');
select test.eq(:'q93a'::jsonb, '{"ok": false, "error": "needs_pin"}'::jsonb, '9e money paid on account: needs_pin');
select test.eq(:'q93'::jsonb, '{"ok": true, "total": 8000, "discount": 0, "paid": true}'::jsonb, '9e with Ana''s PIN and a reason: removed, 8000 left');
select test.eq((test.log484('discount_removed_paid', test.o484(93)::text) -> 0) - 'manager_id' - 'by_login',
               jsonb_build_object('manager_name', 'Ana', 'summary', left('pagó aparte ' || repeat('x', 200), 160), 'approval', :'loc93',
                 'category', 'local', 'beneficiary_name', null, 'reason', left('pagó aparte ' || repeat('x', 200), 160),
                 'discount_kept', 0, 'total_crc', 8000, 'bill', 'Mesa a cuenta 2', 'station', 'Caja 1'),
               '9e discount_removed_paid for the Local, with no beneficiary, and the reason cut to 160 characters');
-- f) a part paid on another device after the page read the bill (V5): the old total is changed; the new total without
--    a PIN is needs_pin; nothing is removed
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(94), 'Mesa Quim') ->> 'ok' as b94 \gset
select test.emp484('quim', test.o484(94), 10000) ->> 'total' as t94 \gset
select test.payitem484(test.o484(94)) ->> 'left' as p94 \gset
select public.descuento_quitar_cuenta(test.o484(94), 7000, 'Caja 1') as q94a \gset
select public.descuento_quitar_cuenta(test.o484(94), 4200, 'Caja 1') as q94b \gset
select test.bill_now484(test.o484(94)) as st94 \gset
reset role;
select test.eq(:'t94' || '|' || :'p94', '7000|4200', '9f fixture: the page shows 7000; another device takes a payment by item (4200 left)');
select test.eq(:'q94a'::jsonb, '{"ok": false, "error": "changed"}'::jsonb, '9f sent with the total the page read: changed');
select test.eq(:'q94b'::jsonb, '{"ok": false, "error": "needs_pin"}'::jsonb, '9f sent with the new total and no PIN: needs_pin (decided under the bill''s lock)');
select test.eq((:'st94'::jsonb) ->> 'discount' || '|' || ((:'st94'::jsonb) ->> 'total'), '3000|4200', '9f nothing removed');
select test.eq(jsonb_array_length(test.log484('discount_removed_paid', test.o484(94)::text))
               + jsonb_array_length(test.log484('tab_discount_removed', test.o484(94)::text)), 0, '9f no discount_removed_paid or tab_discount_removed row');
-- g) cancel_unpaid_order: cancelled with no PIN, the day still counts until a manager gives it back
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(95), 'Mesa Raul') ->> 'ok' as b95 \gset
select test.emp484('raul', test.o484(95), 10000) ->> 'id' as raul1 \gset
select public.cancel_unpaid_order(test.o484(95)) as c95 \gset
select test.emp484('raul') as raul2 \gset
reset role;
select test.eq(:'c95'::jsonb || jsonb_build_object('status', test.bill_now484(test.o484(95)) ->> 'status'), '{"ok": true, "status": "cancelled"}'::jsonb,
               '9g cancel_unpaid_order on the discounted bill: cancelled, no PIN');
select test.eq(test.day484(:'raul1'), 'counts|' || test.o484(95), '9g the day still counts');
select test.eq(test.log484('discount_not_freed', :'raul1') -> 0 ->> 'why' || '|' || (test.log484('discount_not_freed', :'raul1') -> 0 ->> 'how'),
               'needs_manager|bill_cancelled', '9g discount_not_freed {why: needs_manager, how: bill_cancelled}');
select test.eq(:'raul2'::jsonb ->> 'error', 'daily_used', '9g a new Empleado for Raúl: daily_used');
-- h) a void of a bill with a paid part: the void stands, the day is not freed (money 5)
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(96), 'Mesa Sara') ->> 'ok' as b96 \gset
select test.emp484('sara', test.o484(96), 10000) ->> 'id' as sara1 \gset
select test.payitem484(test.o484(96)) ->> 'ok' as p96 \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o484(96), 'se fueron sin pagar') as v96 \gset
select test.emp484('sara') as sara2 \gset
reset role;
select test.eq(:'v96'::jsonb, '{"ok": true}'::jsonb, '9h Ana voids Sara''s bill after the Latte was paid by item: the void stands');
select test.eq(test.day484(:'sara1'), 'counts|' || test.o484(96), '9h the day is not freed');
select test.eq(test.log484('discount_not_freed', :'sara1'), jsonb_build_array(jsonb_build_object('manager_id', test.staff('ana'),
                 'manager_name', 'Ana', 'summary', 'employee discount still counts: paid parts remain', 'why', 'parts', 'how', 'void',
                 'approval', :'sara1', 'order', test.o484(96), 'beneficiary_name', 'Sara', 'by_login', :'cafe')),
               '9h discount_not_freed {why: parts, how: void} names Ana');
select test.eq(:'sara2'::jsonb ->> 'error', 'daily_used', '9h a new Empleado for Sara: daily_used');
-- i) the legacy tab_set_discount: never puts a category approval on a bill, never takes a category discount off after a
--    payment, never replaces one; with nothing paid it takes one off as today (W3)
select test.calm484();
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(97), 'Mesa limpia 2') ->> 'ok' as b97 \gset
select test.cat484('local') ->> 'id' as tk97 \gset
select test.cat484('local') ->> 'id' as rel97 \gset
select public.descuento_liberar(:'rel97') ->> 'ok' as lib97 \gset
select test.bill484(test.o484(98), 'Mesa Tomas') ->> 'ok' as b98 \gset
select test.emp484('tomas', test.o484(98), 10000) ->> 'id' as tomas1 \gset
select test.payitem484(test.o484(98)) ->> 'left' as p98 \gset
select test.bill484(test.o484(99), 'Mesa a cuenta 3') ->> 'ok' as b99 \gset
select test.cat484('local', test.o484(99), 10000) ->> 'id' as loc99 \gset
select test.payacct484(test.o484(99), 2000) ->> 'left' as p99 \gset
select test.bill484(test.o484(100), 'Mesa Local 3') ->> 'ok' as b100 \gset
select test.cat484('local', test.o484(100), 10000) ->> 'id' as loc100 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 20, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old100 \gset
select test.fp484() as fp9i, test.last484() as l9i \gset
select test.throws(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o484(97), :'tk97', 'Caja 1'), '^tab_set_discount_category$',
                   '9i a ticket category approval put on a bill through the legacy call: tab_set_discount_category');
select test.throws(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o484(97), :'rel97', 'Caja 1'), '^tab_set_discount_category$',
                   '9i a let-go category approval re-applied to a bill: tab_set_discount_category');
select test.throws(format('select public.tab_set_discount(%L, null, 4200, %L)', test.o484(98), 'Caja 1'), '^tab_set_discount_category$',
                   '9i a category discount taken off after a payment by item, without the manager''s PIN: tab_set_discount_category');
select test.throws(format('select public.tab_set_discount(%L, null, 7000, %L)', test.o484(99), 'Caja 1'), '^tab_set_discount_category$',
                   '9i the same after a payment on account: tab_set_discount_category');
select test.throws(format('select public.tab_set_discount(%L, %L, 9000, %L)', test.o484(100), :'old100', 'Caja 1'), '^tab_set_discount_category$',
                   '9i an old-kind approval over a category discount: tab_set_discount_category');
select test.throws(format('select public.tab_set_discount(%L, %L, 9000, %L)', test.o484(100), :'loc100', 'Caja 1'), '^tab_set_discount_category$',
                   '9i the bill''s own category approval applied again: tab_set_discount_category');
select public.tab_set_discount(test.o484(100), null, 1234, 'Caja 1') as g_changed \gset
select test.err484(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o484(97), :'tk97', 'Caja 1')) as g_err \gset
select test.fp484() as fp9i2, test.since484(:l9i) as g_rows \gset
reset role;
select test.eq(:'g_err'::text, 'P0001:tab_set_discount_category',
               '9i the guard raises with SQLSTATE P0001 and the message tab_set_discount_category (an old page reads it as «needs a database update», /tab_/)');
select test.eq(concat_ws('|', :'b97', :'lib97', :'b98', :'p98', :'b99', :'p99', :'b100'), 'true|true|true|4200|true|7000|true',
               '9i fixtures: a clean bill, a ticket approval, a let-go one, bills with a category discount and a payment, one with nothing paid');
select test.eq(:'g_changed'::jsonb, '{"ok": false, "error": "changed"}'::jsonb, '9i the guard comes after the bill''s own checks: a wrong total is changed, as today');
select test.eq(:'fp9i2'::text || '|' || :'g_rows', :'fp9i'::text || '|', '9i every refused call changed nothing and wrote nothing');
select test.eq(concat_ws(' ', test.day484(:'tk97'), test.day484(:'rel97'), test.day484(:'old100')), 'counts|no order released|no order counts|no order',
               '9i the refused approvals are where they were (unused, let go, unused)');
-- nothing paid: the old page's × still takes a category discount off (W3), and the day still counts
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(101), 'Mesa Uma') ->> 'ok' as b101 \gset
select test.emp484('uma', test.o484(101), 10000) ->> 'id' as uma1 \gset
select test.last484() as l101 \gset
select public.tab_set_discount(test.o484(101), null, 7000, 'Caja 1') as w3 \gset
select test.kinds484(:l101) as w3_rows, test.bill_now484(test.o484(101)) as st101 \gset
select test.emp484('uma') as uma2 \gset
select test.throws(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o484(101), :'uma1', 'Caja 1'), '^tab_set_discount_category$',
                   '9i the approval taken off cannot go back on its bill through the legacy call');
reset role;
select test.eq(:'w3'::jsonb, '{"ok": true, "total": 10000, "discount": 0}'::jsonb, '9i the legacy tab_set_discount(bill, null) with nothing paid: removed as today (W3)');
select test.eq((:'st101'::jsonb) - 'flags' - 'paid' - 'status' - 'voided', '{"by": null, "parts": 0, "total": 10000, "reason": null, "discount": 0, "subtotal": null, "discount_id": null}'::jsonb,
               '9i the bill is back to 10000 with no discount');
select test.eq(:'w3_rows'::text, 'discount_not_freed,tab_discount_removed', '9i tab_discount_removed is written, and discount_not_freed');
select test.eq(test.log484('discount_not_freed', :'uma1') -> 0 ->> 'why' || '|' || (test.log484('discount_not_freed', :'uma1') -> 0 ->> 'how'),
               'needs_manager|bill_removed', '9i discount_not_freed {why: needs_manager, how: bill_removed}');
select test.eq(test.day484(:'uma1') || '|' || (:'uma2'::jsonb ->> 'error'), 'counts|' || test.o484(101) || '|daily_used', '9i the day still counts: daily_used');
-- old-kind approvals: set and taken off as before 0038, after a payment too; used elsewhere or expired, as before
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(103), 'Mesa vieja 2') ->> 'ok' as b103 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old103 \gset
select public.tab_set_discount(test.o484(103), :'old103', 10000, 'Caja 1') as os1 \gset
select test.bill_now484(test.o484(103)) as st103a \gset
select public.tab_set_discount(test.o484(103), null, 9000, 'Caja 1') as os2 \gset
select test.bill_now484(test.o484(103)) as st103b \gset
select test.bill484(test.o484(104), 'Mesa vieja 3') ->> 'ok' as b104 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old104 \gset
select public.tab_set_discount(test.o484(104), :'old104', 10000, 'Caja 1') ->> 'total' as os3 \gset
select test.payitem484(test.o484(104)) ->> 'left' as p104 \gset
select public.tab_set_discount(test.o484(104), null, 5400, 'Caja 1') as os4 \gset
select test.bill484(test.o484(106), 'Mesa vieja 4') ->> 'ok' as b106 \gset
select public.tab_set_discount(test.o484(106), :'old103', 10000, 'Caja 1') as os5 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 1') ->> 'id' as old106 \gset
reset role;
update public.discount_approvals set created_at = now() - interval '31 minutes' where id = :'old106';
select test.cafe484(); set role authenticated;
select public.tab_set_discount(test.o484(106), :'old106', 10000, 'Caja 1') as os6 \gset
reset role;
select test.eq(:'os1'::jsonb, '{"ok": true, "total": 9000, "discount": 1000}'::jsonb, '9j an old-kind approval goes on a bill as before 0038');
select test.eq((:'st103a'::jsonb) ->> 'reason' || '|' || ((:'st103a'::jsonb) ->> 'by') || '|' || ((:'st103a'::jsonb) ->> 'discount_id'),
               'Regular customer|Ana|' || :'old103', '9j with its reason and Ana');
select test.eq(:'os2'::jsonb, '{"ok": true, "total": 10000, "discount": 0}'::jsonb, '9j and comes off as before');
select test.eq((:'st103b'::jsonb) ->> 'discount_id', null, '9j the bill no longer carries it');
select test.eq(:'os3' || '|' || :'p104' || '|' || (:'os4'::jsonb)::text, '9000|5400|{"ok": true, "total": 6000, "discount": 400}',
               '9j after a payment by item an old-kind discount still comes off with the legacy call, the paid item keeping its 400 (as before 0038)');
select test.eq(:'os5'::jsonb, '{"ok": false, "error": "discount_used"}'::jsonb, '9j an old-kind approval used by another bill: discount_used, as before');
select test.eq(:'os6'::jsonb, '{"ok": false, "error": "discount_expired"}'::jsonb, '9j an old-kind approval 31 minutes old: discount_expired, as before');
-- k) items added later are charged in full; items taken off follow the rate (_tab_discount)
select test.cafe484(); set role authenticated;
select test.bill484(test.o484(105), 'Mesa Vera') ->> 'ok' as b105 \gset
select test.emp484('vera', test.o484(105), 10000) ->> 'total' as t105 \gset
select public.tab_add_items(test.o484(105), jsonb_build_array(jsonb_build_object('menu_item_id', :'tea', 'qty', 1))) ->> 'total' as add105 \gset
select test.bill_now484(test.o484(105)) as st105a \gset
select public.tab_remove_item(test.item484(test.o484(105), 2), 1, 'se equivocó', 'Caja 1', null, null, 8000) ->> 'ok' as rm105 \gset
select test.bill_now484(test.o484(105)) as st105b \gset
reset role;
select test.eq(:'t105' || '|' || :'add105', '7000|8000', '9k a Tea (1000) added to Vera''s discounted bill is charged in full: 7000 + 1000');
select test.eq((:'st105a'::jsonb) ->> 'subtotal' || '|' || ((:'st105a'::jsonb) ->> 'discount'), '11000|3000', '9k the discount stays at what Ana approved (3000)');
select test.eq(:'rm105' || '|' || ((:'st105b'::jsonb) ->> 'subtotal') || '|' || ((:'st105b'::jsonb) ->> 'discount') || '|'
               || ((:'st105b'::jsonb) ->> 'total'), 'true|5000|1500|3500',
               '9k the Ham & Cheese taken off: the discount follows the rate down (30 % of 5000 = 1500), total 3500');

-- 10) across the whole file ------------------------------------------------------------------------------------------
select test.eq((select count(*)::int from public.audit_log
                 where id > :audit_start and (test.pins484(details) > 0 or summary in (select pin from test.t484_people))), 0,
               '10 no audit row written in this file holds a test PIN');
select test.eq(test.wrong484(), 1, '10 the only counted wrong code is section 1''s control: no refusal, replay or removal counted one');
select test.eq(test.n484('discount_trigger_error'), 0, '10 no discount_trigger_error anywhere');
select test.eq(test.n484('discount_check_error'), 1, '10 one discount_check_error: the forced one of section 7');
select test.eq(test.locked484('canopy.discount_tills'), false, '10 nothing in this file took the café-wide tills lock');
select test.eq(test.mark_call484(), '', '10 the mark is not left set');

select test.done();
rollback;
