-- supabase/tools/reversion-0038.sql: undoes migration 0038 (the POS discounts, D-065), and 0038 then applies again
-- (proposal-final §2.12 and §5.1 «500», mecanismo-intentos §4, api-0038 §11, build plan L5). The reversal refuses while
-- 0038 is not applied or while a later migration is, and then changes nothing; it brings approve_discount,
-- _order_discount_check and tab_set_discount back byte for byte (the production snapshot's legacy fingerprints) with
-- their rights, drops the four new triggers and the 42 new functions and nothing else, deletes no data (the 13 columns
-- of discount_approvals with their rules and indexes, discount_tills with its rows and keys, the audit indexes and both
-- settings with their values stay) and takes version 38 off the ledger. The café then works as before 0038: the old
-- window, its sales and bills; a category approval already given is checked as an old one (its fixed rate, 30
-- minutes). 0038 then applies again over what the reversal left: every function and trigger as the first time, nothing
-- added twice, no data moved, the switch keeps its value, the Empleado limit holds, and the registered tills come back
-- with their places, keys and wrong-code counts (a reversal is no fresh budget). Everything the café does goes through
-- the real functions as the café login (authenticated, with a session_id); the structure is read as the test superuser.
begin;

-- helpers (test schema, rolled back with the file) --------------------------------------------------------------------
create function test.o500(n int) returns uuid language sql immutable as $$
  select ('d5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
-- a device of the café: test.login resets the claims and the unlock header, test.session gives the sign-in its id
create function test.dev500(sess text) returns void language sql as $$ select test.login('cafe'); select test.session(sess) $$;
-- the discount window's call on that device, as pos.html sends it
create function test.a500(sess text, cat text, pin text, sub int, emp text default null, comp text default null,
                          bill uuid default null, expect int default null) returns jsonb language plpgsql as $$
begin
  perform test.dev500(sess);
  return public.descuento_autorizar(cat, pin, sub, emp, comp, bill, expect, null, 'Caja 500');
end $$;
-- a paid ticket of one line at p_sub (pos.html's pos_record_sale), p_disc off with approval p_appr
create function test.sale500(oid uuid, sub int, disc int default 0, appr uuid default null, at timestamptz default now())
returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', at, 'total_crc', sub - disc,
           'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'station', 'Caja 500', 'guest_name', 'Ticket 500',
           'subtotal_crc', case when disc = 0 then null else sub end, 'discount_crc', disc, 'discount_id', appr,
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', sub, 'qty', 1)))) $$;
-- an open «Pay later» bill of 10000 (4000 + 6000)
create function test.bill500(oid uuid) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', oid, 'created_at', now(), 'total_crc', 10000,
           'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja 500', 'source', 'front', 'guest_name', 'Mesa 500',
           'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
                                      jsonb_build_object('item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) $$;
-- the error a statement raises ('sqlstate:message'), or 'no error'; what a raising statement did is undone
create function test.err500(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'no error';
exception when others then
  return sqlstate || ':' || sqlerrm;
end $$;
-- the answer of a call that returns jsonb, or {"raised": "sqlstate:message"} when it raises (so a defect is reported by
-- the assertion that expects the answer, not by stopping the file)
create function test.try500(q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute q into r;
  return r;
exception when others then
  return jsonb_build_object('raised', sqlstate || ':' || sqlerrm);
end $$;
create function test.okr500(r jsonb) returns text language sql immutable as $$ select coalesce(r ->> 'ok', r ->> 'raised', 'null') $$;
-- the structure, read as the test superuser: every function of public, canopy and acct (body md5, rights, settings,
-- arguments with defaults), every trigger, constraint, index and column, every table's row security, rights and rules
create function test.fns500() returns table (k text, h text, secdef boolean, cfg text, acl text, args text, res text)
language sql stable as $$
  select p.oid::regprocedure::text, md5(p.prosrc), p.prosecdef, coalesce(p.proconfig::text, '-'), coalesce(p.proacl::text, '-'),
         pg_get_function_arguments(p.oid), coalesce(pg_get_function_result(p.oid), '-')
    from pg_proc p where p.pronamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.trg500() returns table (k text, v text) language sql stable as $$
  select c.oid::regclass::text || '.' || g.tgname, pg_get_triggerdef(g.oid) || ' [' || g.tgenabled::text || ']'
    from pg_trigger g join pg_class c on c.oid = g.tgrelid
   where not g.tgisinternal and c.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.cons500() returns table (k text, v text) language sql stable as $$
  select r.oid::regclass::text || '.' || k.conname, pg_get_constraintdef(k.oid)
    from pg_constraint k join pg_class r on r.oid = k.conrelid
   where r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.idx500() returns table (k text, v text) language sql stable as $$
  select x.indexrelid::regclass::text, pg_get_indexdef(x.indexrelid)
    from pg_index x join pg_class r on r.oid = x.indrelid
   where r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.cols500() returns table (k text, v text) language sql stable as $$
  select r.oid::regclass::text || '.' || a.attname,
         format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
           || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')
    from pg_attribute a join pg_class r on r.oid = a.attrelid
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where r.relkind in ('r', 'p', 'v') and a.attnum > 0 and not a.attisdropped
     and r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.sec500() returns table (k text, v text) language sql stable as $$
  select r.oid::regclass::text, r.relrowsecurity::text || ' ' || r.relforcerowsecurity::text || ' ' || coalesce(r.relacl::text, '-')
    from pg_class r where r.relkind in ('r', 'p', 'v')
     and r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace)
  union all
  select 'policy ' || schemaname || '.' || tablename || '.' || policyname,
         cmd || ' ' || roles::text || ' ' || coalesce(qual, '-') || ' ' || coalesce(with_check, '-')
    from pg_policies where schemaname in ('public', 'canopy', 'acct', 'storage') $$;
-- every row of every table of public, canopy and acct except the ledger, as a count and an md5 per table
create function test.data500() returns table (k text, v text) language plpgsql stable as $$
declare r record;
begin
  for r in select c.oid::regclass::text as n from pg_class c
            where c.relkind in ('r', 'p') and c.oid <> 'canopy.migrations'::regclass
              and c.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) order by 1 loop
    k := r.n;
    execute format('select count(*) || '':'' || coalesce(md5(string_agg(x::text, E''\n'' order by x::text)), ''-'') from %s x', r.n) into v;
    return next;
  end loop;
end $$;
-- the keys (column k) of the rows that differ between two captures, in either direction; each argument is a relation
-- name or a parenthesized query
create function test.diff500(a text, b text) returns text language plpgsql as $$
declare res text;
begin
  execute format('select coalesce(string_agg(distinct k, '' '' order by k), '''') from ('
                 || '(select j ->> ''k'' from (select to_jsonb(x) from %1$s x except select to_jsonb(y) from %2$s y) q(j)) union all '
                 || '(select j ->> ''k'' from (select to_jsonb(y) from %2$s y except select to_jsonb(x) from %1$s x) q(j))) z(k)', a, b) into res;
  return res;
end $$;
-- the read-only owner tools' cells (one JSON value each), kept by name
create temp table snap500 (k text primary key, j jsonb);
\set tmp500 `mktemp`

-- 0) the state made under 0038, through the real functions ----------------------------------------------------------
-- 0039 and 0040 (Proveedores) come after: they are reverted first (each reversal refuses while a later migration is applied)
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\ir ../../supabase/tools/reversion-0039.sql
\o
set local lock_timeout = 0;   -- as before those two reversals (the check in 2 reads it)
select test.eq(public.canopy_schema_version(), 38, '0 the database is at version 38');
-- the 42 functions 0038 adds (api-0038 §4 and §6: 11 public, 28 internal, 3 for the triggers) and the 3 it replaces
create temp table new500 (sig text);
insert into new500 select to_regprocedure(s)::text from unnest(array[
  'public.descuento_estado(text)', 'public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text)',
  'public.descuento_liberar(uuid, uuid)', 'public.descuento_quitar_cuenta(uuid, int, text, uuid, text, text, uuid)',
  'public.descuento_cupo_devolver(uuid, uuid, text, text)', 'public.descuentos_informe(date, date)',
  'public.descuento_caja_registrar(text, uuid)', 'public.descuento_caja_volver(text, text)', 'public.descuento_cajas()',
  'public.descuento_caja_reanudar(int, uuid, text, text)', 'public.descuento_caja_quitar(uuid, uuid, text, text)',
  'public._discount_rate(text)', 'public._discount_label(text)', 'public._discount_clean(text)', 'public._discount_company(text)',
  'public._discount_reserved(text)', 'public._staff_by_code(text)', 'public._discount_till_limits()', 'public._discount_session()',
  'public._discount_tag(text)', 'public._discount_station(text)', 'public._discount_key_hash(text)', 'public._discount_new_key()',
  'public._discount_till_mine()', 'public._discount_slot_state(int)', 'public._discount_take_staff(uuid, text, text)',
  'public._discount_staff_state(uuid, text)', 'public._discount_person(uuid)', 'public._discount_places(uuid)',
  'public._discount_wrong(public.discount_tills, text, text, text, text, uuid, text)', 'public._discount_till_unknown(text, text)',
  'public._discount_answer(public.discount_approvals)', 'public._discount_bill_problem(uuid, int, int, boolean)',
  'public._discount_retake_day(uuid, date)', 'public._discount_freeable(public.discount_approvals)',
  'public._discount_places_summary()', 'public._discount_tills_resume_all(text)', 'public._discount_tills_end_all(text)',
  'public._pin_locks_clear_all(text)', 'public._order_discount_flags()', 'public._order_discount_after()',
  'public._discount_pin_changed()']) s;
create temp table old500 (sig text, legacy text, v0038 text);
insert into old500 values
  (to_regprocedure('public.approve_discount(uuid, text, text, int, int, text, text)')::text, '259bc8afa7ef', '8fa07d1f3abd'),
  (to_regprocedure('public._order_discount_check()')::text, '812056181d36', '33d8b472b586'),
  (to_regprocedure('public.tab_set_discount(uuid, uuid, int, text)')::text, '340dd98542a4', '22a3252832c4');
select test.eq((select count(*)::int from new500 where sig is not null), 42, '0 under 0038 the 42 new functions exist (11 public, 28 internal, 3 for the triggers)');
select test.eq((select string_agg(o.sig || ':' || left(md5(p.prosrc), 12), ' ' order by o.sig) from old500 o join pg_proc p on p.oid = o.sig::regprocedure),
               (select string_agg(sig || ':' || v0038, ' ' order by sig) from old500),
               '0 approve_discount, _order_discount_check and tab_set_discount carry the 0038 text (the snapshot''s 0038 fingerprints)');
select test.eq((select string_agg(tgname, ' ' order by tgname) from pg_trigger where tgrelid = 'public.orders'::regclass and tgname like 'order_zz_discount%'),
               'order_zz_discount order_zz_discount_after order_zz_discount_lock',
               '0 the three new triggers are on orders (order_zz_discount_lock: the per-employee lock before any stock row)');
select test.eq((select string_agg(tgname, ' ') from pg_trigger where tgrelid = 'public.staff'::regclass and tgfoid = 'public._discount_pin_changed()'::regprocedure),
               'staff_pin_changed', '0 ... and staff_pin_changed on staff (a new or removed PIN ends that person''s unlocks on other devices)');

-- Guía on, as only the owner with the phone code can, after the accountant's confirmation (A-13): a non-default value
-- the reversal and the reapply must keep
select test.login('owner', 'aal2'); set role authenticated;
select public.compliance_confirm('courtesy_iva_confirmed', 'Contador (prueba)', 'A-13 (prueba)') ->> 'ok' as cc \gset
select public.setting_set('pos_discount_guia', '"on"') ->> 'ok' as so \gset
reset role;
select test.eq(:'cc' || ' ' || :'so', 'true true', '0 (fixture) the owner records the accountant''s confirmation and turns Guía on');
-- two tills, each registered on its own device by Ana with the owner areas open there (Reloj de marcas › Bitácora)
select test.dev500('till-500-a'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.descuento_caja_registrar('Caja A 500') as ra \gset
reset role;
select test.dev500('till-500-b'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.descuento_caja_registrar('Caja B 500') as rb \gset
reset role;
select (:'ra'::jsonb) ->> 'key' as key_a \gset
select test.eq((:'ra'::jsonb) ->> 'ok' || ' ' || ((:'ra'::jsonb) ->> 'slot') || ' ' || ((:'rb'::jsonb) ->> 'ok') || ' ' || ((:'rb'::jsonb) ->> 'slot')
               || ' ' || ((:'ra'::jsonb) ->> 'key' ~ '^[0-9a-f]{64}$')::text,
               'true 1 true 2 true', '0 (fixture) Ana registers «Caja A 500» in place 1 and «Caja B 500» in place 2; each device keeps its key');
-- category approvals at till A (Ana's code; the owner's for Guía), some used now, some left for after the reversal
set role authenticated;
select test.a500('till-500-a', 'local', '4826', 5000) as l1 \gset
select test.a500('till-500-a', 'local', '4826', 3000) as l2 \gset
select test.a500('till-500-a', 'local', '4826', 5000) as l4 \gset
select test.a500('till-500-a', 'local', '4826', 1000) as l3 \gset
select test.a500('till-500-a', 'local', '4826', 10000) as c5 \gset
select test.a500('till-500-a', 'empleado', '4826', 4000, '5284') as e1 \gset
select test.a500('till-500-a', 'empleado', '4826', 2000, '6173') as e2 \gset
select test.a500('till-500-a', 'huesped', '4826', 2000) as h1 \gset
select test.a500('till-500-a', 'guia', '7391', 6000, null, 'Tours Monteverde') as g1 \gset
select public.descuento_liberar(((:'h1'::jsonb) ->> 'id')::uuid) ->> 'ok' as h1_rel \gset
select test.sale500(test.o500(1), 3000, 300, ((:'l2'::jsonb) ->> 'id')::uuid) ->> 'ok' as s1 \gset
select test.sale500(test.o500(2), 2000, 600, ((:'e2'::jsonb) ->> 'id')::uuid) ->> 'ok' as s2 \gset
-- the old window (pos_free_discount on): one approval used now, two left
select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 500') as od1 \gset
select public.approve_discount(test.staff('ana'), '4826', 'amount', 700, 5000, 'Promotion', 'Caja 500') as od2 \gset
select public.approve_discount(test.staff('ana'), '4826', 'percent', 20, 3000, 'Team member', 'Caja 500') as od3 \gset
select test.sale500(test.o500(3), 5000, 500, ((:'od1'::jsonb) ->> 'id')::uuid) ->> 'ok' as s3 \gset
select test.bill500(test.o500(4)) ->> 'ok' as b1 \gset
-- three wrong codes at till B: the third makes it wait
select test.a500('till-500-b', 'local', '0000', 1000) as w1 \gset
select test.a500('till-500-b', 'local', '0001', 1000) as w2 \gset
select test.a500('till-500-b', 'local', '0002', 1000) as w3 \gset
reset role;
select test.eq(concat_ws(' ', (:'l1'::jsonb) ->> 'ok', (:'l2'::jsonb) ->> 'ok', (:'l4'::jsonb) ->> 'ok', (:'l3'::jsonb) ->> 'ok',
                         (:'c5'::jsonb) ->> 'ok', (:'e1'::jsonb) ->> 'ok', (:'e2'::jsonb) ->> 'ok', (:'h1'::jsonb) ->> 'ok',
                         (:'g1'::jsonb) ->> 'ok', :'h1_rel', :'s1', :'s2'),
               'true true true true true true true true true true true true',
               '0 (fixture) at till A: five Local, Empleado for Luis and for Marta, a Huésped let go, a Guía; two of them used by sales');
select test.eq(concat_ws(' ', (:'od1'::jsonb) ->> 'ok', (:'od2'::jsonb) ->> 'ok', (:'od3'::jsonb) ->> 'ok', :'s3', :'b1'),
               'true true true true true', '0 (fixture) three old-window approvals (one used by a sale) and an open bill of 10000');
select test.eq(concat_ws(' ', (:'w1'::jsonb) ->> 'error', (:'w2'::jsonb) ->> 'error', (:'w3'::jsonb) ->> 'error', (:'w3'::jsonb) ->> 'blocked'),
               'bad_pin bad_pin bad_pin wait', '0 (fixture) three wrong codes at till B: the third makes place 2 wait');
-- the owner turns the old window off (supabase/tools/descuento-libre-apagar.sql): a non-default value to keep
\o /dev/null
\ir ../../supabase/tools/descuento-libre-apagar.sql
\o
select test.eq(public.setting('pos_free_discount') #>> '{}' || ' ' || (public.setting('pos_discount_guia') #>> '{}'), 'off on',
               '0 (fixture) pos_free_discount off, pos_discount_guia on');
-- what the pages read under 0038: each till's line, and the approvals log's block «Cajas para descuentos»
select test.dev500('till-500-a'); set role authenticated;
select public.descuento_estado('Caja A 500') as est_a \gset
reset role;
select test.dev500('till-500-b'); set role authenticated;
select public.descuento_estado('Caja B 500') as est_b \gset
reset role;
select test.dev500('log-500'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.descuento_cajas() as cajas_0038 \gset
reset role;
select test.eq(concat_ws(' ', (:'est_a'::jsonb) #>> '{till,state}', (:'est_b'::jsonb) #>> '{till,state}', (:'est_b'::jsonb) #>> '{till,wait}',
                         (select string_agg(p ->> 'wrong_24h', ',' order by (p ->> 'slot')::int) from jsonb_array_elements((:'cajas_0038'::jsonb) -> 'places') p)),
               'ok wait 30s 0,3,0', '0 till A is ok, till B waits 30 s; the approvals log counts 0, 3 and 0 wrong codes in the three places');
select to_jsonb(a)::text as od3_row from public.discount_approvals a where id = ((:'od3'::jsonb) ->> 'id')::uuid \gset
select md5(string_agg(to_jsonb(a)::text, E'\n' order by a.id)) as olds_0038 from public.discount_approvals a where category is null \gset
-- everything, before the reversal
create temp table f38 as select * from test.fns500();
create temp table t38 as select * from test.trg500();
create temp table k38 as select * from test.cons500();
create temp table i38 as select * from test.idx500();
create temp table c38 as select * from test.cols500();
create temp table s38 as select * from test.sec500();
create temp table d38 as select * from test.data500();
\pset format unaligned
\pset tuples_only on
\o :tmp500
\ir ../../supabase/tools/production-snapshot.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('snap_0038', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/consistency-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('cons_0038', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/release-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('rc_0038', :'j500'::jsonb);
\pset tuples_only off
\pset format aligned
select test.eq((select (j -> 'migrations_missing') || (j -> 'functions_missing') from snap500 where k = 'rc_0038'), '[39, 40, "proveedor_anticipos_aplicar", "proveedor_borrador_descartar", "proveedor_borrador_guardar", "proveedor_factura_anular", "proveedor_factura_registrar", "proveedor_ficha", "proveedor_guardar", "proveedor_historial", "proveedor_pago_anular", "proveedor_pago_registrar", "proveedor_pedido", "proveedor_pedido_asignar", "proveedor_pedido_cancelar", "proveedor_pedido_cerrar", "proveedor_pedido_confirmar", "proveedor_pedido_crear", "proveedor_pedido_editar", "proveedor_producto_guardar", "proveedor_recepcion_corregir", "proveedor_recibir", "proveedores_alertas", "proveedores_lista", "proveedores_por_recibir", "turno_aqui", "turno_desde_caja", "turno_estado", "turno_terminar"]'::jsonb,
               '0 release-check.sql under 0038: no migration and no function missing but those of 0039 and 0040 (reverted first)');
select test.eq((select (j #>> '{schema,functions_by_version,0038}') || ' ' || jsonb_array_length(j #> '{schema,functions_changed}')
                       || ' ' || jsonb_array_length(j #> '{schema,functions_unknown}') from snap500 where k = 'snap_0038'), '45 0 0',
               '0 production-snapshot.sql under 0038: 45 functions of 0038 (42 new + 3 replaced), none changed or unknown');

-- 1) a later migration is applied: the script stops at its first statement and changes nothing ------------------------------
insert into canopy.migrations (version, name) values (40, 'siguiente de prueba');
savepoint later;
\set ON_ERROR_STOP 0
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
\set ON_ERROR_STOP 1
\set later_state :LAST_ERROR_SQLSTATE
rollback to savepoint later;
-- like one paste in the SQL Editor: every statement after the guard was refused («transaction aborted»)
select test.eq(:'later_state'::text, '25P02', '1 with a later migration applied, the script stops at its guard: every statement after it is refused');
-- the guard's own message (each statement in its own savepoint here, so the guard's error is the only one; undone)
savepoint later_msg;
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint later_msg;
select test.eq(:'LAST_ERROR_SQLSTATE' || ' ' || :'LAST_ERROR_MESSAGE',
               'P0001 Hay una migración posterior a la 0038 aplicada (40): revierta esa primero. No se cambió nada.',
               '1 its message: «Hay una migración posterior a la 0038 aplicada (40): revierta esa primero. No se cambió nada.»');
select test.eq(test.diff500('f38', '(select * from test.fns500())'), '', '1 every function exactly as 0038 left it (text, rights, settings)');
select test.eq(test.diff500('t38', '(select * from test.trg500())'), '', '1 every trigger as it was (the four of 0038 included)');
select test.eq(test.diff500('d38', '(select * from test.data500())'), '', '1 and no row of any table changed');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 36), '36 37 38 40', '1 the ledger as it was');
delete from canopy.migrations where version = 40;

-- 2) the reversal ---------------------------------------------------------------------------------------------------------
select current_setting('lock_timeout') as lt_before \gset
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
select test.eq(public.canopy_schema_version(), 37, '2 the database is back at version 37');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 36), '36 37', '2 the ledger: 38 deleted, 36 and 37 kept');
select test.eq(:'lt_before' || ' -> ' || current_setting('lock_timeout'), '0 -> 8s', '2 it waits at most 8 seconds for a lock, like a migration (it never freezes the tills)');
-- functions: the 42 go, nothing else goes or comes, only the three old ones change, and only in their text
select test.eq((select string_agg(f.k, ' ' order by f.k) from f38 f where not exists (select 1 from test.fns500() g where g.k = f.k)),
               (select string_agg(sig, ' ' order by sig) from new500), '2 exactly the 42 new functions are gone, no other');
select test.eq((select count(*)::int from new500 where to_regprocedure(sig) is not null), 0, '2 by signature: none of the 42 exists');
select test.eq((select coalesce(string_agg(g.k, ' ' order by g.k), '') from test.fns500() g where not exists (select 1 from f38 f where f.k = g.k)),
               '', '2 no function is added');
select test.eq((select string_agg(g.k, ' ' order by g.k) from test.fns500() g join f38 f on f.k = g.k
                 where (g.h, g.secdef, g.cfg, g.acl, g.args, g.res) is distinct from (f.h, f.secdef, f.cfg, f.acl, f.args, f.res)),
               (select string_agg(sig, ' ' order by sig) from old500),
               '2 only approve_discount, _order_discount_check and tab_set_discount change; every other function is byte for byte as before');
select test.eq((select string_agg(g.k || ':' || left(g.h, 12), ' ' order by g.k) from test.fns500() g join old500 o on o.sig = g.k),
               (select string_agg(sig || ':' || legacy, ' ' order by sig) from old500),
               '2 the three are byte for byte the legacy text (production-snapshot.sql''s legacy fingerprints: 259bc8afa7ef, 812056181d36, 340dd98542a4)');
select test.eq((select count(*)::int from test.fns500() g join f38 f on f.k = g.k join old500 o on o.sig = g.k
                 where (g.secdef, g.cfg, g.acl, g.args, g.res) is not distinct from (f.secdef, f.cfg, f.acl, f.args, f.res)), 3,
               '2 with the same owner rights, search path, grants, arguments and defaults as before');
select test.eq((select string_agg(p.proname || ':' || p.prosecdef || ':' || array_to_string(p.proconfig, ';'), ' ' order by p.proname collate "C")
                  from pg_proc p join old500 o on p.oid = o.sig::regprocedure),
               '_order_discount_check:true:search_path=public, extensions approve_discount:true:search_path=public, extensions tab_set_discount:true:search_path=public',
               '2 as in pos-stations.sql and pos-tabs.sql: security definer, search_path public, extensions (public for tab_set_discount)');
select test.eq((select string_agg(p.proname || ':' || has_function_privilege('anon', p.oid, 'execute') || ':' || has_function_privilege('authenticated', p.oid, 'execute')
                                  || ':' || (coalesce(p.proacl::text, '') ~ '(^|[{,])=X'), ' ' order by p.proname)
                  from pg_proc p where p.oid in ('public.approve_discount(uuid, text, text, int, int, text, text)'::regprocedure,
                                                 'public.tab_set_discount(uuid, uuid, int, text)'::regprocedure)),
               'approve_discount:false:true:false tab_set_discount:false:true:false',
               '2 the café login may call approve_discount and tab_set_discount; a visitor and PUBLIC may not (grants as in the legacy scripts)');
select test.eq((select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace
                   and p.proname ~ '^(descuento|_discount_|_staff_by_code$|_pin_locks_clear_all$|_order_discount_(flags|after)$)'), 0,
               '2 no function named like 0038''s is left in public');
select test.eq((select coalesce(string_agg(g.k, ' ' order by g.k), '') from test.fns500() g join pg_proc p on p.oid = g.k::regprocedure
                 where p.prosrc ~ '\m(descuentos?_\w+|_discount_\w+|_staff_by_code|_pin_locks_clear_all|_order_discount_flags|_order_discount_after)\M'),
               '', '2 and no function left behind calls one of the dropped ones');
-- triggers: the four of 0038 go; order_discount_check stays on orders with the old check
select test.eq((select string_agg(x.k, ' ' order by x.k) from t38 x where not exists (select 1 from test.trg500() y where y.k = x.k)),
               'orders.order_zz_discount orders.order_zz_discount_after orders.order_zz_discount_lock staff.staff_pin_changed',
               '2 the four new triggers are gone (three on orders, staff_pin_changed on staff)');
select test.eq(test.diff500('(select * from t38 where k not like ''orders.order_zz_discount%'' and k <> ''staff.staff_pin_changed'')', '(select * from test.trg500())'), '',
               '2 every other trigger exactly as it was');
select test.ok(exists (select 1 from test.trg500() where k = 'orders.order_discount_check'
                         and v ~ '^CREATE TRIGGER order_discount_check BEFORE INSERT ON public\.orders FOR EACH ROW EXECUTE FUNCTION (public\.)?_order_discount_check\(\) \[O\]$'),
               '2 order_discount_check still checks every sale before insert, with the old function');
-- the data structure stays: columns, rules, indexes, the till table and its locks
select test.eq(test.diff500('c38', '(select * from test.cols500())'), '', '2 every column of every table stays as it was');
select test.eq((select string_agg(column_name || ':' || data_type, ' ' order by ordinal_position) from information_schema.columns
                 where table_schema = 'public' and table_name = 'discount_approvals'
                   and column_name in ('category', 'beneficiary_id', 'beneficiary_name', 'company', 'cr_day', 'approver_role', 'bill_id',
                                       'login_id', 'session_id', 'request_id', 'freed_at', 'freed_how', 'till_id')),
               'category:text beneficiary_id:uuid beneficiary_name:text company:text cr_day:date approver_role:text bill_id:uuid login_id:uuid '
               || 'session_id:text request_id:uuid freed_at:timestamp with time zone freed_how:text till_id:uuid',
               '2 the 13 columns 0038 added to discount_approvals stay (till_id among them)');
select test.eq(test.diff500('k38', '(select * from test.cons500())'), '', '2 every constraint stays, with the same definition');
select test.eq((select string_agg(conname, ' ' order by conname collate "C") from pg_constraint where conrelid = 'public.discount_approvals'::regclass
                   and conname in ('discount_approvals_categoria', 'discount_approvals_category_check', 'discount_approvals_approver_role_check',
                                   'discount_approvals_freed_how_check', 'discount_approvals_beneficiary_id_fkey', 'discount_approvals_till_id_fkey')),
               'discount_approvals_approver_role_check discount_approvals_categoria discount_approvals_category_check '
               || 'discount_approvals_freed_how_check discount_approvals_till_id_fkey',
               '2 among them the category rule (discount_approvals_categoria), its three checks and the till''s key (beneficiary_id has '
               'no key to staff: it would lock the employee''s row, mecanismo §7)');
select test.eq(test.diff500('i38', '(select * from test.idx500())'), '', '2 every index stays, with the same definition');
select test.eq((select string_agg(x.indexrelid::regclass::text, ' ' order by x.indexrelid::regclass::text collate "C") from pg_index x
                 where x.indexrelid::regclass::text in ('discount_employee_once', 'discount_approvals_request', 'discount_approvals_day',
                         'discount_tills_pkey', 'discount_tills_live_session', 'discount_tills_live_slot', 'discount_tills_key', 'discount_tills_session',
                         'audit_log_discount_slot', 'audit_log_discount_wrong', 'audit_log_discount_admin', 'audit_log_discount_removed_paid',
                         'discount_pin_shared_pkey')),
               'audit_log_discount_admin audit_log_discount_removed_paid audit_log_discount_slot audit_log_discount_wrong discount_approvals_day '
               || 'discount_approvals_request discount_employee_once discount_pin_shared_pkey '
               || 'discount_tills_key discount_tills_live_session discount_tills_live_slot discount_tills_pkey discount_tills_session',
               '2 among them the one-Empleado-a-day index, the request index, the day index, the four of discount_tills, the four of the log and discount_pin_shared''s key');
select test.eq(test.diff500('s38', '(select * from test.sec500())'), '', '2 every table''s row security, rights and rules as they were');
select test.ok((select relrowsecurity from pg_class where oid = 'public.discount_tills'::regclass)
               and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'discount_tills')
               and not has_table_privilege('authenticated', 'public.discount_tills', 'select,insert,update,delete,truncate,references,trigger')
               and not has_table_privilege('anon', 'public.discount_tills', 'select,insert,update,delete,truncate,references,trigger')
               and coalesce((select relacl::text from pg_class where oid = 'public.discount_tills'::regclass), '') !~ '(^|[{,])=',
               '2 discount_tills stays closed: row security on, no rule, no right for a login, a visitor or PUBLIC');
select test.ok((select relrowsecurity from pg_class where oid = 'public.discount_pin_shared'::regclass)
               and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'discount_pin_shared')
               and not has_table_privilege('authenticated', 'public.discount_pin_shared', 'select,insert,update,delete,truncate,references,trigger')
               and not has_table_privilege('anon', 'public.discount_pin_shared', 'select,insert,update,delete,truncate,references,trigger')
               and coalesce((select relacl::text from pg_class where oid = 'public.discount_pin_shared'::regclass), '') !~ '(^|[{,])=',
               '2 discount_pin_shared (who shares a code) stays, closed the same way');
-- no data is deleted or changed (only the ledger's version 38 went)
select test.eq((select md5(string_agg(to_jsonb(a)::text, E'\n' order by a.id)) from public.discount_approvals a where category is null), :'olds_0038',
               '2 the old-kind approvals'' md5 unchanged by the reversal');
select test.eq(test.diff500('d38', '(select * from test.data500())'), '', '2 no row of any table of public, canopy or acct changed, appeared or went');
select test.eq((select count(*) filter (where ended_at is null and key_hash ~ '^[0-9a-f]{64}$')::text || ' of ' || count(*) from public.discount_tills), '2 of 2',
               '2 the two registered tills stay, live and with their key fingerprints (unused while reverted)');
select test.eq((select string_agg(category || ':' || count, ' ' order by category collate "C") from (select category, count(*) from public.discount_approvals
                  where category is not null group by 1) q), 'empleado:2 guia:1 huesped:1 local:5', '2 the nine category approvals stay, with their category');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = '2'), 3,
               '2 the three wrong codes of place 2 stay in the log');
select test.eq((select string_agg(key || ':' || kind || ':' || default_value::text || ':' || coalesce(guard, '-'), ' ' order by key collate "C") from canopy.setting_defs
                 where key in ('pos_free_discount', 'pos_discount_guia')),
               'pos_discount_guia:choice:"off":courtesy_iva_confirmed pos_free_discount:choice:"on":-', '2 both settings stay defined, with their guard');
select test.eq(public.setting('pos_free_discount') #>> '{}' || ' ' || (public.setting('pos_discount_guia') #>> '{}'), 'off on',
               '2 and with the values the owner left (no effect while reverted)');
-- what the owner's read-only tools say now
\pset format unaligned
\pset tuples_only on
\o :tmp500
\ir ../../supabase/tools/production-snapshot.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('snap_rev', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/consistency-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('cons_rev', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/release-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('rc_rev', :'j500'::jsonb);
\pset tuples_only off
\pset format aligned
create function test.s500(key text, path text[]) returns jsonb language sql stable as $$ select j #> path from snap500 where k = key $$;
select test.eq(test.s500('rc_rev', '{migrations_missing}'), '[38, 39, 40]'::jsonb, '2 release-check.sql: migrations_missing = [38, 39, 40] (39 and 40 reverted first)');
select test.eq(test.s500('rc_rev', '{functions_missing}'),
               '["descuento_autorizar", "descuento_caja_quitar", "descuento_caja_reanudar", "descuento_caja_registrar", "descuento_caja_volver", "descuento_cajas", "descuento_cupo_devolver", "descuento_estado", "descuento_liberar", "descuento_quitar_cuenta", "descuentos_informe", "proveedor_anticipos_aplicar", "proveedor_borrador_descartar", "proveedor_borrador_guardar", "proveedor_factura_anular", "proveedor_factura_registrar", "proveedor_ficha", "proveedor_guardar", "proveedor_historial", "proveedor_pago_anular", "proveedor_pago_registrar", "proveedor_pedido", "proveedor_pedido_asignar", "proveedor_pedido_cancelar", "proveedor_pedido_cerrar", "proveedor_pedido_confirmar", "proveedor_pedido_crear", "proveedor_pedido_editar", "proveedor_producto_guardar", "proveedor_recepcion_corregir", "proveedor_recibir", "proveedores_alertas", "proveedores_lista", "proveedores_por_recibir", "turno_aqui", "turno_desde_caja", "turno_estado", "turno_terminar"]'::jsonb,
               '2 release-check.sql: functions_missing = the eleven public functions of 0038 and the 27 of 0039 and 0040, nothing else');
select test.eq(test.s500('rc_rev', '{anon_can_run}'), test.s500('rc_0038', '{anon_can_run}'), '2 release-check.sql: a visitor runs what it ran (the same five)');
select test.eq(test.s500('rc_rev', '{tables_without_rls}'), '[]'::jsonb, '2 release-check.sql: no table without row security');
select test.eq(jsonb_build_array(test.s500('rc_rev', '{settings}'), test.s500('rc_rev', '{confirmations}')),
               jsonb_build_array(test.s500('rc_0038', '{settings}'), test.s500('rc_0038', '{confirmations}')),
               '2 release-check.sql: the switches and confirmations as before');
select test.eq((test.s500('snap_rev', '{migrations_applied}') ->> -1) || ' ' || jsonb_array_length(test.s500('snap_rev', '{migrations_applied}'))::text,
               '37 ' || (jsonb_array_length(test.s500('snap_0038', '{migrations_applied}')) - 1)::text, '2 production-snapshot.sql: migrations_applied ends in 37');
select test.eq(test.s500('snap_rev', '{schema,functions_changed}') || test.s500('snap_rev', '{schema,functions_unknown}'), '[]'::jsonb,
               '2 production-snapshot.sql: functions_changed = [] and functions_unknown = [] (the three count as legacy again)');
select test.eq(test.s500('snap_rev', '{schema,functions_by_version}'),
               (test.s500('snap_0038', '{schema,functions_by_version}') - '0038')
                 || jsonb_build_object('legacy', (test.s500('snap_0038', '{schema,functions_by_version,legacy}'))::int + 3),
               '2 production-snapshot.sql: no function of 0038 left, legacy + 3, every other version as before');
select test.eq((test.s500('snap_rev', '{schema,functions_total}'))::int, (test.s500('snap_0038', '{schema,functions_total}'))::int - 42,
               '2 production-snapshot.sql: functions_total - 42');
select test.eq(test.s500('snap_rev', '{schema,triggers_differ}'), '{}'::jsonb, '2 production-snapshot.sql: triggers_differ = {} (exactly the triggers of version 37)');
select test.eq(test.s500('snap_rev', '{schema,tables_missing}') || test.s500('snap_rev', '{schema,live_pages_rpc_missing}'), '[]'::jsonb,
               '2 production-snapshot.sql: no table missing, nothing the published pages call missing');
select test.eq(jsonb_build_array(test.s500('snap_rev', '{schema,tables_columns_differ}'), test.s500('snap_rev', '{schema,tables_other}'), test.s500('snap_rev', '{schema,indexes}')),
               jsonb_build_array(test.s500('snap_0038', '{schema,tables_columns_differ}'), test.s500('snap_0038', '{schema,tables_other}'), test.s500('snap_0038', '{schema,indexes}')),
               '2 production-snapshot.sql: columns, other tables (public.discount_tills among them) and indexes as under 0038');
select test.ok(test.s500('snap_rev', '{schema,tables_other}') ?& array['public.discount_tills', 'public.discount_pin_shared'],
               '2 production-snapshot.sql still lists public.discount_tills and public.discount_pin_shared');
select test.eq(test.s500('snap_rev', '{security}') - 'signed_in_definer_functions_without_account_check',
               test.s500('snap_0038', '{security}') - 'signed_in_definer_functions_without_account_check',
               '2 production-snapshot.sql: security as under 0038 (no table without row security, the same rules, a visitor runs the same)');
select test.eq(test.s500('snap_rev', '{security,signed_in_definer_functions_without_account_check}'),
               (select coalesce(jsonb_agg(f order by f collate "C"), '[]') from jsonb_array_elements_text(test.s500('snap_0038', '{security,signed_in_definer_functions_without_account_check}')) f
                 where f !~ '^public\.(descuento|_discount_|_staff_by_code|_pin_locks_clear_all|_order_discount_(flags|after))'),
               '2 production-snapshot.sql: the functions without an account check are those of before, less any of 0038');
select test.eq(test.s500('snap_rev', '{data_fingerprint}'), test.s500('snap_0038', '{data_fingerprint}'), '2 production-snapshot.sql: data_fingerprint unchanged');
select test.eq(test.s500('snap_rev', '{switches}'), test.s500('snap_0038', '{switches}'), '2 production-snapshot.sql: switches unchanged (pos_free_discount off, Guía on, A-13 confirmed)');
select test.eq(jsonb_build_array(test.s500('cons_rev', '{kept}'), test.s500('cons_rev', '{problems}')),
               jsonb_build_array(test.s500('cons_0038', '{kept}'), test.s500('cons_0038', '{problems}')),
               '2 consistency-check.sql: kept and problems unchanged (sales, discounts, voids, register, stock, hours, staff, log)');
select test.eq(test.s500('cons_rev', '{after,migrations}'), '"37"'::jsonb, '2 consistency-check.sql: migrations 37');

-- the café works as before 0038 (the previous pages, and sales saved offline under 0038)
select test.dev500('till-500-a'); set role authenticated;
select test.err500('select public.descuento_estado()') as gone1 \gset
select test.err500($$select public.descuento_autorizar('local', '4826', 1000)$$) as gone2 \gset
-- the old window: the switch is off, but nothing reads it any more; a free reason that reads as a category is accepted again
select test.try500($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 10000, 'Regular customer', 'Caja 500')$$) as od4 \gset
select test.try500($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 2000, 'Other · Local', 'Caja 500')$$) as od5 \gset
-- a sale with an old approval given under 0038; with category approvals given under 0038 (an offline sale arriving late)
select test.okr500(test.try500(format('select test.sale500(%L, 5000, 700, %L)', test.o500(5), (:'od2'::jsonb) ->> 'id'))) as s5 \gset
select test.okr500(test.try500(format('select test.sale500(%L, 5000, 500, %L)', test.o500(6), (:'l1'::jsonb) ->> 'id'))) as s6 \gset
select test.okr500(test.try500(format('select test.sale500(%L, 4000, 1200, %L)', test.o500(7), (:'e1'::jsonb) ->> 'id'))) as s7 \gset
select test.err500(format('select test.sale500(%L, 5000, 600, %L)', test.o500(8), (:'l4'::jsonb) ->> 'id')) as s8 \gset
select test.okr500(test.try500(format('select test.sale500(%L, 2200)', test.o500(9)))) as s9 \gset
-- a bill: the old approval on and off; a category approval given under 0038 goes on and off the same way
select test.try500(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o500(4), (:'od4'::jsonb) ->> 'id', 'Caja 500')) as tb1 \gset
select test.try500(format('select public.tab_set_discount(%L, null, 9000, %L)', test.o500(4), 'Caja 500')) as tb2 \gset
select test.try500(format('select public.tab_set_discount(%L, %L, 10000, %L)', test.o500(4), (:'c5'::jsonb) ->> 'id', 'Caja 500')) as tb3 \gset
select test.try500(format('select public.tab_set_discount(%L, null, 9000, %L)', test.o500(4), 'Caja 500')) as tb4 \gset
-- Ana voids Marta's Empleado sale (made under 0038)
select test.okr500(test.try500(format('select public.manager_void_order(%L, %L, %L, %L)', test.staff('ana'), '4826', test.o500(2), 'prueba 500'))) as v2 \gset
reset role;
-- a category approval 31 minutes old by the time its sale arrives
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = ((:'l3'::jsonb) ->> 'id')::uuid;
select test.dev500('till-500-a'); set role authenticated;
select test.err500(format('select test.sale500(%L, 1000, 100, %L)', test.o500(10), (:'l3'::jsonb) ->> 'id')) as s10 \gset
reset role;
select test.ok(:'gone1' ~ '^42883:function public\.descuento_estado\(\) does not exist$' and :'gone2' ~ '^42883:function public\.descuento_autorizar\(.*\) does not exist$',
               '2 the new window''s functions do not exist (the new page then says the database needs an update; selling goes on)');
select test.eq((:'od4'::jsonb) ->> 'ok' || ' ' || ((:'od4'::jsonb) ->> 'amount') || ' ' || ((:'od4'::jsonb) ->> 'name'), 'true 1000 Ana',
               '2 approve_discount works as before 0038 although pos_free_discount is off (nothing reads the switch)');
select test.eq((:'od5'::jsonb) ->> 'ok' || ' ' || ((:'od5'::jsonb) ->> 'reason'), 'true Other · Local',
               '2 and, as before 0038, a free reason that reads as a category is accepted');
select test.eq(:'s5' || ' ' || (select discount_reason || ' ' || discount_by || ' ' || discount_crc || ' ' || total_crc from public.orders where id = test.o500(5))
               || ' ' || (select (order_id = test.o500(5))::text from public.discount_approvals where id = ((:'od2'::jsonb) ->> 'id')::uuid),
               'true Promotion Ana 700 4300 true', '2 a sale with an old approval given under 0038 is recorded as before: its reason, Ana, 700 off, the approval used');
select test.eq(:'s6' || ' ' || (select discount_reason || ' ' || discount_by || ' ' || discount_crc || ' ' || total_crc || ' ' || (discount_id::text = (:'l1'::jsonb) ->> 'id')::text
                                       from public.orders where id = test.o500(6))
               || ' ' || (select (order_id = test.o500(6) and used_at is not null)::text from public.discount_approvals where id = ((:'l1'::jsonb) ->> 'id')::uuid),
               'true Local Ana 500 4500 true true', '2 a Local given under 0038 is checked as an old approval of its fixed 10 %: recorded with its label, Ana, linked and used');
select test.eq(:'s7' || ' ' || (select discount_reason || ' ' || discount_by || ' ' || discount_crc || ' ' || total_crc from public.orders where id = test.o500(7)),
               'true Employee Ana 1200 2800', '2 an Empleado given under 0038 (Luis, 30 %): recorded the same way');
select test.eq((select coalesce(string_agg(f, ' ' order by f), '') from public.orders o, unnest(coalesce(o.flags, '{}')) f
                 where o.id in (test.o500(5), test.o500(6), test.o500(7)) and f like 'discount%'), '',
               '2 none of those sales gets a 0038 flag (no discount_not_verified, discount_late, discount_daily_twice)');
select test.eq(:'s8'::text, 'P0001:discount_too_big', '2 more than a category approval allows is refused as the old window refused it (discount_too_big: the old page re-sends without it)');
select test.ok(not exists (select 1 from public.orders where id = test.o500(8))
               and (select order_id is null and used_at is null from public.discount_approvals where id = ((:'l4'::jsonb) ->> 'id')::uuid),
               '2 that sale is not recorded and the approval stays unused');
select test.eq(:'s10'::text, 'P0001:discount_expired', '2 a category approval older than 30 minutes is refused as an old one (discount_expired)');
select test.eq(:'s9'::text, 'true', '2 a sale without a discount is recorded as usual');
select test.eq(:'tb1'::jsonb, '{"ok": true, "total": 9000, "discount": 1000}'::jsonb, '2 tab_set_discount puts an old approval on a bill (10 % of 10000)');
select test.eq(:'tb2'::jsonb, '{"ok": true, "total": 10000, "discount": 0}'::jsonb, '2 and takes it off, as before 0038');
select test.eq(:'tb3'::jsonb, '{"ok": true, "total": 9000, "discount": 1000}'::jsonb,
               '2 the 0038 guard is gone with it: a Local given under 0038 goes on a bill through tab_set_discount like an old approval');
select test.eq(:'tb4'::jsonb, '{"ok": true, "total": 10000, "discount": 0}'::jsonb, '2 and comes off the same way');
select test.eq(:'v2' || ' ' || (select coalesce(string_agg(action, ' '), 'none') from public.audit_log
                                  where target_id = (:'e2'::jsonb) ->> 'id' and action in ('discount_freed', 'discount_not_freed', 'discount_self_void', 'discount_trigger_error')),
               'true none', '2 a void writes no discount_freed / discount_not_freed row: the trigger that judged it is gone');
select test.eq((select coalesce(freed_at::text, 'null') || ' ' || coalesce(freed_how, 'null') || ' ' || (order_id = test.o500(2))::text
                  from public.discount_approvals where id = ((:'e2'::jsonb) ->> 'id')::uuid), 'null null true',
               '2 and Marta''s approval is left exactly as it was');
select test.ok(not exists (select 1 from public.audit_log where action in ('discount_not_verified', 'discount_used_after_release', 'discount_check_error')
                             and target_id in (test.o500(5)::text, test.o500(6)::text, test.o500(7)::text, test.o500(9)::text,
                                                             (:'l1'::jsonb) ->> 'id', (:'e1'::jsonb) ->> 'id', (:'od2'::jsonb) ->> 'id')),
               '2 and no sale wrote a row of the 0038 sale check');
-- the owner's switch tool needs 0038: that is why the reversal's header says to turn the switch on BEFORE reverting
savepoint tool;
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/descuento-libre-encender.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint tool;
select test.eq(:'LAST_ERROR_SQLSTATE' || ' ' || :'LAST_ERROR_MESSAGE',
               'P0001 La migración 0038 no está aplicada: el ajuste pos_free_discount todavía no existe. No se cambió nada.',
               '2 descuento-libre-encender.sql refuses once 0038 is reverted («La migración 0038 no está aplicada…»)');
create temp table f37 as select * from test.fns500();

-- 3) 0038 not applied: the script refuses with its message and changes nothing ---------------------------------------------
create temp table d37 as select * from test.data500();
savepoint again;
\set ON_ERROR_STOP 0
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
\set ON_ERROR_STOP 1
\set again_state :LAST_ERROR_SQLSTATE
rollback to savepoint again;
select test.eq(:'again_state'::text, '25P02', '3 run again: the script stops at its guard, every statement after it is refused');
savepoint again_msg;
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint again_msg;
select test.eq(:'LAST_ERROR_SQLSTATE' || ' ' || :'LAST_ERROR_MESSAGE',
               'P0001 La migración 0038 no está aplicada: no hay nada que revertir. No se cambió nada.',
               '3 its message: «La migración 0038 no está aplicada: no hay nada que revertir. No se cambió nada.»');
select test.eq(public.canopy_schema_version(), 37, '3 still at version 37');
select test.eq(test.diff500('f37', '(select * from test.fns500())'), '', '3 the functions untouched');
select test.eq(test.diff500('d37', '(select * from test.data500())'), '', '3 and the tables untouched');

-- 4) 0038 applies again and finds everything as it was ----------------------------------------------------------------------
create temp table dpre as select * from test.data500();
select md5(string_agg(to_jsonb(a)::text, E'\n' order by a.id)) as olds_pre from public.discount_approvals a where category is null \gset
\pset format unaligned
\pset tuples_only on
\o :tmp500
\ir ../../supabase/tools/production-snapshot.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('snap_pre', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/consistency-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('cons_pre', :'j500'::jsonb);
\pset tuples_only off
\pset format aligned
\o /dev/null
\ir ../../supabase/migrations/0038_descuentos_caja.sql
\o
select test.eq(public.canopy_schema_version(), 38, '4 applied again: version 38');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 36), '36 37 38', '4 the ledger: 38 once');
select test.eq(test.diff500('f38', '(select * from test.fns500())'), '',
               '4 every function exactly as the first time: the 41 back, the three in their 0038 text, the same rights and settings');
select test.eq(test.diff500('t38', '(select * from test.trg500())'), '', '4 every trigger as the first time: the four of 0038 back, once each');
select test.eq(test.diff500('c38', '(select * from test.cols500())'), '', '4 no column added twice or changed');
select test.eq(test.diff500('k38', '(select * from test.cons500())'), '', '4 no constraint added twice or changed (the keys of beneficiary_id and till_id once)');
select test.eq(test.diff500('i38', '(select * from test.idx500())'), '', '4 no index added twice or changed');
select test.eq(test.diff500('s38', '(select * from test.sec500())'), '', '4 row security, rights and rules as the first time');
select test.eq(test.diff500('dpre', '(select * from test.data500())'), '', '4 applying again moves no data: every table as the reversal left it');
select test.eq((select md5(string_agg(to_jsonb(a)::text, E'\n' order by a.id)) from public.discount_approvals a where category is null), :'olds_pre',
               '4 the old-kind approvals'' md5 unchanged');
select test.eq((select to_jsonb(a)::text from public.discount_approvals a where id = ((:'od3'::jsonb) ->> 'id')::uuid), :'od3_row',
               '4 an old approval nobody used is the row it was under the first 0038');
select test.eq(public.setting('pos_free_discount') #>> '{}' || ' ' || (public.setting('pos_discount_guia') #>> '{}'), 'off on',
               '4 the switch keeps its value (off), and Guía stays on');
\pset format unaligned
\pset tuples_only on
\o :tmp500
\ir ../../supabase/tools/production-snapshot.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('snap_again', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/consistency-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('cons_again', :'j500'::jsonb);
\o :tmp500
\ir ../../supabase/tools/release-check.sql
\o
\set j500 `cat :'tmp500'`
insert into snap500 values ('rc_again', :'j500'::jsonb);
\pset tuples_only off
\pset format aligned
select test.eq(test.s500('rc_again', '{migrations_missing}') || test.s500('rc_again', '{functions_missing}'), '[39, 40, "proveedor_anticipos_aplicar", "proveedor_borrador_descartar", "proveedor_borrador_guardar", "proveedor_factura_anular", "proveedor_factura_registrar", "proveedor_ficha", "proveedor_guardar", "proveedor_historial", "proveedor_pago_anular", "proveedor_pago_registrar", "proveedor_pedido", "proveedor_pedido_asignar", "proveedor_pedido_cancelar", "proveedor_pedido_cerrar", "proveedor_pedido_confirmar", "proveedor_pedido_crear", "proveedor_pedido_editar", "proveedor_producto_guardar", "proveedor_recepcion_corregir", "proveedor_recibir", "proveedores_alertas", "proveedores_lista", "proveedores_por_recibir", "turno_aqui", "turno_desde_caja", "turno_estado", "turno_terminar"]'::jsonb,
               '4 release-check.sql: no migration and no function missing but those of 0039 and 0040 (reverted at the start)');
select test.eq(test.s500('snap_again', '{schema}') - 'functions_total', test.s500('snap_0038', '{schema}') - 'functions_total',
               '4 production-snapshot.sql: the schema as under the first 0038 (functions by version, none changed, triggers, tables, indexes)');
select test.eq(test.s500('snap_again', '{schema,functions_total}'), test.s500('snap_0038', '{schema,functions_total}'), '4 production-snapshot.sql: functions_total as the first time');
select test.eq(test.s500('snap_again', '{security}'), test.s500('snap_0038', '{security}'), '4 production-snapshot.sql: security as the first time');
select test.eq(test.s500('snap_again', '{data_fingerprint}'), test.s500('snap_pre', '{data_fingerprint}'), '4 production-snapshot.sql: data_fingerprint unchanged by applying again');
select test.eq(test.s500('snap_again', '{switches}'), test.s500('snap_0038', '{switches}'), '4 production-snapshot.sql: switches as the owner left them');
select test.eq(jsonb_build_array(test.s500('cons_again', '{kept}'), test.s500('cons_again', '{problems}')),
               jsonb_build_array(test.s500('cons_pre', '{kept}'), test.s500('cons_pre', '{problems}')),
               '4 consistency-check.sql: kept and problems unchanged by applying again');
-- the registered tills come back as they were: their places, their counts (a reversal is no fresh budget), their keys
select test.dev500('log-500'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.descuento_cajas() as cajas_again \gset
reset role;
select test.dev500('till-500-a'); set role authenticated;
select public.descuento_estado('Caja A 500') as est_a2 \gset
reset role;
select test.dev500('till-500-b'); set role authenticated;
select public.descuento_estado('Caja B 500') as est_b2 \gset
select test.a500('till-500-b', 'local', '4826', 1000) as wb \gset
reset role;
select test.eq(:'cajas_again'::jsonb, :'cajas_0038'::jsonb,
               '4 the approvals log reads exactly what it read under the first 0038 (the three places, their tills, counts and the person''s limits)');
select test.eq(:'est_a2'::jsonb, :'est_a'::jsonb, '4 till A: registered in place 1 by Ana, since the same time, ok');
select test.eq((:'est_b2'::jsonb) #- '{till,wait_s}', (:'est_b'::jsonb) #- '{till,wait_s}', '4 till B: registered in place 2, still waiting until the same moment');
select test.eq((:'wb'::jsonb) ->> 'error' || ' ' || ((:'wb'::jsonb) ->> 'until')::timestamptz::text, 'till_wait ' || ((:'est_b'::jsonb) #>> '{till,until}')::timestamptz::text,
               '4 a right code at till B is not tested while it waits (till_wait, the same until)');
select test.eq((select count(*)::int from public.audit_log where action = 'discount_code_wrong'), 3, '4 and nothing more is counted');
set role authenticated;
select test.a500('till-500-a', 'local', '4826', 2000) as l6 \gset
select test.a500('till-500-a', 'empleado', '4826', 3000, '5284') as e4 \gset
select test.a500('till-500-a', 'guia', '7391', 5000, null, 'Tours Monteverde') as g2 \gset
select test.err500($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 500')$$) as off1 \gset
-- the 0038 sale check is back: more than approved is recorded and flagged, never refused
select test.okr500(test.try500(format('select test.sale500(%L, 5000, 600, %L)', test.o500(8), (:'l4'::jsonb) ->> 'id'))) as s8b \gset
-- the void trigger is back: Ana's Empleado given by the owner's code, sold, then voided by the owner
select test.a500('till-500-a', 'empleado', '7391', 2000, '4826') as e3 \gset
select test.okr500(test.try500(format('select test.sale500(%L, 2000, 600, %L)', test.o500(11), (:'e3'::jsonb) ->> 'id'))) as s11 \gset
select test.okr500(test.try500(format('select public.manager_void_order(%L, %L, %L, %L)', test.staff('dueno'), '7391', test.o500(11), 'prueba 500'))) as v11 \gset
select test.err500(format('select public.tab_set_discount(%L, %L, 10000, ''Caja 500'')', test.o500(4), (:'c5'::jsonb) ->> 'id')) as tb5 \gset
reset role;
select test.eq((:'l6'::jsonb) ->> 'ok' || ' ' || ((:'l6'::jsonb) ->> 'amount') || ' ' || ((:'l6'::jsonb) ->> 'name'), 'true 200 Ana',
               '4 the window works again at till A (Local, Ana''s code)');
select test.eq(:'e4'::jsonb, '{"ok": false, "error": "daily_used", "beneficiary": "Luis", "pending": false}'::jsonb,
               '4 the Empleado limit is still enforced: Luis''s day was used by the sale that arrived while reverted');
select test.eq(test.err500(format($q$insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, station, subtotal_crc,
                                       amount_crc, category, beneficiary_id, beneficiary_name, cr_day, approver_role)
                                     values (%L, 'Ana', 'percent', 30, 'Employee', 'Caja 500', 1000, 300, 'empleado', %L, 'Luis', public.cr_today(), 'manager')$q$,
                                   test.staff('ana'), test.staff('luis'))),
               '23505:duplicate key value violates unique constraint "discount_employee_once"',
               '4 and in the database itself: a second live Empleado for Luis today breaks discount_employee_once');
select test.eq((:'g2'::jsonb) ->> 'ok' || ' ' || ((:'g2'::jsonb) ->> 'role') || ' ' || ((:'g2'::jsonb) ->> 'amount'), 'true owner 5000',
               '4 Guía works again with the owner''s code (the setting kept on)');
select test.eq(:'off1'::text, 'P0001:approve_discount_off', '4 the old window reads the switch again: off, so approve_discount refuses (approve_discount_off)');
select test.eq(:'s8b' || ' ' || (select discount_reason || ' ' || coalesce(discount_by, 'null') || ' ' || discount_crc || ' ' || ('discount_not_verified' = any (flags))::text
                                        from public.orders where id = test.o500(8)),
               'true Local · not verified null 600 true', '4 the sale check of 0038 is back: 600 off a 500 Local is recorded as charged and flagged discount_not_verified');
select test.eq(:'s11' || ' ' || :'v11' || ' ' || (select freed_how from public.discount_approvals where id = ((:'e3'::jsonb) ->> 'id')::uuid)
               || ' ' || (select count(*)::text from public.audit_log where action = 'discount_freed' and target_id = (:'e3'::jsonb) ->> 'id'),
               'true true void 1', '4 the void trigger of 0038 is back: the owner voids Ana''s Empleado sale and her day comes back (discount_freed)');
select test.eq(:'tb5'::text, 'P0001:tab_set_discount_category', '4 the bill guard of 0038 is back: a category approval goes on a bill only through descuento_autorizar');
-- the key a till got before the reversal still brings it back after a new sign-in (descuento_caja_volver)
select test.dev500('till-500-a2'); set role authenticated;
select public.descuento_caja_volver(:'key_a', 'Caja A 500') as va \gset
reset role;
select test.eq((:'va'::jsonb) ->> 'ok' || ' ' || ((:'va'::jsonb) ->> 'slot') || ' ' || ((:'va'::jsonb) ->> 'station') || ' ' || ((:'va'::jsonb) ->> 'key' ~ '^[0-9a-f]{64}$')::text
               || ' ' || ((:'va'::jsonb) ->> 'key' <> :'key_a')::text,
               'true 1 Caja A 500 true true', '4 till A''s key from before the reversal brings a new sign-in back to place 1, with a new key');
-- the owner's switch tool works again, and the old window with it (a free reason reading as a category refused again)
\o /dev/null
\ir ../../supabase/tools/descuento-libre-encender.sql
\o
select test.dev500('till-500-a'); set role authenticated;
select test.okr500(test.try500($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Regular customer', 'Caja 500')$$)) as on1 \gset
select coalesce(test.try500($$select public.approve_discount(test.staff('ana'), '4826', 'percent', 10, 5000, 'Other · Local', 'Caja 500')$$) ->> 'error', 'none') as on2 \gset
reset role;
select test.eq(public.setting('pos_free_discount') #>> '{}' || ' ' || :'on1' || ' ' || :'on2', 'on true missing_reason',
               '4 descuento-libre-encender.sql works again; approve_discount approves, and refuses «Other · Local» again (missing_reason)');

-- 5) the cycle repeats: reverted again, the same 41 go and the same legacy text comes back; applied again, as the first time
create temp table d2 as select * from test.data500();
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
select test.eq(public.canopy_schema_version() || ' ' || test.diff500('f37', '(select * from test.fns500())'), '37 ',
               '5 reverted a second time: version 37, every function as after the first reversal');
select test.eq(test.diff500('d2', '(select * from test.data500())'), '', '5 no data moved');
\o /dev/null
\ir ../../supabase/migrations/0038_descuentos_caja.sql
\o
select test.eq(public.canopy_schema_version() || ' ' || test.diff500('f38', '(select * from test.fns500())') || test.diff500('t38', '(select * from test.trg500())'),
               '38 ', '5 applied a third time: version 38, every function and trigger as the first time');
select test.eq(test.diff500('d2', '(select * from test.data500())'), '', '5 no data moved');

select test.done();
rollback;
