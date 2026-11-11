-- supabase/tools/reversion-0040.sql then reversion-0039.sql: undo the Proveedores migrations (D-067), and they then apply
-- again. Each reversal refuses while it is not applied or while a later migration is, and then changes nothing; together
-- they drop the 79 new functions and the 9 new triggers and nothing else (0039 replaced no function; 0040's three
-- redefinitions go back to their 0025, 0029 and 0035 texts), delete no
-- data (the six tables with their rows, the new columns, rules and indexes, the 1160 mappings and the widened payment
-- rule stay) and take versions 40 and 39 off the ledger. The published Inventario page then works as before (orders,
-- deliveries, receive-and-pay, items with a supplier, the clock). 0039 and 0040 then apply again over what the reversal
-- left: every function and trigger as the first time, nothing added twice, no row of an original table touched; only what
-- the published page did meanwhile is copied into the new tables (the catalog row of a supplier chosen, the lines of a
-- delivery received the old way). Twice. Read as the test superuser; the café's calls go through the real functions.
begin;
create function test.fns520() returns table (k text, h text, secdef boolean, cfg text, acl text) language sql stable as $$
  select p.oid::regprocedure::text, md5(p.prosrc), p.prosecdef, coalesce(p.proconfig::text, '-'), coalesce(p.proacl::text, '-')
    from pg_proc p where p.pronamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.trg520() returns table (k text, v text) language sql stable as $$
  select c.oid::regclass::text || '.' || g.tgname, pg_get_triggerdef(g.oid) || ' [' || g.tgenabled::text || ']'
    from pg_trigger g join pg_class c on c.oid = g.tgrelid
   where not g.tgisinternal and c.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.str520() returns table (k text, v text) language sql stable as $$
  select 'con ' || r.oid::regclass::text || '.' || k.conname, pg_get_constraintdef(k.oid) from pg_constraint k join pg_class r on r.oid = k.conrelid
   where r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace)
  union all
  select 'idx ' || x.indexrelid::regclass::text, pg_get_indexdef(x.indexrelid) from pg_index x join pg_class r on r.oid = x.indrelid
   where r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace)
  union all
  select 'col ' || r.oid::regclass::text || '.' || a.attname, format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
           || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')
    from pg_attribute a join pg_class r on r.oid = a.attrelid left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where r.relkind in ('r', 'p') and a.attnum > 0 and not a.attisdropped and r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace)
  union all
  select 'sec ' || r.oid::regclass::text, r.relrowsecurity::text || ' ' || coalesce(r.relacl::text, '-') from pg_class r
   where r.relkind in ('r', 'p') and r.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace)
  union all
  select 'pol ' || schemaname || '.' || tablename || '.' || policyname, cmd || ' ' || coalesce(qual, '-') || ' ' || coalesce(with_check, '-') from pg_policies
   where schemaname in ('public', 'canopy', 'acct', 'storage') $$;
create function test.data520() returns table (k text, v text) language plpgsql stable as $$
declare r record;
begin
  for r in select c.oid::regclass::text as n from pg_class c where c.relkind in ('r', 'p') and c.oid <> 'canopy.migrations'::regclass
              and c.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) order by 1 loop
    k := r.n;
    execute format('select count(*) || '':'' || coalesce(md5(string_agg(x::text, E''\n'' order by x::text)), ''-'') from %s x', r.n) into v;
    return next;
  end loop;
end $$;
create function test.diff520(a text, b text) returns text language plpgsql as $$
declare res text;
begin
  execute format('select coalesce(string_agg(distinct k, '' '' order by k), '''') from ('
                 || '(select j ->> ''k'' from (select to_jsonb(x) from %1$s x except select to_jsonb(y) from %2$s y) q(j)) union all '
                 || '(select j ->> ''k'' from (select to_jsonb(y) from %2$s y except select to_jsonb(x) from %1$s x) q(j))) z(k)', a, b) into res;
  return res;
end $$;
create function test.try520(q text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute q into r; return r;
exception when others then return jsonb_build_object('raised', sqlstate || ':' || sqlerrm);
end $$;
create function test.v520(o text) returns int language sql security definer as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.lines520(o text, n numeric) returns jsonb language sql security definer as $$
  select jsonb_agg(jsonb_build_object('line_id', id, 'packs', n)) from public.purchase_lines where po_id = o::uuid $$;
create temp table snap520 (k text primary key, j jsonb);
\set tmp520 `mktemp`

-- 0) the state made under 0039 and 0040, through the real functions ------------------------------------------------------
select test.eq(public.canopy_schema_version(), 40, '0 the database is at version 40');
create temp table new520 as select p.oid::regprocedure::text as sig from pg_proc p
 where p.pronamespace = 'public'::regnamespace and (p.proname ~ '^(proveedor|proveedores|turno)_' or p.proname ~ '^_prov_');
select test.eq((select count(*)::int from new520), 79, '0 the 79 new functions exist (56 of 0039, 23 of 0040)');
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000052001', 'Lácteos Monteverde');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values
  ('5a000000-0000-4000-8000-000000052001', 'Leche', 'unit', 12, 12000, '5b000000-0000-4000-8000-000000052001');
select (select id::text from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000052001') as vi \gset
select test.login('cafe'); select test.session('dev-520'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000052001', jsonb_build_array(jsonb_build_object('vendor_item_id', :'vi', 'packs', 4)), null,
                                     '9a000000-0000-4000-8000-000000052001') ->> 'ok' as c1 \gset
select public.proveedor_recibir('9a000000-0000-4000-8000-000000052001', '7e000000-0000-4000-8000-000000052001', test.v520('9a000000-0000-4000-8000-000000052001'),
         test.lines520('9a000000-0000-4000-8000-000000052001', 2)) ->> 'status' as r1 \gset
select public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000052001","po_id":"9a000000-0000-4000-8000-000000052001","amount":20000,"method":"sinpe","reference":"52001-SINPE"}',
         '5d000000-0000-4000-8000-000000052001', test.staff('ana'), '4826') ->> 'ok' as p1 \gset
-- the milk's catalog row is moved to boxes of 24 (its earlier order was by 12): applied again, the copy must not revive the 12
select public.proveedor_producto_guardar(jsonb_build_object('id', :'vi', 'pack_label', 'caja de 24', 'pack_qty', 24, 'usual_price', 24000)) ->> 'ok' as e1 \gset
select test.eq(:'e1'::text, 'true', '0 (the milk''s row edited to boxes of 24)');
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000052001', jsonb_build_array(jsonb_build_object('vendor_item_id', :'vi', 'packs', 1)), null, 0) ->> 'ok' as d1 \gset
select public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000052001","notes":"Entrega martes"}') ->> 'ok' as g1 \gset
select test.login('cafe'); select test.session('dev-520-r'); set role authenticated;
select test.turno(test.staff('luis'), '5284') as tok \gset
select public.proveedor_recibir('9a000000-0000-4000-8000-000000052001', '7e000000-0000-4000-8000-000000052002', test.v520('9a000000-0000-4000-8000-000000052001'),
         test.lines520('9a000000-0000-4000-8000-000000052001', 1), :'tok') ->> 'status' as r2 \gset
reset role;
select test.eq(concat_ws(' ', :'c1', :'r1', :'p1', :'d1', :'g1', :'r2'), 'true partially_received true true true partially_received',
               '0 (fixture) an order, a delivery by Ana and one by Luis on shift, a SINPE payment, a draft, a supplier edited');
select md5(string_agg(to_jsonb(w)::text, ',' order by w.id)) as ws_0040 from public.work_sessions w \gset
select public._prov_dinero('9a000000-0000-4000-8000-000000052001') as money_0040 \gset
create temp table f40 as select * from test.fns520();
create temp table t40 as select * from test.trg520();
create temp table s40 as select * from test.str520();
create temp table d40 as select * from test.data520();
\pset format unaligned
\pset tuples_only on
\o :tmp520
\ir ../../supabase/tools/production-snapshot.sql
\o
\set j520 `cat :'tmp520'`
insert into snap520 values ('snap_40', :'j520'::jsonb);
\o :tmp520
\ir ../../supabase/tools/consistency-check.sql
\o
\set j520 `cat :'tmp520'`
insert into snap520 values ('cons_40', :'j520'::jsonb);
\o :tmp520
\ir ../../supabase/tools/release-check.sql
\o
\set j520 `cat :'tmp520'`
insert into snap520 values ('rc_40', :'j520'::jsonb);
\pset tuples_only off
\pset format aligned
create function test.s520(key text, path text[]) returns jsonb language sql stable as $$ select j #> path from snap520 where k = key $$;
select test.eq(test.s520('rc_40', '{migrations_missing}') || test.s520('rc_40', '{functions_missing}'), '[]'::jsonb, '0 release-check.sql: nothing missing');
select test.eq((test.s520('snap_40', '{schema,functions_by_version,0039}') #>> '{}') || ' ' || (test.s520('snap_40', '{schema,functions_by_version,0040}') #>> '{}')
               || ' ' || jsonb_array_length(test.s520('snap_40', '{schema,functions_changed}')) || ' ' || jsonb_array_length(test.s520('snap_40', '{schema,functions_unknown}')),
               '56 26 0 0', '0 production-snapshot.sql: 56 functions of 0039, 26 of 0040 (its 23 new ones and supplier_invoice_save, supplier_payment_save and expense_pay redefined), none changed or unknown');

-- 1) the guards: 0039 refuses while 0040 is applied; 0040 refuses while a later one is ----------------------------------------
savepoint g1;
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0039.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint g1;
select test.eq(:'LAST_ERROR_SQLSTATE' || ' ' || :'LAST_ERROR_MESSAGE',
               'P0001 Hay una migración posterior a la 0039 aplicada (40): revierta esa primero. No se cambió nada.',
               '1 reversion-0039.sql first: «Hay una migración posterior a la 0039 aplicada (40): revierta esa primero»');
insert into canopy.migrations (version, name) values (41, 'siguiente de prueba');
savepoint g2;
\set ON_ERROR_STOP 0
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\o
\set ON_ERROR_STOP 1
\set g2_state :LAST_ERROR_SQLSTATE
rollback to savepoint g2;
select test.eq(:'g2_state'::text, '25P02', '1 with a later migration applied, reversion-0040.sql stops at its guard: every statement after it is refused');
savepoint g3;
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint g3;
select test.eq(:'LAST_ERROR_SQLSTATE' || ' ' || :'LAST_ERROR_MESSAGE',
               'P0001 Hay una migración posterior a la 0040 aplicada (41): revierta esa primero. No se cambió nada.', '1 its message names 41');
delete from canopy.migrations where version = 41;
select test.eq(test.diff520('f40', '(select * from test.fns520())') || test.diff520('t40', '(select * from test.trg520())') || test.diff520('d40', '(select * from test.data520())'),
               '', '1 nothing changed: functions, triggers, rows');

-- 2) the reversal: 0040, then 0039 -------------------------------------------------------------------------------------------
select current_setting('lock_timeout') as lt_before \gset
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\o
select test.eq(public.canopy_schema_version(), 39, '2 reversion-0040.sql: back at version 39');
\o /dev/null
\ir ../../supabase/tools/reversion-0039.sql
\o
select test.eq(public.canopy_schema_version(), 38, '2 reversion-0039.sql: back at version 38');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 37), '37 38', '2 the ledger: 39 and 40 deleted');
select test.eq(:'lt_before' || ' -> ' || current_setting('lock_timeout'), '0 -> 8s', '2 each waits at most 8 seconds for a lock');
select test.eq((select string_agg(f.k, ' ' order by f.k) from f40 f where not exists (select 1 from test.fns520() g where g.k = f.k)),
               (select string_agg(sig, ' ' order by sig) from new520), '2 exactly the 79 new functions are gone');
select test.eq(test.diff520('(select * from f40 where k not in (select sig from new520) and k not in (''supplier_invoice_save(jsonb,uuid)'', ''supplier_payment_save(jsonb,uuid)'', ''expense_pay(jsonb,uuid)''))',
                             '(select * from test.fns520() where k not in (''supplier_invoice_save(jsonb,uuid)'', ''supplier_payment_save(jsonb,uuid)'', ''expense_pay(jsonb,uuid)''))'), '',
               '2 every other function byte for byte as it was, with its rights (0039 replaced none)');
select test.ok((select prosrc !~ '0040' and prosrc ~ 'the deliveries are this vendor''s and not invoiced yet' from pg_proc where oid = 'public.supplier_invoice_save(jsonb,uuid)'::regprocedure),
               '2 supplier_invoice_save is back to its 0025 text (the snapshot below reads it as 0025''s)');
select test.ok((select prosrc !~ '_prov_aplicar' and prosrc !~ '_prov_sinpe_taken' and prosrc ~ 'one invoice or payment of a supplier at a time' from pg_proc where oid = 'public.supplier_payment_save(jsonb,uuid)'::regprocedure),
               '2 supplier_payment_save is back to its 0029 text (no Proveedores payments applied first, no SINPE cross-check)');
select test.ok((select prosrc !~ '_prov_sinpe_taken' and prosrc ~ 'no payment dated before its expense' from pg_proc where oid = 'public.expense_pay(jsonb,uuid)'::regprocedure),
               '2 expense_pay is back to its 0035 text');
select test.eq((select string_agg(x.k, ' ' order by x.k) from t40 x where not exists (select 1 from test.trg520() y where y.k = x.k)),
               'purchase_lines.purchase_lines_po_version purchase_lines.purchase_lines_protect_new purchase_orders.purchase_orders_version '
               || 'purchase_receipts.purchase_receipts_po_version staff.staff_work_session_end stock_items.stock_items_vendor_catalog '
               || 'supplier_payment_allocations.supplier_payment_allocations_within_invoice supplier_payments.supplier_payments_within_advance time_entries.time_entries_work_session_end',
               '2 the nine new triggers are gone (seven of 0039, the two guards of 0040)');
select test.eq(test.diff520('(select * from t40 where k !~ ''(po_version|protect_new|purchase_orders_version|work_session_end|vendor_catalog|within_invoice|within_advance)$'')', '(select * from test.trg520())'), '',
               '2 every other trigger as it was (0038''s staff_pin_changed included)');
select test.eq(test.diff520('s40', '(select * from test.str520())'), '', '2 every table, column, rule, index, right and row rule stays as it was');
select test.eq(test.diff520('d40', '(select * from test.data520())'), '', '2 no row of any table changed, appeared or went');
select test.eq((select account || ' ' || label from acct.mappings where key = 'supplier_advance'), '1160 Pago a proveedor antes de aplicarlo a su factura (Proveedores)',
               '2 the mappings stay');
select test.ok((select pg_get_constraintdef(oid) ~ 'advance' from pg_constraint where conname = 'supplier_payments_paid_from_check'),
               '2 and so does the widened payment rule (the applied payments keep it)');
select test.eq((select md5(string_agg(to_jsonb(w)::text, ',' order by w.id)) from public.work_sessions w), :'ws_0040', '2 the work sessions are kept as they were (now unused)');
\pset format unaligned
\pset tuples_only on
\o :tmp520
\ir ../../supabase/tools/production-snapshot.sql
\o
\set j520 `cat :'tmp520'`
insert into snap520 values ('snap_rev', :'j520'::jsonb);
\o :tmp520
\ir ../../supabase/tools/consistency-check.sql
\o
\set j520 `cat :'tmp520'`
insert into snap520 values ('cons_rev', :'j520'::jsonb);
\o :tmp520
\ir ../../supabase/tools/release-check.sql
\o
\set j520 `cat :'tmp520'`
insert into snap520 values ('rc_rev', :'j520'::jsonb);
\pset tuples_only off
\pset format aligned
select test.eq(test.s520('rc_rev', '{migrations_missing}'), '[39, 40]'::jsonb, '2 release-check.sql: migrations_missing = [39, 40]');
select test.eq(test.s520('rc_rev', '{functions_missing}'),
               '["proveedor_anticipos_aplicar", "proveedor_borrador_descartar", "proveedor_borrador_guardar", "proveedor_factura_anular", "proveedor_factura_registrar", '
               '"proveedor_ficha", "proveedor_guardar", "proveedor_historial", "proveedor_pago_anular", "proveedor_pago_registrar", "proveedor_pedido", "proveedor_pedido_asignar", '
               '"proveedor_pedido_cancelar", "proveedor_pedido_cerrar", "proveedor_pedido_confirmar", "proveedor_pedido_crear", "proveedor_pedido_editar", "proveedor_producto_guardar", '
               '"proveedor_recepcion_corregir", "proveedor_recibir", "proveedores_alertas", "proveedores_bitacora", "proveedores_lista", "proveedores_por_recibir", "turno_aqui", "turno_desde_caja", '
               '"turno_estado", "turno_terminar"]'::jsonb, '2 release-check.sql: functions_missing = the 28 public functions, nothing else');
select test.eq(jsonb_build_array(test.s520('rc_rev', '{anon_can_run}'), test.s520('rc_rev', '{tables_without_rls}'), test.s520('rc_rev', '{settings}')),
               jsonb_build_array(test.s520('rc_40', '{anon_can_run}'), test.s520('rc_40', '{tables_without_rls}'), test.s520('rc_40', '{settings}')),
               '2 release-check.sql: a visitor runs the same, no table without row security, the same switches');
select test.eq((test.s520('snap_rev', '{migrations_applied}') ->> -1), '38', '2 production-snapshot.sql: migrations_applied ends in 38');
select test.eq(test.s520('snap_rev', '{schema,functions_changed}') || test.s520('snap_rev', '{schema,functions_unknown}'), '[]'::jsonb,
               '2 production-snapshot.sql: no function changed or unknown');
select test.eq(test.s520('snap_rev', '{schema,functions_by_version}'), test.s520('snap_40', '{schema,functions_by_version}') - '0039' - '0040'
                 || jsonb_build_object('0025', (test.s520('snap_40', '{schema,functions_by_version,0025}') #>> '{}')::int + 1,
                                       '0029', (test.s520('snap_40', '{schema,functions_by_version,0029}') #>> '{}')::int + 1,
                                       '0035', (test.s520('snap_40', '{schema,functions_by_version,0035}') #>> '{}')::int + 1),
               '2 production-snapshot.sql: every version as before, without 0039 and 0040 (supplier_invoice_save, supplier_payment_save and expense_pay are 0025''s, 0029''s and 0035''s again)');
select test.eq((test.s520('snap_rev', '{schema,functions_total}'))::int, (test.s520('snap_40', '{schema,functions_total}'))::int - 79, '2 functions_total − 79');
select test.eq(test.s520('snap_rev', '{schema,triggers_differ}'), '{}'::jsonb, '2 triggers_differ = {} (exactly the triggers of version 38)');
select test.eq(test.s520('snap_rev', '{schema,tables_missing}') || test.s520('snap_rev', '{schema,live_pages_rpc_missing}'), '[]'::jsonb,
               '2 no table missing, nothing the published pages call missing');
select test.eq(jsonb_build_array(test.s520('snap_rev', '{data_fingerprint}'), test.s520('snap_rev', '{switches}')),
               jsonb_build_array(test.s520('snap_40', '{data_fingerprint}'), test.s520('snap_40', '{switches}')), '2 data_fingerprint and switches unchanged');
select test.eq(jsonb_build_array(test.s520('cons_rev', '{kept}'), test.s520('cons_rev', '{problems}')),
               jsonb_build_array(test.s520('cons_40', '{kept}'), test.s520('cons_40', '{problems}')), '2 consistency-check.sql: kept and problems unchanged');
select test.eq(test.s520('cons_rev', '{after,migrations}'), '"38"'::jsonb, '2 consistency-check.sql: migrations 38');

-- 3) while reverted the published Inventario page works as before ---------------------------------------------------------
select test.login('cafe'); select test.session('dev-520'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.try520('select public.proveedores_lista()') ->> 'raised' ~ '^42883' as gone \gset
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values
  ('5a000000-0000-4000-8000-000000052002', 'Queso', 'g', 500, 1750, '5b000000-0000-4000-8000-000000052001');
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000052002', '5b000000-0000-4000-8000-000000052001', 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values
  ('9b000000-0000-4000-8000-000000052002', '9a000000-0000-4000-8000-000000052002', '5a000000-0000-4000-8000-000000052002', 2, 4000, 3.5);
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000052002', '[{"line_id":"9b000000-0000-4000-8000-000000052002","qty":4000}]', '7e000000-0000-4000-8000-000000052003', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-520', 'date', public.cr_today(), 'currency', 'CRC', 'net', 14000, 'iva', 1820),
         '[{"method":"bank","amount_crc":15820,"reference":"BN 52003"}]', test.staff('ana'), '4826') as old1 \gset
select test.eq(public.clock_punch(test.staff('luis'), '5284') ->> 'action', 'out', '3 (Luis clocks out)');
reset role;
select test.eq(:'gone'::text || ' ' || ((:'old1'::jsonb) ->> 'ok') || ' ' || ((:'old1'::jsonb) ->> 'open_crc'), 't true 0.00',
               '3 the new functions do not exist; the published page receives, invoices and pays in one call');
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000052002'), 4000.0000, '3 the cheese is in stock');
select test.eq((select count(*)::int from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000052002'), 0, '3 no catalog row is made while reverted');
select test.eq((select count(*)::int from public.work_sessions where ended_at is null and staff_id = test.staff('luis')), 1, '3 the clock-out ends no session while reverted (nobody reads them)');
select count(*)::int as pinch_rev from public.staff_pin_changes \gset
update public.staff set pin_hash = pin_hash where id = test.staff('marta');
update public.staff set pin_hash = extensions.crypt('6173', extensions.gen_salt('bf')) where id = test.staff('marta');
select test.eq((select count(*)::int from public.staff_pin_changes), :pinch_rev, '3 a PIN change while reverted writes no PIN-change row (the trigger is gone; the table stays)');
create temp table d38 as select * from test.data520();
create temp table f38 as select * from test.fns520();

-- 4) 0039 and 0040 again, over what the reversal left -----------------------------------------------------------------------
\o /dev/null
\ir ../../supabase/migrations/0039_proveedores.sql
\ir ../../supabase/migrations/0040_proveedores_pagos.sql
\o
select test.eq(public.canopy_schema_version(), 40, '4 applied again: version 40');
select test.eq(test.diff520('f40', '(select * from test.fns520())'), '', '4 every function exactly as the first time (text, rights, settings)');
select test.eq(test.diff520('t40', '(select * from test.trg520())'), '', '4 every trigger once, as the first time');
select test.eq(test.diff520('s40', '(select * from test.str520())'), '', '4 every column, rule, index and right as the first time (none added twice)');
select test.eq(test.diff520('d38', '(select * from test.data520())'), 'purchase_receipt_lines vendor_items',
               '4 only two new tables gain rows (the copies of 0039); every other table, the original ones and the ledger included, untouched');
select test.eq((select count(*)::int from acct.mappings where key in ('supplier_advance', 'from_advance')), 2, '4 the two mappings once');
select test.eq((select string_agg(vendor_id || ':' || pack_qty || ':' || created_by, ' ') from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000052002'),
               '5b000000-0000-4000-8000-000000052001:500:migración 0039 5b000000-0000-4000-8000-000000052001:2000:migración 0039',
               '4 the item the published page saved with a supplier gets its row, and its order''s presentation (2 blocks of 2 kg) another');
select test.eq((select string_agg(pack_qty || ':' || coalesce(pack_label, '-'), ' ' order by pack_qty) from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000052001'),
               '24:caja de 24', '4 the row moved to boxes of 24 is not revived as a row of 12 (neither from the item nor from its earlier order)');
select test.eq((select packs || ' ' || qty || ' ' || pack_qty || ' ' || unit_cost || ' ' || pack_price from public.purchase_receipt_lines where receipt_id = '7e000000-0000-4000-8000-000000052003'),
               '2.0000 4000 2000 3.5 7000.00', '4 the delivery received the old way gets its line (2 blocks of 2 000 g at ₡7 000)');
select test.eq((select count(*)::int from public.purchase_receipt_lines where receipt_id in ('7e000000-0000-4000-8000-000000052001', '7e000000-0000-4000-8000-000000052002')), 2,
               '4 the deliveries made under 0039 are not copied twice');
select test.login('cafe'); select test.session('dev-520'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000052001') -> 'money', :'money_0040'::jsonb, '4 the new functions read the data as before (the order''s money the same)');
select test.login('cafe'); select test.session('dev-520-r'); set role authenticated;
select test.eq(public.proveedores_lista(:'tok'), '{"ok":false,"error":"no_session","why":"not_on_shift"}'::jsonb,
               '4 Luis''s session does not survive his clock-out made while reverted (checked at use)');
reset role;

-- 5) a second time ------------------------------------------------------------------------------------------------------------
create temp table d40b as select * from test.data520();
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\ir ../../supabase/tools/reversion-0039.sql
\o
select test.eq(public.canopy_schema_version() || ' ' || test.diff520('f38', '(select * from test.fns520())') || test.diff520('d40b', '(select * from test.data520())'), '38 ',
               '5 reverted again: the functions of version 38, no row changed');
\o /dev/null
\ir ../../supabase/migrations/0039_proveedores.sql
\ir ../../supabase/migrations/0040_proveedores_pagos.sql
\o
select test.eq(public.canopy_schema_version() || ' ' || test.diff520('f40', '(select * from test.fns520())') || test.diff520('t40', '(select * from test.trg520())')
               || test.diff520('d40b', '(select * from test.data520())'), '40 ', '5 applied again: every function and trigger as the first time, no row added or changed');

select test.done();
rollback;
