-- Migration 0038 (D-065): the discounts report, descuentos_informe (proposal §2.5e, §4 and §5.1 item 16; build plan L5
-- «486»; mecanismo-intentos §10.5 for its wrong-code block; api-0038 §4.6 and §13 items 14-15 where the sources are
-- silent). Who reads it: the sales permission or the books (the owner with the phone code, a manager allowed to see
-- sales, the accountant), never the café login alone; there is no is_cafe(), so the accountant reads it. One row per
-- approval: category approvals by their Costa Rica day, old-kind ones by the Costa Rica day they were made, ordered by
-- time; each with exactly one status code of §2.5e (the first rule that applies, V7), what was charged (the payments,
-- parts included, given-back parts netting out, refunds apart: money 8) and the products covered (the lines at the
-- discount; later adds apart, the row «partial»). Totals by category, employee, authorizer with role and company over
-- the discounts given; the courtesies' list value by stamped IVA rate (information only, A-13); the sales that used an
-- approval another order had already used, listed apart (P4); and, per Costa Rica day, the block «Códigos
-- equivocados» of mecanismo §10.5 (by step and why; per place: stations, wrong codes, waits started, stops, resumes
-- and who, sign-outs, rebinds; registrations and endings; shared codes; unregistered devices and their names; alerts;
-- approvals with person_locked; no pause fields). Everything is produced through the real functions as the café login
-- (authenticated, with a session_id) on tills registered through descuento_caja_registrar; the few direct writes move
-- a time (now() does not move inside one transaction) or set a state no function leaves, and each says so. The report
-- itself writes nothing. Test PINs only (the seed's and this file's).
begin;

-- people: the seed (Ana manager 4826, Luis 5284 and Marta 6173 staff, Dueño owner 7391) plus this file's: Bea, Ciro and
-- Hal (managers, 3941-3943), Pablo (staff, given Marta's PIN on purpose: a code shared by two people, D-053; written
-- directly, as the team editor refuses a shared PIN since 0033) and one employee per Empleado case, so no
-- case shares a day with another (8605-8617). Cost 4 keeps each code's single bcrypt pass over every active PIN short
create table test.t486_people (name text primary key, id uuid not null, pin text not null, role text not null);
grant select on test.t486_people to authenticated;
insert into test.t486_people values
  ('ana', test.staff('ana'), '4826', 'manager'), ('luis', test.staff('luis'), '5284', 'staff'),
  ('marta', test.staff('marta'), '6173', 'staff'), ('dueno', test.staff('dueno'), '7391', 'owner');
insert into test.t486_people (name, id, pin, role)
  select n, ('b4860000-0000-4000-8000-' || lpad(o::text, 12, '0'))::uuid,
         case n when 'bea' then '3941' when 'ciro' then '3942' when 'hal' then '3943' when 'pablo' then '6173'
                else (8600 + o)::text end,
         case when n in ('bea', 'ciro', 'hal') then 'manager' else 'staff' end
    from unnest(array['bea', 'ciro', 'hal', 'pablo', 'abel', 'beto', 'cata', 'dino', 'elio', 'fara', 'gala', 'hugo',
                      'iker', 'jana', 'kira', 'lalo', 'mora']) with ordinality u(n, o);
insert into public.staff (id, name, role, active, pin_hash)
  select id, initcap(name), role, true, extensions.crypt(pin, extensions.gen_salt('bf', 4))
    from test.t486_people where name not in ('ana', 'luis', 'marta', 'dueno');
create function test.p486(n text) returns uuid language sql stable as $$ select id from test.t486_people where name = n $$;
create function test.k486(n text) returns text language sql stable as $$ select pin from test.t486_people where name = n $$;
-- order ids and request ids of this file
create function test.o486(n int) returns uuid language sql immutable as $$ select ('d4860000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.r486(n int) returns uuid language sql immutable as $$ select ('e4860000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
\set cafe_uid 'c0000000-0000-4000-8000-000000000001'

-- the devices: their current sign-in (session id), the name the page reports as its station (device C reports
-- «Tablet C», though it was registered as «Caja C»: the report names a place by its registered till), and the device
-- key the page keeps once the device is registered
create table test.dv486 (dev text primary key, sess text not null, station text not null, key text);
grant all on test.dv486 to authenticated;
insert into test.dv486 (dev, sess, station) values
  ('A', 'sess-486-a1', 'Caja A'), ('B', 'sess-486-b1', 'Caja B'), ('C', 'sess-486-c1', 'Tablet C'),
  ('D', 'sess-486-d1', 'Caja D'), ('E', 'sess-486-e1', 'Caja E');
-- a sign-in of the café login (test.login resets the claims and the unlock header; test.session gives it its id)
create function test.dev486(p_sess text) returns void language sql as $$ select test.login('cafe'); select test.session(p_sess) $$;
-- on that sign-in a person opens the owner areas with their PIN (0033 binds the unlock to the sign-in)
create function test.open486(p_sess text, p_who text) returns jsonb language sql as $$
  select test.dev486(p_sess); select test.unlock(test.p486(p_who), test.k486(p_who)) $$;
-- the discount window's call on a device, as pos.html sends it (its name as the station)
create function test.w486(p_dev text, p_cat text, p_pin text, p_emp text default null, p_sub int default 1000,
                          p_comp text default null, p_bill uuid default null, p_expect int default null,
                          p_req uuid default null) returns jsonb language plpgsql as $$
declare d test.dv486;
begin
  select * into d from test.dv486 where dev = p_dev;
  perform test.dev486(d.sess);
  return public.descuento_autorizar(p_cat, p_pin, p_sub, p_emp, p_comp, p_bill, p_expect, p_req, d.station);
end $$;
-- at till A: one code (Local, Huésped, Guía), or an Empleado with Ana's code and the employee's
create function test.cat486(p_cat text, p_sub int, p_pin text default '4826', p_bill uuid default null,
                            p_expect int default null, p_comp text default null, p_req uuid default null) returns jsonb
language sql as $$ select test.w486('A', p_cat, p_pin, null, p_sub, p_comp, p_bill, p_expect, p_req) $$;
create function test.emp486(p_who text, p_sub int, p_bill uuid default null, p_expect int default null) returns jsonb
language sql as $$ select test.w486('A', 'empleado', '4826', test.k486(p_who), p_sub, null, p_bill, p_expect) $$;
-- a line as the till sends it, and as the report should list it ({name, qty, price, tax_rate}: the rate stamped from the
-- menu, 13 % for every product of the seed menu)
create function test.it486(p_name text, p_price int, p_qty int default 1) returns jsonb language sql immutable as $$
  select jsonb_build_object('item_name', p_name, 'price_crc', p_price, 'qty', p_qty) $$;
create function test.ln486(p_name text, p_price int, p_qty int default 1, p_rate numeric default 0.13) returns jsonb
language sql immutable as $$ select jsonb_build_object('name', p_name, 'qty', p_qty, 'price', p_price, 'tax_rate', p_rate) $$;
-- a paid ticket carrying an approval, as pos.html sends it (pos_record_sale)
create function test.tk486(p_id uuid, p_appr text, p_lines jsonb, p_disc int, p_method text default 'cash_crc') returns jsonb
language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p_id, 'created_at', now(), 'total_crc', x.sub - p_disc,
           'payment_method', p_method, 'paid', true, 'status', 'done', 'station', 'Caja A', 'guest_name', 'Ticket 486',
           'subtotal_crc', x.sub, 'discount_crc', p_disc, 'discount_id', p_appr, 'items', p_lines))
    from (select sum((e ->> 'price_crc')::int * (e ->> 'qty')::int)::int as sub from jsonb_array_elements(p_lines) e) x $$;
-- an open «Pay later» bill (or a room bill from the live bar), its line ids derived from its id; one guest pays line n
-- by item; the last payment closes it
create function test.li486(p_bill uuid, n int) returns uuid language sql immutable as $$ select md5(p_bill::text || '-' || n)::uuid $$;
create function test.bill486(p_bill uuid, guest text, p_lines jsonb, p_src text default 'front',
                             p_at timestamptz default now()) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p_bill, 'created_at', p_at, 'total_crc', x.tot,
           'payment_method', 'pending', 'paid', false, 'status', case when p_src = 'room' then 'new' else 'ready' end,
           'station', 'Caja A', 'source', p_src, 'guest_name', guest, 'items', x.items))
    from (select jsonb_agg(e || jsonb_build_object('id', test.li486(p_bill, o::int)) order by o) as items,
                 sum((e ->> 'price_crc')::int * (e ->> 'qty')::int)::int as tot
            from jsonb_array_elements(p_lines) with ordinality l(e, o)) x $$;
create function test.payitem486(p_bill uuid, n int default 1) returns jsonb language sql as $$
  select public.tab_pay(p_bill, 'cash_crc', jsonb_build_array(jsonb_build_object('item_id', test.li486(p_bill, n), 'qty', 1)),
                        null, 'Caja A') $$;
create function test.payall486(p_bill uuid) returns jsonb language sql as $$
  select public.tab_pay(p_bill, 'cash_crc', null, null, 'Caja A') $$;
create function test.void486(p_id uuid, p_who text default 'ana') returns jsonb language sql as $$
  select public.manager_void_order(test.p486(p_who), test.k486(p_who), p_id, 'prueba 486') $$;

-- what each approval of this file should look like in the report (written by hand from the fixture, never computed
-- by the report's rules): its status, whether it counts as given, the money, the products, the order and bill it is on
create table test.fx486 (n serial primary key, tag text unique not null, what text not null, id uuid not null,
  in_range boolean not null default true, day date not null default public.cr_today(), status text not null,
  given boolean not null, category text, beneficiary text, company text, authorizer text, role text, kind text, value int,
  reason text, station text, freed_how text, list_value int, discount int, charged int, refunded int not null default 0,
  flags jsonb not null default '[]', products jsonb not null default '[]', added_after jsonb not null default '[]',
  order_id uuid, bill_id uuid);
-- a category approval: its rate and English label by category, the authorizer's role by who typed the code
create function test.fx486(p_tag text, p_what text, p_id text, p_status text, p_cat text, p_list int, p_disc int,
    p_charged int, p_given boolean, p_products jsonb default '[]', p_order uuid default null, p_bill uuid default null,
    p_ben text default null, p_comp text default null, p_auth text default 'Ana', p_freed text default null,
    p_flags jsonb default '[]', p_refunded int default 0, p_after jsonb default '[]') returns void language sql as $$
  insert into test.fx486 (tag, what, id, status, given, category, beneficiary, company, authorizer, role, kind, value, reason,
                          station, freed_how, list_value, discount, charged, refunded, flags, products, added_after, order_id, bill_id)
  values (p_tag, p_what, p_id::uuid, p_status, p_given, p_cat, p_ben, p_comp, p_auth,
          case when p_auth = 'Dueño' then 'owner' else 'manager' end, 'percent',
          case p_cat when 'empleado' then 30 when 'guia' then 100 else 10 end,
          case p_cat when 'empleado' then 'Employee' when 'local' then 'Local' when 'huesped' then 'Hotel guest' else 'Tour guide' end,
          'Caja A', p_freed, p_list, p_disc, p_charged, p_refunded, p_flags, p_products, p_after, p_order, p_bill) $$;

-- the reports this file reads (each call made as the login named, then kept here) and readers of them
create table test.reps486 (name text primary key, j jsonb);
grant all on test.reps486 to authenticated;
create function test.rep486(p_name text) returns jsonb language sql stable as $$ select j from test.reps486 where name = p_name $$;
create function test.row486(p_rep text, p_id uuid) returns jsonb language sql stable as $$
  select x from jsonb_array_elements(test.rep486(p_rep) -> 'rows') x where x ->> 'id' = p_id::text limit 1 $$;
create function test.wday486(p_rep text, p_day date) returns jsonb language sql stable as $$
  select x from jsonb_array_elements(test.rep486(p_rep) -> 'wrong_codes') x where (x ->> 'day')::date = p_day limit 1 $$;
create function test.place486(p_rep text, p_day date, p_slot int) returns jsonb language sql stable as $$
  select x from jsonb_array_elements(test.wday486(p_rep, p_day) -> 'places') x where x ->> 'slot' = p_slot::text limit 1 $$;
-- a list of lines in a fixed order (the report orders by when each line was added; lines of one sale share that time)
create function test.sort486(j jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(e order by e ->> 'name', (e ->> 'price')::int, (e ->> 'qty')::int), '[]') from jsonb_array_elements(j) e $$;
create function test.sortby486(j jsonb, k1 text, k2 text default null) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(e order by e ->> k1 nulls first, e ->> k2 nulls first), '[]') from jsonb_array_elements(j) e $$;
-- the list's objects without their time (checked apart)
create function test.noat486(j jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(e - 'at' order by o), '[]') from jsonb_array_elements(j) with ordinality x(e, o) $$;
-- every key and every string value anywhere in a report
create function test.walk486(j jsonb) returns table (k text, v text) language plpgsql immutable as $$
declare e record;
begin
  if jsonb_typeof(j) = 'object' then
    for e in select * from jsonb_each(j) loop
      k := e.key; v := null; return next;
      return query select * from test.walk486(e.value);
    end loop;
  elsif jsonb_typeof(j) = 'array' then
    for e in select value from jsonb_array_elements(j) loop
      return query select * from test.walk486(e.value);
    end loop;
  elsif jsonb_typeof(j) = 'string' then
    k := null; v := j #>> '{}'; return next;
  end if;
end $$;
-- the Costa Rica day 0038 was applied on (the report's applied_0038): the main range starts there, so an old-kind
-- approval made before 0038 is in it whatever the time of day this file runs
select (applied_at at time zone 'America/Costa_Rica')::date as d_lo, applied_at as m38 from canopy.migrations where version = 38 \gset
select public.cr_today() as today, public.cr_today() - 2 as d2 \gset

-- 1) two days ago (D2): three tills registered, waits, two stops, three kinds of resume, a rebind, the café alert, a
--    code from an unregistered device. Done first, with the clock moved back between steps (test.back), then every row
--    moved to D2's evening (23:30 Costa Rica time at the latest: the later rows are already the next day in UTC, so
--    the days are Costa Rica days; still more than 24 hours before now, so today's places start clean) ------------
set role authenticated;
select test.open486('sess-486-a1', 'ana');
select public.descuento_caja_registrar('Caja A') as reg_a \gset
select test.open486('sess-486-b1', 'ana');
select public.descuento_caja_registrar('Caja B') as reg_b \gset
select test.open486('sess-486-c1', 'bea');
select public.descuento_caja_registrar('Caja C') as reg_c \gset
reset role;
update test.dv486 set key = (:'reg_a'::jsonb) ->> 'key' where dev = 'A';
update test.dv486 set key = (:'reg_b'::jsonb) ->> 'key' where dev = 'B';
update test.dv486 set key = (:'reg_c'::jsonb) ->> 'key' where dev = 'C';
select test.eq((:'reg_a'::jsonb) ->> 'slot' || '|' || ((:'reg_b'::jsonb) ->> 'slot') || '|' || ((:'reg_c'::jsonb) ->> 'slot')
               || '|' || ((:'reg_a'::jsonb) ->> 'by') || ',' || ((:'reg_b'::jsonb) ->> 'by') || ',' || ((:'reg_c'::jsonb) ->> 'by'),
               '1|2|3|Ana,Ana,Bea', '1 D2: Ana registers Caja A and Caja B, Bea registers Caja C (places 1, 2 and 3)');
-- Caja B: three wrong codes (the 3rd starts a 30-second wait); the owner's SQL tool resumes every place that is not ok
set role authenticated;
select test.w486('B', 'local', '0000') ->> 'error' as b1 \gset
select test.w486('B', 'local', '0001') ->> 'error' as b2 \gset
select test.w486('B', 'local', '0002') as b3 \gset
reset role;
select public._discount_tills_resume_all('owner (SQL Editor)') as tool1 \gset
-- then a wrong employee code after Ana's right one, two more (the 3rd since the resume: 30 s), and after the wait one
-- more (the 4th in the hour: 1 minute)
set role authenticated;
select test.w486('B', 'empleado', '4826', '0003') as b4 \gset
select test.w486('B', 'local', '0004') ->> 'error' as b5 \gset
select test.w486('B', 'local', '0005') as b6 \gset
reset role;
select test.back('31 seconds');
set role authenticated;
select test.w486('B', 'local', '0006') as b7 \gset
-- device B signs in again: its key brings it back to place 2
select test.dev486('sess-486-b2');
select public.descuento_caja_volver((select key from test.dv486 where dev = 'B')) as vol_b \gset
reset role;
update test.dv486 set sess = 'sess-486-b2', key = (:'vol_b'::jsonb) ->> 'key' where dev = 'B';
select test.eq(:'b1' || '|' || :'b2' || '|' || ((:'b3'::jsonb) ->> 'error') || ',' || ((:'b3'::jsonb) ->> 'blocked') || ','
               || ((:'b3'::jsonb) ->> 'wait'), 'bad_pin|bad_pin|bad_pin,wait,30s',
               '1 D2 Caja B: two wrong codes cost nothing, the 3rd starts a 30-second wait');
select test.eq((:'tool1'::jsonb) ->> 'resumed', '1', '1 D2: the owner''s SQL tool resumes the one place that is not ok (place 2)');
select test.eq((:'b4'::jsonb) ->> 'error' || '|' || ((:'b4'::jsonb) ->> 'step') || '|' || :'b5' || '|'
               || ((:'b6'::jsonb) ->> 'blocked') || ',' || ((:'b6'::jsonb) ->> 'wait') || '|'
               || ((:'b7'::jsonb) ->> 'blocked') || ',' || ((:'b7'::jsonb) ->> 'wait'),
               'bad_employee|employee|bad_pin|wait,30s|wait,1m',
               '1 D2 Caja B after the resume: a wrong employee code, then the 3rd wrong (30 s) and the 4th in the hour (1 minute)');
select test.eq((:'vol_b'::jsonb) ->> 'ok' || '|' || ((:'vol_b'::jsonb) ->> 'slot'), 'true|2',
               '1 D2: device B, signed in again, comes back to place 2 with its key (a rebind)');
select test.back('61 minutes');
-- Caja A and Caja C, six rounds an hour apart: C two wrong codes a round (its 12th has 2 in its hour); A 2, 2, 2, 2,
-- 1 and 3 (its 12th is the 3rd in its hour). The 12th in 24 hours stops each till. The café's 10th wrong code in 24
-- hours (C's first of round 1) writes the one alert
set role authenticated;
select test.w486('A', 'local', '5284') ->> 'error' as x \gset
select test.w486('A', 'local', '0010') ->> 'error' as x \gset
select test.w486('C', 'local', '0020') ->> 'error' as x \gset
select test.w486('C', 'local', '0021') ->> 'error' as x \gset
reset role;
select test.back('61 minutes');
set role authenticated;
select test.w486('A', 'local', '0011') ->> 'error' as x \gset
select test.w486('A', 'local', '0012') ->> 'error' as x \gset
select test.w486('C', 'local', '0022') ->> 'error' as x \gset
select test.w486('C', 'local', '0023') ->> 'error' as x \gset
reset role;
select test.back('61 minutes');
set role authenticated;
select test.w486('A', 'local', '0013') ->> 'error' as x \gset
select test.w486('A', 'local', '0014') ->> 'error' as x \gset
select test.w486('C', 'local', '0024') ->> 'error' as x \gset
select test.w486('C', 'local', '0025') ->> 'error' as x \gset
reset role;
select test.back('61 minutes');
set role authenticated;
select test.w486('A', 'local', '0015') ->> 'error' as x \gset
select test.w486('A', 'local', '0016') ->> 'error' as x \gset
select test.w486('C', 'local', '0026') ->> 'error' as x \gset
select test.w486('C', 'local', '0027') ->> 'error' as x \gset
reset role;
select test.back('61 minutes');
set role authenticated;
select test.w486('A', 'local', '0017') ->> 'error' as x \gset
select test.w486('C', 'local', '0028') ->> 'error' as x \gset
select test.w486('C', 'local', '0029') ->> 'error' as x \gset
reset role;
select test.back('61 minutes');
set role authenticated;
select test.w486('A', 'local', '0018') as a10 \gset
select test.w486('A', 'local', '0019') as a11 \gset
select test.w486('A', 'local', '0030') as a12 \gset
select test.w486('C', 'local', '0031') as c11 \gset
select test.w486('C', 'local', '0032') as c12 \gset
reset role;
select test.eq(((:'a10'::jsonb) ->> 'blocked') is null and ((:'a11'::jsonb) ->> 'blocked') is null
               and ((:'c11'::jsonb) ->> 'blocked') is null, true,
               '1 D2: Caja A''s 10th and 11th and Caja C''s 11th wrong codes start nothing (at most 2 in their hour)');
select test.eq((:'a12'::jsonb) - 'until' - 'wait_s',
               '{"ok": false, "error": "bad_pin", "step": "manager", "warn": null, "blocked": "stopped", "wait": "stop"}'::jsonb,
               '1 D2: Caja A''s 12th wrong code in 24 hours (the 3rd in its hour) stops the till: blocked stopped, no wait');
select test.eq((:'c12'::jsonb) ->> 'blocked' || '|' || ((:'c12'::jsonb) ->> 'wait'), 'stopped|stop',
               '1 D2: Caja C''s 12th wrong code (the 2nd in its hour) stops it');
select test.eq((select details ->> 'hour_n' || '|' || (details ->> 'day_n') from public.audit_log
                 where action = 'discount_code_wrong' and details ->> 'slot' = '1' order by id desc limit 1), '3|12',
               '1 D2: Caja A''s stopping code is logged with hour_n 3 and day_n 12');
select test.eq((select string_agg(s || ':' || n, ',' order by s)
                  from (select details ->> 'slot' s, count(*) n from public.audit_log where action = 'discount_code_wrong' group by 1) q),
               '1:12,2:7,3:12',
               '1 D2: every wrong code was counted (place 1: 12, place 2: 7, place 3: 12)');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_alert'), 1,
               '1 D2: the café''s 10th wrong code in 24 hours wrote the one alert (at most one a day)');
-- the stopped places are resumed: place 1 by Bea with her own PIN, place 3 by the owner with the phone code
set role authenticated;
select test.open486('sess-486-m1', 'bea');
select public.descuento_caja_reanudar(1, test.p486('bea'), test.k486('bea'), 'Reloj') as res_a \gset
reset role;
select test.login('owner', 'aal2'); select test.session('sess-486-o1'); set role authenticated;
select public.descuento_caja_reanudar(3) as res_c \gset
-- a code typed on a device nobody registered: refused before any code is tested, logged with the name its page reported
select test.dev486('sess-486-u0');
select public.descuento_autorizar('local', '4826', 1000, p_station => 'Cocina') ->> 'error' as unk0 \gset
reset role;
select test.eq((:'res_a'::jsonb) ->> 'ok' || '|' || ((:'res_c'::jsonb) ->> 'ok') || '|' || :'unk0', 'true|true|till_not_enrolled',
               '1 D2: Bea resumes place 1, the owner place 3; the unregistered device gets till_not_enrolled');
-- every row of D2 to D2 (the latest at 23:30 Costa Rica time): more than 24 hours before now, whatever the time of day
select test.back(now() - (public.cr_day_start(public.cr_today() - 2) + interval '23 hours 30 minutes'));
select test.eq((select count(*)::int from public.audit_log where (action like 'discount%' or action = 'pin_duplicate')
                  and (at at time zone 'America/Costa_Rica')::date <> :'d2'::date), 0,
               '1 every discount row written so far now lies on D2 (two Costa Rica days ago)');
select test.eq((select count(distinct (at at time zone 'UTC')::date)::int from public.audit_log
                 where action like 'discount%' or action = 'pin_duplicate'), 2,
               '1 and those rows span two UTC dates (the report must bucket by the Costa Rica day)');
select test.eq((select max(at) < now() - interval '24 hours' from public.audit_log where action like 'discount%'), true,
               '1 and all of them are more than 24 hours old');

-- 2) today: the codes block. Device A signs in again (a rebind); wrong codes of every step and why at the three tills;
--    two unregistered devices; Ciro, locked at the name-picked PIN boxes, authorizes at the window (person_locked);
--    a removal, a registration and a replacement -------------------------------------------------------------------
set role authenticated;
select test.dev486('sess-486-a2');
select public.descuento_caja_volver((select key from test.dv486 where dev = 'A')) as vol_a \gset
reset role;
update test.dv486 set sess = 'sess-486-a2', key = (:'vol_a'::jsonb) ->> 'key' where dev = 'A';
select test.eq((:'vol_a'::jsonb) ->> 'slot' || '|' || ((:'vol_a'::jsonb) ->> 'state'), '1|ok',
               '2 device A signs in again and comes back to place 1 with its key; the place starts today clean');
-- Guía Turista on, as the accountant's confirmation and the owner's switch would (tests turn it on as the superuser: L2)
insert into public.compliance_confirmations (key, confirmed_by, reference) values ('courtesy_iva_confirmed', 'test', 'test 486');
insert into public.settings (key, value) values ('pos_discount_guia', '"on"');
set role authenticated;
select test.w486('A', 'local', '0000') as t1 \gset
select test.w486('A', 'huesped', '5284') as t2 \gset
select test.w486('B', 'guia', '4826', null, 1000, 'Canopy Tours') as t3 \gset
select test.w486('B', 'empleado', '4826', '7391') as t4 \gset
select test.w486('C', 'local', '6173') as t5 \gset
select test.w486('C', 'empleado', '4826', '6173') as t6 \gset
select test.w486('C', 'empleado', '4826', '0009') as t7 \gset
reset role;
select test.eq((:'t1'::jsonb) ->> 'error' || ',' || ((:'t1'::jsonb) ->> 'step') || '|' || ((:'t2'::jsonb) ->> 'error') || ','
               || ((:'t2'::jsonb) ->> 'step') || '|' || ((:'t3'::jsonb) ->> 'error') || ',' || ((:'t3'::jsonb) ->> 'step') || '|'
               || ((:'t4'::jsonb) ->> 'error') || ',' || ((:'t4'::jsonb) ->> 'step'),
               'bad_pin,manager|bad_pin,manager|bad_pin,owner|bad_employee,employee',
               '2 today: a code of nobody and Luis''s at Caja A; Ana''s code for Guía and the owner''s as the employee at Caja B');
select test.eq((:'t5'::jsonb) ->> 'error' || '|' || ((:'t6'::jsonb) ->> 'error') || '|' || ((:'t7'::jsonb) ->> 'error') || ','
               || ((:'t7'::jsonb) ->> 'blocked') || ',' || ((:'t7'::jsonb) ->> 'wait'), 'bad_pin|bad_employee|bad_employee,wait,30s',
               '2 today: at Caja C a code two people share, at both steps, then a wrong employee code (the 3rd: 30 s)');
select test.eq((select string_agg(distinct (details ->> 'station') || '/' || (details ->> 'till_station'), ',')
                  from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = '3' and at = now()), 'Tablet C/Caja C',
               '2 today: Caja C''s page reports itself as «Tablet C» (station), its registration says «Caja C» (till_station)');
select test.eq((select string_agg(details ->> 'step', ',' order by id) from public.audit_log where action = 'pin_duplicate'),
               'manager,employee', '2 today: the shared code wrote pin_duplicate at the manager step and at the employee step');
set role authenticated;
select test.dev486('sess-486-u1');
select public.descuento_autorizar('local', '4826', 1000, p_station => 'Cocina') ->> 'error' as u1 \gset
select public.descuento_autorizar('local', '0000', 1000, p_station => 'Cocina') ->> 'error' as u1b \gset
select test.dev486('sess-486-u2');
select public.descuento_autorizar('local', '4826', 1000, p_station => 'Barra') ->> 'error' as u2 \gset
reset role;
select test.eq(:'u1' || '|' || :'u1b' || '|' || :'u2', 'till_not_enrolled|till_not_enrolled|till_not_enrolled',
               '2 today: two unregistered devices («Cocina» twice, «Barra»): till_not_enrolled');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_till_unknown' and at = now()), 2,
               '2 today: one discount_till_unknown row per sign-in and hour (the second try from «Cocina» writes none)');
-- Ciro: five wrong PINs at the name-picked unlock box lock him there (0033); the window still accepts his code and
-- marks the approval person_locked (rule 5). His second approval's log row is moved to nine days ago (a time fixture)
set role authenticated;
select test.dev486('sess-486-m2');
select public.access_unlock(test.p486('ciro'), '0000') ->> 'error' as x \gset
select public.access_unlock(test.p486('ciro'), '0001') ->> 'error' as x \gset
select public.access_unlock(test.p486('ciro'), '0002') ->> 'error' as x \gset
select public.access_unlock(test.p486('ciro'), '0003') ->> 'error' as x \gset
select public.access_unlock(test.p486('ciro'), '0004') ->> 'error' as x \gset
select public.access_unlock(test.p486('ciro'), test.k486('ciro')) ->> 'error' as ciro_unlock \gset
select test.cat486('local', 1000, test.k486('ciro')) as l9 \gset
select test.cat486('local', 1200, test.k486('ciro')) as l9b \gset
reset role;
select test.eq(:'ciro_unlock'::text, 'locked', '2 today: Ciro''s PIN is locked at the name-picked boxes (five wrong tries)');
select test.eq((:'l9'::jsonb) ->> 'ok' || '|' || ((:'l9b'::jsonb) ->> 'ok') || '|'
               || (select string_agg(details ->> 'person_locked', ',' order by id) from public.audit_log
                    where action = 'discount_approved' and manager_id = test.p486('ciro')), 'true|true|true,true',
               '2 today: Ciro''s code at Caja A is approved twice, each discount_approved row with person_locked');
update public.audit_log set at = public.cr_day_start(public.cr_today() - 9) + interval '12 hours'
 where action = 'discount_approved' and target_id = (:'l9b'::jsonb) ->> 'id';
-- Ana removes Caja C; Bea registers Caja D in the free place; Ana registers Caja E in Caja B's place (a replacement)
select id as till_c from public.discount_tills where session_id = 'sess-486-c1' and ended_at is null \gset
select id as till_b from public.discount_tills where session_id = 'sess-486-b2' and ended_at is null \gset
set role authenticated;
select test.open486('sess-486-m3', 'ana');
select public.descuento_caja_quitar(:'till_c', test.staff('ana'), '4826', 'Reloj') as q_c \gset
select test.open486('sess-486-d1', 'bea');
select public.descuento_caja_registrar('Caja D') as reg_d \gset
select test.open486('sess-486-e1', 'ana');
select public.descuento_caja_registrar('Caja E', :'till_b') as reg_e \gset
reset role;
select test.eq((:'q_c'::jsonb) ->> 'ok' || '|' || ((:'reg_d'::jsonb) ->> 'slot') || '|' || ((:'reg_e'::jsonb) ->> 'slot') || '|'
               || ((:'reg_e'::jsonb) ->> 'replaced'), 'true|3|2|Caja B',
               '2 today: Caja C removed by Ana; Caja D registered by Bea (place 3); Caja E by Ana in place of Caja B');

-- 3) today's approvals at Caja A: one fixture for every lifecycle the report names (proposal §5.1 item 16), with what
--    the report should show for it ------------------------------------------------------------------------------------
-- L1: a Local ticket sold at the approved amount
set role authenticated;
select test.cat486('local', 4400) as l1 \gset
select test.tk486(test.o486(1), (:'l1'::jsonb) ->> 'id', jsonb_build_array(test.it486('Latte', 2200, 2)), 440) ->> 'ok' as s \gset
reset role;
select test.eq((:'l1'::jsonb) ->> 'amount' || '|' || :'s', '440|true', '3 L1: a Local of ₡4400 (₡440), its ticket recorded');
select test.fx486('L1', 'a Local ticket sold at the approved amount', (:'l1'::jsonb) ->> 'id', 'used', 'local', 4400, 440, 3960,
                  true, jsonb_build_array(test.ln486('Latte', 2200, 2)), test.o486(1));
-- H1: a Huésped ticket, authorized with the owner's code
set role authenticated;
select test.cat486('huesped', 2000, '7391') as h1 \gset
select test.tk486(test.o486(2), (:'h1'::jsonb) ->> 'id', jsonb_build_array(test.it486('Cappuccino', 2000)), 200) ->> 'ok' as s \gset
reset role;
select test.eq((:'h1'::jsonb) ->> 'role' || '|' || :'s', 'owner|true', '3 H1: a Huésped with the owner''s code, its ticket recorded');
select test.fx486('H1', 'a Huésped ticket authorized with the owner''s code', (:'h1'::jsonb) ->> 'id', 'used', 'huesped', 2000,
                  200, 1800, true, jsonb_build_array(test.ln486('Cappuccino', 2000)), test.o486(2), p_auth => 'Dueño');
-- E1: an Empleado (Abel) whose ticket charged a smaller discount than approved: recorded as charged, not verified
set role authenticated;
select test.emp486('abel', 6000) as e1 \gset
select test.tk486(test.o486(3), (:'e1'::jsonb) ->> 'id',
                  jsonb_build_array(test.it486('Ham & Cheese', 4000), test.it486('Cappuccino', 2000)), 1000) ->> 'ok' as s \gset
reset role;
select test.eq((:'e1'::jsonb) ->> 'amount' || '|' || :'s' || '|'
               || (select ('discount_not_verified' = any (flags))::text || ',' || (discount_id is not null)::text from public.orders where id = test.o486(3)),
               '1800|true|true,true', '3 E1: Abel''s Empleado (₡1800) on a ticket that charged ₡1000: linked and flagged not verified');
select test.fx486('E1', 'an Empleado ticket that charged less than approved (a mismatch)', (:'e1'::jsonb) ->> 'id',
                  'used_unverified', 'empleado', 6000, 1000, 5000, true,
                  jsonb_build_array(test.ln486('Ham & Cheese', 4000), test.ln486('Cappuccino', 2000)), test.o486(3),
                  p_ben => 'Abel', p_flags => '["discount_not_verified"]');
-- L2: a Local used by its ticket, then sent again on a second order (that order is the used_by_other anomaly)
set role authenticated;
select test.cat486('local', 2200) as l2 \gset
select test.tk486(test.o486(4), (:'l2'::jsonb) ->> 'id', jsonb_build_array(test.it486('Latte', 2200)), 220) ->> 'ok' as s \gset
select test.tk486(test.o486(40), (:'l2'::jsonb) ->> 'id', jsonb_build_array(test.it486('Latte', 2200)), 220) ->> 'ok' as s2 \gset
reset role;
select (:'l2'::jsonb) ->> 'id' as l2_id \gset
select test.eq(:'s' || '|' || :'s2' || '|' || (select coalesce(discount_id::text, 'unlinked') || ',' || array_to_string(flags, ',')
                                                  from public.orders where id = test.o486(40)),
               'true|true|unlinked,discount_not_verified',
               '3 L2: a Local used by its ticket; the same approval on a second order is recorded unlinked and not verified');
select test.eq((select details ->> 'why' || '|' || (details ->> 'approval') from public.audit_log
                 where action = 'discount_not_verified' and target_id = test.o486(40)::text), 'used_by_other|' || :'l2_id',
               '3 L2: the second order''s discount_not_verified row names the approval it claimed (used_by_other)');
select test.fx486('L2', 'a Local used by its ticket, then claimed by a second order', :'l2_id', 'used', 'local', 2200, 220, 1980,
                  true, jsonb_build_array(test.ln486('Latte', 2200)), test.o486(4));
-- E2: an Empleado (Beto) sold, then voided by Ana: the day is freed
set role authenticated;
select test.emp486('beto', 2400) as e2 \gset
select test.tk486(test.o486(5), (:'e2'::jsonb) ->> 'id', jsonb_build_array(test.it486('Mocha', 2400)), 720) ->> 'ok' as s \gset
select test.void486(test.o486(5)) ->> 'ok' as v \gset
reset role;
select test.eq(:'s' || '|' || :'v' || '|' || (select freed_how from public.discount_approvals where id = ((:'e2'::jsonb) ->> 'id')::uuid),
               'true|true|void', '3 E2: Beto''s Empleado sale voided by Ana: freed as void');
select test.fx486('E2', 'an Empleado sale voided by a manager who is not the beneficiary', (:'e2'::jsonb) ->> 'id', 'voided_freed',
                  'empleado', 2400, 720, 0, false, jsonb_build_array(test.ln486('Mocha', 2400)), test.o486(5), p_ben => 'Beto',
                  p_freed => 'void');
-- EB: an Empleado for Bea (a manager; Ana authorizes) whose sale Bea voids herself: the day stays used
set role authenticated;
select test.emp486('bea', 1500) as eb \gset
select test.tk486(test.o486(6), (:'eb'::jsonb) ->> 'id', jsonb_build_array(test.it486('Americano', 1500)), 450) ->> 'ok' as s \gset
select test.void486(test.o486(6), 'bea') ->> 'ok' as v \gset
reset role;
select test.eq(:'s' || '|' || :'v' || '|' || (select coalesce(freed_how, 'counts') from public.discount_approvals
                                               where id = ((:'eb'::jsonb) ->> 'id')::uuid), 'true|true|counts',
               '3 EB: Bea voids her own Empleado sale: the void stands, the day still counts');
select test.fx486('EB', 'an Empleado sale its beneficiary voided', (:'eb'::jsonb) ->> 'id', 'voided_counts', 'empleado', 1500, 450,
                  0, false, jsonb_build_array(test.ln486('Americano', 1500)), test.o486(6), p_ben => 'Bea');
-- E3: an Empleado (Cata) on a bill; one guest pays the Latte by item; Ana voids the bill: the paid part stays a sale
set role authenticated;
select test.bill486(test.o486(7), 'Mesa Cata', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000))) ->> 'ok' as b \gset
select test.emp486('cata', 6200, test.o486(7), 6200) as e3 \gset
select test.payitem486(test.o486(7)) as p \gset
select test.void486(test.o486(7)) ->> 'ok' as v \gset
reset role;
select test.eq(:'b' || '|' || ((:'e3'::jsonb) ->> 'total') || '|' || ((:'p'::jsonb) ->> 'amount') || '|' || :'v', 'true|4340|1540|true',
               '3 E3: Cata''s bill of ₡6200 less 30 % = ₡4340; the Latte paid by item (₡1540); the bill voided');
select test.fx486('E3', 'an Empleado bill voided while a part paid by item stays a sale', (:'e3'::jsonb) ->> 'id', 'voided_counts',
                  'empleado', 6200, 1860, 1540, false,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(7), test.o486(7),
                  p_ben => 'Cata');
-- L3: a Local sale voided
set role authenticated;
select test.cat486('local', 1300) as l3 \gset
select test.tk486(test.o486(8), (:'l3'::jsonb) ->> 'id', jsonb_build_array(test.it486('Espresso', 1300)), 130) ->> 'ok' as s \gset
select test.void486(test.o486(8)) ->> 'ok' as v \gset
reset role;
select test.eq(:'s' || '|' || :'v', 'true|true', '3 L3: a Local sale, voided by Ana');
select test.fx486('L3', 'a Local sale voided', (:'l3'::jsonb) ->> 'id', 'voided', 'local', 1300, 130, 0, false,
                  jsonb_build_array(test.ln486('Espresso', 1300)), test.o486(8));
-- L4: a Local on a bill, taken off with nothing paid (descuento_quitar_cuenta, no PIN), the bill then paid in full
set role authenticated;
select test.bill486(test.o486(9), 'Mesa L4', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000))) ->> 'ok' as b \gset
select test.cat486('local', 6200, '4826', test.o486(9), 6200) as l4 \gset
select public.descuento_quitar_cuenta(test.o486(9), 5580, 'Caja A') as q \gset
select test.payall486(test.o486(9)) as p \gset
reset role;
select test.eq(((:'l4'::jsonb) ->> 'total') || '|' || ((:'q'::jsonb) ->> 'total') || '|' || ((:'p'::jsonb) ->> 'amount'), '5580|6200|6200',
               '3 L4: a Local on a bill (₡5580), taken off with nothing paid (₡6200), the bill paid in full');
select test.fx486('L4', 'a Local taken off a bill with nothing paid, the bill then paid in full', (:'l4'::jsonb) ->> 'id', 'removed',
                  'local', 6200, 620, 6200, false,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(9), test.o486(9));
-- E4: an Empleado (Dino) taken off a bill with nothing paid; Ana gives the day back (descuento_cupo_devolver)
set role authenticated;
select test.bill486(test.o486(10), 'Mesa Dino', jsonb_build_array(test.it486('Flat White', 2200), test.it486('Carrot Cake', 2000))) ->> 'ok' as b \gset
select test.emp486('dino', 4200, test.o486(10), 4200) as e4 \gset
select public.descuento_quitar_cuenta(test.o486(10), 2940, 'Caja A') ->> 'counts' as q \gset
select test.open486('sess-486-m4', 'ana');
select public.descuento_cupo_devolver(((:'e4'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826', 'Reloj') ->> 'how' as g \gset
reset role;
select test.eq(:'b' || '|' || ((:'e4'::jsonb) ->> 'total') || '|' || :'q' || '|' || :'g', 'true|2940|true|bill_removed',
               '3 E4: Dino''s Empleado taken off his bill with nothing paid (the day counts), then Ana gives it back');
select test.fx486('E4', 'an Empleado taken off a bill with nothing paid, its day given back by Ana', (:'e4'::jsonb) ->> 'id',
                  'removed', 'empleado', 4200, 1260, 0, false,
                  jsonb_build_array(test.ln486('Flat White', 2200), test.ln486('Carrot Cake', 2000)), test.o486(10), test.o486(10),
                  p_ben => 'Dino', p_freed => 'bill_removed');
-- E5: an Empleado (Elio) taken off a bill with nothing paid, never given back: the day still counts
set role authenticated;
select test.bill486(test.o486(11), 'Mesa Elio', jsonb_build_array(test.it486('Macchiato', 1800), test.it486('Butter Croissant', 1500))) ->> 'ok' as b \gset
select test.emp486('elio', 3300, test.o486(11), 3300) as e5 \gset
select public.descuento_quitar_cuenta(test.o486(11), 2310, 'Caja A') ->> 'counts' as q \gset
reset role;
select test.eq(:'b' || '|' || ((:'e5'::jsonb) ->> 'total') || '|' || :'q', 'true|2310|true',
               '3 E5: Elio''s Empleado taken off his bill with nothing paid; nobody gives the day back');
select test.fx486('E5', 'an Empleado taken off a bill with nothing paid, its day not given back', (:'e5'::jsonb) ->> 'id',
                  'removed_counts', 'empleado', 3300, 990, 0, false,
                  jsonb_build_array(test.ln486('Macchiato', 1800), test.ln486('Butter Croissant', 1500)), test.o486(11),
                  test.o486(11), p_ben => 'Elio');
-- E6: an Empleado (Fara) on a bill; the Latte paid by item; taken off with Ana's PIN and a reason; the rest paid
set role authenticated;
select test.bill486(test.o486(12), 'Mesa Fara', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000))) ->> 'ok' as b \gset
select test.emp486('fara', 6200, test.o486(12), 6200) as e6 \gset
select test.payitem486(test.o486(12)) ->> 'amount' as p1 \gset
select public.descuento_quitar_cuenta(test.o486(12), 2800, 'Caja A', test.staff('ana'), '4826', 'el cliente lo pidió') as q \gset
select test.payall486(test.o486(12)) ->> 'amount' as p2 \gset
reset role;
select test.eq(:'b' || '|' || :'p1' || '|' || ((:'q'::jsonb) ->> 'total') || ',' || ((:'q'::jsonb) ->> 'discount') || '|' || :'p2',
               'true|1540|4000,660|4000',
               '3 E6: Fara''s bill: the Latte paid by item (₡1540); taken off after it (the Latte keeps its ₡660); the rest ₡4000');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_removed_paid'
                  and details ->> 'approval' = (:'e6'::jsonb) ->> 'id'), 1, '3 E6: one discount_removed_paid row names the approval');
-- the Latte paid first kept its part of the discount (₡660): that part was given (the bill keeps it as discount_crc, the
-- books post the revenue net of it, Sales' «Discounts given» counts it), so the row shows ₡660, given, and
-- list − discount = charged; the ₡1860 approved was never all given
select test.fx486('E6', 'an Empleado taken off a bill after a payment, with a manager''s PIN (the part the paid Latte kept was given)',
                  (:'e6'::jsonb) ->> 'id', 'removed_paid', 'empleado', 6200, 660, 5540, true,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(12), test.o486(12),
                  p_ben => 'Fara');
-- E7: an Empleado (Gala) on a bill cancelled with nothing paid (cancel_unpaid_order); Ana gives the day back
set role authenticated;
select test.bill486(test.o486(13), 'Mesa Gala', jsonb_build_array(test.it486('Cappuccino', 2000), test.it486('Espresso', 1300))) ->> 'ok' as b \gset
select test.emp486('gala', 3300, test.o486(13), 3300) as e7 \gset
select public.cancel_unpaid_order(test.o486(13)) ->> 'ok' as c \gset
select test.open486('sess-486-m4', 'ana');
select public.descuento_cupo_devolver(((:'e7'::jsonb) ->> 'id')::uuid, test.staff('ana'), '4826', 'Reloj') ->> 'how' as g \gset
reset role;
select test.eq(:'b' || '|' || ((:'e7'::jsonb) ->> 'ok') || '|' || :'c' || '|' || :'g', 'true|true|true|bill_cancelled',
               '3 E7: Gala''s bill with her Empleado cancelled with nothing paid; Ana gives the day back');
select test.fx486('E7', 'an Empleado on a bill cancelled with nothing paid, its day given back by Ana', (:'e7'::jsonb) ->> 'id',
                  'bill_cancelled', 'empleado', 3300, 990, 0, false,
                  jsonb_build_array(test.ln486('Cappuccino', 2000), test.ln486('Espresso', 1300)), test.o486(13), test.o486(13),
                  p_ben => 'Gala', p_freed => 'bill_cancelled');
-- L5: a Local on a bill cancelled with nothing paid
set role authenticated;
select test.bill486(test.o486(14), 'Mesa L5', jsonb_build_array(test.it486('Americano', 1500), test.it486('Butter Croissant', 1500))) ->> 'ok' as b \gset
select test.cat486('local', 3000, '4826', test.o486(14), 3000) as l5 \gset
select public.cancel_unpaid_order(test.o486(14)) ->> 'ok' as c \gset
reset role;
select test.eq(:'b' || '|' || ((:'l5'::jsonb) ->> 'total') || '|' || :'c', 'true|2700|true', '3 L5: a Local on a bill, the bill cancelled');
select test.fx486('L5', 'a Local on a bill cancelled with nothing paid', (:'l5'::jsonb) ->> 'id', 'bill_cancelled', 'local', 3000,
                  300, 0, false, jsonb_build_array(test.ln486('Americano', 1500), test.ln486('Butter Croissant', 1500)),
                  test.o486(14), test.o486(14));
-- E8: an Empleado (Hugo) on a room bill; the Latte paid by item; «No show» (cancel_room_order): money was paid
set role authenticated;
select test.bill486(test.o486(15), 'Hab Hugo', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000)), 'room') ->> 'ok' as b \gset
select test.emp486('hugo', 6200, test.o486(15), 6200) as e8 \gset
select test.payitem486(test.o486(15)) ->> 'amount' as p1 \gset
select public.cancel_room_order(test.o486(15)) ->> 'ok' as c \gset
reset role;
select test.eq(:'b' || '|' || ((:'e8'::jsonb) ->> 'total') || '|' || :'p1' || '|' || :'c', 'true|4340|1540|true',
               '3 E8: Hugo''s room bill with his Empleado; the Latte paid by item (₡1540); then «No show»');
select test.fx486('E8', 'an Empleado on a room bill cancelled after an item was paid', (:'e8'::jsonb) ->> 'id',
                  'bill_cancelled_counts', 'empleado', 6200, 1860, 1540, false,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(15), test.o486(15),
                  p_ben => 'Hugo');
-- E9: an Empleado (Iker) on a bill cancelled with nothing paid, never given back
set role authenticated;
select test.bill486(test.o486(16), 'Mesa Iker', jsonb_build_array(test.it486('Mocha', 2400), test.it486('Espresso', 1300))) ->> 'ok' as b \gset
select test.emp486('iker', 3700, test.o486(16), 3700) as e9 \gset
select public.cancel_unpaid_order(test.o486(16)) ->> 'ok' as c \gset
reset role;
select test.eq(:'b' || '|' || ((:'e9'::jsonb) ->> 'total') || '|' || :'c', 'true|2590|true',
               '3 E9: Iker''s bill with his Empleado cancelled with nothing paid; nobody gives the day back');
select test.fx486('E9', 'an Empleado on a bill cancelled with nothing paid, its day not given back', (:'e9'::jsonb) ->> 'id',
                  'bill_cancelled_counts', 'empleado', 3700, 1110, 0, false,
                  jsonb_build_array(test.ln486('Mocha', 2400), test.ln486('Espresso', 1300)), test.o486(16), test.o486(16),
                  p_ben => 'Iker');
-- L6: a Local ticket (refunded at the end of this section, after the register closes)
set role authenticated;
select test.cat486('local', 2000) as l6 \gset
select test.tk486(test.o486(17), (:'l6'::jsonb) ->> 'id', jsonb_build_array(test.it486('Carrot Cake', 2000)), 200) ->> 'ok' as s \gset
reset role;
select test.eq(:'s'::text, 'true', '3 L6: a Local ticket recorded (refunded after the register closes)');
select test.fx486('L6', 'a Local sale refunded after the register closed', (:'l6'::jsonb) ->> 'id', 'refunded', 'local', 2000, 200,
                  1800, true, jsonb_build_array(test.ln486('Carrot Cake', 2000)), test.o486(17), p_refunded => 1800);
-- L7: a Local let go by the page (descuento_liberar)
set role authenticated;
select test.cat486('local', 1800) as l7 \gset
select public.descuento_liberar(((:'l7'::jsonb) ->> 'id')::uuid) ->> 'ok' as r \gset
reset role;
select test.eq(:'r'::text, 'true', '3 L7: a Local let go before any sale');
select test.fx486('L7', 'a Local let go by the page', (:'l7'::jsonb) ->> 'id', 'released', 'local', 1800, 180, null, false,
                  p_freed => 'released');
-- J1, J2: an Empleado for Jana never used; 31 minutes later (its time moved back) her next request expires it and is
-- approved, not used yet
set role authenticated;
select test.emp486('jana', 2200) as j1 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = ((:'j1'::jsonb) ->> 'id')::uuid;
set role authenticated;
select test.emp486('jana', 2200) as j2 \gset
reset role;
select test.eq((:'j2'::jsonb) ->> 'ok' || '|' || (select freed_how from public.discount_approvals where id = ((:'j1'::jsonb) ->> 'id')::uuid),
               'true|expired', '3 J1: Jana''s unused Empleado, 31 minutes old, is expired by her next request (J2), which is approved');
select test.fx486('J1', 'an Empleado never used, expired by the employee''s next request', (:'j1'::jsonb) ->> 'id', 'expired',
                  'empleado', 2200, 660, null, false, p_ben => 'Jana', p_freed => 'expired');
select test.fx486('J2', 'an Empleado approved minutes ago, not used yet', (:'j2'::jsonb) ->> 'id', 'pending', 'empleado', 2200, 660,
                  null, false, p_ben => 'Jana');
-- L8: a Local never used, 31 minutes old (its time moved back); the same request sent again is then refused
-- (bad_request, logged as discount_refused: the request backstop)
set role authenticated;
select test.cat486('local', 1500, '4826', null, null, null, test.r486(1)) as l8 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = ((:'l8'::jsonb) ->> 'id')::uuid;
set role authenticated;
select test.cat486('local', 1500, '4826', null, null, null, test.r486(1)) as l8r \gset
reset role;
select test.eq((:'l8'::jsonb) ->> 'ok' || '|' || ((:'l8r'::jsonb) ->> 'error') || '|'
               || (select string_agg(details ->> 'why', ',') from public.audit_log where action = 'discount_refused'),
               'true|bad_request|bad_request', '3 L8: a Local never used; 31 minutes later its request sent again: bad_request, discount_refused');
select test.fx486('L8', 'a Local never used, older than 30 minutes', (:'l8'::jsonb) ->> 'id', 'expired', 'local', 1500, 150, null, false);
-- L14, L15: the 30-minute edge (their times moved back): 29 min 59 s old is still waiting, 30 min 1 s old has expired
set role authenticated;
select test.cat486('local', 1600) as l14 \gset
select test.cat486('local', 1700) as l15 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '29 minutes 59 seconds' where id = ((:'l14'::jsonb) ->> 'id')::uuid;
update public.discount_approvals set created_at = created_at - interval '30 minutes 1 second' where id = ((:'l15'::jsonb) ->> 'id')::uuid;
select test.fx486('L14', 'a Local never used, 29 min 59 s old', (:'l14'::jsonb) ->> 'id', 'pending', 'local', 1600, 160, null, false);
select test.fx486('L15', 'a Local never used, 30 min 1 s old', (:'l15'::jsonb) ->> 'id', 'expired', 'local', 1700, 170, null, false);
-- L9, L9b: Ciro's two Locals (section 2), not used yet
select test.fx486('L9', 'a Local Ciro authorized while his PIN was locked at the name lists', (:'l9'::jsonb) ->> 'id', 'pending',
                  'local', 1000, 100, null, false, p_auth => 'Ciro');
select test.fx486('L9b', 'Ciro''s second Local (its log row moved to nine days ago)', (:'l9b'::jsonb) ->> 'id', 'pending', 'local',
                  1200, 120, null, false, p_auth => 'Ciro');
-- L10: a Local on a bill rung 20 minutes ago; the discount applied (its time moved back 10 minutes: now() does not move
-- in one transaction); then an Espresso added to the bill: listed apart, the row partial, the bill still open
set role authenticated;
select test.bill486(test.o486(24), 'Mesa L10', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000)),
                    'front', now() - interval '20 minutes') ->> 'ok' as b \gset
select test.cat486('local', 6200, '4826', test.o486(24), 6200) as l10 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '10 minutes', used_at = used_at - interval '10 minutes'
 where id = ((:'l10'::jsonb) ->> 'id')::uuid;
select id as espresso from public.menu_items where name = 'Espresso' \gset
set role authenticated;
select test.dev486('sess-486-a2');
select public.tab_add_items(test.o486(24), jsonb_build_array(jsonb_build_object('menu_item_id', :'espresso', 'qty', 1))) ->> 'ok' as a \gset
reset role;
select test.eq(:'b' || '|' || ((:'l10'::jsonb) ->> 'total') || '|' || :'a' || '|'
               || (select total_crc || ',' || discount_crc || ',' || paid from public.orders where id = test.o486(24)),
               'true|5580|true|6880,620,false', '3 L10: a Local on a bill (₡5580); an Espresso added later, charged in full (₡6880)');
select test.fx486('L10', 'a Local on a bill still open, an Espresso added after the discount', (:'l10'::jsonb) ->> 'id', 'open_bill',
                  'local', 6200, 620, 0, true,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(24), test.o486(24),
                  p_after => jsonb_build_array(test.ln486('Espresso', 1300)));
-- L11: a Local bill paid in two parts: the Latte by item, then the rest
set role authenticated;
select test.bill486(test.o486(25), 'Mesa L11', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000))) ->> 'ok' as b \gset
select test.cat486('local', 6200, '4826', test.o486(25), 6200) as l11 \gset
select test.payitem486(test.o486(25)) ->> 'amount' as p1 \gset
select test.payall486(test.o486(25)) as p2 \gset
reset role;
select test.eq(:'b' || '|' || ((:'l11'::jsonb) ->> 'total') || '|' || :'p1' || '|' || ((:'p2'::jsonb) ->> 'closed') || ','
               || ((:'p2'::jsonb) ->> 'amount'), 'true|5580|1980|true,3600',
               '3 L11: a Local bill (₡5580) paid in two parts: the Latte by item (₡1980), then the rest (₡3600)');
select test.fx486('L11', 'a Local bill paid in two parts', (:'l11'::jsonb) ->> 'id', 'used', 'local', 6200, 620, 5580, true,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(25), test.o486(25));
-- H2: a Huésped bill: ₡1000 paid on account (its time moved to yesterday: tab_give_back refuses a payment of today),
-- given back by Ana (a negative part), then the whole bill paid
set role authenticated;
select test.bill486(test.o486(26), 'Hab H2', jsonb_build_array(test.it486('Cappuccino', 2000), test.it486('Mocha', 2400))) ->> 'ok' as b \gset
select test.cat486('huesped', 4400, '4826', test.o486(26), 4400) as h2 \gset
select public.tab_pay(test.o486(26), 'cash_crc', null, 1000, 'Caja A') as pa \gset
reset role;
update public.orders set created_at = public.cr_day_start(public.cr_today()) - interval '1 hour' where id = ((:'pa'::jsonb) ->> 'part_id')::uuid;
set role authenticated;
select test.dev486('sess-486-a2');
select public.tab_give_back(test.staff('ana'), '4826', ((:'pa'::jsonb) ->> 'part_id')::uuid, 'pago equivocado', 'Caja A') as gb \gset
select test.payall486(test.o486(26)) as p2 \gset
reset role;
select test.eq(:'b' || '|' || ((:'h2'::jsonb) ->> 'total') || '|' || ((:'pa'::jsonb) ->> 'amount') || '|' || ((:'gb'::jsonb) ->> 'given_back')
               || '|' || ((:'p2'::jsonb) ->> 'amount'), 'true|3960|1000|1000|3960',
               '3 H2: a Huésped bill (₡3960): ₡1000 on account, given back, then the whole ₡3960 paid');
select test.eq((select string_agg(total_crc::text, ',' order by total_crc) from public.orders where part_of = test.o486(26)), '-1000,1000',
               '3 H2: the payment and its give-back are two parts of the bill (₡1000 and -₡1000)');
select test.fx486('H2', 'a Huésped bill whose payment on account was given back, then paid in full', (:'h2'::jsonb) ->> 'id', 'used',
                  'huesped', 4400, 440, 3960, true,
                  jsonb_build_array(test.ln486('Cappuccino', 2000), test.ln486('Mocha', 2400)), test.o486(26), test.o486(26));
-- K1: an Empleado (Kira) ticket sold at the approved amount
set role authenticated;
select test.emp486('kira', 3700) as k1 \gset
select test.tk486(test.o486(27), (:'k1'::jsonb) ->> 'id', jsonb_build_array(test.it486('Mocha', 2400), test.it486('Espresso', 1300)), 1110) ->> 'ok' as s \gset
reset role;
select test.eq(:'s'::text, 'true', '3 K1: Kira''s Empleado ticket recorded at the approved amount');
select test.fx486('K1', 'an Empleado ticket sold at the approved amount', (:'k1'::jsonb) ->> 'id', 'used', 'empleado', 3700, 1110, 2590,
                  true, jsonb_build_array(test.ln486('Mocha', 2400), test.ln486('Espresso', 1300)), test.o486(27), p_ben => 'Kira');
-- LA1, LA2: Lalo's Empleado is let go, a second one holds his day, then the first one's queued sale arrives: recorded,
-- linked, the approval stays freed and the sale is flagged discount_daily_twice (§2.7)
set role authenticated;
select test.emp486('lalo', 1300) as la1 \gset
select public.descuento_liberar(((:'la1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.emp486('lalo', 1300) as la2 \gset
select test.tk486(test.o486(42), (:'la1'::jsonb) ->> 'id', jsonb_build_array(test.it486('Espresso', 1300)), 390) ->> 'ok' as s \gset
reset role;
select test.eq(:'rel' || '|' || ((:'la2'::jsonb) ->> 'ok') || '|' || :'s' || '|'
               || (select array_to_string(flags, ',') from public.orders where id = test.o486(42)) || '|'
               || (select freed_how from public.discount_approvals where id = ((:'la1'::jsonb) ->> 'id')::uuid),
               'true|true|true|discount_daily_twice|released',
               '3 LA1: Lalo''s let-go Empleado used by a queued sale while LA2 holds his day: flagged discount_daily_twice, still released');
select test.fx486('LA1', 'an Empleado let go, then used by its queued sale while another holds the day', (:'la1'::jsonb) ->> 'id',
                  'used', 'empleado', 1300, 390, 910, true, jsonb_build_array(test.ln486('Espresso', 1300)), test.o486(42),
                  p_ben => 'Lalo', p_freed => 'released', p_flags => '["discount_daily_twice"]');
select test.fx486('LA2', 'the Empleado that holds Lalo''s day, not used yet', (:'la2'::jsonb) ->> 'id', 'pending', 'empleado', 1300, 390,
                  null, false, p_ben => 'Lalo');
-- MO1, MO2: the same for Mora, and then Ana voids the discount_daily_twice sale. The trigger changes nothing (MO1 was
-- already freed; MO2 holds the day). The sources give this state no row of its own (482 left it to 486): its sale is
-- voided (so a voided_* code, never «used»), and the employee's day still counts (MO2 holds it; Mora cannot get a
-- third), which is what voided_counts says («Anulado · sigue contando hoy»); voided_freed («cupo libre») would be false
set role authenticated;
select test.emp486('mora', 1300) as mo1 \gset
select public.descuento_liberar(((:'mo1'::jsonb) ->> 'id')::uuid) ->> 'ok' as rel \gset
select test.emp486('mora', 1300) as mo2 \gset
select test.tk486(test.o486(43), (:'mo1'::jsonb) ->> 'id', jsonb_build_array(test.it486('Espresso', 1300)), 390) ->> 'ok' as s \gset
select test.void486(test.o486(43)) ->> 'ok' as v \gset
select test.emp486('mora', 1300) ->> 'error' as mo3 \gset
reset role;
select test.eq(:'rel' || '|' || ((:'mo2'::jsonb) ->> 'ok') || '|' || :'s' || '|' || :'v' || '|' || :'mo3' || '|'
               || (select coalesce(freed_how, 'counts') from public.discount_approvals where id = ((:'mo1'::jsonb) ->> 'id')::uuid) || ','
               || (select coalesce(freed_how, 'counts') from public.discount_approvals where id = ((:'mo2'::jsonb) ->> 'id')::uuid),
               'true|true|true|true|daily_used|released,counts',
               '3 MO1: Mora''s discount_daily_twice sale voided: MO1 stays released, MO2 keeps the day (a third request: daily_used)');
select test.fx486('MO1', 'an Empleado discount_daily_twice sale voided (its approval already freed, another holds the day)',
                  (:'mo1'::jsonb) ->> 'id', 'voided_counts', 'empleado', 1300, 390, 0, false,
                  jsonb_build_array(test.ln486('Espresso', 1300)), test.o486(43), p_ben => 'Mora', p_freed => 'released',
                  p_flags => '["discount_daily_twice"]');
select test.fx486('MO2', 'the Empleado that holds Mora''s day, not used yet', (:'mo2'::jsonb) ->> 'id', 'pending', 'empleado', 1300, 390,
                  null, false, p_ben => 'Mora');
-- L12: a Local rung more than 30 minutes after its approval (the approval's time moved back 2 hours): recorded,
-- flagged discount_late
set role authenticated;
select test.cat486('local', 1500) as l12 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '2 hours' where id = ((:'l12'::jsonb) ->> 'id')::uuid;
set role authenticated;
select test.tk486(test.o486(45), (:'l12'::jsonb) ->> 'id', jsonb_build_array(test.it486('Americano', 1500)), 150) ->> 'ok' as s \gset
reset role;
select test.eq(:'s' || '|' || (select array_to_string(flags, ',') from public.orders where id = test.o486(45)), 'true|discount_late',
               '3 L12: a Local sold two hours after its approval: recorded, flagged discount_late');
select test.fx486('L12', 'a Local sold more than 30 minutes after its approval', (:'l12'::jsonb) ->> 'id', 'used', 'local', 1500, 150,
                  1350, true, jsonb_build_array(test.ln486('Americano', 1500)), test.o486(45), p_flags => '["discount_late"]');
-- L13: a Local bill; the Latte paid by item, that part voided by Ana (the Latte is to pay again), then the whole bill
-- paid: the voided part is not charged
set role authenticated;
select test.bill486(test.o486(46), 'Mesa L13', jsonb_build_array(test.it486('Latte', 2200), test.it486('Ham & Cheese', 4000))) ->> 'ok' as b \gset
select test.cat486('local', 6200, '4826', test.o486(46), 6200) as l13 \gset
select test.payitem486(test.o486(46)) as p1 \gset
select test.void486(((:'p1'::jsonb) ->> 'part_id')::uuid) ->> 'ok' as vp \gset
select test.payall486(test.o486(46)) ->> 'amount' as p2 \gset
reset role;
select test.eq(:'b' || '|' || ((:'l13'::jsonb) ->> 'total') || '|' || ((:'p1'::jsonb) ->> 'amount') || '|' || :'vp' || '|' || :'p2',
               'true|5580|1980|true|5580',
               '3 L13: a Local bill (₡5580): the Latte paid by item (₡1980), that part voided, then the whole ₡5580 paid');
select test.fx486('L13', 'a Local bill whose part paid by item was voided, then paid in full', (:'l13'::jsonb) ->> 'id', 'used',
                  'local', 6200, 620, 5580, true,
                  jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Ham & Cheese', 4000)), test.o486(46), test.o486(46));
-- the Guía courtesies (owner's code, 100 %, ₡0, «other», no tender). For the rates: Banana Bread is given a second rate
-- (4 %, a rate of this test only), and one Espresso line is left without a stamped rate, as a line from before the
-- tax engine (0009) would be: both set directly, since no function changes a stamped line
insert into public.tax_rates (code, name, rate, confirmed_by, reference) values ('T486', 'Tarifa de prueba 486', 0.04, 'test', 'test 486');
update public.menu_items set tax_code = 'T486' where name = 'Banana Bread';
-- G1: Canopy Tours, a ticket of three lines (13 %, 4 % and no rate)
set role authenticated;
select test.cat486('guia', 5000, '7391', null, null, 'Canopy Tours') as g1 \gset
select test.tk486(test.o486(28), (:'g1'::jsonb) ->> 'id', jsonb_build_array(test.it486('Latte', 2200), test.it486('Banana Bread', 1500),
                  test.it486('Espresso', 1300)), 5000, 'other') ->> 'ok' as s \gset
reset role;
update public.order_items set tax_rate = null where order_id = test.o486(28) and item_name = 'Espresso';
select test.eq((:'g1'::jsonb) ->> 'amount' || '|' || ((:'g1'::jsonb) ->> 'role') || '|' || :'s' || '|'
               || (select total_crc from public.orders where id = test.o486(28)), '5000|owner|true|0',
               '3 G1: a Guía for Canopy Tours with the owner''s code (100 %), its ticket at ₡0');
select test.eq((select string_agg(item_name || ':' || coalesce(tax_rate::text, 'none'), ',' order by item_name)
                  from public.order_items where order_id = test.o486(28)), 'Banana Bread:0.0400,Espresso:none,Latte:0.1300',
               '3 G1: its lines carry the rates 4 %, none and 13 %');
select test.fx486('G1', 'a Guía courtesy ticket of three lines (13 %, 4 %, no rate)', (:'g1'::jsonb) ->> 'id', 'used', 'guia', 5000,
                  5000, 0, true, jsonb_build_array(test.ln486('Latte', 2200), test.ln486('Banana Bread', 1500, 1, 0.04),
                  test.ln486('Espresso', 1300, 1, null)), test.o486(28), p_comp => 'Canopy Tours', p_auth => 'Dueño');
-- G2: Selvatura Tours, two Lattes
set role authenticated;
select test.cat486('guia', 4400, '7391', null, null, 'Selvatura Tours') as g2 \gset
select test.tk486(test.o486(29), (:'g2'::jsonb) ->> 'id', jsonb_build_array(test.it486('Latte', 2200, 2)), 4400, 'other') ->> 'ok' as s \gset
reset role;
select test.eq(:'s'::text, 'true', '3 G2: a Guía for Selvatura Tours, its ticket at ₡0');
select test.fx486('G2', 'a Guía courtesy ticket for a second company', (:'g2'::jsonb) ->> 'id', 'used', 'guia', 4400, 4400, 0, true,
                  jsonb_build_array(test.ln486('Latte', 2200, 2)), test.o486(29), p_comp => 'Selvatura Tours', p_auth => 'Dueño');
-- G3: Canopy Tours again, voided (not given: not in the courtesies)
set role authenticated;
select test.cat486('guia', 2400, '7391', null, null, 'Canopy Tours') as g3 \gset
select test.tk486(test.o486(30), (:'g3'::jsonb) ->> 'id', jsonb_build_array(test.it486('Mocha', 2400)), 2400, 'other') ->> 'ok' as s \gset
select test.void486(test.o486(30)) ->> 'ok' as v \gset
reset role;
select test.eq(:'s' || '|' || :'v', 'true|true', '3 G3: a second Guía for Canopy Tours, voided by Ana');
select test.fx486('G3', 'a Guía courtesy voided', (:'g3'::jsonb) ->> 'id', 'voided', 'guia', 2400, 2400, 0, false,
                  jsonb_build_array(test.ln486('Mocha', 2400)), test.o486(30), p_comp => 'Canopy Tours', p_auth => 'Dueño');
-- G4: Sky Tours on a bill rung 20 minutes ago, still open; an Espresso added after the courtesy (charged in full; not a
-- covered line, so not in the courtesies)
set role authenticated;
select test.bill486(test.o486(31), 'Mesa Sky', jsonb_build_array(test.it486('Cappuccino', 2000)), 'front', now() - interval '20 minutes') ->> 'ok' as b \gset
select test.cat486('guia', 2000, '7391', test.o486(31), 2000, 'Sky Tours') as g4 \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '10 minutes', used_at = used_at - interval '10 minutes'
 where id = ((:'g4'::jsonb) ->> 'id')::uuid;
set role authenticated;
select test.dev486('sess-486-a2');
select public.tab_add_items(test.o486(31), jsonb_build_array(jsonb_build_object('menu_item_id', :'espresso', 'qty', 1))) ->> 'ok' as a \gset
reset role;
select test.eq(:'b' || '|' || ((:'g4'::jsonb) ->> 'total') || '|' || :'a' || '|' || (select total_crc from public.orders where id = test.o486(31)),
               'true|0|true|1300', '3 G4: a Guía for Sky Tours on a bill (₡0); an Espresso added later (₡1300)');
select test.fx486('G4', 'a Guía courtesy on a bill still open, an Espresso added after it', (:'g4'::jsonb) ->> 'id', 'open_bill', 'guia',
                  2000, 2000, 0, true, jsonb_build_array(test.ln486('Cappuccino', 2000)), test.o486(31), test.o486(31),
                  p_comp => 'Sky Tours', p_auth => 'Dueño', p_after => jsonb_build_array(test.ln486('Espresso', 1300)));
-- C1: a Local of an earlier Costa Rica day (its day moved back: no function makes an approval of another day)
set role authenticated;
select test.cat486('local', 1100) as c1 \gset
reset role;
update public.discount_approvals set cr_day = :'d_lo'::date - 1 where id = ((:'c1'::jsonb) ->> 'id')::uuid;
select test.fx486('C1', 'a Local of the day before the range', (:'c1'::jsonb) ->> 'id', 'pending', 'local', 1100, 110, null, false);
update test.fx486 set day = :'d_lo'::date - 1, in_range = false where tag = 'C1';
-- O1-O4: the old window (approve_discount, the switch on by default). O1 made before 0038 was applied (its time
-- moved to the start of that Costa Rica day) and never used; O2 a microsecond before that day (out of the range; its
-- log row moved to ten days ago); O3 made now and used by its sale; O4 made now, used, its sale voided
set role authenticated;
select test.dev486('sess-486-a2');
select public.approve_discount(test.staff('ana'), '4826', 'percent', 15, 3000, 'Cumpleaños', 'Caja A') as old1 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 5, 1000, 'Vecino', 'Caja A') as old2 \gset
select public.approve_discount(test.staff('ana'), '4826', 'amount', 500, 2200, 'Cliente frecuente', 'Caja A') as old3 \gset
select test.tk486(test.o486(34), (:'old3'::jsonb) ->> 'id', jsonb_build_array(test.it486('Latte', 2200)), 500) ->> 'ok' as s \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 1500, 'Promoción', 'Caja A') as old4 \gset
select test.tk486(test.o486(44), (:'old4'::jsonb) ->> 'id', jsonb_build_array(test.it486('Americano', 1500)), 150) ->> 'ok' as s4 \gset
select test.void486(test.o486(44)) ->> 'ok' as v4 \gset
reset role;
select test.eq(:'s4' || '|' || :'v4', 'true|true', '3 O4: a fourth old-window approval used by its sale, the sale voided');
update public.discount_approvals set created_at = public.cr_day_start(:'d_lo'::date) where id = ((:'old1'::jsonb) ->> 'id')::uuid;
update public.discount_approvals set created_at = public.cr_day_start(:'d_lo'::date) - interval '1 microsecond'
 where id = ((:'old2'::jsonb) ->> 'id')::uuid;
update public.audit_log set at = public.cr_day_start(public.cr_today() - 10) + interval '12 hours'
 where action = 'discount_approved' and target_id = (:'old2'::jsonb) ->> 'id';
select test.eq((:'old1'::jsonb) ->> 'ok' || '|' || ((:'old2'::jsonb) ->> 'ok') || '|' || ((:'old3'::jsonb) ->> 'ok') || '|' || :'s'
               || '|' || (select (order_id = test.o486(34))::text from public.discount_approvals where id = ((:'old3'::jsonb) ->> 'id')::uuid),
               'true|true|true|true|true', '3 O1-O3: three approvals of the old window; O3 used by its sale');
insert into test.fx486 (tag, what, id, in_range, day, status, given, authorizer, kind, value, reason, station, list_value, discount,
                        charged, products, order_id) values
  ('O1', 'an old-window approval made before 0038 was applied, never used', ((:'old1'::jsonb) ->> 'id')::uuid, true, :'d_lo'::date,
   'free_old', false, 'Ana', 'percent', 15, 'Cumpleaños', 'Caja A', 3000, 450, null, '[]', null),
  ('O2', 'an old-window approval of the day before the range', ((:'old2'::jsonb) ->> 'id')::uuid, false, :'d_lo'::date - 1,
   'free_old', false, 'Ana', 'percent', 5, 'Vecino', 'Caja A', 1000, 50, null, '[]', null),
  ('O3', 'an old-window approval made after 0038, used by its sale', ((:'old3'::jsonb) ->> 'id')::uuid, true, public.cr_today(),
   'free_old_after_0038', true, 'Ana', 'amount', 500, 'Cliente frecuente', 'Caja A', 2200, 500, 1700,
   jsonb_build_array(test.ln486('Latte', 2200)), test.o486(34)),
  ('O4', 'an old-window approval made after 0038 whose sale was voided (not given)', ((:'old4'::jsonb) ->> 'id')::uuid, true,
   public.cr_today(), 'free_old_after_0038', false, 'Ana', 'percent', 10, 'Promoción', 'Caja A', 1500, 150, 0,
   jsonb_build_array(test.ln486('Americano', 1500)), test.o486(44));
-- L16 and G5: a line taken off a discounted bill with the POS «Take off» button (tab_remove_item, no PIN), then the
-- bill paid: the list value is the covered lines as they are now (₡4000), so list value − discount = charged, the
-- totals and the courtesies (A-13) agree, and the approved subtotal (₡10000) stays apart as approved_value
set role authenticated;
select test.bill486(test.o486(70), 'Mesa L16', jsonb_build_array(test.it486('Ham & Cheese', 4000), test.it486('Latte', 6000))) ->> 'ok' as b \gset
select test.bill486(test.o486(71), 'Mesa G5', jsonb_build_array(test.it486('Ham & Cheese', 4000), test.it486('Latte', 6000))) ->> 'ok' as b2 \gset
select test.cat486('local', 10000, '4826', test.o486(70), 10000) as l16 \gset
select test.cat486('guia', 10000, '7391', test.o486(71), 10000, 'Tours Quitados') as g5 \gset
select test.dev486('sess-486-a2');
select public.tab_remove_item(test.li486(test.o486(70), 2), 1, null, 'Caja A', null, null, 9000) ->> 'ok' as rl \gset
select public.tab_remove_item(test.li486(test.o486(71), 2), 1, null, 'Caja A', null, null, 0) ->> 'ok' as rg \gset
select test.payall486(test.o486(70)) ->> 'ok' as pl \gset
select public.tab_pay(test.o486(71), 'other', null, null, 'Caja A') ->> 'ok' as pg \gset
reset role;
select test.eq(concat_ws('|', :'b', :'b2', (:'l16'::jsonb) ->> 'total', (:'g5'::jsonb) ->> 'total', :'rl', :'rg', :'pl', :'pg',
                         (select string_agg(subtotal_crc || '/' || discount_crc || '/' || total_crc || '/' || paid, ',' order by id)
                            from public.orders where id in (test.o486(70), test.o486(71)))),
               'true|true|9000|0|true|true|true|true|4000/400/3600/true,4000/4000/0/true',
               '3 L16 and G5: a Local and a Guía on 4000 + 6000 bills; the 6000 line taken off each (the discount follows the rate down); both paid');
select test.fx486('L16', 'a Local on a bill, a line taken off before paying', (:'l16'::jsonb) ->> 'id', 'used', 'local', 4000, 400, 3600,
                  true, jsonb_build_array(test.ln486('Ham & Cheese', 4000)), test.o486(70), test.o486(70));
select test.fx486('G5', 'a Guía courtesy on a bill, a line taken off before closing it', (:'g5'::jsonb) ->> 'id', 'used', 'guia', 4000,
                  4000, 0, true, jsonb_build_array(test.ln486('Ham & Cheese', 4000)), test.o486(71), test.o486(71),
                  p_comp => 'Tours Quitados', p_auth => 'Dueño');
-- three more orders claim L2 (already used by its ticket), as two tabs or a replayed queue could send them: one paid and
-- voided by Ana, one «Pay later» left open, one «Pay later» cancelled; and one paid, refunded after the close (below).
-- Each is an anomaly with the status the rows' ladder gives and what it really charged
set role authenticated;
select test.tk486(test.o486(41), :'l2_id', jsonb_build_array(test.it486('Latte', 2200)), 220) ->> 'ok' as a41 \gset
select test.tk486(test.o486(49), :'l2_id', jsonb_build_array(test.it486('Latte', 2200)), 220) ->> 'ok' as a49 \gset
select string_agg(public.pos_record_sale(jsonb_build_object('id', o, 'created_at', now(), 'total_crc', 1980, 'payment_method', 'pending',
         'paid', false, 'status', 'ready', 'station', 'Caja A', 'source', 'front', 'guest_name', 'Mesa anomalía', 'subtotal_crc', 2200,
         'discount_crc', 220, 'discount_id', :'l2_id',
         'items', jsonb_build_array(test.it486('Latte', 2200) || jsonb_build_object('id', test.li486(o, 1))))) ->> 'ok', ',') as a4x
  from unnest(array[test.o486(47), test.o486(48)]) o \gset
select test.void486(test.o486(41)) ->> 'ok' as v41 \gset
select public.cancel_unpaid_order(test.o486(48)) ->> 'ok' as c48 \gset
reset role;
select test.eq(concat_ws('|', :'a41', :'a49', :'a4x', :'v41', :'c48',
                         (select string_agg(coalesce(discount_id::text, 'unlinked') || ',' || array_to_string(flags, ','), ';' order by id)
                            from public.orders where id in (test.o486(41), test.o486(47), test.o486(48), test.o486(49)))),
               'true|true|true,true|true|true|unlinked,discount_not_verified;unlinked,discount_not_verified;unlinked,discount_not_verified;unlinked,discount_not_verified',
               '3 L2 claimed again by four orders: each recorded unlinked and not verified; one voided by Ana, one cancelled unpaid');
-- the refund: today's register closes (a closed register_days row, as 482 does), then Ana refunds L6's sale
insert into public.register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name)
  values (public.cr_today(), 'Ana', 50000, now(), 'Ana');
set role authenticated;
select test.dev486('sess-486-a2');
select public.manager_refund_order(test.staff('ana'), '4826', test.o486(17), 'cliente') as rf \gset
select public.manager_refund_order(test.staff('ana'), '4826', test.o486(49), 'cliente') ->> 'ok' as rf49 \gset
reset role;
select test.eq(:'rf49'::text, 'true', '3 the paid anomaly o49 refunded after the close too');
select test.eq((:'rf'::jsonb) ->> 'ok' || '|' || (select (refunded_at is not null and voided_at is null)::text from public.orders
                                                    where id = test.o486(17)), 'true|true', '3 L6: Ana refunds the sale after the close');
-- last, the owner's SQL tool ends every live till (descuento-cajas-quitar-todas.sql)
select public._discount_tills_end_all('owner (SQL Editor)') ->> 'ended' as ended_all \gset
select test.eq(:'ended_all'::text, '3', '3 the owner''s SQL tool ends the three live tills (A, E and D)');
select test.eq((select count(*)::int from public.audit_log where action in ('discount_trigger_error', 'discount_check_error')), 0,
               '3 no sale check and no trigger failed while the fixtures were made');

-- 4) who may read it: the sales permission or the books, and nothing else (proposal §2.5e «Access», P12, spec 12) ----
-- (the unlocks below write access_open rows and the owner's switch a sales_access row: those are not the report's)
select count(*) as audit_n0 from public.audit_log where action not in ('access_open', 'sales_access') \gset
select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) as appr0 from public.discount_approvals t \gset
set role authenticated;
select test.dev486('sess-486-x1');
select public.descuentos_informe(public.cr_today(), public.cr_today()) as acc_cafe \gset
select test.open486('sess-486-x2', 'ana');
select public.descuentos_informe(public.cr_today(), public.cr_today()) as acc_ana \gset
select test.open486('sess-486-x3', 'dueno');
insert into test.reps486 values ('dueno_pin', public.descuentos_informe(:'d_lo', public.cr_today()));
reset role;
select test.login('owner', 'aal1'); set role authenticated;
select public.descuentos_informe(public.cr_today(), public.cr_today()) as acc_owner1 \gset
reset role;
select test.login('owner', 'aal2'); set role authenticated;
insert into test.reps486 values ('final', public.descuentos_informe(:'d_lo', public.cr_today()));
select public.owner_set_sales_access(test.p486('hal'), true) ->> 'ok' as hal_sales \gset
reset role;
set role authenticated;
select test.open486('sess-486-x4', 'hal');
insert into test.reps486 values ('hal', public.descuentos_informe(:'d_lo', public.cr_today()));
reset role;
select test.login('accountant', 'aal1'); set role authenticated;
select public.descuentos_informe(public.cr_today(), public.cr_today()) as acc_acct1 \gset
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
insert into test.reps486 values ('accountant', public.descuentos_informe(:'d_lo', public.cr_today()));
reset role;
select test.eq(:'acc_cafe'::jsonb, '{"ok": false, "error": "not_allowed"}'::jsonb,
               '4 the café login alone (owner areas closed): not_allowed, and nothing else in the answer');
select test.eq(:'acc_ana'::jsonb, '{"ok": false, "error": "not_allowed"}'::jsonb,
               '4 the café login with Ana''s unlock, Ana not allowed to see sales: not_allowed (a manager PIN alone is not enough)');
select test.eq(:'acc_owner1'::jsonb, '{"ok": false, "error": "not_allowed"}'::jsonb,
               '4 the owner''s login without the phone code: not_allowed');
select test.eq(:'acc_acct1'::jsonb, '{"ok": false, "error": "not_allowed"}'::jsonb,
               '4 the accountant''s login without the phone code: not_allowed');
select test.eq(test.rep486('final') ->> 'ok', 'true', '4 the owner with the phone code reads it');
select test.eq(:'hal_sales' || '|' || (test.rep486('hal') ->> 'ok'), 'true|true',
               '4 a manager the owner allowed to see sales (Hal), with his unlock on the café login, reads it');
select test.eq(test.rep486('dueno_pin') ->> 'ok', 'true', '4 the café login with the owner''s PIN unlock (owner level) reads it');
select test.eq(test.rep486('accountant') ->> 'ok', 'true', '4 the accountant with the phone code reads it (no is_cafe(): spec 12)');
select test.eq(test.rep486('accountant'), test.rep486('final'), '4 the accountant sees the same report as the owner');
select test.eq(test.rep486('hal'), test.rep486('final'), '4 so does the manager allowed to see sales');
select test.eq(test.rep486('dueno_pin'), test.rep486('final'), '4 so does the owner''s PIN unlock on the café login');
select test.login('anon'); set role anon;
select test.throws($$select public.descuentos_informe(null, null)$$, 'permission denied', '4 anon cannot run it');
reset role;
select test.eq((select has_function_privilege('anon', p.oid, 'execute')::text || '|' || has_function_privilege('authenticated', p.oid, 'execute')
                       || '|' || has_function_privilege('canopy_backup', p.oid, 'execute')
                       || '|' || exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0 and x.privilege_type = 'EXECUTE')
                  from pg_proc p where p.oid = 'public.descuentos_informe(date, date)'::regprocedure), 'false|true|false|false',
               '4 grants: authenticated only (not anon, not PUBLIC, not the backup account)');
select test.eq((select p.prosecdef::text || '|' || p.provolatile::text || '|' || (pg_get_functiondef(p.oid) ~ 'is_cafe')::text
                       || '|' || (pg_get_functiondef(p.oid) ~ '_insights_allowed')::text
                  from pg_proc p where p.oid = 'public.descuentos_informe(date, date)'::regprocedure), 'true|s|false|true',
               '4 a stable owner-rights function that checks _insights_allowed() and not is_cafe()');

-- 5) the range ---------------------------------------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.descuentos_informe(null, null) as rg_null \gset
select public.descuentos_informe(public.cr_today() - 3, null) as rg_from \gset
select public.descuentos_informe(public.cr_today(), public.cr_today() - 1) as rg_back \gset
select public.descuentos_informe(public.cr_today() - 400, public.cr_today()) ->> 'ok' as rg_400 \gset
select public.descuentos_informe(public.cr_today() - 401, public.cr_today()) as rg_401 \gset
insert into test.reps486 values ('before', public.descuentos_informe(:'d_lo'::date - 1, :'d_lo'::date - 1));
insert into test.reps486 values ('today', public.descuentos_informe(public.cr_today(), public.cr_today()));
insert into test.reps486 values ('d2_today', public.descuentos_informe(public.cr_today() - 2, public.cr_today()));
insert into test.reps486 values ('d2', public.descuentos_informe(public.cr_today() - 2, public.cr_today() - 2));
insert into test.reps486 values ('yesterday', public.descuentos_informe(public.cr_today() - 1, public.cr_today() - 1));
insert into test.reps486 values ('day9', public.descuentos_informe(public.cr_today() - 9, public.cr_today() - 9));
insert into test.reps486 values ('day10', public.descuentos_informe(public.cr_today() - 10, public.cr_today() - 10));
reset role;
select test.eq((:'rg_null'::jsonb) ->> 'ok' || '|' || ((:'rg_null'::jsonb) ->> 'from') || '|' || ((:'rg_null'::jsonb) ->> 'to'),
               'true|' || :'today' || '|' || :'today', '5 no dates: today (from = to = today in Costa Rica)');
select test.eq(((:'rg_from'::jsonb) ->> 'from') || '|' || ((:'rg_from'::jsonb) ->> 'to'),
               (public.cr_today() - 3)::text || '|' || (public.cr_today() - 3)::text, '5 no end date: the end is the start');
select test.eq(:'rg_back'::jsonb, '{"ok": false, "error": "bad_range"}'::jsonb, '5 an end before the start: bad_range');
select test.eq(:'rg_400' || '|' || (:'rg_401'::jsonb)::text, 'true|{"ok": false, "error": "bad_range"}',
               '5 the end 400 days after the start is allowed; 401: bad_range');
select test.eq((test.rep486('final') ->> 'from') || '|' || (test.rep486('final') ->> 'to'), :'d_lo' || '|' || :'today',
               '5 the answer names its range');
select test.eq((test.rep486('final') ->> 'applied_0038')::timestamptz, :'m38'::timestamptz,
               '5 applied_0038 is when 0038 was applied (canopy.migrations 38)');

-- 6) the rows: one per approval of the range (category approvals by their day, old-kind by the day they were made),
--    in time order, each with exactly one status of §2.5e and what the fixture says ---------------------------------
select test.eq((select string_agg(k, ',' order by k) from jsonb_object_keys(test.rep486('final')) k),
               'anomalies,applied_0038,courtesies,from,ok,rows,to,totals,wrong_codes', '6 the answer''s keys');
select test.eq((select string_agg(f.tag, ',' order by f.tag) from test.fx486 f where f.in_range
                   and not exists (select 1 from jsonb_array_elements(test.rep486('final') -> 'rows') x where x ->> 'id' = f.id::text)),
               null, '6 every approval of the range is a row (category by its Costa Rica day, old-kind by its creation day)');
select test.eq((select string_agg(x ->> 'id', ',') from jsonb_array_elements(test.rep486('final') -> 'rows') x
                 where not exists (select 1 from test.fx486 f where f.in_range and f.id::text = x ->> 'id')), null,
               '6 and nothing else: no approval outside the range (C1 of an earlier day, O2 made the day before)');
select test.eq((select count(*)::int - count(distinct x ->> 'id')::int from jsonb_array_elements(test.rep486('final') -> 'rows') x), 0,
               '6 each approval is listed once');
select test.eq((select jsonb_agg(x ->> 'id' order by o) from jsonb_array_elements(test.rep486('final') -> 'rows') with ordinality r(x, o)),
               (select jsonb_agg(a.id::text order by a.created_at, a.id) from public.discount_approvals a
                 where a.id in (select id from test.fx486 where in_range)), '6 the rows are in time order (then by id)');
select test.eq((select string_agg(distinct k, ',' order by k) from jsonb_array_elements(test.rep486('final') -> 'rows') x,
                       jsonb_object_keys(x) k),
               'added_after,approved_value,at,authorizer,beneficiary,bill_id,category,charged,company,day,discount,flags,freed_how,given,id,kind,'
               'list_value,order_id,partial,products,reason,receipt_no,refunded,role,station,status,value', '6 the keys of a row');
select test.eq((select count(*)::int from jsonb_array_elements(test.rep486('final') -> 'rows') x
                 where (select count(*) from jsonb_object_keys(x)) <> 27), 0, '6 every row has all 27 keys');
-- the list value is what the covered lines are now while the order carries the approval (L16, G5: a line taken off);
-- the approved subtotal stays apart; on every used row with nothing added after, list value − discount = charged
select test.eq((select count(*)::int from jsonb_array_elements(test.rep486('final') -> 'rows') x join public.discount_approvals a on a.id::text = x ->> 'id'
                 where (x ->> 'approved_value')::int is distinct from a.subtotal_crc), 0, '6 approved_value is each approval''s own subtotal');
select test.eq((select string_agg(f.tag || ':' || (r ->> 'list_value') || '/' || (r ->> 'approved_value'), ' ' order by f.tag)
                  from test.fx486 f cross join lateral (select test.row486('final', f.id) r) q where f.tag in ('L16', 'G5')),
               'G5:4000/10000 L16:4000/10000', '6 L16 and G5: list value ₡4000 (the lines left), approved ₡10000');
select test.eq((select coalesce(string_agg(x ->> 'id', ','), '') from jsonb_array_elements(test.rep486('final') -> 'rows') x
                 where x ->> 'status' = 'used' and not (x ->> 'partial')::boolean
                   and (x ->> 'list_value')::int - (x ->> 'discount')::int <> (x ->> 'charged')::int), '',
               '6 every used row with nothing added after: list value − discount = charged (L16: 4000 − 400 = 3600; G5: 4000 − 4000 = 0)');
-- per fixture: its status
select test.eq(test.row486('final', f.id) ->> 'status', f.status, '6 ' || f.tag || ' (' || f.what || '): status ' || f.status)
  from test.fx486 f where f.in_range order by f.n;
-- per fixture: given, list value, discount, charged, refunded
select test.eq(jsonb_build_object('given', r -> 'given', 'list_value', r -> 'list_value', 'discount', r -> 'discount',
                                  'charged', r -> 'charged', 'refunded', r -> 'refunded'),
               jsonb_build_object('given', f.given, 'list_value', f.list_value, 'discount', f.discount, 'charged', f.charged,
                                  'refunded', f.refunded),
               '6 ' || f.tag || ': given, list value, discount, charged and refunded')
  from test.fx486 f cross join lateral (select test.row486('final', f.id) r) q where f.in_range order by f.n;
-- per fixture: the products covered, the lines added after, partial
select test.eq(jsonb_build_object('products', test.sort486(r -> 'products'), 'added_after', test.sort486(r -> 'added_after'),
                                  'partial', r -> 'partial'),
               jsonb_build_object('products', test.sort486(f.products), 'added_after', test.sort486(f.added_after),
                                  'partial', jsonb_array_length(f.added_after) > 0),
               '6 ' || f.tag || ': products covered, added after, partial')
  from test.fx486 f cross join lateral (select test.row486('final', f.id) r) q where f.in_range order by f.n;
-- per fixture: who and what
select test.eq(jsonb_build_object('category', r -> 'category', 'beneficiary', r -> 'beneficiary', 'company', r -> 'company',
                                  'authorizer', r -> 'authorizer', 'role', r -> 'role', 'kind', r -> 'kind', 'value', r -> 'value',
                                  'reason', r -> 'reason', 'station', r -> 'station', 'freed_how', r -> 'freed_how', 'flags', r -> 'flags'),
               jsonb_build_object('category', f.category, 'beneficiary', f.beneficiary, 'company', f.company,
                                  'authorizer', f.authorizer, 'role', f.role, 'kind', f.kind, 'value', f.value, 'reason', f.reason,
                                  'station', f.station, 'freed_how', f.freed_how, 'flags', f.flags),
               '6 ' || f.tag || ': category, beneficiary, company, authorizer and role, kind, value, reason, station, freed_how, flags')
  from test.fx486 f cross join lateral (select test.row486('final', f.id) r) q where f.in_range order by f.n;
-- per fixture: its order, bill, receipt number, time and day
select test.eq(jsonb_build_object('order_id', r -> 'order_id', 'bill_id', r -> 'bill_id', 'receipt_no', r -> 'receipt_no',
                                  'at', (r ->> 'at')::timestamptz, 'day', r -> 'day'),
               jsonb_build_object('order_id', f.order_id, 'bill_id', f.bill_id,
                                  'receipt_no', (select o.receipt_no from public.orders o where o.id = f.order_id),
                                  'at', a.created_at, 'day', f.day),
               '6 ' || f.tag || ': order, bill, receipt number, time and day')
  from test.fx486 f join public.discount_approvals a on a.id = f.id cross join lateral (select test.row486('final', f.id) r) q
 where f.in_range order by f.n;
-- a discount taken off after a payment: the report's figure is the one the bill kept, the one the books and Sales count
select test.eq((select jsonb_build_object('discount', (test.row486('final', f.id) ->> 'discount')::int,
                                          'given', (test.row486('final', f.id) ->> 'given')::boolean,
                                          'list_minus_discount', (test.row486('final', f.id) ->> 'list_value')::int
                                                                 - (test.row486('final', f.id) ->> 'discount')::int,
                                          'charged', (test.row486('final', f.id) ->> 'charged')::int)
                  from test.fx486 f where f.tag = 'E6'),
               (select jsonb_build_object('discount', o.discount_crc, 'given', true,
                                          'list_minus_discount', o.subtotal_crc - o.discount_crc,
                                          'charged', o.subtotal_crc - o.discount_crc)
                  from public.orders o where o.id = test.o486(12)),
               '6 E6 (removed_paid): discount = what the bill kept (its discount_crc, the books'' and Sales'' figure), given, and list − discount = charged');
select test.eq((select (x.details ->> 'discount_kept')::int from public.audit_log x, test.fx486 f
                 where f.tag = 'E6' and x.action = 'discount_removed_paid' and x.details ->> 'approval' = f.id::text),
               (select (test.row486('final', f.id) ->> 'discount')::int from test.fx486 f where f.tag = 'E6'),
               '6 E6 ... read from its discount_removed_paid row (discount_kept), exact even if the bill changes later');
-- V7: every status code appears, and no other
select test.eq((select string_agg(c, ',' order by c) from unnest(array['used', 'used_unverified', 'voided_freed', 'voided_counts',
                  'voided', 'removed', 'removed_counts', 'removed_paid', 'bill_cancelled', 'bill_cancelled_counts', 'refunded',
                  'released', 'expired', 'pending', 'open_bill', 'free_old', 'free_old_after_0038']) c
                 where not exists (select 1 from jsonb_array_elements(test.rep486('final') -> 'rows') x where x ->> 'status' = c)), null,
               '6 V7: each of the 17 status codes of §2.5e appears in this report');
select test.eq((select string_agg(distinct x ->> 'status', ',' order by x ->> 'status') from jsonb_array_elements(test.rep486('final') -> 'rows') x
                 where coalesce(x ->> 'status', '') not in ('used', 'used_unverified', 'voided_freed', 'voided_counts', 'voided', 'removed',
                  'removed_counts', 'removed_paid', 'bill_cancelled', 'bill_cancelled_counts', 'refunded', 'released', 'expired',
                  'pending', 'open_bill', 'free_old', 'free_old_after_0038')), null, '6 V7: and no other value');
-- the approvals of the day before the range are in that day's report, and only they
select test.eq((select string_agg(f.tag || ':' || coalesce(test.row486('before', f.id) ->> 'status', 'missing') || ','
                                  || coalesce(test.row486('before', f.id) ->> 'day', 'missing'), ' ' order by f.tag)
                  from test.fx486 f where not f.in_range),
               'C1:pending,' || (:'d_lo'::date - 1)::text || ' O2:free_old,' || (:'d_lo'::date - 1)::text,
               '6 the report of the day before lists C1 (by its Costa Rica day) and O2 (made a microsecond before the range)');
select test.eq(jsonb_array_length(test.rep486('before') -> 'rows'), 2, '6 and nothing else that day');

-- 7) totals, courtesies and the unlinked sales ----------------------------------------------------------------------
-- totals over the fixture's own expectations: rows = every row of the group; given, discount and list value over the
-- discounts given (used, not verified, open bill, refunded, an old-kind one on a live sale)
select test.eq(test.sortby486(test.rep486('final') #> '{totals,by_category}', 'category'),
               (select test.sortby486(jsonb_agg(jsonb_build_object('category', category, 'rows', n, 'given', g, 'discount', d,
                                                                   'list_value', lv)), 'category')
                  from (select category, count(*)::int n, count(*) filter (where given)::int g,
                               coalesce(sum(discount) filter (where given), 0)::int d,
                               coalesce(sum(list_value) filter (where given), 0)::int lv
                          from test.fx486 where in_range group by category) q),
               '7 totals by category (old-kind approvals as category null): rows, given, discount and list value of the given');
select test.eq(test.sortby486(test.rep486('final') #> '{totals,by_employee}', 'beneficiary'),
               (select test.sortby486(jsonb_agg(jsonb_build_object('beneficiary', beneficiary, 'rows', n, 'given', g, 'discount', d,
                                                                   'list_value', lv)), 'beneficiary')
                  from (select beneficiary, count(*)::int n, count(*) filter (where given)::int g,
                               coalesce(sum(discount) filter (where given), 0)::int d,
                               coalesce(sum(list_value) filter (where given), 0)::int lv
                          from test.fx486 where in_range and category = 'empleado' group by beneficiary) q),
               '7 totals by employee (Empleado only; Jana with two rows, none given)');
select test.eq(test.sortby486(test.rep486('final') #> '{totals,by_authorizer}', 'name', 'role'),
               (select test.sortby486(jsonb_agg(jsonb_build_object('name', authorizer, 'role', role, 'rows', n, 'given', g,
                                                                   'discount', d, 'list_value', lv)), 'name', 'role')
                  from (select authorizer, role, count(*)::int n, count(*) filter (where given)::int g,
                               coalesce(sum(discount) filter (where given), 0)::int d,
                               coalesce(sum(list_value) filter (where given), 0)::int lv
                          from test.fx486 where in_range group by authorizer, role) q),
               '7 totals by authorizer with role (Ana manager, Ana with no role for the old window, Ciro, Dueño owner)');
select test.eq(test.sortby486(test.rep486('final') #> '{totals,by_company}', 'company'),
               (select test.sortby486(jsonb_agg(jsonb_build_object('company', company, 'rows', n, 'given', g, 'discount', d,
                                                                   'list_value', lv)), 'company')
                  from (select company, count(*)::int n, count(*) filter (where given)::int g,
                               coalesce(sum(discount) filter (where given), 0)::int d,
                               coalesce(sum(list_value) filter (where given), 0)::int lv
                          from test.fx486 where in_range and category = 'guia' group by company) q),
               '7 totals by company (Guía only; Canopy Tours with a voided courtesy that is not given)');
select test.eq(test.rep486('final') #> '{totals,by_category}' @> '[{"category": "local", "rows": 17, "given": 8, "discount": 3270,
                                                                    "list_value": 32700}]', true,
               '7 by hand: Local has 17 rows, 8 given (L1, L2, L6, L10, L11, L12, L13, L16 at its lines left; the anomalies add nothing): ₡3270 off ₡32700');
select test.eq(test.rep486('final') #> '{totals,by_company}' @> '[{"company": "Tours Quitados", "rows": 1, "given": 1, "discount": 4000,
                                                                   "list_value": 4000}]', true,
               '7 by hand: G5''s company: one courtesy of ₡4000, the same list value as its line in the courtesies (one figure per courtesy)');
select test.eq(test.rep486('final') #> '{totals,by_category}' @> '[{"category": null, "rows": 3, "given": 1, "discount": 500,
                                                                    "list_value": 2200}]', true,
               '7 by hand: the old window in range has 3 rows (O1, O3, O4), 1 given (O3: ₡500 off ₡2200)');
-- the courtesies: the covered lines of the given Guía rows by their stamped rate (null as null); no tax computed
select test.eq(test.rep486('final') -> 'courtesies',
               '[{"tax_rate": null, "list_value": 1300}, {"tax_rate": 0.04, "list_value": 1500}, {"tax_rate": 0.13, "list_value": 12600}]'::jsonb,
               '7 courtesies by IVA rate: no rate ₡1300, 4 % ₡1500, 13 % ₡12600 (G1, G2, G4''s covered Cappuccino and G5''s line left; '
               'not the voided G3, not G4''s Espresso added after, not G5''s line taken off)');
select test.eq((select count(*)::int from jsonb_array_elements(test.rep486('final') -> 'courtesies') c, jsonb_object_keys(c) k
                 where k not in ('tax_rate', 'list_value')), 0, '7 the courtesies carry no tax amount (A-13: information only)');
-- the sale that used an approval another order had already used: listed apart, under the approval it claimed (P4)
select test.eq((select jsonb_agg(x - 'at' - 'products') from jsonb_array_elements(test.rep486('final') -> 'anomalies') x),
               (select jsonb_agg(jsonb_build_object('order_id', test.o486(n), 'approval', :'l2_id', 'category', 'local',
                 'authorizer', 'Ana', 'role', 'manager', 'beneficiary', null, 'company', null,
                 'status', st, 'station', 'Caja A', 'receipt_no', (select receipt_no from public.orders where id = test.o486(n)),
                 'subtotal', 2200, 'discount', 220, 'total', 1980, 'charged', ch, 'refunded', rf, 'reason', 'Local · not verified',
                 'flags', '["discount_not_verified"]'::jsonb) order by o)
                  from (values (1, 40, 'used_unverified', 1980, 0), (2, 41, 'voided', 0, 0), (3, 49, 'refunded', 1980, 1980),
                               (4, 47, 'open_bill', 0, 0), (5, 48, 'bill_cancelled', 0, 0)) v(o, n, st, ch, rf)),
               '7 five anomalies, the orders that claimed L2 after its ticket, in log order: each with the rows'' status ladder (used_unverified, '
               'voided, refunded, open_bill, bill_cancelled) and what it really charged and gave back; its station, receipt, subtotal, '
               'discount, total, reason, flags; the claimed approval''s category and who (P4: Ana, manager)');
select test.eq((select x ->> 'station' from jsonb_array_elements(test.rep486('final') -> 'anomalies') x limit 1),
               (select station from public.orders where id = test.o486(40)),
               '7 the anomaly''s station is its own sale''s (o.station, api-0038 §4.6: the CSV''s «station» cell of a not-verified sale)');
select test.eq((select (x ->> 'at')::timestamptz from jsonb_array_elements(test.rep486('final') -> 'anomalies') x limit 1),
               (select created_at from public.orders where id = test.o486(40)), '7 the anomaly''s time is its order''s');
select test.eq((select x -> 'products' from jsonb_array_elements(test.rep486('final') -> 'anomalies') x limit 1),
               jsonb_build_array(test.ln486('Latte', 2200)),
               '7 the anomaly lists its sale''s products (P4: a not-verified sale keeps its products; item 16 «for a '
               'not-verified sale, its products»)');
select test.eq((test.row486('final', :'l2_id') ->> 'status') || '|' || (test.row486('final', :'l2_id') ->> 'authorizer'), 'used|Ana',
               '7 the approval it claimed is a row of its own (used by its first sale, authorized by Ana)');
select test.eq(jsonb_array_length(test.rep486('d2') -> 'anomalies') || '|' || jsonb_array_length(test.rep486('yesterday') -> 'anomalies'),
               '0|0', '7 the anomaly belongs to today only (its log row''s day)');

-- 8) the wrong-code block, per Costa Rica day (mecanismo §10.5) ------------------------------------------------------
select test.eq((select string_agg(x ->> 'day', ',' order by o) from jsonb_array_elements(test.rep486('d2_today') -> 'wrong_codes')
                  with ordinality w(x, o)), :'d2' || ',' || :'today',
               '8 from D2 to today: one entry for D2 and one for today, none for yesterday (no row that day)');
select test.eq((select string_agg(x ->> 'day', ',') from jsonb_array_elements(test.rep486('today') -> 'wrong_codes') x), :'today',
               '8 today''s report has today''s entry only');
select test.eq(test.rep486('yesterday') -> 'wrong_codes', '[]'::jsonb, '8 yesterday: no entry');
select test.eq((select string_agg(distinct k, ',' order by k) from jsonb_array_elements(test.rep486('d2_today') -> 'wrong_codes') x,
                       jsonb_object_keys(x) k),
               'alerts,by_step,by_why,day,ended,enrolled,person_locked,places,refused,shared,unknown,unknown_stations,wrong',
               '8 the keys of a day: no pause or lift fields (mecanismo §10.5)');
select test.eq((select string_agg(distinct k, ',' order by k) from jsonb_array_elements(test.rep486('d2_today') -> 'wrong_codes') x,
                       jsonb_array_elements(x -> 'places') p, jsonb_object_keys(p) k),
               'rebound,resumes,signed_out,slot,stations,stops,waits,wrong', '8 the keys of a place');
-- today
select coalesce(test.wday486('today', :'today'), '{}'::jsonb) as wt \gset
select test.eq((:'wt'::jsonb) -> 'wrong', '7', '8 today: 7 wrong codes (2 at Caja A, 2 at Caja B, 3 at Caja C)');
select test.eq((:'wt'::jsonb) -> 'by_step', '{"manager": 3, "owner": 1, "employee": 3}'::jsonb, '8 today: by step');
select test.eq((:'wt'::jsonb) -> 'by_why', '{"no_match": 2, "not_allowed": 2, "owner_beneficiary": 1, "ambiguous": 2}'::jsonb,
               '8 today: by why (no_match, not_allowed, owner_beneficiary, ambiguous)');
select test.eq((:'wt'::jsonb) -> 'refused', '1', '8 today: one discount_refused row (the request backstop of L8)');
select test.eq((:'wt'::jsonb) -> 'shared', '2', '8 today: two pin_duplicate rows (a code two people share, at both steps)');
select test.eq((:'wt'::jsonb) -> 'unknown', '2', '8 today: two attempts from unregistered devices');
select test.eq((:'wt'::jsonb) -> 'unknown_stations', '["Barra", "Cocina"]'::jsonb, '8 today: and the names their pages reported');
select test.eq((:'wt'::jsonb) -> 'alerts', '[]'::jsonb, '8 today: no alert (7 wrong codes in 24 hours)');
select test.eq((:'wt'::jsonb) -> 'person_locked', '1', '8 today: one approval with person_locked (L9; L9b''s row is nine days ago)');
select test.eq(test.noat486((:'wt'::jsonb) -> 'enrolled'),
               '[{"slot": 3, "by": "Bea", "station": "Caja D", "replaced_station": null},
                 {"slot": 2, "by": "Ana", "station": "Caja E", "replaced_station": "Caja B"}]'::jsonb,
               '8 today: registrations, who, and the replaced till (Caja D by Bea; Caja E by Ana in place of Caja B)');
select test.eq(test.noat486((:'wt'::jsonb) -> 'ended'),
               '[{"slot": 3, "by": "Ana", "how": "manager", "station": "Caja C"},
                 {"slot": 2, "by": "Ana", "how": "replaced", "station": "Caja B"},
                 {"slot": 1, "by": "owner (SQL Editor)", "how": "sql_editor", "station": "Caja A"},
                 {"slot": 2, "by": "owner (SQL Editor)", "how": "sql_editor", "station": "Caja E"},
                 {"slot": 3, "by": "owner (SQL Editor)", "how": "sql_editor", "station": "Caja D"}]'::jsonb,
               '8 today: endings, who and how (removed by Ana, replaced, then the owner''s SQL tool)');
select test.eq((select string_agg(p ->> 'slot', ',' order by p ->> 'slot') from jsonb_array_elements((:'wt'::jsonb) -> 'places') p),
               '1,2,3', '8 today: the three places that had wrong codes or a rebind');
select test.eq(test.place486('today', :'today', 1) - 'waits' - 'slot',
               '{"stations": ["Caja A"], "wrong": 2, "stops": 0, "resumes": [], "signed_out": 0, "rebound": 1}'::jsonb,
               '8 today place 1: Caja A, 2 wrong codes, no stop, no resume, its rebind by key');
select test.eq(test.place486('today', :'today', 2) - 'waits' - 'slot',
               '{"stations": ["Caja B"], "wrong": 2, "stops": 0, "resumes": [], "signed_out": 0, "rebound": 0}'::jsonb,
               '8 today place 2: Caja B, 2 wrong codes');
select test.eq(test.place486('today', :'today', 3) - 'waits' - 'slot',
               '{"stations": ["Caja C"], "wrong": 3, "stops": 0, "resumes": [], "signed_out": 0, "rebound": 0}'::jsonb,
               '8 today place 3: its registered till «Caja C» (not the page''s «Tablet C»), 3 wrong codes');
select test.eq((test.place486('today', :'today', 1) ->> 'waits') || '|' || (test.place486('today', :'today', 2) ->> 'waits') || '|'
               || (test.place486('today', :'today', 3) ->> 'waits'), '0|0|1',
               '8 today: waits started per place (Caja C''s 3rd wrong code started one)');
select test.eq((select count(*)::int || '|' || count(*) filter (where e ->> 'at' is null
                          or ((e ->> 'at')::timestamptz at time zone 'America/Costa_Rica')::date <> :'today'::date)::int
                  from jsonb_array_elements(((:'wt'::jsonb) -> 'enrolled') || ((:'wt'::jsonb) -> 'ended')) e), '7|0',
               '8 today: each of the 2 registrations and 5 endings carries its time, today');
-- D2
select coalesce(test.wday486('d2', :'d2'), '{}'::jsonb) as wd \gset
select test.eq((:'wd'::jsonb) -> 'wrong', '31', '8 D2: 31 wrong codes (12 at Caja A, 7 at Caja B, 12 at Caja C)');
select test.eq((:'wd'::jsonb) -> 'by_step', '{"manager": 30, "employee": 1}'::jsonb, '8 D2: by step');
select test.eq((:'wd'::jsonb) -> 'by_why', '{"no_match": 30, "not_allowed": 1}'::jsonb, '8 D2: by why');
select test.eq(((:'wd'::jsonb) ->> 'refused') || '|' || ((:'wd'::jsonb) ->> 'shared') || '|' || ((:'wd'::jsonb) ->> 'person_locked'), '0|0|0',
               '8 D2: no refusal after a valid code, no shared code, no person_locked approval');
select test.eq(((:'wd'::jsonb) ->> 'unknown') || '|' || ((:'wd'::jsonb) ->> 'unknown_stations'), '1|["Cocina"]',
               '8 D2: one attempt from an unregistered device, named «Cocina»');
select test.eq(test.noat486((:'wd'::jsonb) -> 'alerts'), '[{"cafe_24h": 10}]'::jsonb,
               '8 D2: the alert, at the café''s 10th wrong code in 24 hours');
select test.eq(test.noat486((:'wd'::jsonb) -> 'enrolled'),
               '[{"slot": 1, "by": "Ana", "station": "Caja A", "replaced_station": null},
                 {"slot": 2, "by": "Ana", "station": "Caja B", "replaced_station": null},
                 {"slot": 3, "by": "Bea", "station": "Caja C", "replaced_station": null}]'::jsonb,
               '8 D2: the three registrations and who made them');
select test.eq((:'wd'::jsonb) -> 'ended', '[]'::jsonb, '8 D2: no ending (a rebind is not an ending)');
select test.eq(test.place486('d2', :'d2', 1) - 'waits' - 'slot' - 'resumes',
               '{"stations": ["Caja A"], "wrong": 12, "stops": 1, "signed_out": 0, "rebound": 0}'::jsonb,
               '8 D2 place 1: Caja A, 12 wrong codes, one stop');
select test.eq(test.noat486(test.place486('d2', :'d2', 1) -> 'resumes'), '[{"how": "manager", "by": "Bea"}]'::jsonb,
               '8 D2 place 1: resumed by Bea with her PIN');
select test.eq(test.place486('d2', :'d2', 2) - 'waits' - 'slot' - 'resumes',
               '{"stations": ["Caja B"], "wrong": 7, "stops": 0, "signed_out": 0, "rebound": 1}'::jsonb,
               '8 D2 place 2: Caja B, 7 wrong codes, no stop, its rebind by key');
select test.eq(test.noat486(test.place486('d2', :'d2', 2) -> 'resumes'), '[{"how": "sql_editor", "by": "owner (SQL Editor)"}]'::jsonb,
               '8 D2 place 2: resumed by the owner''s SQL tool');
select test.eq(test.place486('d2', :'d2', 3) - 'waits' - 'slot' - 'resumes',
               '{"stations": ["Caja C"], "wrong": 12, "stops": 1, "signed_out": 0, "rebound": 0}'::jsonb,
               '8 D2 place 3: Caja C, 12 wrong codes, one stop');
select test.eq(test.noat486(test.place486('d2', :'d2', 3) -> 'resumes'),
               '[{"how": "owner_code", "by": "owner login · owner@test.local"}]'::jsonb, '8 D2 place 3: resumed by the owner with the phone code');
select test.eq((test.place486('d2', :'d2', 2) ->> 'waits') || '|' || (test.place486('d2', :'d2', 3) ->> 'waits'), '3|0',
               '8 D2: waits started at Caja B (its 3rd wrong code, the 3rd after the resume, the 4th in that hour) and none at Caja C');
select test.eq(test.place486('d2', :'d2', 1) -> 'waits', '0'::jsonb,
               '8 D2: no wait started at Caja A: its 12th wrong code was the 3rd in its hour but stopped the till instead '
               '(the answer said blocked stopped, wait stop); mecanismo §10.5 counts waits started');
select test.eq((select count(*)::int || '|' || count(*) filter (where e ->> 'at' is null
                          or ((e ->> 'at')::timestamptz at time zone 'America/Costa_Rica')::date <> :'d2'::date)::int
                  from jsonb_array_elements(((:'wd'::jsonb) -> 'enrolled') || ((:'wd'::jsonb) -> 'alerts')
                        || (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements((:'wd'::jsonb) -> 'places') p,
                                   jsonb_array_elements(p -> 'resumes') r)) e), '7|0',
               '8 D2: each of the 3 registrations, the alert and the 3 resumes carries its time, on D2');
select test.eq((select count(*)::int from jsonb_array_elements(test.rep486('d2_today') -> 'wrong_codes') x,
                       jsonb_array_elements(x -> 'places') p where (p -> 'signed_out')::int <> 0), 0,
               '8 no sign-outs: descuento_caja_cerrar is not built in this release (L1)');
select test.eq(test.wday486('d2_today', :'d2'), test.wday486('d2', :'d2'), '8 a day''s entry is the same whatever the range around it');
-- a day with only an old-window approval's log row has no entry; a day with a person_locked approval's row has one
select test.eq(test.rep486('day10') -> 'wrong_codes', '[]'::jsonb,
               '8 ten days ago only an old-window discount_approved row (O2''s): no entry that day');
select test.eq(test.rep486('day9') -> 'wrong_codes',
               jsonb_build_array(jsonb_build_object('day', public.cr_today() - 9, 'wrong', 0, 'by_step', '{}'::jsonb,
                 'by_why', '{}'::jsonb, 'refused', 0, 'places', '[]'::jsonb, 'enrolled', '[]'::jsonb, 'ended', '[]'::jsonb,
                 'shared', 0, 'unknown', 0, 'unknown_stations', '[]'::jsonb, 'alerts', '[]'::jsonb, 'person_locked', 1)),
               '8 nine days ago only L9b''s person_locked approval row: an entry that counts it');

-- 9) nothing private in the report, and the report writes nothing -------------------------------------------------------
select test.eq((select string_agg(distinct w.k, ',') from test.reps486 r, test.walk486(r.j) w
                 where w.k in ('session_id', 'session_tag', 'session', 'key', 'key_hash', 'login_id', 'request_id', 'till_id', 'pin')),
               null, '9 no report carries a sign-in id or tag, a device key, a login or request id, or a PIN key');
select test.eq((select count(*)::int from test.reps486 r, test.walk486(r.j) w where w.v ~ 'sess-486'), 0,
               '9 no raw sign-in id appears in any value');
select test.eq((select count(*)::int from test.reps486 r, test.walk486(r.j) w, test.t486_people p where w.v = p.pin), 0,
               '9 no PIN appears as a value');
select test.eq((select count(*)::int from test.reps486 r, test.walk486(r.j) w, test.dv486 d
                 where d.key is not null and w.v = d.key), 0, '9 no device key appears as a value');
select test.eq((select count(*)::int from public.audit_log where action not in ('access_open', 'sales_access')), :'audit_n0'::int,
               '9 the report wrote no log row (every call above)');
select test.eq((select md5(coalesce(string_agg(t::text, '|' order by t.id), '')) from public.discount_approvals t), :'appr0',
               '9 and changed no approval (an expired one stays as it was: the report only names it)');

-- 10) the report looks up a removal after a payment once per approval of the range (and the give-back once): by its own
--     partial index, never a pass over the whole log each time (the log only grows; the month's call must stay far under
--     the 8 s statement timeout Supabase gives a signed-in page)
create function test.plan486(q text) returns text language plpgsql as $$
declare r text; t text := '';
begin
  for r in execute 'explain (costs off) ' || q loop t := t || r || E'\n'; end loop;
  return t;
end $$;
select test.ok(position('x.action = ''discount_removed_paid'' and x.details ->> ''approval'' = a.id::text' in prosrc) > 0,
               '10 descuentos_informe looks the removal up by action and approval') from pg_proc where oid = 'public.descuentos_informe(date,date)'::regprocedure;
select test.ok(position('x.action = ''discount_removed_paid'' and x.details ->> ''approval'' = a.id::text' in prosrc) > 0,
               '10 ... and so does _discount_freeable') from pg_proc where oid = 'public._discount_freeable(public.discount_approvals)'::regprocedure;
set local enable_seqscan = off;
select test.plan486($q$select k.kept from public.discount_approvals a left join lateral (select x.details ->> 'discount_kept' as kept
                         from public.audit_log x where x.action = 'discount_removed_paid' and x.details ->> 'approval' = a.id::text
                        order by x.id desc limit 1) k on true$q$) as plan_rp \gset
select test.plan486($q$select 1 from public.discount_approvals a where exists (select 1 from public.audit_log x
                         where x.action = 'discount_removed_paid' and x.details ->> 'approval' = a.id::text)$q$) as plan_fr \gset
set local enable_seqscan = on;
select test.ok(:'plan_rp' ~ 'audit_log_discount_removed_paid', '10 that lookup reads the index audit_log_discount_removed_paid (by approval, then id)', :'plan_rp');
select test.ok(:'plan_fr' ~ 'audit_log_discount_removed_paid', '10 ... and so does the give-back''s', :'plan_fr');
select test.eq((select indexdef from pg_indexes where indexname = 'audit_log_discount_removed_paid'),
               'CREATE INDEX audit_log_discount_removed_paid ON public.audit_log USING btree (((details ->> ''approval''::text)), id) WHERE (action = ''discount_removed_paid''::text)',
               '10 the index: (details ->> approval, id) where action = discount_removed_paid');

select test.done();
rollback;
