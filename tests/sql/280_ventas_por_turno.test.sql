-- Sales by shift (supabase/tools/ventas-por-turno.sql), the owner's read-only report while the POS does not record
-- who takes the money: for each sale, who was clocked in (one name, "compartida (n)" or "nadie con entrada"), plus
-- summaries per person and per station for each Costa Rica day. The file runs as shipped: its first statement makes
-- the paste a read-only transaction, it reads only columns production had before migration 0000, and it shows no PIN
-- hash or email.
begin;
-- Costa Rica time, whatever the session's time zone: the instant of "k days ago at hh:mm:ss" in Costa Rica
create function pg_temp.cr(k int, t text) returns timestamptz language sql stable as $$
  select (((now() at time zone 'America/Costa_Rica')::date - k) + t::time)::timestamp at time zone 'America/Costa_Rica'
$$;
create function pg_temp.day(k int) returns date language sql stable as $$
  select (now() at time zone 'America/Costa_Rica')::date - k
$$;
-- the report covers today and the 6 days before; nothing else in this database falls near them
select test.eq((select count(*)::int from public.orders where created_at >= pg_temp.cr(9, '00:00')), 0,
               'precondition: no other sales near the report''s days');
select test.eq((select count(*)::int from public.time_entries where clock_in >= pg_temp.cr(10, '00:00')), 0,
               'precondition: no other shifts near the report''s days');

insert into public.staff (id, name, role, active, pin_hash) values
  ('c2800000-0000-4000-8000-000000000001', 'Persona Uno', 'staff', true, extensions.crypt('2716', extensions.gen_salt('bf'))),
  ('c2800000-0000-4000-8000-000000000002', 'Persona Dos', 'manager', true, extensions.crypt('3829', extensions.gen_salt('bf'))),
  ('c2800000-0000-4000-8000-000000000003', 'Persona Tres', 'staff', true, extensions.crypt('4937', extensions.gen_salt('bf'))),
  ('c2800000-0000-4000-8000-000000000004', 'Persona Cuatro', 'staff', true, extensions.crypt('5148', extensions.gen_salt('bf')));
insert into public.time_entries (staff_id, clock_in, clock_out) values
  -- 5 days ago: Uno 07:00-12:00, Dos 11:00-15:00
  ('c2800000-0000-4000-8000-000000000001', pg_temp.cr(5, '07:00'), pg_temp.cr(5, '12:00')),
  ('c2800000-0000-4000-8000-000000000002', pg_temp.cr(5, '11:00'), pg_temp.cr(5, '15:00')),
  -- 4 days ago: Tres clocked in at 07:00 and never clocked out (counts until 23:00)
  ('c2800000-0000-4000-8000-000000000003', pg_temp.cr(4, '07:00'), null),
  -- a night shift across midnight, 3 days ago 20:00 to 2 days ago 02:00
  ('c2800000-0000-4000-8000-000000000001', pg_temp.cr(3, '20:00'), pg_temp.cr(2, '02:00')),
  -- a forgotten clock-out: Cuatro clocked in 2 days ago at 06:00 and tapped the green card yesterday at 06:30, which
  -- clocked OUT (the card is a toggle) and closed a shift of 24 h 30 (counts until 22:00)
  ('c2800000-0000-4000-8000-000000000004', pg_temp.cr(2, '06:00'), pg_temp.cr(1, '06:30')),
  -- yesterday: Dos has two shifts at once (one left open, one closed)
  ('c2800000-0000-4000-8000-000000000002', pg_temp.cr(1, '08:00'), null),
  ('c2800000-0000-4000-8000-000000000002', pg_temp.cr(1, '08:05'), pg_temp.cr(1, '12:00'));
-- a discount approved by Dos (the trigger copies the approver's name onto the sale)
insert into public.discount_approvals (id, created_at, approved_by, approved_name, kind, value, reason, subtotal_crc, amount_crc)
  values ('c2820000-0000-4000-8000-000000000001', pg_temp.cr(5, '12:58'), 'c2800000-0000-4000-8000-000000000002', 'Persona Dos',
          'amount', 500, 'prueba', 3000, 500);
-- sales; every total is different so a row can be found by its amount
insert into public.orders (id, created_at, station, total_crc, payment_method, paid, status, source) values
  ('c2810000-0000-4000-8000-000000000001', pg_temp.cr(5, '08:00'), 'Caja · Uno', 1000, 'cash_crc', true, 'done', 'front'),
  ('c2810000-0000-4000-8000-000000000002', pg_temp.cr(5, '08:20'), 'Caja · Uno', 600, 'card', true, 'done', 'front'),       -- a bill, closed
  ('c2810000-0000-4000-8000-000000000004', pg_temp.cr(5, '09:00'), 'Caja · Uno', 5000, 'card', true, 'done', 'front'),      -- voided below
  ('c2810000-0000-4000-8000-000000000005', pg_temp.cr(5, '09:30'), 'Caja · Uno', 6000, 'pending', false, 'ready', 'front'), -- not paid yet
  ('c2810000-0000-4000-8000-000000000006', pg_temp.cr(5, '10:00'), null, 7000, 'cash_crc', true, 'done', 'room'),           -- a guest's room order
  ('c2810000-0000-4000-8000-000000000007', pg_temp.cr(5, '11:30'), 'Caja · Uno', 2000, 'card', true, 'done', 'front'),
  ('c2810000-0000-4000-8000-000000000008', pg_temp.cr(5, '12:04'), 'Caja · Dos', 3000, 'sinpe', true, 'done', 'front'),     -- Uno left 4 minutes ago
  ('c2810000-0000-4000-8000-000000000009', pg_temp.cr(5, '12:06'), 'Caja · Dos', 3500, 'cash_crc', true, 'done', 'front'),  -- 6 minutes ago
  ('c2810000-0000-4000-8000-000000000012', pg_temp.cr(5, '14:00'), 'Caja · Dos', -800, 'cash_crc', true, 'done', 'front'),  -- money given back
  ('c2810000-0000-4000-8000-000000000010', pg_temp.cr(5, '15:30'), 'Barra', 4000, 'cash_crc', true, 'done', 'front'),       -- nobody on shift
  ('c2810000-0000-4000-8000-000000000021', pg_temp.cr(4, '10:00'), 'Barra', 8000, 'card', true, 'done', 'front'),
  ('c2810000-0000-4000-8000-000000000022', pg_temp.cr(4, '22:30'), 'Barra', 1500, 'cash_crc', true, 'done', 'front'),       -- 15 h 30 after the open clock-in
  ('c2810000-0000-4000-8000-000000000023', pg_temp.cr(4, '23:10'), 'Barra', 1700, 'cash_crc', true, 'done', 'front'),       -- 16 h 10 after it
  ('c2810000-0000-4000-8000-000000000031', pg_temp.cr(3, '23:59:59'), 'Caja · Uno', 1100, 'card', true, 'done', 'front'),   -- the next day in UTC
  ('c2810000-0000-4000-8000-000000000032', pg_temp.cr(2, '00:00:00'), 'Caja · Uno', 1200, 'card', true, 'done', 'front'),
  ('c2810000-0000-4000-8000-000000000033', pg_temp.cr(2, '10:00'), 'Barra', 1300, 'cash_crc', true, 'done', 'front'),       -- 4 h after Cuatro's clock-in
  ('c2810000-0000-4000-8000-000000000034', pg_temp.cr(2, '23:30'), 'Barra', 1400, 'card', true, 'done', 'front'),           -- 17 h 30 after it
  ('c2810000-0000-4000-8000-000000000041', pg_temp.cr(1, '09:00'), 'Caja · Dos', 2200, 'sinpe', true, 'done', 'front'),
  ('c2810000-0000-4000-8000-000000000051', pg_temp.cr(7, '23:59:59'), 'Barra', 300, 'cash_crc', true, 'done', 'front'),     -- the day before the report
  ('c2810000-0000-4000-8000-000000000052', pg_temp.cr(6, '00:00:00'), 'Barra', 400, 'cash_crc', true, 'done', 'front'),     -- its first instant
  ('c2810000-0000-4000-8000-000000000053', pg_temp.cr(-1, '00:00:00'), 'Barra', 500, 'cash_crc', true, 'done', 'front');   -- tomorrow (a clock ahead)
-- one person of the bill paid their part at 08:30 on another device
insert into public.orders (id, created_at, station, total_crc, payment_method, paid, status, source, part_of) values
  ('c2810000-0000-4000-8000-000000000003', pg_temp.cr(5, '08:30'), 'Caja · Uno', 900, 'sinpe', true, 'done', 'front', 'c2810000-0000-4000-8000-000000000002');
insert into public.orders (id, created_at, station, subtotal_crc, discount_crc, discount_id, total_crc, payment_method, paid, status, source) values
  ('c2810000-0000-4000-8000-000000000011', pg_temp.cr(5, '13:00'), 'Caja · Dos', 3000, 500, 'c2820000-0000-4000-8000-000000000001', 2500, 'card', true, 'done', 'front');
update public.orders set voided_at = pg_temp.cr(5, '09:10'), void_reason = 'prueba' where id = 'c2810000-0000-4000-8000-000000000004';

-- 1) the file as shipped, in a savepoint, with a session time zone far from Costa Rica's
\set rc_file `mktemp`
\pset format unaligned
\pset fieldsep '\t'
\pset footer off
\pset null '¤'
-- rows written so far in this transaction (the fixtures), in every table
select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) as writes_before from pg_stat_xact_all_tables \gset
savepoint tool_run;
set local timezone = 'Asia/Tokyo';
\o :rc_file
\ir ../../supabase/tools/ventas-por-turno.sql
\o
select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) as writes_after from pg_stat_xact_all_tables \gset
-- still inside the tool's transaction: the database refuses any write
select current_setting('transaction_read_only') as read_only_after \gset
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
insert into public.time_entries (staff_id, clock_in) values ('c2800000-0000-4000-8000-000000000001', now());
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`
select test.eq(:'read_only_after'::text, 'on', 'after the report ran, the transaction is read only');
select test.ok(:'LAST_ERROR_SQLSTATE' = '25006' and :'LAST_ERROR_MESSAGE' ~ 'cannot execute INSERT in a read-only transaction',
               'after the report ran, a write is refused by the database');
select test.eq(:'writes_after'::bigint, :'writes_before'::bigint, 'the report wrote no row in any table, before or after its read-only line');

-- one row per output line: n is its position (line 1 is the header)
create temp table t280 as
select l.n::int as n, l.line, f[1] as fila, nullif(f[2], '')::date as dia, f[3] as hora, f[4] as atribucion, f[5] as estacion,
       nullif(f[6], '¤')::int as ventas, f[7]::bigint as total_crc, f[8] as detalle, f[9] as pago, f[10] as en_turno,
       nullif(f[11], '¤') as descuento
  from regexp_split_to_table(:'rc', E'\n') with ordinality l(line, n), lateral (select string_to_array(l.line, E'\t') as f) s
 where l.n > 1 and array_length(f, 1) = 11;
select test.eq((select split_part(:'rc', E'\n', 1)),
               E'fila\tdia\thora\tatribucion\testacion\tventas\ttotal_crc\tdetalle\tpago\ten_turno\tdescuento_aprobado_por',
               'the columns, in order');
select test.eq((select count(*)::int from regexp_split_to_table(:'rc', E'\n') x where x <> ''), 1 + (select count(*)::int from t280),
               'every line after the header is a row of 11 columns');
create temp table t280_venta as select * from t280 where fila = 'venta';

-- which sales: today and the 6 days before, in Costa Rica time; the day before and tomorrow are left out
select test.eq((select string_agg(total_crc::text, ' ' order by n) from t280_venta),
               '400 1000 600 900 5000 6000 7000 2000 3000 3500 2500 -800 4000 8000 1500 1700 1100 1200 1300 1400 2200',
               'one row per sale of the 7 days, by day and time (voided, unpaid and room orders listed too)');
select test.eq((select dia || ' ' || hora || ' ' || atribucion from t280_venta where total_crc = 400),
               pg_temp.day(6) || ' 00:00 nadie con entrada', 'the first instant of the first day is in');
select test.eq((select dia || ' ' || hora || ' · ' || (select dia || ' ' || hora from t280_venta where total_crc = 1200) from t280_venta where total_crc = 1100),
               pg_temp.day(3) || ' 23:59 · ' || pg_temp.day(2) || ' 00:00',
               'Costa Rica days: 23:59:59 belongs to its day (in UTC and in the session''s Tokyo time it is the next one), 00:00:00 to the next');

-- who was clocked in
select test.eq((select atribucion || ' [' || en_turno || ']' from t280_venta where total_crc = 1000),
               'Persona Uno [Persona Uno]', 'one person on shift: the sale shows their name');
select test.eq((select atribucion || ' [' || en_turno || ']' from t280_venta where total_crc = 2000),
               'compartida (2) [Persona Dos, Persona Uno]', 'two people on shift: "compartida (2)" and both names');
select test.eq((select string_agg(hora || ' ' || atribucion, ', ' order by n) from t280_venta where total_crc in (3000, 3500)),
               '12:04 compartida (2), 12:06 Persona Dos', 'a clock-out counts 5 more minutes, not 6');
select test.eq((select atribucion || ' [' || en_turno || ']' from t280_venta where total_crc = 4000),
               'nadie con entrada []', 'nobody on shift: "nadie con entrada"');
select test.eq((select string_agg(hora || ' ' || atribucion || ' [' || en_turno || ']', ', ' order by n) from t280_venta where total_crc in (8000, 1500, 1700)),
               '10:00 Persona Tres [Persona Tres (sin salida)], 22:30 Persona Tres [Persona Tres (sin salida)], 23:10 nadie con entrada []',
               'a shift with no clock-out counts 16 hours and is flagged "(sin salida)"');
select test.eq((select string_agg(hora || ' ' || atribucion || ' [' || en_turno || ']', ', ' order by n) from t280_venta where total_crc in (1300, 1400)),
               '10:00 Persona Cuatro [Persona Cuatro (más de 16 h)], 23:30 nadie con entrada []',
               'a closed shift of more than 16 hours (a forgotten clock-out closed the next day) counts 16 hours and is flagged "(más de 16 h)"');
select test.eq((select atribucion || ' [' || en_turno || ']' from t280_venta where total_crc = 2200),
               'Persona Dos [Persona Dos (sin salida)]', 'one person with two shifts at once is one person');
select test.eq((select atribucion || ' · ' || estacion || ' · ' || detalle || ' [' || en_turno || ']' from t280_venta where total_crc = 7000),
               'huésped (habitación) · (habitación) · pedido de habitación [Persona Uno]', 'a room order is the guest''s, not the person on shift''s');
select test.eq((select string_agg(total_crc || ' ' || detalle || ' ' || pago, ', ' order by n) from t280_venta where total_crc in (600, 900, 5000, 6000, -800)),
               '600 venta card, 900 pago parcial de una cuenta sinpe, 5000 anulada · no cuenta card, 6000 cuenta abierta, sin pagar · no cuenta pending, '
               '-800 devolución cash_crc',
               'what each sale is: a bill, a part payment, a voided sale and an unpaid bill (these two do not count), money given back');
select test.eq((select atribucion || ' · ' || descuento from t280_venta where total_crc = 2500), 'Persona Dos · Persona Dos',
               'the name of who approved a discount');
select test.eq((select count(*)::int from t280_venta where ventas is not null or descuento is not null and total_crc <> 2500), 0,
               'a sale row has no count and no approver unless there was a discount');

-- the summaries: first, every day in order, people then nobody then stations; the sales after them
select test.ok((select max(n) from t280 where fila <> 'venta') < (select min(n) from t280_venta), 'the summaries come before the sales');
select test.eq((select string_agg(dia || ' ' || fila, ', ' order by n) from t280 where fila <> 'venta'),
               (select string_agg(dia || ' ' || fila, ', ' order by dia, fila = 'RESUMEN ESTACIÓN', n) from t280 where fila <> 'venta'),
               'summaries by day: the people first, then the stations');
select test.eq((select string_agg(dia::text, ' ' order by dia) from (select distinct dia from t280 where fila <> 'venta') q),
               concat_ws(' ', pg_temp.day(6), pg_temp.day(5), pg_temp.day(4), pg_temp.day(3), pg_temp.day(2), pg_temp.day(1)),
               'a summary for each day with sales, none for the day before or tomorrow');
-- per person, 5 days ago: alone on shift in ventas/total_crc, shared ones in detalle; nobody last
select test.eq((select string_agg(atribucion || ' | ' || estacion || ' | ' || ventas || ' | ' || total_crc || ' | ' || detalle, E'\n' order by n)
                  from t280 where fila = 'RESUMEN PERSONA' and dia = pg_temp.day(5)),
               E'Persona Dos | Caja · Dos, Caja · Uno | 3 | 5200 | a solas en turno: 3 · compartidas: 2 (₡5000)\n'
               'Persona Uno | Caja · Dos, Caja · Uno | 3 | 2500 | a solas en turno: 3 · compartidas: 2 (₡5000)\n'
               '(nadie con entrada) | Barra | 1 | 4000 | nadie había marcado entrada',
               'per person: voided, unpaid and room orders left out; money given back counts');
select test.eq((select string_agg(dia || ' ' || atribucion || ' ' || ventas || ' ' || total_crc, ', ' order by n)
                  from t280 where fila = 'RESUMEN PERSONA' and dia <> pg_temp.day(5)),
               pg_temp.day(6) || ' (nadie con entrada) 1 400, ' || pg_temp.day(4) || ' Persona Tres 2 9500, ' || pg_temp.day(4) || ' (nadie con entrada) 1 1700, '
               || pg_temp.day(3) || ' Persona Uno 1 1100, ' || pg_temp.day(2) || ' Persona Cuatro 1 1300, ' || pg_temp.day(2) || ' Persona Uno 1 1200, '
               || pg_temp.day(2) || ' (nadie con entrada) 1 1400, ' || pg_temp.day(1) || ' Persona Dos 1 2200',
               'per person on the other days (a night shift counts on each side of midnight; a forgotten clock-out, 16 hours)');
-- per station, 5 days ago (compared in byte order: CI sorts text case- and punctuation-insensitively)
select test.eq((select string_agg(estacion || ' ' || ventas || ' ' || total_crc, ', ' order by estacion collate "C")
                  from t280 where fila = 'RESUMEN ESTACIÓN' and dia = pg_temp.day(5)),
               '(pedidos de habitación) 1 7000, Barra 1 4000, Caja · Dos 4 8200, Caja · Uno 4 4500',
               'per station: room orders in their own row; voided and unpaid sales left out');
select test.ok((select bool_and(atribucion = '' and en_turno = '' and detalle = '' and pago = '' and hora = '') from t280 where fila = 'RESUMEN ESTACIÓN'),
               'a station row has only its day, station, count and total');
-- each day's station rows add up to what the register close counts that day (supabase/register.sql's rule)
select test.eq((select string_agg(dia || ' ' || ventas || ' ' || total_crc, ', ' order by dia)
                  from (select dia, sum(ventas)::int as ventas, sum(total_crc) as total_crc from t280 where fila = 'RESUMEN ESTACIÓN' group by dia) q),
               (select string_agg(dia || ' ' || n || ' ' || t, ', ' order by dia) from (
                  select (created_at at time zone 'America/Costa_Rica')::date as dia, count(*)::int as n, sum(total_crc) as t
                    from public.orders o
                   where o.created_at >= pg_temp.cr(6, '00:00') and o.created_at < pg_temp.cr(-1, '00:00')
                     and o.voided_at is null and coalesce(o.paid, true)
                   group by 1) q),
               'the station rows of a day add up to the register close''s count and total');

-- nothing private: no PIN hash, no email, no secret
select test.eq((select count(*)::int from t280 r, public.staff s where s.pin_hash is not null and position(s.pin_hash in r.line) > 0), 0,
               'no PIN hash of any staff member appears');
select test.eq((select count(*)::int from t280 r, auth.users u where u.email is not null and position(lower(u.email) in lower(r.line)) > 0), 0,
               'no email appears');
select test.ok((select bool_and(line !~ '\$2[abxy]?\$|@|[0-9a-f]{8}-[0-9a-f]{4}-') from t280), 'no hash-like text, @ or id in any row');

-- 2) as an SQL Editor account that may read only these columns, the ones production had before migration 0000
--    (supabase/timeclock.sql, authorization.sql, kitchen-rooms.sql, pos-stations.sql, pos-tabs.sql): the same result,
--    so the report works on today's production and never reads a PIN hash; and in another session time zone
create temp table t280_first as select :'rc'::text as rc;
select 't280_editor_' || current_database() as editor \gset
create role :"editor" nologin bypassrls;
grant usage on schema public to :"editor";
grant select (id, created_at, total_crc, payment_method, station, source, status, paid, voided_at, part_of, discount_by) on public.orders to :"editor";
grant select (staff_id, clock_in, clock_out) on public.time_entries to :"editor";
grant select (id, name) on public.staff to :"editor";
savepoint tool_run;
set local role :"editor";
set local timezone = 'America/Los_Angeles';
\o :rc_file
\ir ../../supabase/tools/ventas-por-turno.sql
\o
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`
select test.eq(:'rc'::text, (select rc from t280_first), 'with only those columns (no PIN hash), in Los Angeles time, the report is the same');
\set rc_removed `rm -f :'rc_file'`
\pset format aligned
\pset footer on
\pset null ''
select test.done();
rollback;
