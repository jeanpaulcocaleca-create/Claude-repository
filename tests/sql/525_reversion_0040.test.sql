-- supabase/tools/reversion-0040.sql alone: undoes migration 0040 (the Proveedores reads, invoices and payments) and 0040
-- then applies again. It refuses while 0040 is not applied or a later migration is; it drops the 20 functions of 0040 and
-- nothing else (0039's 51 stay and keep working), deletes no data (the payments registered and applied, their entries, the
-- account 1160, the two mappings and the widened payment rule stay), and takes version 40 off the ledger. Contabilidad
-- keeps seeing the applied payments as supplier payments (and may void one). 0040 then applies again over that: every
-- function as the first time, no row added or changed. Twice.
begin;
create function test.fns525() returns table (k text, h text, acl text) language sql stable as $$
  select p.oid::regprocedure::text, md5(p.prosrc), coalesce(p.proacl::text, '-') from pg_proc p
   where p.pronamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) $$;
create function test.data525() returns table (k text, v text) language plpgsql stable as $$
declare r record;
begin
  for r in select c.oid::regclass::text as n from pg_class c where c.relkind in ('r', 'p') and c.oid <> 'canopy.migrations'::regclass
              and c.relnamespace in ('public'::regnamespace, 'canopy'::regnamespace, 'acct'::regnamespace) order by 1 loop
    k := r.n;
    execute format('select count(*) || '':'' || coalesce(md5(string_agg(x::text, E''\n'' order by x::text)), ''-'') from %s x', r.n) into v;
    return next;
  end loop;
end $$;
create function test.diff525(a text, b text) returns text language plpgsql as $$
declare res text;
begin
  execute format('select coalesce(string_agg(distinct k, '' '' order by k), '''') from ('
                 || '(select j ->> ''k'' from (select to_jsonb(x) from %1$s x except select to_jsonb(y) from %2$s y) q(j)) union all '
                 || '(select j ->> ''k'' from (select to_jsonb(y) from %2$s y except select to_jsonb(x) from %1$s x) q(j))) z(k)', a, b) into res;
  return res;
end $$;
create function test.v525(o text) returns int language sql security definer as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.lines525(o text) returns jsonb language sql security definer as $$
  select jsonb_agg(jsonb_build_object('line_id', id, 'rest', true)) from public.purchase_lines where po_id = o::uuid $$;

-- 0) under 0040: an order received and invoiced, paid by SINPE (applied), and a card payment ahead (not applied) ----------
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000052501', 'Lácteos Monteverde');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values
  ('5a000000-0000-4000-8000-000000052501', 'Leche', 'unit', 12, 12000, '5b000000-0000-4000-8000-000000052501');
select (select id::text from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000052501') as vi \gset
select test.login('cafe'); select test.session('dev-525'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000052501', jsonb_build_array(jsonb_build_object('vendor_item_id', :'vi', 'packs', 2)), null,
                                     '9a000000-0000-4000-8000-000000052501') ->> 'ok' as c1 \gset
select public.proveedor_recibir('9a000000-0000-4000-8000-000000052501', '7e000000-0000-4000-8000-000000052501', test.v525('9a000000-0000-4000-8000-000000052501'),
         test.lines525('9a000000-0000-4000-8000-000000052501'), null, false, 'F-525') ->> 'status' as r1 \gset
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000052501', array['7e000000-0000-4000-8000-000000052501']::uuid[],
         jsonb_build_object('date', public.cr_today(), 'net', 24000, 'iva', 3120), '5e000000-0000-4000-8000-000000052501') ->> 'ok' as f1 \gset
select public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000052501","po_id":"9a000000-0000-4000-8000-000000052501","amount":27120,"method":"sinpe","reference":"525-0001"}',
         '5d000000-0000-4000-8000-000000052501', test.staff('ana'), '4826') ->> 'applied_crc' as p1 \gset
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000052501', jsonb_build_array(jsonb_build_object('vendor_item_id', :'vi', 'packs', 1)), null,
                                     '9a000000-0000-4000-8000-000000052502') ->> 'ok' as c2 \gset
select public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000052501","po_id":"9a000000-0000-4000-8000-000000052502","amount":13560,"method":"card_debit"}',
         '5d000000-0000-4000-8000-000000052502', test.staff('ana'), '4826') ->> 'unapplied_crc' as p2 \gset
reset role;
select test.eq(concat_ws(' ', :'c1', :'r1', :'f1', :'p1', :'c2', :'p2'), 'true received true 27120.00 true 13560.00',
               '0 (fixture) received, invoiced and paid by SINPE (applied); a card payment ahead for another order (not applied)');
create temp table new525 as select p.oid::regprocedure::text as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('proveedores_lista', 'proveedores_por_recibir', 'proveedor_ficha', 'proveedor_pedido', 'proveedor_historial', 'proveedor_factura_registrar',
                     'proveedor_factura_anular', 'proveedor_anticipos_aplicar', 'proveedor_pago_registrar', 'proveedor_pago_anular', '_prov_dinero', '_prov_vendor_money',
                     '_prov_po_brief', '_prov_mode', '_prov_can', '_prov_date', '_prov_reverse', '_prov_void_payment', '_prov_aplicar', 'proveedores_bitacora');
select test.eq((select count(*)::int from new525), 20, '0 the 20 functions of 0040');
create temp table f40 as select * from test.fns525();
create temp table d40 as select * from test.data525();

-- 1) a later migration applied: refused, nothing changed ----------------------------------------------------------------------
insert into canopy.migrations (version, name) values (41, 'siguiente de prueba');
savepoint later;
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set LAST_ERROR_SQLSTATE 00000
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint later;
select test.eq(:'LAST_ERROR_MESSAGE'::text, 'Hay una migración posterior a la 0040 aplicada (41): revierta esa primero. No se cambió nada.', '1 refused with its message');
delete from canopy.migrations where version = 41;
select test.eq(test.diff525('f40', '(select * from test.fns525())') || test.diff525('d40', '(select * from test.data525())'), '', '1 nothing changed');

-- 2) the reversal -----------------------------------------------------------------------------------------------------------
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\o
select test.eq(public.canopy_schema_version(), 39, '2 back at version 39');
select test.eq((select string_agg(f.k, ' ' order by f.k) from f40 f where not exists (select 1 from test.fns525() g where g.k = f.k)),
               (select string_agg(sig, ' ' order by sig) from new525), '2 exactly the 20 functions of 0040 are gone');
select test.eq(test.diff525('(select * from f40 where k not in (select sig from new525) and k <> ''supplier_invoice_save(jsonb,uuid)'')',
                             '(select * from test.fns525() where k <> ''supplier_invoice_save(jsonb,uuid)'')'), '', '2 every other one (0039''s included) as it was');
select test.ok((select prosrc !~ '0040' and prosrc ~ 'the deliveries are this vendor''s and not invoiced yet' from pg_proc where oid = 'public.supplier_invoice_save(jsonb,uuid)'::regprocedure),
               '2 supplier_invoice_save is back to its 0025 text (without the corrections that go with their delivery)');
select test.eq((select acl from f40 where k = 'supplier_invoice_save(jsonb,uuid)'), (select acl from test.fns525() where k = 'supplier_invoice_save(jsonb,uuid)'),
               '2 with the same rights');
select test.eq(test.diff525('d40', '(select * from test.data525())'), '', '2 no row changed: payments, applications, entries, mappings');
select test.eq((select string_agg(key, ' ' order by key) from acct.mappings where account = '1160'), 'from_advance supplier_advance', '2 the 1160 mappings stay');
\pset format unaligned
\pset tuples_only on
\set tmp525 `mktemp`
\o :tmp525
\ir ../../supabase/tools/release-check.sql
\o
\set j525 `cat :'tmp525'`
\pset tuples_only off
\pset format aligned
select test.eq((:'j525'::jsonb) -> 'migrations_missing', '[40]'::jsonb, '2 release-check.sql: migrations_missing = [40]');
select test.eq((:'j525'::jsonb) -> 'functions_missing',
               '["proveedor_anticipos_aplicar", "proveedor_factura_anular", "proveedor_factura_registrar", "proveedor_ficha", "proveedor_historial", "proveedor_pago_anular", '
               '"proveedor_pago_registrar", "proveedor_pedido", "proveedores_bitacora", "proveedores_lista", "proveedores_por_recibir"]'::jsonb, '2 release-check.sql: the eleven public functions of 0040');
-- while reverted: ordering and receiving work; the books see the applied payments; the accountant may void one
select test.login('cafe'); select test.session('dev-525'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000052502', '7e000000-0000-4000-8000-000000052502', test.v525('9a000000-0000-4000-8000-000000052502'),
                 test.lines525('9a000000-0000-4000-8000-000000052502')) ->> 'status', 'received', '2 0039 still receives');
reset role;
select (select id::text from public.supplier_payments where advance_id = '5d000000-0000-4000-8000-000000052501') as app \gset
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq((select string_agg(p ->> 'paid_from' || ':' || (p ->> 'amount'), ' ') from jsonb_array_elements(public.ap_aging() -> 'payments') p), 'advance:27120.00',
               '2 Contabilidad lists the applied SINPE payment as a supplier payment');
select test.eq(public.supplier_payment_void(:'app'::uuid, 'prueba de reversión') ->> 'ok', 'true',
               '2 and the accountant may void it there (its entry reversed)');
reset role;
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000052501'), 27120.00, '2 the invoice is open again');
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u), 0, '2 the ledger balanced');
create temp table d39 as select * from test.data525();

-- 3) 0040 again ----------------------------------------------------------------------------------------------------------------
\o /dev/null
\ir ../../supabase/migrations/0040_proveedores_pagos.sql
\o
select test.eq(public.canopy_schema_version(), 40, '3 applied again: version 40');
select test.eq(test.diff525('f40', '(select * from test.fns525())'), '', '3 every function as the first time');
select test.eq(test.diff525('d39', '(select * from test.data525())'), '', '3 no row added or changed (the mappings and the account once)');
select test.login('cafe'); select test.session('dev-525'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000052501') #>> '{money,status}', 'paid',
               '3 the transfer still counts for its order (only its application was voided in Contabilidad)');
select test.eq(public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000052501') ->> 'applied_crc', '0',
               '3 the voided application is never redone on that invoice; the card payment waits for its own order''s invoice');
reset role;
create temp table d40b as select * from test.data525();
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\ir ../../supabase/migrations/0040_proveedores_pagos.sql
\o
select test.eq(public.canopy_schema_version() || ' ' || test.diff525('f40', '(select * from test.fns525())') || test.diff525('d40b', '(select * from test.data525())'), '40 ',
               '4 reverted and applied a second time: the same');

select test.done();
rollback;
